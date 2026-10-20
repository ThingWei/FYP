"""Advisory item-photo evidence. Object presence is not proof of authenticity."""

import json
import math
import os
import re
from threading import Lock
from functools import lru_cache
from pathlib import Path

from ..schemas import VerificationResponse

ROOT = Path(__file__).resolve().parents[2]
CONTRACT = 'renthub-item-evidence-v4'
RISK_CONTRACT = 'renthub-item-risk-v1'
THRESHOLD = 0.55
DETECTOR_LOCK = Lock()


def normalize(value):
    return re.sub(r'[^a-z0-9]+', ' ', value.casefold()).strip()


# Exact aliases only: never treat a text substring/background person as a match.
# This is a label ontology, not a catalogue, authenticity test or price rule.
DOMAINS = {
    'devices': {
        'smartphones': {'cell phone', 'mobile phone', 'smartphone', 'phone'},
        'cameras': {'camera', 'cameras', 'digital camera', 'mirrorless camera', 'dslr'},
        'computers': {'laptop', 'computer', 'desktop', 'desktop computer'},
        'audio': {'speaker', 'headphones', 'headphone', 'microphone', 'amplifier'},
        'gaming': {'game console', 'gaming console', 'console', 'game controller'},
        'other devices': {'tv', 'television', 'projector', 'tablet', 'printer'},
    },
    'vehicles': {
        'cars': {'car', 'cars', 'automobile', 'sedan', 'suv', 'hatchback'},
        'motorcycles': {'motorcycle', 'motorbike', 'scooter'},
        'bicycles': {'bicycle', 'cycle'},
        'other vehicles': {'truck', 'bus', 'van', 'boat'},
    },
    'equipment': {
        'tools': {'drill', 'hammer', 'saw', 'power tool', 'wrench', 'screwdriver'},
        'sports equipment': {'sports ball', 'tennis racket', 'racket', 'baseball bat',
                             'baseball glove', 'skateboard', 'surfboard', 'skis',
                             'snowboard', 'bicycle', 'kayak', 'dumbbell'},
        'event equipment': {'chair', 'dining table', 'table', 'tent', 'canopy',
                            'projector', 'speaker', 'stage light'},
        'other equipment': {'generator', 'ladder', 'pressure washer', 'vacuum cleaner'},
    },
    'books': {key: {'book', 'books'} for key in
              ('textbooks', 'reference books', 'fiction', 'other books')},
    'clothing': {
        'formal wear': {'suit', 'tuxedo', 'dress', 'formal wear'},
        'costumes': {'costume', 'costumes'},
        'traditional wear': {'baju melayu', 'baju kurung', 'kebaya', 'sari'},
        'other clothing': {'clothing', 'shirt', 'coat', 'jacket'},
    },
}


def expected_labels(category, subcategory):
    domains = DOMAINS.get(normalize(category or ''), {})
    if subcategory:
        key = normalize(subcategory)
        return domains.get(key, set()).copy()
    # A missing/unknown specific category cannot silently inherit broad support.
    return set()


# Photo guidance is separate from the label vocabulary. Detail views are useful
# evidence, but a whole-object detector cannot establish what every detail shows.
PHOTO_GUIDANCE = {
    'devices': ('Include a photo of the whole device, then its other side and useful details such as ports or labels.'),
    'vehicles': ('Include the whole vehicle, another angle and details showing its condition.'),
    'equipment': ('Include the whole item, another angle and useful details such as attachments or labels.'),
    'books': ('Include the cover, spine or back cover, and an inside page. Keep the page edges visible.'),
    'clothing': ('Include the whole garment, its other side and details such as the fabric or care label.'),
}


def detector_vocabulary(detector):
    names = detector.names if detector is not None else {}
    return {normalize(str(name)) for name in (names.values() if isinstance(names, dict) else names)}


def category_coverage(category, subcategory, detectors):
    allowed = expected_labels(category, subcategory)
    sources = [{'source': source, 'version': version,
                'labelScope': 'prompted_not_finetuned' if source == 'yolo_world_pretrained' else 'detector_vocabulary',
                'matchingLabels': sorted(allowed & detector_vocabulary(model))}
               for model, source, version in detectors]
    matched = sorted(set().union(*(set(row['matchingLabels']) for row in sources))) if sources else []
    return {
        'category': category, 'subcategory': subcategory,
        'strategy': 'object_detection_then_admin_review' if matched else 'manual_review',
        'status': 'limited_object_labels' if matched else 'no_matching_labels',
        'matchingLabels': matched, 'sources': sources,
        'openVocabularyOnly': bool(matched) and not any(
            row['matchingLabels'] for row in sources if row['source'] != 'yolo_world_pretrained'),
        'allProductsCovered': False,
        'evaluationStatus': 'subcategory_accuracy_not_established',
        'specificCategoryVerified': False,
        'photoGuidance': PHOTO_GUIDANCE.get(normalize(category or ''),
                                          'Include the whole item and different detail views.'),
    }


def coverage_matrix(detectors):
    return [category_coverage(category, subcategory, detectors)
            for category, subcategories in DOMAINS.items() for subcategory in subcategories]


def verification_detectors(detector, status):
    """Keep the configured detector; supplement only with an existing local model.

    Does not change the single-detector contract used by MyKad phone screening.
    An explicitly broken custom path still fails instead of silently falling back.
    """
    if detector is None:
        return []
    result = [(detector, status['detectorSource'], status['detectorVersion'])]
    fallback = artifact_path('ITEM_PRETRAINED_YOLO_PATH', 'yolov8n.pt')
    selected, _ = detector_selection()
    if (status['detectorSource'] == 'configured_item_model' and
            os.getenv('ITEM_ALLOW_PRETRAINED_DETECTOR', 'true').lower() == 'true' and
            fallback.resolve() != selected.resolve() and fallback.is_file()):
        try:
            model = load_detector(fallback, fallback.stat().st_mtime_ns)
            result.append((model, 'general_pretrained', fallback.name))
        except Exception:
            pass  # Optional supplement cannot invalidate the configured detector.
    if status.get('world', {}).get('available'):
        from .item_world import artifact_path as world_path, load_world, SOURCE
        path = world_path()
        try:
            result.append((load_world(path, path.stat().st_mtime_ns), SOURCE, path.name))
        except Exception:
            pass  # Prepared artifact disappeared; no automatic download/fallback pass.
    return result


def original_box(box, image, turns):
    """Map a box from an inference-only CCW rotation back to uploaded pixels."""
    height, width = image.shape[:2]
    rotated_height, rotated_width = (width, height) if turns % 2 else (height, width)
    coordinates = box.xyxy[0].tolist()
    if len(coordinates) != 4:
        return None
    x1, y1, x2, y2 = [float(value) / size for value, size in
                       zip(coordinates, [rotated_width, rotated_height] * 2)]
    if not (all(math.isfinite(v) and 0 <= v <= 1 for v in (x1, y1, x2, y2)) and
            x1 < x2 and y1 < y2):
        return None
    transform = (lambda x, y: (x, y), lambda x, y: (1 - y, x),
                 lambda x, y: (1 - x, 1 - y), lambda x, y: (y, 1 - x))[turns]
    points = [transform(x, y) for x, y in ((x1, y1), (x1, y2), (x2, y1), (x2, y2))]
    return [min(x for x, _ in points), min(y for _, y in points),
            max(x for x, _ in points), max(y for _, y in points)]


def detect_photo(image, allowed, detectors):
    """At most three local models x four orientations; no threshold reduction.

    Stop on positive object evidence. Repeated predictions never become extra
    views or corroboration. A miss remains inconclusive, not a category mismatch.
    """
    import numpy as np
    detections, attempts, failures = [], 0, 0
    eligible = [entry for entry in detectors if allowed & detector_vocabulary(entry[0])]
    # Unknown categories still receive one ordinary detection for admin context.
    candidates = eligible or detectors[:1]
    # Exhaust ordinary detectors/orientations BEFORE open vocabulary, so an
    # already-working trained detector is never replaced by a prompted score.
    phases = ([entry for entry in candidates if entry[1] != 'yolo_world_pretrained'],
              [entry for entry in candidates if entry[1] == 'yolo_world_pretrained'])
    plan = [(turns, entry) for phase in phases
            for turns in ((0, 1, 3, 2) if eligible else (0,)) for entry in phase]
    for turns, (model, source, version) in plan:
        attempts += 1
        try:
            with DETECTOR_LOCK:
                result = model.predict(np.ascontiguousarray(np.rot90(image, turns)),
                                       verbose=False, conf=THRESHOLD, device='cpu', max_det=20)[0]
            for box in result.boxes:
                label = str(result.names[int(box.cls.item())])
                score = float(box.conf.item())
                if not math.isfinite(score) or not THRESHOLD <= score <= 1:
                    continue
                detection = {'label': label, 'confidence': round(score, 4),
                             'matchesCategory': normalize(label) in allowed,
                             'source': source, 'modelVersion': version,
                             'rotationDegrees': turns * 90}
                try:
                    bounds = original_box(box, image, turns)
                    if bounds is not None:
                        detection['boundingBox'] = bounds
                except (AttributeError, TypeError, ValueError, IndexError):
                    pass
                previous = next((d for d in detections if d['label'] == label), None)
                if previous is None:
                    detections.append(detection)
                elif score > previous['confidence']:
                    detections[detections.index(previous)] = detection
            if any(d['matchesCategory'] for d in detections):
                return detections, attempts, failures
        except Exception:
            failures += 1
    return detections, attempts, failures


def artifact_path(setting, default):
    path = Path(os.getenv(setting, default))
    return path if path.is_absolute() else ROOT / path


def detector_selection():
    custom = artifact_path('YOLO_MODEL_PATH', 'models/item_yolo.pt')
    # Explicit custom paths never silently fall back on a typo/corrupt artifact.
    if custom.is_file():
        return custom, 'configured_item_model'
    default_custom = ROOT / 'models/item_yolo.pt'
    fallback = artifact_path('ITEM_PRETRAINED_YOLO_PATH', 'yolov8n.pt')
    allow = os.getenv('ITEM_ALLOW_PRETRAINED_DETECTOR', 'true').lower() == 'true'
    if allow and custom == default_custom and fallback.is_file():
        return fallback, 'general_pretrained'
    return custom, 'unavailable'


def valid_risk_metadata(metadata):
    return (
        metadata.get('contract') == RISK_CONTRACT
        and metadata.get('architecture') == 'efficientnet_b0'
        and metadata.get('classes') == ['normal', 'risky']
        and metadata.get('preprocessing') == 'rgb-224-imagenet-v1'
        and metadata.get('purpose') == 'item_photo_risk_assistance'
    )


@lru_cache(maxsize=4)
def load_detector(path, stamp):
    from ultralytics import YOLO
    model = YOLO(str(path))
    if model.task != 'detect':
        raise ValueError('An object-detection artifact is required')
    return model


@lru_cache(maxsize=4)
def load_risk(path, stamp):
    import torch
    extra = {'metadata.json': ''}
    model = torch.jit.load(str(path), map_location='cpu', _extra_files=extra)
    metadata = json.loads(extra['metadata.json'])
    if not valid_risk_metadata(metadata):
        raise ValueError('Incompatible item-risk artifact contract')
    model.eval()
    with torch.inference_mode():
        output = model(torch.zeros(1, 3, 224, 224))
        if output.shape != (1, 2) or not torch.isfinite(output).all():
            raise ValueError('Item-risk model must return two finite logits')
    return model, metadata


def models_status():
    """Load/validate lazily; report corrupt artifacts, not just file existence."""
    detector_path, source = detector_selection()
    risk_path = artifact_path('IMAGE_RISK_MODEL_PATH', 'models/image_risk_efficientnet.pt')
    detector = risk = None
    metadata = {}
    detector_issue = risk_issue = None
    try:
        detector = load_detector(detector_path, detector_path.stat().st_mtime_ns)
    except Exception:
        source = 'unavailable'
        detector_issue = 'load_failed_or_incompatible' if detector_path.is_file() else 'artifact_missing'
    try:
        risk, metadata = load_risk(risk_path, risk_path.stat().st_mtime_ns)
    except Exception:
        risk_issue = 'load_failed_or_incompatible' if risk_path.is_file() else 'artifact_missing'
    status = {
        'detectorAvailable': detector is not None,
        'detectorSource': source,
        'detectorVersion': detector_path.name if detector is not None else None,
        'riskClassifierAvailable': risk is not None,
        'riskClassifierVersion': risk_path.name if risk is not None else None,
        'riskTrainingSource': metadata.get('sourceTypes', []),
        'riskEvaluation': metadata.get('testMetrics', {}),
        'riskEvaluationScope': metadata.get('evaluationScope', 'not_established'),
        'riskEvaluationBySource': metadata.get('testMetricsBySourceType', {}),
        'detectorIssue': detector_issue,
        'riskClassifierIssue': risk_issue,
    }
    from .item_world import availability as world_availability
    _, status['world'] = world_availability()
    detectors = verification_detectors(detector, status)
    status['detectors'] = [{'source': source, 'version': version,
                            'labels': sorted(detector_vocabulary(model))}
                           for model, source, version in detectors]
    status['categoryCoverage'] = coverage_matrix(detectors)
    return detector, risk, status


def verify(request, decoded, errors, quality_fn, hash_fn, risk_fn):
    fields = {
        'advisory': True, 'authenticityVerified': False, 'adminReviewRequired': True,
        'expectedCategory': request.expected_category,
        'expectedSubcategory': request.expected_subcategory,
        'submittedCondition': request.expected_condition,
        'conditionAssessment': 'not_assessed',
        'matchGranularity': 'object_type_only',
        'categoryMatched': None,
        'confidenceMeaning': 'view_coverage_weighted_detection_score_not_authenticity_probability',
    }
    if len(decoded) < 3 or len(decoded) > 10 or len(request.images) > 10:
        return VerificationResponse(
            accepted=False, outcome='rejected', confidence=0, adapter=CONTRACT,
            reasons=errors + ['At least three and no more than ten valid item images are required'],
            extracted_fields=fields,
        )
    detector, risk, status = models_status()
    detectors = verification_detectors(detector, status)
    # The global matrix belongs in health/audit, not duplicated in each history row.
    fields['models'] = {key: value for key, value in status.items() if key != 'categoryCoverage'}
    coverage = category_coverage(request.expected_category, request.expected_subcategory, detectors)
    fields['categoryCoverage'] = coverage
    fields['photoGuidance'] = coverage['photoGuidance']
    reasons = list(errors)
    indicators = []
    qualities = [quality_fn(image) for _, image in decoded]
    hashes = [hash_fn(image) for _, image in decoded]
    duplicates = len(hashes) - len(set(hashes))
    if duplicates:
        indicators.append('Repeated or visually similar photos detected; upload different views')
    if any(q['isBlurry'] or q['isTooDark'] or q['isTooBright'] or
           not q['hasUsableResolution'] for q in qualities):
        indicators.append('One or more photos need better focus, lighting or resolution')
    allowed = expected_labels(request.expected_category, request.expected_subcategory)
    supported = bool(coverage['matchingLabels'])
    fields['categorySupport'] = 'limited_object_labels' if supported else 'unsupported'
    labels = set()
    per_image = []
    failures = False
    source_indices = {id(entry): index for index, entry in enumerate(request.images)}
    for index, (submitted, image) in enumerate(decoded):
        evidence = {'imageIndex': source_indices.get(id(submitted), index),
                    'imageWidth': image.shape[1], 'imageHeight': image.shape[0],
                    'quality': qualities[index],
                    'detections': [], 'categoryMatched': None}
        detections, attempts, failed = detect_photo(image, allowed, detectors)
        evidence.update({'detections': detections, 'detectionAttempts': attempts,
                         'failedDetectionAttempts': failed})
        labels.update(d['label'] for d in detections)
        matched = any(d['matchesCategory'] for d in detections)
        # Missing whole-object evidence is not bad quality or a wrong-item verdict.
        evidence['categoryMatched'] = True if matched else None
        evidence['objectEvidenceStatus'] = (
            'expected_type_detected' if matched else 'analysis_incomplete' if failed or not detectors
            else 'not_detected' if supported else 'category_not_covered')
        if failed:
            failures = True
            evidence['detectorUnavailable'] = True
        if risk is not None:
            try:
                score = risk_fn(risk, image)
                if not math.isfinite(score) or not 0 <= score <= 1:
                    raise ValueError('Invalid risk probability')
                evidence['imageRiskScore'] = round(score, 4)
                if score >= 0.65:
                    indicators.append(f'Photo {index + 1} has an elevated learned image-risk signal')
            except Exception:
                failures = True
                evidence['riskClassifierUnavailable'] = True
        per_image.append(evidence)
    fields['images'] = per_image
    if detector is None:
        reasons.append('Item detector is unavailable; manual photo review is needed')
    elif any(source == 'general_pretrained' for _, source, _ in detectors):
        reasons.append('General pretrained object detector; not trained to authenticate rental items')
    if not supported:
        reasons.append('The detector does not cover this specific category; this is not a mismatch')
    elif not failures:
        matched_views = sum(e['categoryMatched'] is True for e in per_image)
        fields['categoryMatched'] = True if matched_views == len(per_image) and not errors else None
        if not matched_views:
            reasons.append('Item type could not be established automatically; this is not a photo-quality or authenticity verdict')
        elif matched_views < len(per_image):
            reasons.append('Some views have object evidence; remaining views may be details or missed detections and require administrator review')
    if normalize(request.expected_category or '') == 'books':
        reasons.append('Book detection does not verify the book title, edition or genre')
    if risk is None:
        reasons.append('Trained item image-risk classifier is unavailable; image risk is not assessed')
    if failures:
        reasons.append('A model could not analyse one or more photos; manual review is needed')
    if errors:
        indicators.append('Some supplied images could not be decoded')
    complete = detector is not None and risk is not None and supported and not failures
    all_views_match = all(e['categoryMatched'] is True for e in per_image)
    world_used = any(d['matchesCategory'] and d.get('source') == 'yolo_world_pretrained'
                     for e in per_image for d in e['detections'])
    fields['openVocabularyEvidenceUsed'] = world_used
    if world_used:
        reasons.append('Open-vocabulary evidence is uncalibrated for RentHub; administrator review is mandatory')
    research_risk = status.get('riskTrainingSource') == ['synthetic_manipulation']
    fields['syntheticRiskOnly'] = research_risk
    if research_risk:
        reasons.append('Item-risk classifier has only synthetic training evidence; independent real evaluation is missing')
    submitted_views = max(len(request.images), len(decoded))
    matched_views = sum(e['categoryMatched'] is True for e in per_image)
    fields.update({
        'matchingViewCount': matched_views, 'submittedViewCount': submitted_views,
        'analysedViewCount': len(per_image),
        'unconfirmedViewCount': len(per_image) - matched_views,
        'detailViewsVerified': False,
        'categoryMatchStatus': ('unsupported' if not supported else 'analysis_incomplete' if failures or errors
                                else 'all_views_detected' if all_views_match else 'partial_views' if matched_views
                                else 'not_detected'),
    })
    reasons.append('Detection scores are not calibrated authenticity probabilities. '
                   'Illustrations, wallpapers and screenshots can produce confident false detections; '
                   'review the highlighted region in every photo.')
    accepted = complete and all_views_match and not indicators and not world_used and not research_risk
    outcome = 'approved_candidate' if accepted else (
        'warning' if indicators else 'manual_review')
    if accepted:
        reasons.append('No automated concerns found; administrator approval is still required')
    reasons.append('These checks do not prove ownership, authenticity, brand/model or stated condition')
    return VerificationResponse(
        accepted=accepted, outcome=outcome,
        confidence=round(sum(max((d['confidence'] for d in e['detections'] if d['matchesCategory']), default=0)
                             for e in per_image) / submitted_views, 4),
        labels=sorted(labels), reasons=reasons, adapter=CONTRACT,
        model_versions={key: value for key, value in {
            'objectDetection': status['detectorVersion'],
            'riskClassifier': status['riskClassifierVersion'],
        }.items() if value},
        quality={'images': qualities, 'duplicateCount': duplicates,
                 'duplicateScope': 'within_submission', 'method': 'perceptual_dhash'},
        extracted_fields=fields, risk_indicators=list(dict.fromkeys(indicators)),
    )
