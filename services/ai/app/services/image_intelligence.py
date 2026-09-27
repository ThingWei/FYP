import base64
import os
import re
from functools import lru_cache
from pathlib import Path
from typing import Any

from ..schemas import VerificationRequest, VerificationResponse


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
    return {
        'width': width,
        'height': height,
        'blurVariance': round(blur, 2),
        'brightness': round(brightness, 2),
        'isBlurry': blur < 75,
        'isTooDark': brightness < 40,
        'isTooBright': brightness > 225,
        'hasUsableResolution': width >= 640 and height >= 400,
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
        return spacy.blank('xx')
    except ImportError:
        return None


def _extract_document_fields(text: str) -> dict[str, Any]:
    normalized = re.sub(r'\s+', ' ', text).strip()
    fields: dict[str, Any] = {}
    mykad = re.search(r'\b\d{6}-?\d{2}-?\d{4}\b', normalized)
    passport = re.search(r'\b[A-Z]\d{7,9}\b', normalized.upper())
    licence = re.search(r'\b[A-Z]{1,3}\d{5,9}\b', normalized.upper())
    expiry = re.search(r'(?:EXPIRY|EXPIRES|VALID UNTIL)\s*[:\-]?\s*(\d{1,2}[./-]\d{1,2}[./-]\d{2,4})', normalized.upper())
    if mykad:
        fields['identityNumber'] = mykad.group(0)
        fields['documentType'] = 'mykad'
    elif passport:
        fields['identityNumber'] = passport.group(0)
        fields['documentType'] = 'passport'
    elif licence:
        fields['identityNumber'] = licence.group(0)
        fields['documentType'] = 'driving_licence'
    if expiry:
        fields['expiryDateText'] = expiry.group(1)
    nlp = _nlp()
    if nlp and normalized:
        fields['tokenCount'] = len([token for token in nlp(normalized) if not token.is_space])
    return fields


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
    def verify_document(self, request: VerificationRequest) -> VerificationResponse:
        decoded, errors = _decode_images(request)
        if not decoded:
            return VerificationResponse(
                accepted=False, outcome='unavailable', confidence=0,
                reasons=errors or ['At least one identity-document image is required'],
                adapter='opencv-easyocr-spacy-v1',
            )
        reader = _ocr_reader()
        if reader is None:
            return VerificationResponse(
                accepted=False, outcome='unavailable', confidence=0,
                reasons=['EasyOCR runtime or language models are unavailable'],
                adapter='opencv-easyocr-spacy-v1', quality=_quality(decoded[0][1]),
            )
        quality = _quality(decoded[0][1])
        results = reader.readtext(_ocr_preprocess(decoded[0][1]), detail=1, paragraph=False)
        text = ' '.join(str(item[1]) for item in results)
        ocr_confidence = sum(float(item[2]) for item in results) / len(results) if results else 0
        fields = _extract_document_fields(text)
        reasons = list(errors)
        if not fields.get('identityNumber'):
            reasons.append('A supported identity number was not detected')
        if quality['isBlurry'] or quality['isTooDark'] or quality['isTooBright']:
            reasons.append('Document image quality requires manual review')
        profile_match = None
        if request.profile_name:
            expected_tokens = {part.lower() for part in request.profile_name.split() if len(part) > 1}
            observed = text.lower()
            profile_match = bool(expected_tokens) and all(part in observed for part in expected_tokens)
            fields['profileNameMatched'] = profile_match
            if not profile_match:
                reasons.append('Profile name was not matched confidently in OCR text')
        approved = bool(fields.get('identityNumber')) and not reasons and ocr_confidence >= 0.7
        return VerificationResponse(
            accepted=approved,
            outcome='approved' if approved else 'manual_review',
            confidence=round(max(0, min(1, ocr_confidence)), 4),
            labels=[fields.get('documentType', 'unclassified_document')],
            reasons=reasons or ['Document signals passed automated checks'],
            adapter='opencv-easyocr-spacy-v1',
            model_versions={'ocr': 'easyocr-1.7', 'nlp': 'spacy-regex-v1'},
            quality=quality, ocr_text=text, extracted_fields=fields,
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
