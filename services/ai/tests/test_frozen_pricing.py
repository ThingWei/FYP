"""Controlled pricing fixtures; no marketplace observations or production writes."""
import hashlib
import json
import numpy as np
import pandas as pd
import joblib
from sklearn.dummy import DummyRegressor

from app.training import evaluate_pricing as pricing
from app.training.pricing_dataset import FEATURES, prepare_dataset
from test_ai_readiness import observations


def artifact(tmp_path):
    path = tmp_path / 'fixture.joblib'
    model = DummyRegressor(strategy='constant', constant=110).fit(np.zeros((2, len(FEATURES))), [100, 120])
    joblib.dump({'schema_version': 'renthub-price-v2', 'feature_schema': {'ordered': FEATURES},
                 'trained_at': '2026-01-01T00:00:00Z', 'model_version': 'fixture-only',
                 'global_model': model, 'category_models': {}}, path)
    return path


def test_frozen_evaluation_never_fits_or_replaces_artifact_and_reports_cohorts(tmp_path):
    path, model = tmp_path / 'observations.json', artifact(tmp_path)
    path.write_text(json.dumps({'rows': observations()}))
    checksum = hashlib.sha256(model.read_bytes()).hexdigest()
    report = pricing.evaluate(path, cutoff='2026-10-01', artifact_path=model,
                              pipeline_factory=lambda _: (_ for _ in ()).throw(AssertionError('No training allowed')))
    assert report['status'] == 'diagnostic_evaluation'
    assert report['candidate'] is None and report['artifactWritten'] is False
    assert report['modelMode'] == 'deployed'
    assert report['deployedModel']['rows'] == 10
    assert report['predictionCoverage']['predictedTargets'] == 10
    assert report['trainingOverlapVerification'] == 'unknown_no_row_manifest'
    assert report['evaluationByTargetSource']['completed_rental']['samples'] == 0
    assert report['evaluationByCategory']['Devices']['samples'] == 10
    assert report['evaluationByCategory']['Devices']['holdoutSamples'] == 10
    assert report['evaluationByCategory']['Devices']['abstainedTargets'] == 0
    assert hashlib.sha256(model.read_bytes()).hexdigest() == checksum


def test_ai_unknown_and_simulated_rows_are_excluded_even_when_labelled_real(tmp_path):
    rows = observations()
    for i, row in enumerate(rows):
        row.update(price_origin=['ai_suggested', 'ai_edited', 'unknown', 'owner_entered'][i % 4])
        if i % 4 == 3:
            row['payment_simulated'] = True
    path = tmp_path / 'input.json'
    path.write_text(json.dumps({'rows': rows}))
    report = pricing.evaluate(path, artifact_path=artifact(tmp_path))
    assert report['status'] == 'insufficient_data'
    assert report['excludedProvenanceRows'] == 40
    assert report['candidate'] is None


def test_future_training_ignores_legacy_real_labels_and_ai_lineage(tmp_path):
    rows = observations()
    rows[0]['price_origin'] = 'ai_suggested'
    rows[1].pop('independent_evidence')
    rows[2]['payment_simulated'] = True
    path = tmp_path / 'input.json'
    path.write_text(json.dumps({'rows': rows}))
    frame, _ = prepare_dataset(path, synthetic_rows=0)
    assert len(frame) == 37
    assert frame.price_origin.eq('owner_entered').all()


def test_undefined_r_squared_is_not_reported_as_success():
    assert pricing.safe_metrics(np.array([10, 10]), np.array([10, 11]))['r2'] is None
    assert pricing.safe_metrics(np.array([]), np.array([])) is None


def test_readiness_reports_missing_domains_and_keeps_age_zero_distinct_from_unknown(tmp_path):
    rows = observations()
    for row in rows:
        row['item_age_years'] = None
        row['condition'] = None
    rows[0]['item_age_years'] = 0
    rows[0]['condition'] = 'Good'
    coverage = [{'category': 'Devices', 'subcategory': 'Cameras'},
                {'category': 'Books', 'subcategory': 'Fiction'}]
    path = tmp_path / 'reviewed.json'
    path.write_text(json.dumps({'rows': rows, 'catalogCoverage': coverage}))
    report = pricing.evaluate(path, cutoff='2026-10-01', artifact_path=artifact(tmp_path))
    readiness = report['evidenceReadiness']
    assert readiness['expectedSubcategories'] == 2
    assert readiness['missingSubcategories'] == 1
    camera = next(row for row in readiness['rows'] if row['subcategory'] == 'Cameras')
    assert camera['withItemAge'] == 1
    assert camera['withCondition'] == 1
    assert camera['withBothConditionAndItemAge'] == 1
    assert readiness['automaticTrainingAllowed'] is False
    assert readiness['candidateTrainingDecision'] == 'not_justified_by_current_data'


def test_empty_evaluation_keeps_expected_domains_and_verifies_frozen_artifact(tmp_path):
    path = tmp_path / 'empty.json'
    path.write_text(json.dumps({'rows': [], 'catalogCoverage': [{'category': 'Books', 'subcategory': 'Fiction'}]}))
    report = pricing.evaluate(path, artifact_path=artifact(tmp_path))
    assert report['status'] == 'insufficient_data'
    assert report['artifactUnchanged'] is True
    assert report['evidenceReadiness']['missingSubcategories'] == 1
    assert report['predictionCoverage']['eligibleTargets'] == 0
