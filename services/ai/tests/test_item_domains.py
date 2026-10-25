"""Routing regression fixtures are not evidence of real-photo accuracy."""
import json
from pathlib import Path
from types import SimpleNamespace

import pytest

from app.services import item_verification as items, item_world as world
from app.services.item_domains import PRODUCT_TYPES, TYPE_CONTRACT
from app.training import evaluate_item_recognition as evaluation
from test_item_verification import Detector, verify


@pytest.mark.parametrize('category,subcategory', [
    (category, subcategory) for category, subs in PRODUCT_TYPES.items() for subcategory in subs])
def test_all_22_domains_define_types_without_claiming_complete_support(category, subcategory):
    detector = SimpleNamespace(names=[label for _, label in world.PROMPTS] + ['mouse', 'keyboard'])
    coverage = items.category_coverage(category, subcategory, [(detector, world.SOURCE, 'fixture')])
    assert coverage['productTypeCheckVersion'] == TYPE_CONTRACT
    assert coverage['productTypes']
    assert coverage['allProductsCovered'] is False
    assert coverage['evaluationStatus'] == 'subcategory_accuracy_not_established'
    for kind, labels in PRODUCT_TYPES[category][subcategory].items():
        assert items.expected_labels(category, subcategory, kind) == labels
        assert items.expected_labels(category, subcategory, 'unreviewed_type') == set()


@pytest.mark.parametrize('product_type,label', [('mouse', 'mouse'), ('keyboard', 'keyboard')])
def test_available_peripheral_labels_contribute_to_the_correct_item_type(monkeypatch, product_type, label):
    result = verify(monkeypatch, 'Devices', 'Computers', Detector([label, 'laptop']), product_type=product_type)
    assert result.extracted_fields['categoryMatched'] is True
    assert result.extracted_fields['expectedProductType'] == product_type
    assert result.extracted_fields['productTypeCheckVersion'] == TYPE_CONTRACT
    assert result.extracted_fields['authenticityVerified'] is False


@pytest.mark.parametrize('subcategory,product_type,detected', [
    ('Computers', 'mouse', 'laptop'), ('Computers', 'laptop', 'mouse'),
    ('Computers', 'keyboard', 'mouse'), ('Computers', 'monitor', 'tv'),
    ('Computers', 'monitor', 'screen'), ('Gaming', 'controller', 'game console'),
    ('Gaming', 'vr_headset', 'headphones'), ('Computers', 'unreviewed_type', 'laptop'),
])
def test_same_subcategory_does_not_validate_a_different_object(monkeypatch, subcategory, product_type, detected):
    result = verify(monkeypatch, 'Devices', subcategory, Detector([detected]), product_type=product_type)
    assert result.extracted_fields['categoryMatched'] is None
    assert result.accepted is False
    assert result.outcome == 'manual_review'
    assert result.confidence == 0


def test_controller_uses_existing_world_label_but_remains_reviewable(monkeypatch):
    detector = Detector(['game controller'])
    monkeypatch.setattr(items, 'verification_detectors', lambda *_: [(detector, world.SOURCE, 'fixture')])
    result = verify(monkeypatch, 'Devices', 'Gaming', detector, product_type='controller')
    assert result.extracted_fields['categoryMatched'] is True
    assert result.extracted_fields['openVocabularyEvidenceUsed'] is True
    assert not result.accepted


@pytest.mark.parametrize('category,subcategory,kind,label', [
    ('Vehicles', 'Other vehicles', 'mobility_scooter', 'scooter'),
    ('Vehicles', 'Other vehicles', 'electric_scooter', 'motorcycle'),
    ('Equipment', 'Sports equipment', 'camping_tent', 'tent'),
    ('Clothing', 'Traditional wear', 'hanfu', 'dress'),
    ('Books', 'Fiction', 'book', 'paper'),
])
def test_generic_or_competing_labels_do_not_establish_specialised_types(monkeypatch, category, subcategory, kind, label):
    result = verify(monkeypatch, category, subcategory, Detector([label]), product_type=kind)
    assert result.extracted_fields['categoryMatched'] is None
    assert not result.accepted


def test_catalogue_peripheral_types_have_explicit_recognition_routes():
    # Offline cross-layer check: no catalogue lookup or external API request.
    root = Path(__file__).resolve().parents[2]
    source = (root / 'api/src/modules/catalog/catalog.deviceDomains.js').read_text()
    for subcategory in ('Computers', 'Gaming'):
        import re
        block = re.search(rf'{subcategory}: Object.freeze\(\{{(.*?)\}}\)', source, re.S).group(1)
        types = re.findall(r"Q\d+: '([^']+)'", block)
        assert types and set(types) <= PRODUCT_TYPES['devices'][subcategory.lower()].keys()
    assert 'tv' not in items.expected_labels('Devices', 'Computers', 'monitor')
    assert 'screen' not in items.expected_labels('Devices', 'Computers', 'monitor')


def test_coverage_only_reports_all_types_untested_and_unavailable_without_photos():
    report = evaluation.evaluate([], [])
    assert len(report['categories']) == 22
    assert report['totalCases'] == 0 and report['realPhotoCoverageComplete'] is False
    assert all(row['status'] == 'not_evaluated' for row in report['categories'])
    assert all(kind['status'] == 'not_evaluated' and not kind['matchingLabels']
               for row in report['categories'] for kind in row['productTypes'])


def test_reviewed_cases_require_a_compatible_explicit_type(tmp_path):
    image = tmp_path / 'fixture.jpg'
    image.write_bytes(b'fixture bytes; not used for image inference')
    path = tmp_path / 'cases.json'
    case = {'category': 'Devices', 'subcategory': 'Computers', 'item_id': 'physical-item-1',
            'path': image.name, 'reviewed': True, 'permissionConfirmed': True,
            'expectation': 'target_present', 'label': 'mouse', 'product_type': 'mouse',
            'boxes': [[0, 0, 1, 1]]}
    path.write_text(json.dumps([case]))
    assert evaluation.reviewed_cases(path)[0]['product_type'] == 'mouse'
    path.write_text(json.dumps([{**case, 'product_type': 'laptop'}]))
    with pytest.raises(ValueError, match='compatible canonical object label'):
        evaluation.reviewed_cases(path)
    path.write_text(json.dumps([{**case, 'product_type': 'unknown'}]))
    with pytest.raises(ValueError, match='Unknown product type'):
        evaluation.reviewed_cases(path)


def test_type_metrics_keep_mouse_and_keyboard_separate_and_report_unavailable(monkeypatch):
    import numpy as np
    monkeypatch.setattr(evaluation.cv2, 'imread', lambda _: np.zeros((10, 10, 3)))
    detector = Detector(['mouse', 'keyboard'])
    cases = [{'path': 'fixture', 'category': 'Devices', 'subcategory': 'Computers',
              'product_type': kind, 'label': kind, 'boxes': [[0, 0, 1, 1]], 'expectation': expectation}
             for kind, expectation in [('mouse', 'target_absent'), ('keyboard', 'target_absent')]]
    report = evaluation.evaluate(cases, [(detector, 'general_pretrained', 'fixture')])
    row = next(row for row in report['categories'] if row['subcategory'] == 'computers')
    mouse, keyboard = (next(kind for kind in row['productTypes'] if kind['productType'] == name)
                       for name in ('mouse', 'keyboard'))
    assert mouse['withWorldFalsePositiveCases'] == 1
    assert mouse['metrics']['withWorld']['unrelatedFalsePositiveCaseRate'] == 1
    assert keyboard['withWorldFalsePositiveCases'] == 0
    assert keyboard['metrics']['withWorld']['unrelatedFalsePositiveCaseRate'] == 0
    assert all(kind['metrics']['withWorld']['localizedPositiveCaseRate'] is None for kind in (mouse, keyboard))
    failed = evaluation.evaluate(cases, [(Detector(['mouse'], fail=True), 'general_pretrained', 'fixture')])
    row = next(row for row in failed['categories'] if row['subcategory'] == 'computers')
    assert row['withWorldUnavailableCases'] == 2
    assert row['metrics']['withWorld']['unrelatedFalsePositiveCaseRate'] is None


def test_type_audit_fails_when_category_labels_hide_missing_types(monkeypatch, capsys):
    from app.training import audit_item_coverage as audit
    matrix = items.coverage_matrix([(SimpleNamespace(names=['mouse']), 'general_pretrained', 'fixture')])
    monkeypatch.setattr(audit, 'models_status', lambda: (None, None, {
        'categoryCoverage': matrix, 'detectors': [], 'riskClassifierAvailable': False}))
    monkeypatch.setattr('sys.argv', ['audit_item_coverage', '--require-labels-for-every-type'])
    assert audit.main() == 2
    report = json.loads(capsys.readouterr().out)
    assert report['productTypeCount'] == 92
    assert 'devices/computers/monitor' in report['productTypesWithoutLabels']
    assert 'devices/computers/mouse' not in report['productTypesWithoutLabels']
