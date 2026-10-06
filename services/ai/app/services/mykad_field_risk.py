"""Advisory-only synthetic-risk inference on YOLO-selected MyKad fields.

No uploaded image/crop is saved. Low scores never establish authenticity.
"""

import json
import math
import os
from functools import lru_cache
from pathlib import Path
from threading import Lock

from .document_risk_preprocessing import field_tensor, parse_region, validate_field_contract


ELIGIBLE_FIELDS = {
    'front_identity_number', 'front_name', 'front_address',
    'back_identity_number', 'back_serial_number',
}
REVIEW_NOTICE = (
    'Synthetic-trained field risk is advisory only, not proof of MyKad authenticity; '
    'administrator review is required.'
)
_detector_lock = Lock()


def configured_paths():
    return (
        Path(os.getenv('MYKAD_FIELD_MODEL_PATH', 'models/mykad_fields_front_back_yolo.pt')),
        Path(os.getenv('MYKAD_FIELD_RISK_MODEL_PATH', 'models/document_risk_synthetic_fields_v2_efficientnet.pt')),
    )


def enabled():
    return os.getenv('MYKAD_FIELD_RISK_ENABLED', 'true').strip().lower() == 'true'


def availability():
    detector, classifier = configured_paths()
    return {'enabled': enabled(), 'detectorPresent': detector.is_file(),
            'classifierPresent': classifier.is_file(), 'advisoryOnly': True,
            'requiresAdminReview': True, 'contractValidation': 'required_on_first_inference'}


@lru_cache(maxsize=2)
def _load_bundle(detector_path, classifier_path):
    if not Path(detector_path).is_file() or not Path(classifier_path).is_file():
        raise FileNotFoundError('Field research artifacts are unavailable')
    import torch
    extra = {'renthub_provenance.json': ''}
    classifier = torch.jit.load(classifier_path, map_location='cpu', _extra_files=extra).eval()
    provenance = json.loads(extra['renthub_provenance.json'])
    contract = validate_field_contract(provenance)
    from ultralytics import YOLO
    detector = YOLO(detector_path)
    names = set(detector.names.values()) if isinstance(detector.names, dict) else set(detector.names)
    if not ELIGIBLE_FIELDS.issubset(names):
        raise ValueError('Combined MyKad field classes are missing')
    return detector, classifier, contract


def _threshold():
    threshold = float(os.getenv('MYKAD_FIELD_DETECTION_THRESHOLD', '0.5'))
    if not math.isfinite(threshold) or not 0 < threshold <= 1:
        raise ValueError('Invalid field detection threshold')
    return threshold


def analyse_fields(images):
    detector_path, classifier_path = configured_paths()
    evidence = {
        'status': 'unavailable', 'sourceType': 'synthetic_manipulation',
        'purpose': 'synthetic_manipulation_risk_research',
        'advisoryOnly': True, 'requiresAdminReview': True,
        'riskScore': None, 'signal': 'unavailable',
        'aggregation': 'maximum_scored_field_uncalibrated', 'signalThreshold': 0.5,
        'coverageComplete': False, 'scoredFieldCount': 0, 'images': [],
        'models': {'fieldDetector': detector_path.name, 'fieldRiskClassifier': classifier_path.name},
        'warnings': [REVIEW_NOTICE,
                     'Detected-field aggregation has not been independently calibrated or evaluated end to end.'],
    }
    if not enabled():
        evidence['status'] = 'disabled'
        evidence['warnings'].append('MyKad field-risk analysis is disabled; manual review remains required.')
        return evidence
    try:
        threshold = _threshold()
        detector, classifier, contract = _load_bundle(str(detector_path), str(classifier_path))
    except Exception:
        # Never expose artifact internals, paths or library tracebacks in stored KYC evidence.
        evidence['warnings'].append('MyKad field models are missing, incompatible or failed to load; manual review required.')
        return evidence
    import cv2
    import torch
    from PIL import Image

    for index, image in enumerate(images):
        side = 'front' if index == 0 else 'back' if index == 1 else 'extra'
        summary = {'index': index, 'side': side, 'fields': [],
                   'missingRequiredFields': [f'{side}_identity_number'] if side != 'extra' else [],
                   'analysisError': False}
        evidence['images'].append(summary)
        if side == 'extra':
            summary['analysisError'] = True
            continue
        try:
            rgb = Image.fromarray(cv2.cvtColor(image, cv2.COLOR_BGR2RGB))
            # Ultralytics predictors retain mutable state between calls.
            with _detector_lock:
                result = detector.predict(image, verbose=False, conf=threshold, max_det=30)[0]
            candidates = {}
            for box in result.boxes:
                label = str(result.names[int(box.cls.item())])
                confidence = float(box.conf.item())
                if label not in ELIGIBLE_FIELDS or not label.startswith(f'{side}_') or \
                        not math.isfinite(confidence) or not threshold <= confidence <= 1:
                    continue
                try:
                    region = parse_region(box.xyxy[0].tolist(), rgb.size)
                except ValueError:
                    summary['analysisError'] = True
                    continue
                if region[2] - region[0] < 8 or region[3] - region[1] < 6:
                    continue
                if label not in candidates or confidence > candidates[label][0]:
                    candidates[label] = (confidence, region)
            for label, (confidence, region) in sorted(candidates.items()):
                tensor = field_tensor(rgb, region, contract).unsqueeze(0)
                with torch.inference_mode():
                    logits = classifier(tensor)
                    if tuple(logits.shape) != (1, 2) or not bool(torch.isfinite(logits).all()):
                        raise ValueError('Invalid field classifier output')
                    score = float(torch.softmax(logits, dim=1)[0, 1])
                summary['fields'].append({'field': label, 'detectionConfidence': round(confidence, 4),
                                          'riskScore': round(score, 4),
                                          'signal': 'elevated_signal' if score >= 0.5 else 'no_elevated_signal'})
            summary['missingRequiredFields'] = [name for name in summary['missingRequiredFields']
                                                if name not in {f['field'] for f in summary['fields']}]
        except Exception:
            summary['analysisError'] = True
    scores = [f['riskScore'] for image in evidence['images'] for f in image['fields']]
    evidence['scoredFieldCount'] = len(scores)
    evidence['coverageComplete'] = len(images) == 2 and all(
        not image['missingRequiredFields'] and not image['analysisError'] for image in evidence['images'])
    if scores:
        evidence['riskScore'] = max(scores)
        evidence['signal'] = 'elevated_signal' if any(
            f['signal'] == 'elevated_signal' for image in evidence['images'] for f in image['fields']
        ) else 'no_elevated_signal'
        evidence['status'] = 'available' if evidence['coverageComplete'] else 'partial'
    if not evidence['coverageComplete']:
        evidence['warnings'].append('Front/back identity-field coverage is incomplete or inference failed; do not interpret a low score as clearance.')
    return evidence
