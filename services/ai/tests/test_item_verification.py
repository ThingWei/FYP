"""Controlled detector fixtures test routing/gates, not model accuracy."""

import json
from types import SimpleNamespace

import numpy as np
import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.schemas import VerificationRequest
from app.services import item_verification as items
from app.services.image_intelligence import _risk_probability


class Scalar:
    def __init__(self, value):
        self.value = value

    def item(self):
        return self.value


class Detector:
    def __init__(self, names, detected=None, score=0.91, fail=False):
        self.names = dict(enumerate(names))
        self.detected = detected or [names[0]]
        self.score, self.fail = score, fail

    def predict(self, image, **kwargs):
        if self.fail:
            raise RuntimeError('fixture inference failure')
        boxes = [SimpleNamespace(cls=Scalar(list(self.names.values()).index(label)),
                                 conf=Scalar(self.score)) for label in self.detected]
        return [SimpleNamespace(boxes=boxes, names=self.names)]


def verify(monkeypatch, category='Vehicles', subcategory='Cars', detector=None,
           risk=True, score=0.1, hashes=None, poor=False, errors=None):
    detector = detector or Detector(['car', 'person'])
    monkeypatch.setattr(items, 'models_status', lambda: (detector, object() if risk else None, {
        'detectorAvailable': True, 'detectorSource': 'general_pretrained',
        'riskClassifierAvailable': risk, 'detectorVersion': 'fixture',
        'riskClassifierVersion': 'fixture' if risk else None,
    }))
    request = VerificationRequest(expected_category=category, expected_subcategory=subcategory,
                                  expected_condition='Good')
    decoded = [(None, np.full((10, 10, 3), i, dtype=np.uint8)) for i in range(3)]
    quality = lambda _: dict(isBlurry=poor, isTooDark=False, isTooBright=False,
                            hasUsableResolution=True)
    hashes = hashes or ['a', 'b', 'c']
    return items.verify(request, decoded, errors or [], quality,
                        lambda image: hashes[int(image[0, 0, 0])], lambda *_: score)


@pytest.mark.parametrize('category,subcategory,label', [
    ('Vehicles', 'Cars', 'car'), ('vehicles', 'CARS', 'Car'),
    ('Vehicles', 'Cars', 'cars'), ('Devices', 'Cameras', 'cameras'),
    ('Vehicles', 'Motorcycles', 'motorcycle'), ('Vehicles', 'Bicycles', 'bicycle'),
    ('Devices', 'Smartphones', 'cell phone'), ('Devices', 'Computers', 'laptop'),
    ('Devices', 'Cameras', 'camera'), ('Devices', 'Audio', 'speaker'),
    ('Devices', 'Gaming', 'gaming console'), ('Devices', 'Other devices', 'tv'),
    ('Vehicles', 'Other vehicles', 'truck'), ('Equipment', 'Tools', 'drill'),
    ('Equipment', 'Sports equipment', 'tennis racket'),
    ('Equipment', 'Event equipment', 'chair'), ('Equipment', 'Other equipment', 'generator'),
    ('Books', 'Textbooks', 'book'), ('Books', 'Reference books', 'book'),
    ('Books', 'Fiction', 'book'), ('Books', 'Other books', 'book'),
    ('Clothing', 'Formal wear', 'suit'), ('Clothing', 'Costumes', 'costume'),
    ('Clothing', 'Traditional wear', 'baju kurung'), ('Clothing', 'Other clothing', 'shirt'),
])
def test_domain_aliases_are_category_aware(monkeypatch, category, subcategory, label):
    result = verify(monkeypatch, category, subcategory, Detector([label, 'person']))
    assert result.extracted_fields['categoryMatched'] is True
    assert result.outcome == 'approved_candidate'
    assert result.extracted_fields['authenticityVerified'] is False
    assert result.extracted_fields['adminReviewRequired'] is True
    assert result.extracted_fields['conditionAssessment'] == 'not_assessed'


def test_unrelated_high_confidence_person_cannot_match_car(monkeypatch):
    result = verify(monkeypatch, detector=Detector(['car', 'person'], ['person']))
    assert result.extracted_fields['categoryMatched'] is False
    assert result.confidence == 0
    assert result.outcome == 'warning'


def test_car_is_not_motorcycle_and_label_substrings_are_not_matches(monkeypatch):
    result = verify(monkeypatch, subcategory='Motorcycles',
                    detector=Detector(['motorcycle', 'car'], ['car']))
    assert result.accepted is False
    assert result.extracted_fields['categoryMatched'] is False
    result = verify(monkeypatch, detector=Detector(['carpet']))
    assert result.extracted_fields['categorySupport'] == 'unsupported'
    assert result.extracted_fields['categoryMatched'] is None


def test_unsupported_camera_is_not_a_false_mismatch(monkeypatch):
    result = verify(monkeypatch, 'Devices', 'Cameras', Detector(['car', 'person']))
    assert result.outcome == 'manual_review'
    assert result.extracted_fields['categoryMatched'] is None
    assert not result.risk_indicators


@pytest.mark.parametrize('options', [
    {'risk': False}, {'score': 0.9}, {'score': float('nan')},
    {'hashes': ['a', 'a', 'a']}, {'poor': True},
    {'detector': Detector(['car'], fail=True)}, {'errors': ['Invalid image']},
    {'detector': Detector(['car'], score=0.1)},
])
def test_partial_models_quality_risk_duplicates_never_pass(monkeypatch, options):
    result = verify(monkeypatch, **options)
    assert result.accepted is False
    assert result.outcome != 'approved_candidate'
    assert result.extracted_fields['authenticityVerified'] is False


def test_missing_and_corrupt_models_are_explicit(monkeypatch, tmp_path):
    for content in (None, b'corrupt model'):
        detector = tmp_path / 'detector.pt'
        risk = tmp_path / 'risk.pt'
        if content:
            detector.write_bytes(content)
            risk.write_bytes(content)
        monkeypatch.setenv('YOLO_MODEL_PATH', str(detector))
        monkeypatch.setenv('IMAGE_RISK_MODEL_PATH', str(risk))
        d, r, status = items.models_status()
        assert d is None and r is None
        assert status['detectorSource'] == 'unavailable'


def test_existing_local_general_detector_loads_without_download(monkeypatch, tmp_path):
    if not (items.ROOT / 'yolov8n.pt').is_file():
        pytest.skip('Optional local pretrained artifact is not distributed in Git')
    pretrained = items.ROOT / 'yolov8n.pt'
    monkeypatch.setattr(items, 'ROOT', tmp_path)
    monkeypatch.delenv('YOLO_MODEL_PATH', raising=False)
    monkeypatch.setenv('ITEM_ALLOW_PRETRAINED_DETECTOR', 'true')
    monkeypatch.setenv('ITEM_PRETRAINED_YOLO_PATH', str(pretrained))
    monkeypatch.setenv('IMAGE_RISK_MODEL_PATH', str(tmp_path / 'missing.pt'))
    detector, risk, status = items.models_status()
    assert detector is not None
    assert status['detectorSource'] == 'general_pretrained'
    assert 'car' in detector.names.values()
    assert risk is None


def test_risk_contract_rejects_document_and_generic_classifiers(tmp_path):
    import torch
    metadata = {'contract': items.RISK_CONTRACT, 'architecture': 'efficientnet_b0',
                'classes': ['normal', 'risky'], 'preprocessing': 'rgb-224-imagenet-v1',
                'purpose': 'item_photo_risk_assistance'}
    assert items.valid_risk_metadata(metadata)
    assert not items.valid_risk_metadata({**metadata, 'purpose': 'document_risk'})
    assert not items.valid_risk_metadata({**metadata, 'classes': ['risky', 'normal']})
    model = torch.nn.Sequential(torch.nn.AdaptiveAvgPool2d(1), torch.nn.Flatten(),
                                torch.nn.Linear(3, 2))
    path = tmp_path / 'risk.pt'
    torch.jit.script(model).save(str(path), _extra_files={'metadata.json': json.dumps(metadata)})
    loaded, _ = items.load_risk(path, path.stat().st_mtime_ns)
    score = _risk_probability(loaded, np.full((480, 640, 3), 100, dtype=np.uint8))
    assert 0 <= score <= 1
    torch.jit.script(model).save(str(path))
    items.load_risk.cache_clear()
    with pytest.raises(Exception):
        items.load_risk(path, path.stat().st_mtime_ns)


def test_endpoint_keeps_rejection_and_advisory_contract():
    response = TestClient(app).post('/verify/item', json={
        'images': [], 'expected_category': 'Vehicles', 'expected_subcategory': 'Cars',
    })
    assert response.status_code == 200
    result = response.json()
    assert result['outcome'] == 'rejected'
    assert result['extracted_fields']['expectedSubcategory'] == 'Cars'


def test_one_high_score_view_does_not_become_whole_submission_confidence(monkeypatch):
    class OneViewDetector(Detector):
        def predict(self, image, **kwargs):
            self.detected = ['car'] if int(image[0, 0, 0]) == 0 else ['person']
            return super().predict(image, **kwargs)
    result = verify(monkeypatch, detector=OneViewDetector(['car', 'person'], score=0.97))
    assert result.confidence == pytest.approx(0.97 / 3, abs=0.0001)
    assert result.extracted_fields['matchingViewCount'] == 1
    assert result.extracted_fields['submittedViewCount'] == 3
    assert result.extracted_fields['categoryMatchStatus'] == 'partial_views'
    assert result.extracted_fields['categoryMatched'] is False
    assert result.accepted is False
    assert any('wallpapers' in reason for reason in result.reasons)


def test_per_photo_boxes_are_normalized_for_inspection(monkeypatch):
    class BoxDetector(Detector):
        def predict(self, image, **kwargs):
            result = super().predict(image, **kwargs)
            for box in result[0].boxes:
                box.xyxy = np.array([[1, 2, 9, 8]])
            return result
    result = verify(monkeypatch, detector=BoxDetector(['car']))
    for photo in result.extracted_fields['images']:
        assert photo['imageWidth'] == 10
        assert photo['imageHeight'] == 10
        assert photo['detections'][0]['boundingBox'] == [0.1, 0.2, 0.9, 0.8]
        assert 'quality' in photo
