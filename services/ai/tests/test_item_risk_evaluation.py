import csv
import hashlib
import json

import pytest
import torch
from PIL import Image

from app.training import evaluate_item_risk as risk
from app.training import evaluate_item_recognition as recognition
from test_item_risk_training import write_manifest


class EvaluationFixture(torch.nn.Module):
    """Deterministic fixture, not real evaluation data or EfficientNet results."""
    def forward(self, x):
        means = x.mean(dim=(1, 2, 3))
        return torch.stack((-means, means), dim=1)


def setup_artifact(tmp_path):
    manifest = write_manifest(tmp_path)
    for i in range(48):
        Image.new('RGB', (16, 16), (i * 5, 10, 20)).save(tmp_path / f'photo-{i}.png')
    splits = risk.load_manifest(manifest)
    fingerprint = hashlib.sha256(manifest.read_bytes())
    for phase, rows in splits.items():
        for row in rows:
            fingerprint.update(phase.encode())
            fingerprint.update(hashlib.sha256(row['path'].read_bytes()).digest())
    metadata = {'contract': 'renthub-item-risk-v1', 'architecture': 'efficientnet_b0',
                'purpose': 'item_photo_risk_assistance', 'classes': ['normal', 'risky'],
                'preprocessing': 'rgb-224-imagenet-v1',
                'datasetFingerprintSha256': fingerprint.hexdigest()}
    artifact = tmp_path / 'fixture.pt'
    torch.jit.script(EvaluationFixture()).save(str(artifact), _extra_files={'metadata.json': json.dumps(metadata)})
    return artifact, manifest, splits


def reviewed_manifest(tmp_path, mutate=None):
    rows = []
    for i in range(2):
        Image.new('RGB', (18, 18), (255 * i, 0, 30)).save(tmp_path / f'heldout-{i}.png')
        rows.append({'path': f'heldout-{i}.png', 'item_id': f'independent-{i}',
                     'label': 'normal' if i == 0 else 'risky', 'source_type': 'reviewed_real',
                     'split': 'test', 'reviewed': 'true', 'permission_confirmed': 'true',
                     'label_evidence': 'controlled test fixture only'})
    if mutate:
        mutate(rows)
    path = tmp_path / 'reviewed.csv'
    with path.open('w', newline='', encoding='utf-8') as stream:
        writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    return path


def test_frozen_benchmark_evaluates_only_test_and_does_not_replace_artifact(tmp_path):
    artifact, manifest, _ = setup_artifact(tmp_path)
    before = {p: risk.digest(p) for p in tmp_path.iterdir() if p.is_file()}
    report = risk.evaluate(artifact, manifest, batch_size=3, cpu_threads=1)
    assert report['samples'] == 8
    assert report['sourceManifestFingerprintVerified'] and report['artifactUnchanged']
    assert not report['artifactWritten'] and report['databaseWrites'] == 0
    assert report['evaluationScope'] == 'existing_benchmark_test_only'
    assert report['cohorts']['reviewed_real']['classification']['status'] == 'not_evaluated'
    assert report['cohorts']['synthetic_manipulation']['classification']['samples'] == 8
    assert report['thresholds']['productionElevatedRisk'] == .65
    assert sum(map(sum, report['productionElevatedRisk']['confusionMatrix'])) == 8
    assert all(risk.digest(p) == content for p, content in before.items())
    assert str(tmp_path) not in json.dumps(report)


def test_reviewed_cohort_separate_and_single_class_is_incomplete(tmp_path):
    artifact, manifest, _ = setup_artifact(tmp_path)
    reviewed = reviewed_manifest(tmp_path)
    report = risk.evaluate(artifact, manifest, reviewed, cpu_threads=1)
    assert report['samples'] == 2 and report['evaluationScope'] == 'reviewed_rental_photos'
    assert report['cohorts']['synthetic_manipulation']['classification']['status'] == 'not_evaluated'
    assert report['cohorts']['reviewed_real']['classification']['samples'] == 2
    reviewed = reviewed_manifest(tmp_path, lambda rows: rows[1].update(label='normal'))
    assert risk.evaluate(artifact, manifest, reviewed, cpu_threads=1)['classification']['status'] == 'insufficient_class_coverage'


@pytest.mark.parametrize('mutate,message', [
    (lambda r: r[0].update(permission_confirmed='false'), 'permission'),
    (lambda r: r[0].update(reviewed='false'), 'review'),
    (lambda r: r[0].update(source_type='synthetic_manipulation'), 'provenance'),
    (lambda r: r[0].update(split='train'), 'provenance'),
    (lambda r: r[0].update(item_id='0'), 'overlaps'),
    (lambda r: r[0].update(path='photo-47.png'), 'overlaps'),
    (lambda r: r[1].update(path=r[0]['path']), 'Duplicate'),
    (lambda r: r[0].update(label_evidence=''), 'evidence'),
    (lambda r: r[0].update(label='authentic'), 'normal/risky'),
])
def test_reviewed_photos_require_evidence_and_reject_source_overlap(tmp_path, mutate, message):
    _, _, splits = setup_artifact(tmp_path)
    with pytest.raises(ValueError, match=message):
        risk.read_reviewed(reviewed_manifest(tmp_path, mutate), splits)


def test_changed_training_manifest_and_empty_review_are_not_evaluated(tmp_path):
    artifact, manifest, splits = setup_artifact(tmp_path)
    reviewed = reviewed_manifest(tmp_path)
    reviewed.write_text(reviewed.read_text().splitlines()[0] + '\n')
    with pytest.raises(ValueError, match='No reviewed'):
        risk.read_reviewed(reviewed, splits)
    # Changed valid CSV still cannot borrow the model's original split claim.
    manifest.write_text(manifest.read_text() + '\n')
    with pytest.raises(ValueError, match='fingerprint'):
        risk.evaluate(artifact, manifest, cpu_threads=1)


def test_report_paths_preserve_existing_files_and_production_metrics(tmp_path, monkeypatch):
    monkeypatch.setattr(risk, 'ROOT', tmp_path)
    private = tmp_path / '.data'
    private.mkdir()
    report = private / 'existing.json'
    report.write_text('preserved')
    with pytest.raises(ValueError, match='NEW private'):
        risk.new_report(report)
    with pytest.raises(ValueError, match='NEW private'):
        risk.new_report(tmp_path / 'metrics' / 'report.json')
    assert report.read_text() == 'preserved'


def test_recognition_report_is_json_despite_library_console_noise(tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(recognition.items, 'ROOT', tmp_path)
    def status():
        print('A library diagnostic, not JSON')
        return None, None, {}
    monkeypatch.setattr(recognition.items, 'models_status', status)
    monkeypatch.setattr(recognition.items, 'verification_detectors', lambda *_: [])
    report = tmp_path / '.data' / 'coverage.json'
    monkeypatch.setattr('sys.argv', ['evaluate_item_recognition', '--coverage-only', '--report', str(report)])
    recognition.main()
    payload = json.loads(report.read_text())
    assert payload['totalCases'] == 0 and len(payload['categories']) == 22
    assert all(r['status'] == 'not_evaluated' for r in payload['categories'])
    assert 'library diagnostic' in capsys.readouterr().out
    with pytest.raises(SystemExit):
        recognition.main()
    assert json.loads(report.read_text()) == payload
