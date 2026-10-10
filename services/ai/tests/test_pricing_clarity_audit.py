"""Contract regressions; controlled fixtures do not establish market accuracy."""
from types import SimpleNamespace

import numpy as np

from app.services import pricing
from app.training.audit_pricing_clarity import AGES, controlled_request
from app.training.pricing_dataset import FEATURES


def test_controlled_age_requests_only_change_age():
    baseline = controlled_request('Apple', 'iPhone 17 Pro Max', 0).model_dump()
    for age in AGES:
        current = controlled_request('Apple', 'iPhone 17 Pro Max', age).model_dump()
        assert current['item_profile'].pop('item_age_years') == age
        expected = baseline.copy() | {'item_profile': {k: v for k, v in baseline['item_profile'].items() if k != 'item_age_years'}}
        assert current == expected


def test_identity_and_age_reach_inference_with_fixed_evidence(monkeypatch):
    frames = []

    def predict(frame):
        frames.append(frame.copy())
        return np.array([70.0])

    model = SimpleNamespace(predict=predict)
    bundle = {'global_model': model, 'feature_schema': {'ordered': FEATURES},
              'calibration': {'globalAbsoluteResidual': 5}, 'model_version': 'fixture',
              'supported_categories': ['Devices'], 'metrics': {'dataset': {'sourceTypes': {'real': 100}}}}
    monkeypatch.setattr(pricing, '_artifact', lambda: (bundle, None, None))
    for age in AGES:
        pricing.XGBoostPriceService().recommend(controlled_request('Apple', 'iPhone 17 Pro Max', age))
    pricing.XGBoostPriceService().recommend(controlled_request('Samsung', 'Galaxy S25 Ultra'))
    assert [float(frame.iloc[0]['item_age_years']) for frame in frames[:5]] == AGES
    assert frames[-1].iloc[0]['brand'] == 'Samsung'
    assert frames[-1].iloc[0]['product_model'] == 'Galaxy S25 Ultra'
    assert all(frame.iloc[0]['comparable_active_median'] == 85 for frame in frames)
    assert all(frame.iloc[0]['rental_duration_days'] == 1 for frame in frames)
    assert all(frame.iloc[0]['condition'] == 'Excellent' for frame in frames)
