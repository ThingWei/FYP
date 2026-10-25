"""Controlled detector fixtures test routing/gates, not model accuracy."""

import json
import re
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.schemas import VerificationRequest
from app.services import item_verification as items
from app.services.image_intelligence import _risk_probability


def test_item_risk_preprocessing_matches_training_rgb_resize_and_normalization(tmp_path):
    import torch
    from PIL import Image
    from torchvision import transforms
    from app.training.train_image_risk import ManifestImages

    rgb = np.random.default_rng(42).integers(0, 256, (317, 539, 3), dtype=np.uint8)
    path = tmp_path / 'fixture.png'
    Image.fromarray(rgb).save(path)
    transform = transforms.Compose([
        transforms.Resize((224, 224)), transforms.ToTensor(),
        transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
    ])
    expected, _ = ManifestImages([{'path': path, 'label': 'normal'}], transform)[0]

    class Capture(torch.nn.Module):
        def forward(self, inputs):
            self.inputs = inputs.clone()
            return torch.tensor([[0., 1.]])

    model = Capture()
    probability = items.risk_probability(model, rgb[:, :, ::-1])
    assert torch.equal(model.inputs[0], expected)
    assert probability == pytest.approx(float(torch.softmax(torch.tensor([0., 1.]), dim=0)[1]))


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
           risk=True, score=0.1, hashes=None, poor=False, errors=None, product_type=None):
    detector = detector or Detector(['car', 'person'])
    monkeypatch.setattr(items, 'models_status', lambda: (detector, object() if risk else None, {
        'detectorAvailable': True, 'detectorSource': 'general_pretrained',
        'riskClassifierAvailable': risk, 'detectorVersion': 'fixture',
        'riskClassifierVersion': 'fixture' if risk else None,
    }))
    request = VerificationRequest(expected_category=category, expected_subcategory=subcategory,
                                  expected_condition='Good', expected_product_type=product_type)
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
    assert result.extracted_fields['categoryMatched'] is None
    assert result.confidence == 0
    assert result.outcome == 'manual_review'


def test_car_is_not_motorcycle_and_label_substrings_are_not_matches(monkeypatch):
    result = verify(monkeypatch, subcategory='Motorcycles',
                    detector=Detector(['motorcycle', 'car'], ['car']))
    assert result.accepted is False
    assert result.extracted_fields['categoryMatched'] is None
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
    assert result.extracted_fields['categoryMatched'] is None
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


ALL_DOMAINS = [(category, subcategory, sorted(labels)[0])
               for category, domains in items.DOMAINS.items()
               for subcategory, labels in domains.items()]


def test_coverage_registry_matches_every_live_specific_category():
    # Guard taxonomy drift without making the AI import Express or vice versa.
    source = (items.ROOT.parents[1] / 'services/api/src/modules/catalog/catalog.coverage.js').read_text()
    canonical = {(items.normalize(c), items.normalize(s)) for c, s in
                 re.findall(r"category: '([^']+)', subcategory: '([^']+)'", source)}
    assert {(c, s) for c, s, _ in ALL_DOMAINS} == canonical
    assert len(canonical) == 22


@pytest.mark.parametrize('category,subcategory,label', ALL_DOMAINS)
def test_every_domain_has_honest_coverage_and_detail_view_policy(monkeypatch, category, subcategory, label):
    class OverviewDetector(Detector):
        def predict(self, image, **kwargs):
            self.detected = [label] if int(image[0, 0, 0]) == 0 else ['person']
            return super().predict(image, **kwargs)
    result = verify(monkeypatch, category, subcategory, OverviewDetector([label, 'person']))
    fields = result.extracted_fields
    assert result.outcome == 'manual_review'
    assert result.accepted is False
    assert fields['categoryMatched'] is None
    assert fields['matchingViewCount'] == 1
    assert fields['unconfirmedViewCount'] == 2
    assert fields['detailViewsVerified'] is False
    assert fields['categoryCoverage']['allProductsCovered'] is False
    assert fields['categoryCoverage']['specificCategoryVerified'] is False
    assert fields['photoGuidance']
    assert not result.risk_indicators  # No invented blur/visibility failure.
    assert fields['images'][1]['objectEvidenceStatus'] == 'not_detected'


@pytest.mark.parametrize('category,subcategory,label', ALL_DOMAINS)
def test_every_domain_without_labels_remains_manual_not_mismatched(monkeypatch, category, subcategory, label):
    result = verify(monkeypatch, category, subcategory, Detector(['person']))
    assert result.outcome == 'manual_review'
    assert result.extracted_fields['categoryMatched'] is None
    assert result.extracted_fields['categoryCoverage']['status'] == 'no_matching_labels'
    assert not result.risk_indicators
    assert not result.accepted


def test_unknown_domains_and_generic_equipment_label_do_not_invent_support(monkeypatch):
    for category, subcategory in [('Equipment', 'Other equipment'), ('Devices', 'New category'),
                                 ('Devices', ''), ('Services', 'Photography')]:
        result = verify(monkeypatch, category, subcategory, Detector(['equipment', 'camera']))
        assert result.extracted_fields['categorySupport'] == 'unsupported'
        assert result.extracted_fields['categoryMatched'] is None
        assert not result.accepted


@pytest.mark.parametrize('turns', [1, 2, 3])
def test_generic_orientation_retry_maps_boxes_to_original_and_does_not_invent_views(turns):
    original = np.arange(6 * 10 * 3, dtype=np.uint8).reshape(6, 10, 3)

    class RotatedDetector(Detector):
        def predict(self, image, **kwargs):
            result = super().predict(image, **kwargs)
            if not np.array_equal(image, np.rot90(original, turns)):
                result[0].boxes = []
            else:
                height, width = image.shape[:2]
                result[0].boxes[0].xyxy = np.array([[width * .1, height * .2, width * .5, height * .8]])
            return result
    # Not book-specific: exercise the same strategy for every declared domain.
    for _, _, label in ALL_DOMAINS:
        detector = RotatedDetector([label])
        detections, attempts, failures = items.detect_photo(original, {label}, [(detector, 'fixture', 'v1')])
        assert failures == 0
        assert 2 <= attempts <= 4
        assert len(detections) == 1
        assert detections[0]['rotationDegrees'] == turns * 90
        expected = {1: [.2, .1, .8, .5], 2: [.5, .2, .9, .8], 3: [.2, .5, .8, .9]}[turns]
        assert detections[0]['boundingBox'] == pytest.approx(expected)


def test_local_supplement_preserves_primary_and_is_never_downloaded(monkeypatch, tmp_path):
    primary, supplement = Detector(['camera']), Detector(['sports ball'])
    custom_path, general_path = tmp_path / 'custom.pt', tmp_path / 'general.pt'
    custom_path.touch()
    general_path.touch()
    monkeypatch.setenv('YOLO_MODEL_PATH', str(custom_path))
    monkeypatch.setenv('ITEM_PRETRAINED_YOLO_PATH', str(general_path))
    monkeypatch.setenv('ITEM_ALLOW_PRETRAINED_DETECTOR', 'true')
    monkeypatch.setattr(items, 'load_detector', lambda *args: supplement)
    status = {'detectorSource': 'configured_item_model', 'detectorVersion': 'custom.pt'}
    detectors = items.verification_detectors(primary, status)
    assert [d[0] for d in detectors] == [primary, supplement]
    coverage = items.category_coverage('Equipment', 'Sports equipment', detectors)
    assert coverage['matchingLabels'] == ['sports ball']
    assert coverage['allProductsCovered'] is False
    detections, attempts, failures = items.detect_photo(np.zeros((10, 10, 3)), {'sports ball'}, detectors)
    assert detections[0]['source'] == 'general_pretrained'
    assert attempts == 2 and failures == 0  # Remaining model supplies context, not a forced target.
    monkeypatch.setenv('ITEM_ALLOW_PRETRAINED_DETECTOR', 'false')
    assert len(items.verification_detectors(primary, status)) == 1
    assert items.verification_detectors(None, status) == []


def test_rotation_and_supplement_work_are_bounded_and_never_lower_threshold():
    class NoMatch(Detector):
        def predict(self, image, **kwargs):
            assert kwargs['conf'] == 0.55
            assert kwargs['max_det'] == 20
            return super().predict(image, **kwargs)
    detectors = [(NoMatch(['book', 'person'], ['person']), 'fixture', 'v1') for _ in range(2)]
    detections, attempts, failures = items.detect_photo(np.zeros((10, 10, 3)), {'book'}, detectors)
    assert attempts == 8 and failures == 0
    assert len(detections) == 1
    assert not any(d['matchesCategory'] for d in detections)


def test_audit_command_reports_all_categories_and_can_fail_a_coverage_gate(monkeypatch, capsys):
    from app.training import audit_item_coverage as audit
    matrix = items.coverage_matrix([(Detector(['book']), 'fixture', 'fixture.pt')])
    monkeypatch.setattr(audit, 'models_status', lambda: (None, None, {
        'categoryCoverage': matrix, 'detectors': [], 'riskClassifierAvailable': False}))
    monkeypatch.setattr('sys.argv', ['audit_item_coverage'])
    assert audit.main() == 0
    report = json.loads(capsys.readouterr().out)
    assert report['categoryCount'] == 22
    assert len(report['categoriesWithoutLabels']) == 18
    assert report['riskClassifierAvailable'] is False
    monkeypatch.setattr('sys.argv', ['audit_item_coverage', '--require-labels-for-every-category'])
    assert audit.main() == 2


def test_missing_optional_model_does_not_trigger_a_download(monkeypatch, tmp_path):
    monkeypatch.setenv('ITEM_PRETRAINED_YOLO_PATH', str(tmp_path / 'not-downloaded.pt'))
    monkeypatch.setenv('ITEM_ALLOW_PRETRAINED_DETECTOR', 'true')
    monkeypatch.setattr(items, 'load_detector', lambda *args: pytest.fail('Must not try missing weights'))
    primary = Detector(['camera'])
    assert len(items.verification_detectors(primary, {
        'detectorSource': 'configured_item_model', 'detectorVersion': 'custom.pt'})) == 1
