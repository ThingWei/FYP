import numpy as np
import pytest
from xgboost import XGBRegressor

from app.training.pricing_dataset import prepare_dataset, validate_dataset
from app.training.audit_price_age import controlled_predictions
from app.training.train_tabular_models import _pipeline, _split


def test_dataset_is_provenance_labelled_and_reproducible():
    first, summary = prepare_dataset(None, 240, seed=17)
    second, second_summary = prepare_dataset(None, 240, seed=17)
    assert summary['sourceTypes'] == {'synthetic': 240}
    assert summary['targetSources'] == {'synthetic_seed': 240}
    assert 'highOutliersAboveThreeIqr' in summary
    assert summary['fingerprintSha256'] == second_summary['fingerprintSha256']
    assert first.equals(second)


def test_grouped_split_prevents_product_leakage():
    frame, _ = prepare_dataset(None, 500, seed=19)
    train, validation, test = _split(frame, seed=19)
    assert set(train.group_id).isdisjoint(validation.group_id)
    assert set(train.group_id).isdisjoint(test.group_id)
    assert set(validation.group_id).isdisjoint(test.group_id)


def test_dataset_validation_rejects_duplicate_observation():
    frame, _ = prepare_dataset(None, 50, seed=23)
    duplicated = frame._append(frame.iloc[0], ignore_index=True)
    with pytest.raises(ValueError, match='Duplicate pricing observations'):
        validate_dataset(duplicated)


def test_pipeline_contains_real_xgboost_regressor_and_handles_unknowns():
    frame, _ = prepare_dataset(None, 500, seed=29)
    model = _pipeline(seed=29)
    features = frame.drop(columns=[
        'daily_price', 'source_type', 'target_source', 'observed_at', 'group_id',
    ])
    model.fit(features, frame.daily_price)
    assert isinstance(model.named_steps['model'], XGBRegressor)
    unknown = features.iloc[[0]].copy()
    unknown.loc[:, 'brand'] = 'Unknown future brand'
    prediction = float(model.predict(unknown)[0])
    assert np.isfinite(prediction)


def test_device_age_is_learned_with_fixed_market_evidence():
    frame, _ = prepare_dataset(None, 2500, seed=31)
    frame = frame[frame.category == 'Devices'].reset_index(drop=True)
    model = _pipeline(seed=31, monotone_age=True)
    features = frame.drop(columns=[
        'daily_price', 'source_type', 'target_source', 'observed_at', 'group_id',
    ])
    model.fit(features, frame.daily_price)
    result = controlled_predictions({
        'global_model': model,
        'category_models': {'Devices': model},
        'feature_schema': {'ordered': list(features.columns)},
        'metrics': {},
    }, 'Devices')
    predictions = [item['suggestedDailyPrice'] for item in result['predictions']]
    assert predictions[-1] < predictions[0] * 0.9
