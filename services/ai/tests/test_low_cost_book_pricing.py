"""Fixture inference contracts, not evidence of real-market book accuracy."""
from types import SimpleNamespace

import numpy as np
import pytest

from app.schemas import PriceRecommendationRequest
from app.services import pricing
from app.training.pricing_dataset import FEATURES


@pytest.mark.parametrize('category,value,expected', [
    ('Books', 0.01, 0.01), ('Books', 0.35, 0.35), ('Books', 0.99, 0.99),
    ('Books', 1.0, 1.0), ('Devices', 0.35, 1.0), ('Books', 0.004, None),
])
def test_category_minimum_and_unrounded_evidence(monkeypatch, category, value, expected):
    frames = []

    def predict(frame):
        frames.append(frame)
        return np.array([value])

    artifact = {'global_model': SimpleNamespace(predict=predict),
                'feature_schema': {'ordered': FEATURES},
                'calibration': {'globalAbsoluteResidual': 0.1},
                'model_version': 'fixture', 'supported_categories': [category],
                'metrics': {'dataset': {'sourceTypes': {'synthetic': 5000, 'real': 19}}}}
    monkeypatch.setattr(pricing, '_artifact', lambda: (artifact, None, None))
    result = pricing.XGBoostPriceService().recommend(PriceRecommendationRequest(
        item_profile={'category': category, 'subcategory': 'Fiction' if category == 'Books' else 'Smartphones',
                      'brand': 'Author', 'product_model': 'Title', 'condition': 'Good', 'item_age_years': 1},
        rental_duration_days=14, owner_trust_score=80, market_evidence={'comparable_active_count': 3,
            'comparable_active_median': 5 / 14, 'active_comparable_tier': 'exact_product_malaysia'},
    ))
    assert frames[0].iloc[0]['comparable_active_median'] == 5 / 14
    assert frames[0].iloc[0]['rental_duration_days'] == 14
    assert result.suggested_daily_price == expected
    assert result.available == (expected is not None)
    if expected is not None:
        assert (0.01 if category == 'Books' else 1) <= result.lower_bound <= expected <= result.upper_bound
        assert any('synthetic/demo' in message for message in result.warnings)
        assert result.confidence_label == 'low'


def test_relative_uncertainty_is_not_hidden_by_one_ringgit_denominator():
    args = ({'comparable_active_count': 10}, {'category': 'Books'}, {'Books'}, 'manual_entry')
    assert pricing._confidence(0.35, 0.2, *args) == pricing._confidence(35, 20, *args)
