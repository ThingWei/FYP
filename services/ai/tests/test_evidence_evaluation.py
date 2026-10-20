import json
import subprocess
import sys

import pytest

from app.training.pricing_dataset import FEATURES, prepare_dataset, validate_dataset
from app.training.recommendation_dataset import prepare_recommendation_dataset
from app.training.train_recommendation import train_recommendation_artifact
from app.training.train_tabular_models import TARGET_SOURCE_WEIGHTS


def interactions(source='marketplace', users=3, items=5):
    return [{'userId': f'{source}-u-{u}', 'listingId': f'{source}-i-{i}',
             'rating': 4.5, 'interactionType': 'completed_rental',
             'observedAt': f'2026-10-{i + 1:02d}T00:00:00Z', 'sourceType': source}
            for u in range(users) for i in range(items)]


def export_file(tmp_path, rows):
    export = tmp_path / 'input.json'
    export.write_text(json.dumps({'rows': rows}), encoding='utf-8')
    return export


def run_evaluation(tmp_path, export, **kwargs):
    return train_recommendation_artifact(real_export=export, models_dir=tmp_path / 'models',
        metrics_dir=tmp_path / 'metrics', data_dir=tmp_path / 'data',
        include_synthetic=False, evaluate_only=True, **kwargs)


def test_source_specific_and_marketplace_only_evaluation_without_writes(tmp_path):
    export = export_file(tmp_path, interactions() + interactions('demo_seed'))
    before = set(tmp_path.rglob('*'))
    report = run_evaluation(tmp_path, export)
    assert report['artifactWritten'] is False
    assert set(tmp_path.rglob('*')) == before
    assert report['evaluationBySource']['marketplace']['testInteractions'] == 3
    assert report['evaluationBySource']['demo_seed']['testInteractions'] == 3
    assert report['evaluationBySource']['synthetic']['status'] == 'no_holdout'
    assert report['marketplaceOnly']['trainingSources'] == ['marketplace']
    assert report['marketplaceOnly']['interactions'] == 15
    assert report['marketplaceOnly']['rmse'] is not None
    assert report['existingArtifact']['status'] == 'unavailable'


def test_sparse_real_cohort_is_not_reported_as_zero_error(tmp_path):
    report = run_evaluation(tmp_path, export_file(tmp_path, interactions(users=1, items=2)))
    assert report['status'] == 'insufficient_data'
    assert report['marketplaceOnly']['rmse'] is None
    assert not (tmp_path / 'models').exists()


def test_seen_holdout_model_comparison_is_blocked_and_artifact_unchanged(tmp_path):
    export = export_file(tmp_path, interactions())
    train_recommendation_artifact(real_export=export, models_dir=tmp_path / 'models',
        metrics_dir=tmp_path / 'metrics', data_dir=tmp_path / 'data', include_synthetic=False)
    before = {p: p.read_bytes() for p in tmp_path.rglob('*') if p.is_file()}
    report = run_evaluation(tmp_path, export)
    assert report['existingArtifact']['status'] == 'not_comparable_seen_holdout'
    assert report['existingArtifact']['seenHoldoutPairs'] == 3
    assert 'metrics' not in report['existingArtifact']
    assert {p: p.read_bytes() for p in tmp_path.rglob('*') if p.is_file()} == before
    assert 'marketplace-u-' not in json.dumps(report)


def test_corrupt_baseline_has_sanitized_diagnostic(tmp_path):
    artifact = tmp_path / 'private-model.pkl'
    artifact.write_bytes(b'broken')
    report = run_evaluation(tmp_path, export_file(tmp_path, interactions()), baseline_artifact=artifact)
    assert report['existingArtifact']['status'] == 'unavailable'
    assert str(tmp_path) not in json.dumps(report)


def test_list_export_and_source_precedence_preserve_marketplace(tmp_path):
    row = interactions(users=1, items=1)[0]
    demo = {**row, 'sourceType': 'demo_seed', 'rating': 5, 'interactionType': 'published_review'}
    export = tmp_path / 'list.json'
    export.write_text(json.dumps([row, demo]))
    frame, summary = prepare_recommendation_dataset(export, include_synthetic=False)
    assert len(frame) == 1
    assert frame.iloc[0].source_type == 'marketplace'
    assert summary['demoSeedInteractions'] == 0


def test_cli_evaluation_report_is_opt_in_and_never_overwrites(tmp_path):
    export = export_file(tmp_path, interactions(users=1, items=1))
    report = tmp_path / 'evaluation.json'
    command = [sys.executable, '-m', 'app.training.train_recommendation',
               '--real-export', str(export), '--evaluate-only', '--no-synthetic', '--report', str(report)]
    result = subprocess.run(command, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    before = report.read_bytes()
    assert json.loads(before)['artifactWritten'] is False
    repeated = subprocess.run(command, capture_output=True, text=True)
    assert repeated.returncode != 0
    assert report.read_bytes() == before
    protected = subprocess.run(command[:-1] + ['metrics/do-not-write-evaluation.json'], capture_output=True, text=True)
    assert protected.returncode != 0
    assert 'outside deployed' in protected.stderr


def test_external_pricing_provenance_preserved_without_model_feature_changes(tmp_path):
    frame, _ = prepare_dataset(None, 1)
    row = frame.iloc[0].to_dict()
    row.update(source_type='external_asking_price', target_source='external_asking_price',
        group_id='public-product', source_url='https://example.com/rental', source_name='Reviewed source',
        collection_method='automatic', package_notes='Body only; tax excluded',
        quoted_rental_days=1, duration_min_days=7, duration_max_days=30,
        rental_duration_days=7, duration_feature_basis='eligible_band_minimum',
        owner_trust_score=None, owner_average_rating=None, owner_completed_rentals=None)
    other_band = {**row, 'rental_duration_days': 31, 'duration_min_days': 31, 'duration_max_days': 60}
    prepared, summary = prepare_dataset(export_file(tmp_path, [row, other_band]), 0)
    assert len(prepared) == 2
    assert summary['sourceTypes'] == {'external_asking_price': 2}
    assert summary['targetSources'] == {'external_asking_price': 2}
    assert prepared.iloc[0].source_url == row['source_url']
    assert prepared.owner_trust_score.isna().all()
    assert 'source_url' not in FEATURES
    assert TARGET_SOURCE_WEIGHTS['external_asking_price'] == TARGET_SOURCE_WEIGHTS['active_asking']


@pytest.mark.parametrize('source,target', [('external_asking_price', 'completed_rental'),
    ('demo_seed', 'completed_rental'), ('real', 'synthetic_seed'), ('unknown', 'active_asking')])
def test_pricing_source_target_cannot_be_misrepresented(source, target):
    frame, _ = prepare_dataset(None, 5)
    frame.loc[0, 'source_type'] = source
    frame.loc[0, 'target_source'] = target
    with pytest.raises(ValueError, match='provenance'):
        validate_dataset(frame)
