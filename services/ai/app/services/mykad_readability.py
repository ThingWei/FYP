"""Mandatory MyKad readability/pair checks. Not authenticity or liveness proof.

Images and unmasked field text stay in memory. Public evidence contains statuses only.
"""
import math
import os
import re
from functools import lru_cache
from threading import Lock

from .mykad_field_risk import configured_paths, _threshold, _detector_lock
from .document_risk_preprocessing import parse_region
from .mykad_document_type import assess_mykad_capture

CONTRACT = 'mykad-required-fields-v1'
OCR_THRESHOLD = 0.60
REQUIRED = {'front': ('front_identity_number', 'front_name', 'front_address'),
            'back': ('back_identity_number',)}
READABILITY_MESSAGE = 'Please rescan with your name, IC number and address fully visible.'
SCREEN_MESSAGE = 'Scan your physical MyKad, not a screenshot or an image displayed on another screen.'
PAIR_MESSAGE = 'The front and back IC numbers do not match. Rescan both sides of the same MyKad.'
whole_card_lock = Lock()

@lru_cache(maxsize=2)
def _field_detector(path):
    from pathlib import Path
    if not Path(path).is_file():
        raise FileNotFoundError('MyKad field detector unavailable')
    from ultralytics import YOLO
    model = YOLO(path)
    names = set(model.names.values()) if isinstance(model.names, dict) else set(model.names)
    if not set(sum(REQUIRED.values(), ())).issubset(names):
        raise ValueError('Required MyKad field classes unavailable')
    return model

def confident_lines(results):
    return [str(item[1]).strip() for item in results
            if math.isfinite(float(item[2])) and float(item[2]) >= OCR_THRESHOLD
            and str(item[1]).strip()]

def screen_evidence(lines):
    text = '\n'.join(lines).upper()
    patterns = {
        'visual_search': r'\b(?:SEARCH INSIDE IMAGE|SEARCH BY IMAGE|GOOGLE LENS|VISUAL MATCHES)\b',
        'browser_context': r'(?:HTTPS?://|WWW\.)|\b(?:CHROME|OPEN IN BROWSER|GOOGLE IMAGES)\b',
        'image_results': r'\b(?:RELATED IMAGES|MORE IMAGES|VIEW IMAGE|VISIT SITE|VISIT WEBSITE)\b',
        'share_action': r'^\s*SHARE\s*$',
        'save_action': r'^\s*SAVE\s*$',
    }
    cues = [key for key, pattern in patterns.items() if re.search(pattern, text, re.M)]
    strong = {'visual_search', 'browser_context', 'image_results'}
    detected = len(cues) >= 2 and bool(set(cues) & strong)
    return {'status': 'detected' if detected else 'not_detected', 'cues': cues,
            'absenceProvesPhysicalCard': False}

def identity_candidates(lines):
    # No O->0 substitutions, no birth-date filtering of conflicting rear numbers.
    result = set()
    for line in lines:
        for match in re.finditer(r'(?<![A-Za-z0-9])\d{6}[ \t-]?\d{2}[ \t-]?\d{4}(?![A-Za-z0-9])', line):
            result.add(re.sub(r'[ \t-]', '', match.group()))
    return result

def meaningful_lines(lines):
    # Known capture overlays do not count as personal name/address evidence.
    result = []
    for line in lines:
        upper = line.upper()
        if screen_evidence([line])['cues'] or re.search(r'\b(?:SAMPLE|SPECIMEN|CONTOH)\b', upper):
            continue
        # A readable detail sharing a line with a privacy notice remains usable.
        line = re.sub(r'\bFOR .{1,60}? ONLY\b', '', line, flags=re.I)
        line = re.sub(r'\bUNTUK KEGUNAAN .{1,60}? SAHAJA\b', '', line, flags=re.I).strip()
        if re.search(r'\bUNTUK KEGUNAAN\b', line, re.I):
            continue
        if sum(char.isalpha() for char in line) >= 3:
            result.append(line)
    return result

def _required_regions(card, side):
    model = _field_detector(str(configured_paths()[0]))
    threshold = _threshold()
    height, width = card.shape[:2]
    with _detector_lock:
        prediction = model.predict(card, verbose=False, conf=threshold, max_det=30)[0]
    regions = {name: [] for name in REQUIRED[side]}
    for box in prediction.boxes:
        label = str(prediction.names[int(box.cls.item())])
        confidence = float(box.conf.item())
        if label not in regions or not math.isfinite(confidence) or confidence < threshold:
            continue
        region = pixel_region(box.xyxy[0].tolist(), (width, height))
        if region[2] - region[0] >= 8 and region[3] - region[1] >= 6:
            regions[label].append((confidence, region))
    return regions

def pixel_region(value, image_size):
    left, top, right, bottom = parse_region(value, image_size)
    return (math.floor(left), math.floor(top), math.ceil(right), math.ceil(bottom))

def locate_card(image, side, whole_detector):
    detector, _path = whole_detector()
    if detector is None:
        raise RuntimeError('Whole-card detector unavailable')
    with whole_card_lock:
        prediction = detector.predict(image, verbose=False)[0]
    if prediction.boxes is None or len(prediction.boxes) == 0:
        return None, None
    index = int(prediction.boxes.conf.argmax())
    threshold = float(os.getenv('DOCUMENT_DETECTION_THRESHOLD', '0.65'))
    if not math.isfinite(threshold) or not 0 < threshold <= 1:
        raise ValueError('Invalid document detection threshold')
    if float(prediction.boxes.conf[index]) < threshold:
        return None, None
    label_index = int(prediction.boxes.cls[index])
    names = prediction.names
    label = names.get(label_index, '') if isinstance(names, dict) else names[label_index]
    detected_side = {'mykad_front': 'front', 'mykad_back': 'back'}.get(str(label).lower())
    bounds = pixel_region(prediction.boxes.xyxy[index].tolist(), (image.shape[1], image.shape[0]))
    return bounds, detected_side

def check_side(image, side, reader, preprocess, extract, whole_detector,
               card_bounds=None, detected_side=None):
    evidence = {'method': CONTRACT, 'status': 'unconfirmed', 'accepted': False,
                'expectedSide': side, 'detectedSide': detected_side,
                'authenticityVerified': False, 'requiredFields': {},
                'screenCopy': {'status': 'unavailable', 'cues': []}}
    private = {}
    if side not in REQUIRED or reader is None:
        evidence.update(status='unavailable', guidance='MyKad required-detail checks are unavailable. Retry after the AI service is ready.')
        return evidence, private
    try:
        # Full-scene OCR prevents card cropping from hiding browser/search context.
        scene_results = reader.readtext(preprocess(image), detail=1, paragraph=False)
        evidence['screenCopy'] = screen_evidence(confident_lines(scene_results))
        if evidence['screenCopy']['status'] == 'detected':
            evidence.update(status='screen_copy', guidance=SCREEN_MESSAGE)
            return evidence, private
        if card_bounds is None:
            card_bounds, detected_side = locate_card(image, side, whole_detector)
        evidence['detectedSide'] = detected_side
        if detected_side != side:
            evidence.update(status='wrong_side' if detected_side else 'unconfirmed',
                            guidance=f'Scan the MyKad {side} with the entire card visible.')
            return evidence, private
        x1, y1, x2, y2 = card_bounds
        card = image[y1:y2, x1:x2]
        card_results = reader.readtext(preprocess(card), detail=1, paragraph=False)
        text = '\n'.join(str(item[1]) for item in card_results)
        certain = '\n'.join(confident_lines(card_results))
        type_check, guidance = assess_mykad_capture(text, certain, extract(text, 'mykad'),
                                                  extract(certain, 'mykad'), side, detected_side)
        if not type_check['accepted']:
            evidence.update(status=type_check['status'], guidance=guidance)
            return evidence, private
        regions = _required_regions(card, side)
        field_lines = {}
        for label, detections in regions.items():
            lines, best_confidence = [], 0
            # All number regions contribute candidates; do not silently select one holder.
            chosen = detections if label.endswith('identity_number') else sorted(detections, reverse=True)[:1]
            for confidence, (left, top, right, bottom) in chosen:
                crop = card[top:bottom, left:right]
                lines.extend(confident_lines(reader.readtext(preprocess(crop), detail=1, paragraph=False)))
                best_confidence = max(best_confidence, confidence)
            field_lines[label] = lines
            meaningful = meaningful_lines(lines)
            readable = bool(identity_candidates(lines)) if label.endswith('identity_number') else bool(meaningful)
            if label.endswith('name'):
                readable = bool(meaningful) and sum(c.isalpha() for c in ' '.join(meaningful)) >= 3
            if label.endswith('address'):
                # More than a standalone state/overlay: require multiple readable address words.
                readable = bool(meaningful) and len(re.findall(r'\w+', ' '.join(meaningful), re.UNICODE)) >= 3
            # Visible browser text inside a required field is an obstructing overlay.
            if any(screen_evidence([line])['cues'] for line in lines):
                readable = False
            evidence['requiredFields'][label] = {'detected': bool(detections), 'readable': readable,
                                                 'detectionConfidence': round(best_confidence, 4)}
        numbers = identity_candidates(field_lines[f'{side}_identity_number'])
        evidence['identityNumberStatus'] = 'readable' if len(numbers) == 1 else 'ambiguous' if numbers else 'unreadable'
        if len(numbers) != 1 or not all(field['readable'] for field in evidence['requiredFields'].values()):
            evidence.update(status='unreadable_fields', guidance=READABILITY_MESSAGE if side == 'front'
                            else 'Please rescan the back with its IC number fully visible and readable.')
            return evidence, private
        number = next(iter(numbers))
        parsed = extract(number, 'mykad')
        if side == 'front' and parsed.get('identityNumberFormatValid') is not True:
            evidence.update(status='unreadable_fields', guidance='Please rescan the front IC number clearly.')
            return evidence, private
        private = {'identityNumber': number, 'identityNumberFormatValid': parsed.get('identityNumberFormatValid', False)}
        if side == 'front':
            private.update(fullName=' '.join(meaningful_lines(field_lines['front_name'])),
                           address=' '.join(meaningful_lines(field_lines['front_address'])))
            if parsed.get('dateOfBirth'):
                private['dateOfBirth'] = parsed['dateOfBirth']
        evidence.update(status='validated', accepted=True, guidance='Required details are readable. Administrator review is still required.')
    except Exception:
        evidence.update(status='unavailable', accepted=False,
                        guidance='MyKad required-detail checks are unavailable. Retry the check or rescan.')
        private = {}
    return evidence, private

def check_pair(front_result, back_result):
    front, front_fields = front_result
    back, back_fields = back_result
    evidence = {'method': CONTRACT, 'status': 'unconfirmed', 'accepted': False,
                'authenticityVerified': False, 'sides': [front, back]}
    if not front.get('accepted') or not back.get('accepted'):
        unavailable = any(side.get('status') == 'unavailable' for side in (front, back))
        evidence.update(status='unavailable' if unavailable else 'unconfirmed',
                        guidance=next((side.get('guidance') for side in (front, back) if not side.get('accepted')),
                                      READABILITY_MESSAGE))
        return evidence, {}
    if front_fields.get('identityNumber') != back_fields.get('identityNumber'):
        evidence.update(status='mismatched', guidance=PAIR_MESSAGE)
        return evidence, {}
    evidence.update(status='matched', accepted=True,
                    guidance='Front and back numbers match. Administrator review is still required.')
    return evidence, front_fields

