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
CONTRACT = 'renthub-item-evidence-v2'
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
        'cameras': {'camera', 'digital camera', 'mirrorless camera', 'dslr'},
        'computers': {'laptop', 'computer', 'desktop', 'desktop computer'},
        'audio': {'speaker', 'headphones', 'headphone', 'microphone', 'amplifier'},
        'gaming': {'game console', 'gaming console', 'console', 'game controller'},
        'other devices': {'tv', 'television', 'projector', 'tablet', 'printer'},
    },
    'vehicles': {
        'cars': {'car', 'automobile', 'sedan', 'suv', 'hatchback'},
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
        'other equipment': {'equipment', 'generator', 'ladder'},
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
        labels = domains.get(key)
        return labels | {key} if labels is not None else set()
    return set().union(*(labels | {key} for key, labels in domains.items())) if domains else set()


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
    return detector, risk, {
        'detectorAvailable': detector is not None,
        'detectorSource': source,
        'detectorVersion': detector_path.name if detector is not None else None,
        'riskClassifierAvailable': risk is not None,
        'riskClassifierVersion': risk_path.name if risk is not None else None,
        'riskTrainingSource': metadata.get('sourceTypes', []),
        'riskEvaluation': metadata.get('testMetrics', {}),
        'detectorIssue': detector_issue,
        'riskClassifierIssue': risk_issue,
    }


def verify(request, decoded, errors, quality_fn, hash_fn, risk_fn):
    fields = {
        'advisory': True, 'authenticityVerified': False, 'adminReviewRequired': True,
        'expectedCategory': request.expected_category,
        'expectedSubcategory': request.expected_subcategory,
        'submittedCondition': request.expected_condition,
        'conditionAssessment': 'not_assessed',
        'matchGranularity': 'object_type_only',
        'categoryMatched': None,
    }
    if len(decoded) < 3:
        return VerificationResponse(
            accepted=False, outcome='rejected', confidence=0, adapter=CONTRACT,
            reasons=errors + ['At least three valid item images are required'],
            extracted_fields=fields,
        )
    detector, risk, status = models_status()
    fields['models'] = status
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
    names = detector.names if detector is not None else {}
    vocabulary = names.values() if isinstance(names, dict) else names
    supported = bool(allowed & {normalize(name) for name in vocabulary})
    fields['categorySupport'] = 'supported' if supported else 'unsupported'
    labels = set()
    matching_scores = []
    per_image = []
    failures = False
    for index, (_, image) in enumerate(decoded):
        evidence = {'imageIndex': index, 'detections': [], 'categoryMatched': None}
        if detector is not None:
            try:
                # Ultralytics caches mutable prediction state on the model.
                with DETECTOR_LOCK:
                    result = detector.predict(image, verbose=False, conf=THRESHOLD, device='cpu')[0]
                for box in result.boxes:
                    label = str(result.names[int(box.cls.item())])
                    score = float(box.conf.item())
                    if not math.isfinite(score) or not THRESHOLD <= score <= 1:
                        continue
                    matches = supported and normalize(label) in allowed
                    labels.add(label)
                    evidence['detections'].append({
                        'label': label, 'confidence': round(score, 4),
                        'matchesCategory': matches,
                    })
                    if matches:
                        matching_scores.append(score)
                if supported:
                    evidence['categoryMatched'] = any(
                        entry['matchesCategory'] for entry in evidence['detections'])
            except Exception:
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
    elif status['detectorSource'] == 'general_pretrained':
        reasons.append('General pretrained object detector; not trained to authenticate rental items')
    if not supported:
        reasons.append('The detector does not cover this specific category; this is not a mismatch')
    elif not failures:
        fields['categoryMatched'] = bool(matching_scores)
        matched_views = sum(e['categoryMatched'] is True for e in per_image)
        if not matching_scores:
            indicators.append('Expected item type was not detected clearly in the photos; admin review needed')
        elif matched_views < 2:
            reasons.append('Item type was detected in only one view; admin should check the remaining photos')
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
    accepted = complete and all_views_match and not indicators
    outcome = 'approved_candidate' if accepted else (
        'warning' if indicators else 'manual_review')
    if accepted:
        reasons.append('No automated concerns found; administrator approval is still required')
    reasons.append('These checks do not prove ownership, authenticity, brand/model or stated condition')
    return VerificationResponse(
        accepted=accepted, outcome=outcome,
        confidence=round(sum(matching_scores) / len(matching_scores), 4) if matching_scores else 0,
        labels=sorted(labels), reasons=reasons, adapter=CONTRACT,
        model_versions={key: value for key, value in {
            'objectDetection': status['detectorVersion'],
            'riskClassifier': status['riskClassifierVersion'],
        }.items() if value},
        quality={'images': qualities, 'duplicateCount': duplicates,
                 'duplicateScope': 'within_submission', 'method': 'perceptual_dhash'},
        extracted_fields=fields, risk_indicators=list(dict.fromkeys(indicators)),
    )
