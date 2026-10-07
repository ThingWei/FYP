"""Capture/submission parity tests; synthetic pixels only, no identity images."""

from types import SimpleNamespace

import cv2
import numpy as np
import pytest

from app.schemas import DocumentFrameRequest, VerificationRequest
from app.services import image_intelligence as intelligence


def sharp_image(width=720, height=1280):
    return np.random.default_rng(42).integers(60, 210, (height, width, 3), dtype=np.uint8)


def install_detector(monkeypatch, image, confidence=0.98, box=None):
    monkeypatch.setattr(intelligence, '_decode_images', lambda request: ([(None, image)], []))
    height, width = image.shape[:2]
    guide = intelligence._document_guide(width, height)
    normalized = box if box is not None else [guide[0] + 0.01, guide[1] + 0.01,
                                              guide[2] - 0.01, guide[3] - 0.01]
    class SyntheticBoxes(SimpleNamespace):
        def __len__(self):
            return 1

    boxes = SyntheticBoxes(conf=np.array([confidence]), xyxy=np.array([[
        normalized[0] * width, normalized[1] * height,
        normalized[2] * width, normalized[3] * height,
    ]]))
    prediction = SimpleNamespace(boxes=boxes)
    model = SimpleNamespace(predict=lambda *args, **kwargs: [prediction])
    monkeypatch.setattr(intelligence, '_document_yolo_model', lambda: (model, None))
    # Stop after quality checking; these tests do not evaluate OCR/authenticity.
    monkeypatch.setattr(intelligence, '_ocr_reader', lambda: None)


def inspect():
    return intelligence.ImageIntelligenceService().inspect_document_frame(
        DocumentFrameRequest(content_base64='synthetic', expected_type='mykad'))


def submit():
    return intelligence.ImageIntelligenceService().verify_document(
        VerificationRequest(expected_type='mykad'))


def test_resolution_accepts_rotated_copy_equally():
    landscape = sharp_image(640, 480)
    portrait = np.transpose(landscape, (1, 0, 2)).copy()
    for image in (landscape, portrait):
        assert intelligence._quality(image)['hasUsableResolution'] is True
        assert intelligence._quality_issues(intelligence._quality(image)) == []
    assert intelligence._quality(sharp_image(639, 400))['hasUsableResolution'] is False
    assert intelligence._quality(sharp_image(640, 399))['hasUsableResolution'] is False


@pytest.mark.parametrize(('width', 'height'), [(720, 1280), (1280, 720), (480, 640)])
def test_guide_ratio_and_fit_in_both_orientations(width, height):
    box = intelligence._document_guide(width, height)
    assert ((box[2] - box[0]) * width) / ((box[3] - box[1]) * height) == pytest.approx(1.586)
    assert 0 <= box[0] < box[2] <= 1
    assert 0 <= box[1] < box[3] <= 1
    assert box[0] + box[2] == pytest.approx(1)
    assert box[1] + box[3] == pytest.approx(1)


@pytest.mark.parametrize(('kind', 'expected'), [
    ('blur', 'blur'), ('dark', 'too_dark'), ('bright', 'too_bright'),
    ('glare', 'glare'), ('small', 'low_resolution'),
])
def test_high_detection_confidence_never_bypasses_quality(monkeypatch, kind, expected):
    image = sharp_image()
    if kind == 'blur':
        image = cv2.GaussianBlur(image, (31, 31), 8)
    elif kind == 'dark':
        image //= 8
    elif kind == 'bright':
        image = np.full_like(image, 235)
    elif kind == 'glare':
        image[:500] = 255
    elif kind == 'small':
        image = sharp_image(320, 480)
    install_detector(monkeypatch, image)
    frame, final = inspect(), submit()
    assert frame.confidence == 0.98
    assert frame.ready is False
    assert final.outcome == 'rescan_required' and final.accepted is False
    codes = {issue['code'] for issue in frame.quality['issues']}
    assert expected in codes
    assert frame.quality['issues'] == final.quality['images'][0]['issues']
    assert all('Image 1:' in reason for reason in final.reasons)
    assert 'One or more images' not in ' '.join(final.reasons)


def test_good_aligned_portrait_reaches_ocr_not_resolution_rescan(monkeypatch):
    install_detector(monkeypatch, sharp_image())
    frame, final = inspect(), submit()
    assert frame.ready is True
    assert frame.adapter == 'opencv-document-yolo-v2'
    assert frame.guidance == 'Ready to capture'
    assert frame.quality['issues'] == []
    assert final.outcome == 'unavailable'  # Our deliberately missing OCR, not quality.
    assert final.quality['images'][0]['issues'] == []


def test_bad_alignment_is_not_ready_even_with_good_quality(monkeypatch):
    install_detector(monkeypatch, sharp_image(), box=[0, 0.1, 0.7, 0.5])
    assert inspect().ready is False


def test_front_back_messages_identify_only_the_failed_side(monkeypatch):
    front, back = sharp_image(), np.full((1280, 720, 3), 128, dtype=np.uint8)
    monkeypatch.setattr(intelligence, '_decode_images', lambda request: ([(None, front), (None, back)], []))
    final = submit()
    assert final.outcome == 'rescan_required'
    assert final.reasons == [
        'MyKad back: Image is blurry. Clean the lens, let the camera focus and hold steady.']
    assert final.quality['images'][0]['issues'] == []


def test_missing_detector_remains_explicit(monkeypatch):
    install_detector(monkeypatch, sharp_image())
    monkeypatch.setattr(intelligence, '_document_yolo_model', lambda: (None, None))
    result = inspect()
    assert result.available is False and result.ready is False
    assert result.adapter == 'opencv-document-yolo-v2'
    assert result.guide_box is not None
