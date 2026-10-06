"""Synthetic images/stubbed models only; no authenticity or live accuracy claims."""

import json
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import pytest
import torch
from PIL import Image
from torchvision import transforms

from app.schemas import VerificationRequest
from app.services import image_intelligence as intelligence
from app.services import mykad_field_risk as risk
from app.services.document_risk_preprocessing import (
    Letterbox, crop_field, field_tensor, validate_field_contract,
)


def provenance():
    return {'purpose': 'synthetic_manipulation_risk_research',
            'containsSyntheticManipulations': True,
            'inputContract': {'inputMode': 'fields', 'resize': 'aspect_preserving_letterbox',
                              'runtimeCompatibleWithoutAdapter': False,
                              'regionSource': 'manifest_annotations_not_automatic_detection',
                              'imageSize': 224, 'cropPadding': 0.25,
                              'normalizationMean': [0.485, 0.456, 0.406],
                              'normalizationStd': [0.229, 0.224, 0.225]}}


NAMES = {0: 'front_identity_number', 1: 'front_name', 2: 'back_identity_number',
         3: 'back_serial_number', 4: 'front_address', 5: 'front_face'}


def box(label, confidence=0.9, region=(20, 20, 100, 40)):
    return SimpleNamespace(cls=torch.tensor([label]), conf=torch.tensor([confidence]),
                           xyxy=torch.tensor([region], dtype=torch.float32))


class Detector:
    def __init__(self, detections):
        self.detections = iter(detections)
    def predict(self, image, **kwargs):
        return [SimpleNamespace(names=NAMES, boxes=next(self.detections))]


class Classifier:
    def __init__(self, logits=(-1.0, 1.0)):
        self.logits = logits
        self.inputs = []
    def __call__(self, inputs):
        self.inputs.append(inputs.clone())
        return torch.tensor([self.logits])


@pytest.fixture
def images():
    image = np.zeros((80, 160, 3), dtype=np.uint8)
    image[:, :, 2] = 255  # BGR red: detects accidental RGB channel reversal.
    return [image.copy(), image.copy()]


def stub_bundle(monkeypatch, detections, logits=(-1.0, 1.0)):
    classifier = Classifier(logits)
    detector = Detector(detections)
    monkeypatch.setenv('MYKAD_FIELD_RISK_ENABLED', 'true')
    monkeypatch.setattr(risk, '_load_bundle', lambda *args: (detector, classifier,
                        validate_field_contract(provenance())))
    return classifier


def test_runtime_crops_match_training_and_preserve_rgb(monkeypatch, images):
    classifier = stub_bundle(monkeypatch, [[box(0), box(1)], [box(2), box(3)]])
    evidence = risk.analyse_fields(images)
    assert evidence['status'] == 'available' and evidence['coverageComplete']
    assert evidence['sourceType'] == 'synthetic_manipulation'
    assert evidence['requiresAdminReview'] and evidence['advisoryOnly']
    assert evidence['scoredFieldCount'] == 4
    contract = provenance()['inputContract']
    rgb = Image.fromarray(images[0][:, :, ::-1])
    expected = transforms.Compose([Letterbox(224), transforms.ToTensor(),
                                  transforms.Normalize(contract['normalizationMean'], contract['normalizationStd'])])(
                                      crop_field(rgb, (20, 20, 100, 40), 0.25))
    assert torch.equal(classifier.inputs[0][0], expected)
    assert torch.equal(field_tensor(rgb, (20, 20, 100, 40), contract), expected)
    assert classifier.inputs[0][0, 0, 112, 112] > classifier.inputs[0][0, 2, 112, 112]
    assert 'identityNumber' not in json.dumps(evidence)


def test_side_semantics_confidence_and_noneligible_classes_are_filtered(monkeypatch, images):
    classifier = stub_bundle(monkeypatch, [[box(0, 0.2), box(0, 0.6), box(0, 0.9),
                                           box(2), box(5)], [box(2), box(1)]])
    evidence = risk.analyse_fields(images)
    assert evidence['scoredFieldCount'] == len(classifier.inputs) == 2
    assert evidence['images'][0]['fields'][0]['field'] == 'front_identity_number'
    assert evidence['images'][0]['fields'][0]['detectionConfidence'] == 0.9
    assert evidence['images'][1]['fields'][0]['field'] == 'back_identity_number'


@pytest.mark.parametrize('detections,count,status', [
    ([[box(1)], [box(3)]], 2, 'partial'),
    ([[], []], 0, 'unavailable'),
    ([[box(0, region=(-1, 0, 80, 30))], [box(2)]], 1, 'partial'),
    ([[box(0, region=(20, 20, 24, 24))], [box(2)]], 1, 'partial'),
])
def test_missing_small_or_invalid_regions_do_not_mean_clearance(monkeypatch, images, detections, count, status):
    stub_bundle(monkeypatch, detections, logits=(2.0, -2.0))
    result = risk.analyse_fields(images)
    assert result['status'] == status and result['scoredFieldCount'] == count
    assert result['coverageComplete'] is False and result['requiresAdminReview']
    assert any('incomplete' in warning for warning in result['warnings'])


@pytest.mark.parametrize('logits', [(float('nan'), 1.0), (1.0,), (1.0, 2.0, 3.0)])
def test_bad_classifier_output_fails_closed(monkeypatch, images, logits):
    stub_bundle(monkeypatch, [[box(0)], [box(2)]], logits=logits)
    result = risk.analyse_fields(images)
    assert result['status'] == 'unavailable' and result['riskScore'] is None


def test_disabled_missing_and_incompatible_models_are_safe(monkeypatch, images, tmp_path):
    monkeypatch.setenv('MYKAD_FIELD_RISK_ENABLED', 'false')
    assert risk.analyse_fields(images)['status'] == 'disabled'
    monkeypatch.setenv('MYKAD_FIELD_RISK_ENABLED', 'true')
    monkeypatch.setenv('MYKAD_FIELD_MODEL_PATH', str(tmp_path / 'absent.pt'))
    monkeypatch.setenv('MYKAD_FIELD_RISK_MODEL_PATH', str(tmp_path / 'absent-risk.pt'))
    assert risk.analyse_fields(images)['status'] == 'unavailable'
    def failed(*args):
        raise RuntimeError('private-path/secret-upload-content')
    monkeypatch.setattr(risk, '_load_bundle', failed)
    result = risk.analyse_fields(images)
    assert result['riskScore'] is None
    assert 'secret-upload-content' not in json.dumps(result)


@pytest.mark.parametrize('key,value', [
    ('inputMode', 'full'), ('imageSize', True), ('cropPadding', float('nan')),
    ('resize', 'square_resize'), ('normalizationStd', [0, 0, 0]),
    ('runtimeCompatibleWithoutAdapter', True), ('regionSource', 'unknown'),
])
def test_incompatible_preprocessing_contract_rejected(key, value):
    metadata = provenance()
    metadata['inputContract'][key] = value
    with pytest.raises(ValueError):
        validate_field_contract(metadata)


def test_loader_rejects_artifacts_without_field_provenance(tmp_path):
    path = tmp_path / 'whole.pt'
    torch.jit.script(torch.nn.Linear(3, 2)).save(str(path))
    # Contract is validated before detector initialization or any inference.
    with pytest.raises((ValueError, json.JSONDecodeError)):
        risk._load_bundle(str(path), str(path))


@pytest.mark.parametrize('logits', [(-2.0, 2.0), (2.0, -2.0)])
def test_low_and_high_synthetic_signals_never_approve_mykad(monkeypatch, images, logits):
    stub_bundle(monkeypatch, [[box(0)], [box(2)]], logits)
    monkeypatch.setattr(intelligence, '_decode_images', lambda request: ([(None, im) for im in images], []))
    monkeypatch.setattr(intelligence, '_quality', lambda image: {
        'isBlurry': False, 'isTooDark': False, 'isTooBright': False,
        'hasSevereGlare': False, 'hasUsableResolution': True})
    monkeypatch.setattr(intelligence, '_ocr_preprocess', lambda image: image)
    monkeypatch.setattr(intelligence, '_text_region_signals', lambda *args: ('normal', []))
    monkeypatch.setattr(intelligence, '_nlp', lambda: None)
    reader = SimpleNamespace(readtext=lambda *args, **kwargs: [(None, 'MYKAD 900101-07-1234', 0.95)])
    monkeypatch.setattr(intelligence, '_ocr_reader', lambda: reader)
    def forbidden():
        pytest.fail('MyKad must not fall through to the full-image classifier')
    monkeypatch.setattr(intelligence, '_document_risk_model', forbidden)
    result = intelligence.ImageIntelligenceService().verify_document(VerificationRequest(expected_type='mykad'))
    assert result.accepted is False and result.outcome == 'manual_review'
    assert result.extracted_fields['requiresAdminReview'] is True
    assert result.extracted_fields['documentFieldRisk']['status'] == 'available'
    assert result.confidence == 0.95  # OCR score, not a synthetic authenticity confidence.


def test_crop_artifact_cannot_be_used_by_legacy_full_image_loader(monkeypatch, tmp_path):
    path = tmp_path / 'crop.pt'
    torch.jit.script(torch.nn.Linear(3, 2)).save(str(path), _extra_files={
        'renthub_provenance.json': json.dumps(provenance())})
    monkeypatch.setenv('DOCUMENT_RISK_MODEL_PATH', str(path))
    intelligence._document_risk_model.cache_clear()
    try:
        assert intelligence._document_risk_model()[0] is None
    finally:
        intelligence._document_risk_model.cache_clear()
