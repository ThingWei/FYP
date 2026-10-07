"""Capture/submission parity tests; synthetic pixels only, no identity images."""

from types import SimpleNamespace

import cv2
import numpy as np
import pytest

from app.schemas import DocumentFrameRequest, VerificationRequest
from app.services import image_intelligence as intelligence


def sharp_image(width=720, height=1280):
    return np.random.default_rng(42).integers(60, 210, (height, width, 3), dtype=np.uint8)


def install_detector(monkeypatch, image, confidence=0.98, box=None, side='front'):
    monkeypatch.setattr(intelligence, '_decode_images', lambda request: ([(None, image)], []))
    height, width = image.shape[:2]
    guide = intelligence._document_guide(width, height)
    normalized = box if box is not None else [guide[0] + 0.01, guide[1] + 0.01,
                                              guide[2] - 0.01, guide[3] - 0.01]
    class SyntheticBoxes(SimpleNamespace):
        def __len__(self):
            return 1

    boxes = SyntheticBoxes(conf=np.array([confidence]), cls=np.array([0 if side == 'front' else 1]), xyxy=np.array([[
        normalized[0] * width, normalized[1] * height,
        normalized[2] * width, normalized[3] * height,
    ]]))
    prediction = SimpleNamespace(boxes=boxes, names={0: 'mykad_front', 1: 'mykad_back'})
    model = SimpleNamespace(predict=lambda *args, **kwargs: [prediction])
    monkeypatch.setattr(intelligence, '_document_yolo_model', lambda: (model, None))
    # Stop after quality checking; these tests do not evaluate OCR/authenticity.
    monkeypatch.setattr(intelligence, '_ocr_reader', lambda: None)


def inspect(expected_side=None, validate_capture=False):
    return intelligence.ImageIntelligenceService().inspect_document_frame(
        DocumentFrameRequest(content_base64='synthetic', expected_type='mykad',
                             expected_side=expected_side, validate_capture=validate_capture))


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
    assert frame.adapter == 'opencv-document-yolo-v3'
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
    assert result.adapter == 'opencv-document-yolo-v3'
    assert result.guide_box is not None


def install_ocr(monkeypatch, text, confidence=0.95):
    monkeypatch.setattr(intelligence, '_ocr_reader', lambda: SimpleNamespace(
        readtext=lambda *args, **kwargs: [(None, line, confidence) for line in text.splitlines()]))
    monkeypatch.setattr(intelligence, '_nlp', lambda: None)


@pytest.mark.parametrize('side,expected', [('front', 'back'), ('back', 'front')])
def test_live_side_label_mismatch_never_becomes_ready(monkeypatch, side, expected):
    install_detector(monkeypatch, sharp_image(), side=side)
    monkeypatch.setattr(intelligence, '_ocr_reader', lambda: pytest.fail('Live frame must not load OCR'))
    result = inspect(expected)
    assert result.detected_side == side
    assert result.ready is False
    assert f'Scan the {expected} instead' in result.guidance


@pytest.mark.parametrize('side,text,status', [
    ('front', 'VISA\n4111 1111 1111 1111\nVALID THRU 12/30', 'wrong_document'),
    ('back', 'AUTHORISED SIGNATURE\nCVV 123', 'wrong_document'),
    ('front', 'MALAYSIA\nPENDAFTARAN NEGARA\nALAMAT TEST', 'unconfirmed'),
    ('front', 'MYKAD\n900101-07-1234\nKETUA PENGARAH PENDAFTARAN NEGARA', 'wrong_side'),
    ('back', 'MYKAD\n900101-07-1234\nTEST USER', 'wrong_side'),
    ('front', 'STUDENT CARD\n900101-07-1234', 'wrong_document'),
    ('front', 'TEST USER\n900101-07-1234', 'unconfirmed'),
    ('back', 'TEST USER\nMALAYSIA', 'unconfirmed'),
])
def test_high_yolo_confidence_never_accepts_wrong_or_unknown_capture(monkeypatch, side, text, status):
    install_detector(monkeypatch, sharp_image(), side=side)
    install_ocr(monkeypatch, text)
    result = inspect(side, validate_capture=True)
    assert result.confidence == 0.98
    assert result.ready is False
    assert result.capture_validation['accepted'] is False
    assert result.capture_validation['status'] == status
    assert '4111 1111 1111 1111' not in str(result.model_dump())
    assert 'CVV 123' not in str(result.model_dump())


@pytest.mark.parametrize('side,text', [
    ('front', 'MALAYSIA\nMYKAD\n900101-07-1234\nTEST USER'),
    ('back', 'MALAYSIA\nKETUA PENGARAH PENDAFTARAN NEGARA'),
    ('back', 'MYKAD\nKETUA PENGARAH PENDAFTARAN NEGARA'),
])
def test_positive_matching_capture_can_be_used_but_not_identity_approved(monkeypatch, side, text):
    install_detector(monkeypatch, sharp_image(), side=side)
    install_ocr(monkeypatch, text)
    result = inspect(side, validate_capture=True)
    assert result.ready is True
    assert result.detected_side == side
    assert result.capture_validation['status'] == 'validated'
    assert result.capture_validation['accepted'] is True
    assert result.capture_validation['authenticityVerified'] is False


def test_ocr_outage_missing_side_and_unknown_class_cannot_bypass_capture_gate(monkeypatch):
    install_detector(monkeypatch, sharp_image())
    result = inspect('front', validate_capture=True)
    assert result.ready is False
    assert result.capture_validation['status'] == 'unavailable'
    install_ocr(monkeypatch, 'MYKAD\n900101-07-1234')
    result = inspect(validate_capture=True)
    assert result.ready is False
    assert result.capture_validation['accepted'] is False
    class UnknownBoxes(SimpleNamespace):
        def __len__(self):
            return 1
    model = SimpleNamespace(predict=lambda *args, **kwargs: [SimpleNamespace(
        names={0: 'document'}, boxes=UnknownBoxes(conf=np.array([.99]), cls=np.array([0]),
                                                 xyxy=np.array([[100, 100, 600, 900]])))])
    monkeypatch.setattr(intelligence, '_document_yolo_model', lambda: (model, None))
    assert inspect('front', validate_capture=True).ready is False


def test_capture_ocr_failure_is_explicit_and_never_releases_image(monkeypatch):
    install_detector(monkeypatch, sharp_image())
    def fail(*args, **kwargs):
        raise RuntimeError('Synthetic OCR failure')
    monkeypatch.setattr(intelligence, '_ocr_reader', lambda: SimpleNamespace(readtext=fail))
    result = inspect('front', validate_capture=True)
    assert result.ready is False
    assert result.capture_validation['status'] == 'unavailable'


def test_low_confidence_positive_heading_is_not_enough_for_use_image(monkeypatch):
    install_detector(monkeypatch, sharp_image())
    install_ocr(monkeypatch, 'MYKAD\n900101-07-1234', confidence=0.2)
    result = inspect('front', validate_capture=True)
    assert result.ready is False
    assert result.capture_validation['status'] == 'unconfirmed'
