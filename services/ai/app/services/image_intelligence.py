import base64
import os
import re
from functools import lru_cache
from pathlib import Path
from typing import Any

from ..schemas import (
    DocumentFrameRequest,
    DocumentFrameResponse,
    EncodedImage,
    VerificationRequest,
    VerificationResponse,
)


def _decode_images(request: VerificationRequest):
    try:
        import cv2
        import numpy as np
    except ImportError as error:
        return [], [f'Image runtime unavailable: {error}']

    decoded = []
    errors = []
    for index, encoded in enumerate(request.images):
        try:
            raw = base64.b64decode(encoded.content_base64, validate=True)
            image = cv2.imdecode(np.frombuffer(raw, dtype=np.uint8), cv2.IMREAD_COLOR)
            if image is None:
                raise ValueError('unsupported or corrupt image')
            decoded.append((encoded, image))
        except (ValueError, TypeError) as error:
            errors.append(f'Image {index + 1}: {error}')
    if request.image_url and not request.images:
        errors.append('Remote image URLs are not fetched; send authenticated image bytes')
    return decoded, errors


def _quality(image) -> dict[str, Any]:
    import cv2

    grey = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    blur = float(cv2.Laplacian(grey, cv2.CV_64F).var())
    brightness = float(grey.mean())
    height, width = grey.shape
    glare_ratio = float((grey >= 245).sum()) / float(grey.size)
    return {
        'width': width,
        'height': height,
        'blurVariance': round(blur, 2),
        'brightness': round(brightness, 2),
        'isBlurry': blur < 75,
        'isTooDark': brightness < 40,
        'isTooBright': brightness > 225,
        'hasUsableResolution': width >= 640 and height >= 400,
        'glareRatio': round(glare_ratio, 4),
        'hasSevereGlare': glare_ratio > 0.12,
    }


def _document_crop(image):
    import cv2
    import numpy as np

    original = image.copy()
    ratio = image.shape[0] / 720.0
    resized = cv2.resize(image, (int(image.shape[1] / ratio), 720)) if ratio > 1 else image
    grey = cv2.cvtColor(resized, cv2.COLOR_BGR2GRAY)
    edges = cv2.Canny(cv2.GaussianBlur(grey, (5, 5), 0), 50, 150)
    contours, _ = cv2.findContours(edges, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    for contour in sorted(contours, key=cv2.contourArea, reverse=True)[:8]:
        perimeter = cv2.arcLength(contour, True)
        polygon = cv2.approxPolyDP(contour, 0.02 * perimeter, True)
        if len(polygon) != 4:
            continue
        points = polygon.reshape(4, 2).astype('float32')
        if ratio > 1:
            points *= ratio
        sums = points.sum(axis=1)
        differences = np.diff(points, axis=1).flatten()
        ordered = np.array([
            points[sums.argmin()], points[differences.argmin()],
            points[sums.argmax()], points[differences.argmax()],
        ], dtype='float32')
        top_left, top_right, bottom_right, bottom_left = ordered
        width = int(max(np.linalg.norm(bottom_right - bottom_left), np.linalg.norm(top_right - top_left)))
        height = int(max(np.linalg.norm(top_right - bottom_right), np.linalg.norm(top_left - bottom_left)))
        if width < 300 or height < 180:
            continue
        target = np.array([[0, 0], [width - 1, 0], [width - 1, height - 1], [0, height - 1]], dtype='float32')
        return cv2.warpPerspective(original, cv2.getPerspectiveTransform(ordered, target), (width, height))
    return original


def _ocr_preprocess(image):
    import cv2

    cropped = _document_crop(image)
    grey = cv2.cvtColor(cropped, cv2.COLOR_BGR2GRAY)
    contrasted = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8)).apply(grey)
    return cv2.addWeighted(contrasted, 1.5, cv2.GaussianBlur(contrasted, (0, 0), 2), -0.5, 0)


@lru_cache(maxsize=1)
def _ocr_reader():
    try:
        import easyocr
        return easyocr.Reader(
            ['en', 'ms'],
            gpu=os.getenv('EASYOCR_GPU', 'false').lower() == 'true',
            model_storage_directory=os.getenv('EASYOCR_MODEL_DIR', 'models/easyocr'),
            download_enabled=os.getenv('EASYOCR_ALLOW_DOWNLOAD', 'false').lower() == 'true',
        )
    except (ImportError, RuntimeError, OSError):
        return None


@lru_cache(maxsize=1)
def _nlp():
    try:
        import spacy
        nlp = spacy.blank('xx')
        ruler = nlp.add_pipe('entity_ruler')
        ruler.add_patterns([
            {'label': 'DOCUMENT_TYPE', 'pattern': [
                {'LOWER': {'IN': ['mykad', 'passport']}},
            ]},
            {'label': 'DOCUMENT_TYPE', 'pattern': [
                {'LOWER': 'driving'}, {'LOWER': {'IN': ['licence', 'license']}},
            ]},
            {'label': 'IDENTITY_NUMBER', 'pattern': [
                {'TEXT': {'REGEX': r'^\d{6}-?\d{2}-?\d{4}$'}},
            ]},
            {'label': 'PASSPORT_NUMBER', 'pattern': [
                {'TEXT': {'REGEX': r'^[A-Z]\d{7,9}$'}},
            ]},
            {'label': 'DATE_VALUE', 'pattern': [
                {'TEXT': {'REGEX': r'^\d{1,2}[./-]\d{1,2}[./-]\d{2,4}$'}},
            ]},
            {'label': 'DATE_OF_BIRTH', 'pattern': [
                {'LOWER': {'IN': ['dob', 'birth']}},
                {'TEXT': {'REGEX': r'^\d{1,2}[./-]\d{1,2}[./-]\d{2,4}$'}},
            ]},
            {'label': 'EXPIRY_DATE', 'pattern': [
                {'LOWER': {'IN': ['expiry', 'expires']}},
                {'TEXT': {'REGEX': r'^\d{1,2}[./-]\d{1,2}[./-]\d{2,4}$'}},
            ]},
        ])
        return nlp
    except ImportError:
        return None


def _valid_mykad_birth_date(value: str):
    from datetime import date

    digits = re.sub(r'\D', '', value)
    if len(digits) != 12:
        return None
    year = int(digits[:2])
    year += 1900 if year > date.today().year % 100 else 2000
    try:
        return date(year, int(digits[2:4]), int(digits[4:6]))
    except ValueError:
        return None


def _mrz_check_digit(value: str) -> str:
    values = {str(index): index for index in range(10)}
    values.update({chr(code): code - 55 for code in range(65, 91)})
    values['<'] = 0
    weights = (7, 3, 1)
    total = sum(
        values.get(character, 0) * weights[index % 3]
        for index, character in enumerate(value)
    )
    return str(total % 10)


def _passport_mrz_signal(text: str) -> dict[str, Any]:
    compact_lines = [
        re.sub(r'[^A-Z0-9<]', '', part.upper())
        for part in re.split(r'[\r\n]+|\s{2,}', text)
    ]
    candidates = [part for part in compact_lines if len(part) >= 30]
    heading_index = next(
        (index for index, part in enumerate(candidates) if part.startswith('P<')),
        None,
    )
    line_one = candidates[heading_index][:44] if heading_index is not None else ''
    line_two = next(
        (part[:44] for part in candidates[(heading_index + 1):]
         if len(part) >= 44 and not part.startswith('P<')),
        '',
    ) if heading_index is not None else ''
    format_valid = len(line_one) == 44 and len(line_two) == 44
    checks_valid = False
    if format_valid:
        checks = [
            _mrz_check_digit(line_two[0:9]) == line_two[9],
            _mrz_check_digit(line_two[13:19]) == line_two[19],
            _mrz_check_digit(line_two[21:27]) == line_two[27],
            _mrz_check_digit(line_two[28:42]) == line_two[42],
            _mrz_check_digit(
                line_two[0:10] + line_two[13:20] + line_two[21:43]
            ) == line_two[43],
        ]
        checks_valid = all(checks)
    return {
        'present': bool(line_one or line_two),
        'formatValid': format_valid,
        'checkDigitsValid': checks_valid,
    }


def _document_type_signals(text: str) -> dict[str, Any]:
    """Heuristic evidence weights, not learned probabilities or authenticity scores.

    Identity-number formats deliberately contribute no document-type evidence:
    Malaysian driving licences also print the holder's IC number.
    """
    upper = re.sub(r'\s+', ' ', text.upper()).strip()
    signals = {
        kind: {'score': 0, 'evidence': []}
        for kind in ('mykad', 'passport', 'driving_licence')
    }

    def add(kind, label, weight, pattern):
        if re.search(pattern, upper):
            signals[kind]['score'] += weight
            signals[kind]['evidence'].append(label)

    # Narrow common OCR substitutions only in document-heading patterns.
    add('mykad', 'identity_card_heading', 4,
        r'\b(?:MY\s*K[A4]D|K[A4]D\s+PENGEN[A4]L[A4]N|IDENTITY\s+CARD)\b')
    add('passport', 'passport_heading', 4, r'\bP[A4]S(?:SPORT|PORT)\b')
    if re.search(r'(?<![A-Z0-9])P<', text.upper()):
        signals['passport']['score'] += 4
        signals['passport']['evidence'].append('passport_mrz_heading')
    add('driving_licence', 'driving_licence_heading', 4,
        r'\b(?:DR[I1L]V[I1L]NG\s+L[I1L]CEN[CS][E3]|LES[E3]N\s+MEM[A4]NDU)\b')
    add('driving_licence', 'licence_class', 2,
        r'\b(?:CLASS|KELAS)\s*[:\-]?\s*[A-Z]{1,2}\d{0,2}\b')
    add('driving_licence', 'validity_date', 1,
        r'\b(?:VALID\s+UNTIL|EXPIRY|EXPIRES|TARIKH\s+LUPUT)\s*[:\-]?\s*\d{1,2}[./-]\d{1,2}[./-]\d{2,4}\b')
    add('driving_licence', 'malaysia_heading', 1, r'\bMALAYSIA\b')
    return signals


def _resolve_document_type(signals: dict[str, Any], expected_type: str | None):
    heading_types = [
        kind for kind, evidence in signals.items()
        if any(label.endswith('_heading') and label != 'malaysia_heading'
               for label in evidence['evidence'])
    ]
    if len(heading_types) > 1:
        return None, 'ambiguous'
    candidates = []
    for kind, evidence in signals.items():
        score = evidence['score']
        # Context helps incomplete licence OCR only with both structural fields.
        contextual_licence = (
            kind == expected_type == 'driving_licence' and score >= 3 and
            {'licence_class', 'validity_date'}.issubset(evidence['evidence'])
        )
        if score >= 4 or contextual_licence:
            candidates.append((score, kind))
    candidates.sort(reverse=True)
    if not candidates:
        return None, 'insufficient_evidence'
    if len(candidates) > 1 and candidates[0][0] - candidates[1][0] < 2:
        return None, 'ambiguous'
    return candidates[0][1], 'resolved'


def _extract_document_fields(text: str, expected_type: str | None = None) -> dict[str, Any]:
    normalized = re.sub(r'\s+', ' ', text).strip()
    fields: dict[str, Any] = {}
    mykad = re.search(r'\b\d{6}-?\d{2}-?\d{4}\b', normalized)
    passport = re.search(r'\b[A-Z]\d{7,9}\b', normalized.upper())
    licence = re.search(r'\b[A-Z]{1,3}\d{5,9}\b', normalized.upper())
    signals = _document_type_signals(text)
    document_type, resolution = _resolve_document_type(signals, expected_type)
    fields['documentTypeSignals'] = signals
    fields['documentTypeResolution'] = resolution
    if document_type:
        fields['documentType'] = document_type
    expiry = re.search(r'\b(?:EXPIRY|EXPIRES|VALID UNTIL|TARIKH LUPUT)\s*[:\-]?\s*(\d{1,2}[./-]\d{1,2}[./-]\d{2,4})', normalized.upper())
    birth = re.search(r'(?:DATE OF BIRTH|BIRTH|DOB)\s*[:\-]?\s*(\d{1,2}[./-]\d{1,2}[./-]\d{2,4})', normalized.upper())
    name = re.search(
        r"\b(?:NAME|NAMA)\s*[:\-]?\s*([A-Z][A-Z @'\-]{2,60}?)"
        r'(?=\s+(?:NATIONALITY|DOB|DATE OF BIRTH|ADDRESS|ALAMAT|SEX|EXPIRY|'
        r'EXPIRES|VALID UNTIL|CLASS|KELAS|WARGANEGARA|TARIKH|NO|IC)\b|\s*\d|$)',
        normalized.upper(),
    )
    address = re.search(r'(?:ADDRESS|ALAMAT)\s*[:\-]?\s*(.{8,140}?)(?=\s(?:EXPIRY|VALID|DOB)\b|$)', normalized, re.IGNORECASE)
    licence_class = re.search(
        r'\b(?:CLASS|KELAS)\s*[:\-]?\s*'
        r'([A-Z]{1,2}\d{0,2}(?:\s*[,/]\s*[A-Z]{1,2}\d{0,2})*)\b',
        normalized.upper(),
    )
    number_context = document_type or expected_type
    if passport and number_context == 'passport':
        fields['identityNumber'] = passport.group(0)
    elif mykad:
        fields['identityNumber'] = mykad.group(0)
    elif passport:
        fields['identityNumber'] = passport.group(0)
    elif licence:
        fields['identityNumber'] = licence.group(0)
    if licence_class and number_context == 'driving_licence':
        fields['licenceClass'] = licence_class.group(1)
    if expiry:
        fields['expiryDateText'] = expiry.group(1)
    if birth:
        fields['dateOfBirthText'] = birth.group(1)
    if name:
        fields['fullName'] = re.sub(r'\s+', ' ', name.group(1)).strip()
    if address:
        fields['address'] = re.sub(r'\s+', ' ', address.group(1)).strip()
    if mykad and fields.get('identityNumber') == mykad.group(0):
        birth_date = _valid_mykad_birth_date(mykad.group(0))
        fields['identityNumberFormatValid'] = birth_date is not None
        if birth_date:
            fields['dateOfBirth'] = birth_date.isoformat()
    fields['mrz'] = (
        _passport_mrz_signal(text)
        if document_type == 'passport' or expected_type == 'passport'
        else {'present': False, 'formatValid': False, 'checkDigitsValid': False}
    )
    nlp = _nlp()
    if nlp and normalized:
        document = nlp(normalized)
        fields['entityLabels'] = sorted({entity.label_ for entity in document.ents})
    return fields


@lru_cache(maxsize=1)
def _document_yolo_model():
    path = Path(os.getenv('DOCUMENT_YOLO_MODEL_PATH', 'models/document_yolo.pt'))
    if not path.is_file():
        return None, path
    from ultralytics import YOLO
    return YOLO(str(path)), path


@lru_cache(maxsize=1)
def _document_risk_model():
    path = Path(os.getenv(
        'DOCUMENT_RISK_MODEL_PATH',
        'models/document_risk_efficientnet.pt',
    ))
    if not path.is_file():
        return None, path
    import torch
    model = torch.jit.load(str(path), map_location='cpu')
    model.eval()
    return model, path


def _text_region_signals(image, results) -> tuple[str, list[str]]:
    import cv2
    import numpy as np

    heights = []
    sharpness = []
    for box, _text, confidence in results:
        if float(confidence) < 0.25:
            continue
        points = np.array(box, dtype='int32')
        x1, y1 = points.min(axis=0)
        x2, y2 = points.max(axis=0)
        if x2 <= x1 or y2 <= y1:
            continue
        region = image[max(0, y1):y2, max(0, x1):x2]
        if region.size == 0:
            continue
        heights.append(float(y2 - y1))
        grey = cv2.cvtColor(region, cv2.COLOR_BGR2GRAY)
        sharpness.append(float(cv2.Laplacian(grey, cv2.CV_64F).var()))
    if len(heights) < 3:
        return 'unavailable', []
    height_cv = float(np.std(heights) / max(np.mean(heights), 1))
    sharpness_cv = float(np.std(sharpness) / max(np.mean(sharpness), 1))
    indicators = []
    if height_cv > 0.75:
        indicators.append('Possible font/style inconsistency across text regions')
    if sharpness_cv > 1.25:
        indicators.append('Possible text-region edge or compression inconsistency')
    return ('suspicious' if indicators else 'normal'), indicators


@lru_cache(maxsize=1)
def _yolo_model():
    path = Path(os.getenv('YOLO_MODEL_PATH', 'models/item_yolo.pt'))
    if not path.is_file():
        return None, path
    from ultralytics import YOLO
    return YOLO(str(path)), path


@lru_cache(maxsize=1)
def _risk_model():
    path = Path(os.getenv('IMAGE_RISK_MODEL_PATH', 'models/image_risk_efficientnet.pt'))
    if not path.is_file():
        return None, path
    import torch
    model = torch.jit.load(str(path), map_location='cpu')
    model.eval()
    return model, path


def _perceptual_hash(image) -> str:
    import cv2

    grey = cv2.cvtColor(cv2.resize(image, (9, 8)), cv2.COLOR_BGR2GRAY)
    bits = grey[:, 1:] > grey[:, :-1]
    return ''.join(
        f'{sum(int(bit) << position for position, bit in enumerate(row)):02x}'
        for row in bits
    )


def _risk_probability(model, image) -> float:
    import cv2
    import numpy as np
    import torch

    resized = cv2.cvtColor(cv2.resize(image, (224, 224)), cv2.COLOR_BGR2RGB)
    tensor = torch.from_numpy(np.transpose(resized.astype('float32') / 255, (2, 0, 1))).unsqueeze(0)
    mean = torch.tensor([0.485, 0.456, 0.406]).view(1, 3, 1, 1)
    std = torch.tensor([0.229, 0.224, 0.225]).view(1, 3, 1, 1)
    with torch.inference_mode():
        logits = model((tensor - mean) / std)
        return float(torch.softmax(logits, dim=1)[0, 1])


class ImageIntelligenceService:
    def inspect_document_frame(
        self,
        request: DocumentFrameRequest,
    ) -> DocumentFrameResponse:
        decoded, errors = _decode_images(VerificationRequest(images=[
            EncodedImage(
                content_base64=request.content_base64,
                content_type=request.content_type,
                filename='scanner-frame.jpg',
            ),
        ]))
        if not decoded:
            return DocumentFrameResponse(
                available=True, detected=False, ready=False, confidence=0,
                guidance=errors[0] if errors else 'Frame could not be decoded',
                adapter='opencv-document-yolo-v1',
            )
        image = decoded[0][1]
        quality = _quality(image)
        detector, _path = _document_yolo_model()
        if detector is None:
            return DocumentFrameResponse(
                available=False, detected=False, ready=False, confidence=0,
                guidance='Document detector unavailable. Use manual capture.',
                quality=quality, adapter='opencv-document-yolo-v1',
            )
        prediction = detector.predict(image, verbose=False)[0]
        if not prediction.boxes or len(prediction.boxes) == 0:
            return DocumentFrameResponse(
                available=True, detected=False, ready=False, confidence=0,
                guidance='No document detected', quality=quality,
                adapter='opencv-document-yolo-v1',
            )
        best_index = int(prediction.boxes.conf.argmax())
        confidence = float(prediction.boxes.conf[best_index])
        x1, y1, x2, y2 = [
            float(value) for value in prediction.boxes.xyxy[best_index].tolist()
        ]
        height, width = image.shape[:2]
        box = [x1 / width, y1 / height, x2 / width, y2 / height]
        area = max(0.0, box[2] - box[0]) * max(0.0, box[3] - box[1])
        inside_guide = box[0] >= 0.06 and box[1] >= 0.16 and box[2] <= 0.94 and box[3] <= 0.84
        if confidence < float(os.getenv('DOCUMENT_DETECTION_THRESHOLD', '0.65')):
            guidance = 'Hold steady while the document is detected'
        elif area < 0.28:
            guidance = 'Move document closer'
        elif area > 0.78:
            guidance = 'Move document farther'
        elif not inside_guide:
            guidance = 'Align document inside frame'
        elif quality['isBlurry']:
            guidance = 'Hold steady'
        elif quality['isTooDark'] or quality['isTooBright']:
            guidance = 'Improve lighting'
        elif quality['hasSevereGlare']:
            guidance = 'Reduce glare and reflections'
        else:
            guidance = 'Ready to capture'
        ready = guidance == 'Ready to capture'
        return DocumentFrameResponse(
            available=True,
            detected=True,
            ready=ready,
            confidence=round(confidence, 4),
            guidance=guidance,
            quality=quality,
            bounding_box=[round(value, 4) for value in box],
            adapter='opencv-document-yolo-v1',
        )

    def verify_document(self, request: VerificationRequest) -> VerificationResponse:
        decoded, errors = _decode_images(request)
        if not decoded:
            return VerificationResponse(
                accepted=False, outcome='unavailable', confidence=0,
                reasons=errors or ['At least one identity-document image is required'],
                adapter='opencv-easyocr-spacy-v1',
            )
        qualities = [_quality(image) for _, image in decoded]
        severe_quality = [
            item for item in qualities
            if item['isBlurry'] or item['isTooDark'] or item['isTooBright']
            or item['hasSevereGlare'] or not item['hasUsableResolution']
        ]
        if severe_quality:
            return VerificationResponse(
                accepted=False, outcome='rescan_required', confidence=0,
                reasons=['One or more images are blurry, poorly lit, low resolution, or affected by severe glare'],
                adapter='opencv-easyocr-spacy-risk-v2',
                quality={'images': qualities},
            )
        reader = _ocr_reader()
        if reader is None:
            return VerificationResponse(
                accepted=False, outcome='unavailable', confidence=0,
                reasons=['EasyOCR runtime or language models are unavailable'],
                adapter='opencv-easyocr-spacy-risk-v2',
                quality={'images': qualities},
            )
        per_image = []
        all_results = []
        texts = []
        font_states = []
        risk_indicators = []
        for index, (_encoded, image) in enumerate(decoded):
            results = reader.readtext(_ocr_preprocess(image), detail=1, paragraph=False)
            all_results.extend((image, result) for result in results)
            font_state, text_indicators = _text_region_signals(image, results)
            if font_state != 'unavailable':
                font_states.append(font_state)
            risk_indicators.extend(text_indicators)
            image_text = '\n'.join(str(item[1]) for item in results)
            texts.append(image_text)
            per_image.append({
                'index': index,
                'confidence': round(
                    sum(float(item[2]) for item in results) / len(results), 4,
                ) if results else 0,
                'fieldCount': len(_extract_document_fields(image_text, request.expected_type)),
            })
        text = '\n'.join(texts)
        result_values = [item for _image, item in all_results]
        ocr_confidence = sum(float(item[2]) for item in result_values) / len(result_values) if result_values else 0
        fields = _extract_document_fields(text, request.expected_type)
        reasons = list(errors)
        if not fields.get('identityNumber'):
            reasons.append('A supported identity number was not detected')
        detected_type = fields.get('documentType')
        if not detected_type:
            reasons.append('Document type evidence is insufficient or ambiguous; manual review is required')
        if detected_type and request.expected_type and detected_type != request.expected_type:
            reasons.append('Selected document type does not match extracted document fields')
        if fields.get('identityNumberFormatValid') is False:
            reasons.append('Extracted Malaysian identity number has an invalid birth-date segment')
        if detected_type == 'passport' and fields['mrz']['present'] and not fields['mrz']['checkDigitsValid']:
            reasons.append('Passport MRZ format or check digits could not be validated')
        profile_match = None
        if request.profile_name:
            expected_tokens = {part.lower() for part in request.profile_name.split() if len(part) > 1}
            observed = text.lower()
            profile_match = bool(expected_tokens) and all(part in observed for part in expected_tokens)
            fields['profileNameMatched'] = profile_match
            if not profile_match:
                reasons.append('Profile name was not matched confidently in OCR text')
        from datetime import date, datetime
        date_of_birth = fields.get('dateOfBirth') or fields.get('dateOfBirthText')
        if date_of_birth:
            parsed_birth = None
            for pattern in ('%Y-%m-%d', '%d/%m/%Y', '%d-%m-%Y', '%d.%m.%Y'):
                try:
                    parsed_birth = datetime.strptime(date_of_birth, pattern).date()
                    break
                except ValueError:
                    continue
            if parsed_birth:
                age = date.today().year - parsed_birth.year - (
                    (date.today().month, date.today().day) <
                    (parsed_birth.month, parsed_birth.day)
                )
                fields['ageAtAnalysis'] = age
                fields['minimumAgeMet'] = age >= request.minimum_age
                if age < request.minimum_age:
                    reasons.append('Extracted date of birth does not meet the platform minimum age')
        expiry_text = fields.get('expiryDateText')
        if expiry_text:
            parsed_expiry = None
            for pattern in ('%d/%m/%Y', '%d-%m-%Y', '%d.%m.%Y'):
                try:
                    parsed_expiry = datetime.strptime(expiry_text, pattern).date()
                    break
                except ValueError:
                    continue
            fields['documentExpired'] = bool(parsed_expiry and parsed_expiry < date.today())
            if fields['documentExpired']:
                reasons.append('Document expiry date is in the past')
        fields['fontConsistency'] = (
            'suspicious' if 'suspicious' in font_states
            else 'normal' if font_states else 'unavailable'
        )
        risk_model, risk_path = _document_risk_model()
        if risk_model is not None:
            scores = [_risk_probability(risk_model, image) for _, image in decoded]
            fields['documentRiskScore'] = round(max(scores), 4)
            if max(scores) >= 0.65:
                risk_indicators.append('Document manipulation-risk model reported a high-risk signal')
        else:
            fields['documentRiskModel'] = 'unavailable'
            fields['documentRiskModelPath'] = risk_path.name
            reasons.append('Document risk model is unavailable; manual review is required')
        approved = (
            bool(fields.get('identityNumber')) and
            not reasons and
            not risk_indicators and
            ocr_confidence >= request.review_threshold
        )
        return VerificationResponse(
            accepted=approved,
            outcome='approved_candidate' if approved else 'manual_review',
            confidence=round(max(0, min(1, ocr_confidence)), 4),
            labels=[fields.get('documentType', 'unclassified_document')],
            reasons=reasons or ['Document signals passed automated checks'],
            adapter='opencv-easyocr-spacy-risk-v2',
            model_versions={
                'ocr': 'easyocr-1.7',
                'nlp': 'spacy-entity-ruler-v2',
                'risk': 'document-risk-efficientnet-b0' if risk_model else 'unavailable',
            },
            quality={'images': qualities, 'ocr': per_image},
            ocr_text=text,
            extracted_fields=fields,
            risk_indicators=sorted(set(risk_indicators)),
        )

    def verify_item(self, request: VerificationRequest) -> VerificationResponse:
        decoded, errors = _decode_images(request)
        if len(decoded) < 3:
            return VerificationResponse(
                accepted=False, outcome='rejected', confidence=0,
                reasons=errors + ['At least three valid item images are required'],
                adapter='opencv-yolo-efficientnet-v1',
            )
        yolo, yolo_path = _yolo_model()
        risk_model, risk_path = _risk_model()
        qualities = [_quality(image) for _, image in decoded]
        hashes = [_perceptual_hash(image) for _, image in decoded]
        duplicate_count = len(hashes) - len(set(hashes))
        reasons = list(errors)
        risk_indicators = []
        if duplicate_count:
            risk_indicators.append(f'{duplicate_count} duplicate or near-identical image(s) detected')
        poor_quality = sum(
            item['isBlurry'] or item['isTooDark'] or item['isTooBright'] or not item['hasUsableResolution']
            for item in qualities
        )
        if poor_quality:
            risk_indicators.append(f'{poor_quality} image(s) have quality issues')
        labels = []
        detection_confidences = []
        if yolo is not None:
            for _, image in decoded:
                result = yolo.predict(image, verbose=False)[0]
                for box in result.boxes:
                    labels.append(str(result.names[int(box.cls.item())]))
                    detection_confidences.append(float(box.conf.item()))
        else:
            reasons.append(f'YOLO model artifact is unavailable at {yolo_path}')
        risk_scores = []
        if risk_model is not None:
            risk_scores = [_risk_probability(risk_model, image) for _, image in decoded]
            if max(risk_scores, default=0) >= 0.65:
                risk_indicators.append('Trained risk classifier found a high-risk image')
        else:
            reasons.append(f'EfficientNet risk model artifact is unavailable at {risk_path}')
        expected = (request.expected_category or request.expected_type or '').lower()
        category_match = not expected or any(expected in label.lower() or label.lower() in expected for label in labels)
        if labels and not category_match:
            risk_indicators.append('Detected object class does not match the submitted category')
        confidence = sum(detection_confidences) / len(detection_confidences) if detection_confidences else 0
        fully_available = yolo is not None and risk_model is not None
        accepted = fully_available and category_match and not risk_indicators and confidence >= 0.55
        outcome = 'approved' if accepted else ('manual_review' if not fully_available or confidence < 0.55 else 'warning')
        return VerificationResponse(
            accepted=accepted, outcome=outcome,
            confidence=round(max(0, min(1, confidence)), 4),
            labels=sorted(set(labels)),
            reasons=reasons or ['Item images passed automated checks'],
            adapter='opencv-yolo-efficientnet-v1',
            model_versions={
                **({'objectDetection': yolo_path.name} if yolo else {}),
                **({'riskClassifier': risk_path.name} if risk_model else {}),
            },
            quality={'images': qualities, 'duplicateCount': duplicate_count},
            extracted_fields={'categoryMatched': category_match},
            risk_indicators=risk_indicators,
        )
