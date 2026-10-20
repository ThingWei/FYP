"""Controlled policy fixtures plus optional local-artifact offline smoke tests."""

import json
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import pytest

from app.schemas import VerificationRequest
from app.services import item_world as world, item_verification as items
from app.training import evaluate_item_recognition as evaluation


class Detector:
    def __init__(self, label, detected=None):
        self.names = {0: label, 1: 'person'}
        self.detected = label if detected is None else detected
        self.calls = 0

    def predict(self, image, **kwargs):
        assert 'classes' not in kwargs and 'texts' not in kwargs
        self.calls += 1
        boxes = [] if self.detected == '' else [SimpleNamespace(
            cls=np.array(list(self.names.values()).index(self.detected)),
            conf=np.array(.91), xyxy=np.array([[1, 1, 9, 9]]))]
        return [SimpleNamespace(names=self.names, boxes=boxes)]


def test_fixed_vocabulary_covers_all_22_domains_but_not_full_accuracy():
    detector = SimpleNamespace(names=[label for _, label in world.PROMPTS])
    matrix = items.coverage_matrix([(detector, world.SOURCE, 'fixture.pt')])
    assert len(matrix) == 22
    assert all(row['matchingLabels'] and row['openVocabularyOnly'] for row in matrix)
    assert all(not row['allProductsCovered'] and not row['specificCategoryVerified'] for row in matrix)
    assert 'person' not in items.expected_labels('Clothing', 'Other clothing')
    assert 'detail page' not in items.expected_labels('Books', 'Fiction')


@pytest.mark.parametrize('category,subcategory', [(c, s) for c, domains in items.DOMAINS.items() for s in domains])
def test_prompted_matches_cannot_become_automatic_candidates(monkeypatch, category, subcategory):
    label = next(label for _, label in world.PROMPTS if label in items.expected_labels(category, subcategory))
    detector = Detector(label)
    status = {'detectorSource': 'configured_item_model', 'detectorVersion': 'fixture.pt',
              'riskClassifierVersion': 'fixture.pt'}
    monkeypatch.setattr(items, 'models_status', lambda: (detector, object(), status))
    monkeypatch.setattr(items, 'verification_detectors', lambda *_: [(detector, world.SOURCE, 'fixture.pt')])
    images = [(None, np.full((10, 10, 3), i, dtype=np.uint8)) for i in range(3)]
    result = items.verify(VerificationRequest(expected_category=category, expected_subcategory=subcategory),
                          images, [], lambda _: dict(isBlurry=False, isTooDark=False,
                          isTooBright=False, hasUsableResolution=True),
                          lambda image: str(image[0, 0, 0]), lambda *_: .1)
    assert result.accepted is False and result.outcome == 'manual_review'
    assert result.extracted_fields['openVocabularyEvidenceUsed'] is True
    assert result.extracted_fields['authenticityVerified'] is False
    assert result.extracted_fields['matchingViewCount'] == 3


def test_ordinary_rotations_precede_world_and_target_is_never_forced():
    class Sideways(Detector):
        def predict(self, image, **kwargs):
            self.detected = 'book' if self.calls else ''
            return super().predict(image, **kwargs)
    primary, fallback = Sideways('book'), Detector('book')
    ds, attempts, failures = items.detect_photo(np.zeros((10, 10, 3)), {'book'},
        [(primary, 'configured_item_model', 'a.pt'), (fallback, world.SOURCE, 'b.pt')])
    assert attempts == 2 and failures == 0
    assert ds[0]['source'] == 'configured_item_model'
    assert fallback.calls == 0


def test_world_runs_only_after_fixed_model_misses_and_unrelated_is_not_a_match():
    primary, fallback = Detector('book', ''), Detector('book')
    ds, attempts, _ = items.detect_photo(np.zeros((10, 10, 3)), {'book'},
        [(primary, 'configured_item_model', 'a.pt'), (fallback, world.SOURCE, 'b.pt')])
    assert attempts == 5 and ds[0]['source'] == world.SOURCE
    ds, attempts, _ = items.detect_photo(np.zeros((10, 10, 3)), {'book'},
        [(Detector('book', 'person'), world.SOURCE, 'b.pt')])
    assert attempts == 4 and not any(d['matchesCategory'] for d in ds)


def test_disabled_missing_or_incompatible_world_never_downloads(monkeypatch, tmp_path):
    monkeypatch.setenv('ITEM_WORLD_MODEL_PATH', str(tmp_path / 'missing.pt'))
    monkeypatch.setenv('ITEM_WORLD_ENABLED', 'true')
    monkeypatch.setattr(world, 'load_world', lambda *_: pytest.fail('Must not load/download missing weights'))
    assert world.availability()[1]['issue'] == 'prepared_artifact_missing'
    monkeypatch.setenv('ITEM_WORLD_ENABLED', 'false')
    assert world.availability()[1]['issue'] == 'disabled'
    path = tmp_path / 'missing.pt'
    path.touch()
    monkeypatch.setenv('ITEM_WORLD_ENABLED', 'true')
    def corrupt(*_):
        raise ValueError('private exception/path must not escape')
    monkeypatch.setattr(world, 'load_world', corrupt)
    assert world.availability()[1]['issue'] == 'incompatible_or_load_failed'
    assert 'private' not in json.dumps(world.availability()[1])


def test_evaluation_does_not_turn_untested_categories_into_passes(monkeypatch):
    monkeypatch.setattr(evaluation.cv2, 'imread', lambda _: np.zeros((10, 10, 3)))
    detector = Detector('book')
    cases = [{'path': Path('not-read.jpg'), 'category': 'Books', 'subcategory': 'Other books',
              'expectation': 'target_present', 'label': 'book', 'boxes': [[.1, .1, .9, .9]]}]
    result = evaluation.evaluate(cases, [(detector, world.SOURCE, 'fixture.pt')])
    tested = [row for row in result['categories'] if row['cases']]
    assert tested[0]['withWorldLocalized'] == 1
    assert tested[0]['baselineLocalized'] == 0
    assert sum(row['status'] == 'not_evaluated' for row in result['categories']) == 21
    assert not result['realPhotoCoverageComplete']
    assert evaluation.iou([0, 0, .1, .1], [.9, .9, 1, 1]) == 0


def test_optional_prepared_artifact_predicts_without_network_or_clip(monkeypatch):
    path = world.artifact_path()
    if not path.is_file():
        pytest.skip('Optional prepared artifact is intentionally not distributed in Git')
    import requests
    import urllib.request
    import sys
    def forbidden(*args, **kwargs):
        pytest.fail('Runtime must not download/encode prompts')
    monkeypatch.setattr(requests.sessions.Session, 'request', forbidden)
    monkeypatch.setattr(urllib.request, 'urlopen', forbidden)
    monkeypatch.setitem(sys.modules, 'clip', None)
    model = world.load_world(path, path.stat().st_mtime_ns)
    monkeypatch.setattr(model, 'set_classes', forbidden)
    result = model.predict(np.full((320, 320, 3), 128, dtype=np.uint8),
                           conf=.55, verbose=False, device='cpu', max_det=20)
    assert not len(result[0].boxes)


def test_low_synthetic_only_risk_cannot_claim_a_candidate_pass(monkeypatch):
    detector = Detector('car')
    monkeypatch.setattr(items, 'models_status', lambda: (detector, object(), {
        'detectorSource': 'configured_item_model', 'detectorVersion': 'fixture.pt',
        'riskClassifierVersion': 'synthetic.pt', 'riskTrainingSource': ['synthetic_manipulation']}))
    monkeypatch.setattr(items, 'verification_detectors', lambda *_: [(detector, 'configured_item_model', 'fixture.pt')])
    images = [(None, np.full((10, 10, 3), i, dtype=np.uint8)) for i in range(3)]
    result = items.verify(VerificationRequest(expected_category='Vehicles', expected_subcategory='Cars'),
                          images, [], lambda _: dict(isBlurry=False, isTooDark=False,
                          isTooBright=False, hasUsableResolution=True),
                          lambda image: str(image[0, 0, 0]), lambda *_: .01)
    assert not result.accepted and result.outcome == 'manual_review'
    assert result.extracted_fields['syntheticRiskOnly'] is True


def test_preparation_cannot_overwrite_an_existing_detector(monkeypatch):
    from app.training.prepare_item_world import output_path
    monkeypatch.setenv('ITEM_WORLD_MODEL_PATH', 'models/item_yolo.pt')
    with pytest.raises(ValueError, match='protected'):
        output_path()
