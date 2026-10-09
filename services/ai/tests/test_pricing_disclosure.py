"""Controlled fixtures validate disclosures, not price-model accuracy."""
from types import SimpleNamespace

import numpy as np
import pytest

from app.schemas import PriceRecommendationRequest
from app.services import pricing
from app.training.pricing_dataset import FEATURES


class Model:
    calls = 0
    def __init__(self):
        encoder = SimpleNamespace(categories_=[['Apple'], ['iPhone 16']])
        transformer = SimpleNamespace(named_steps={'encoder': encoder})
        self.named_steps = {'features': SimpleNamespace(transformers_=[('categorical', transformer, ['brand', 'product_model'])])}
    def predict(self, frame):
        self.calls += 1
        return np.array([70.0])


def bundle(monkeypatch, sources=None):
    model = Model()
    artifact = {'global_model': model, 'feature_schema': {'ordered': FEATURES},
                'calibration': {'globalAbsoluteResidual': 5, 'categories': {}},
                'model_version': 'fixture', 'supported_categories': ['Devices'],
                'metrics': {'dataset': {'sourceTypes': sources or {'real': 100}}}}
    monkeypatch.setattr(pricing, '_artifact', lambda: (artifact, None, None))
    return model


def request(evidence, brand='Apple', model='iPhone 16'):
    return PriceRecommendationRequest(item_profile={
        'category': 'Devices', 'subcategory': 'Smartphones', 'condition': 'Excellent',
        'brand': brand, 'product_model': model, 'state': 'Kuala Lumpur', 'item_age_years': 1,
        'productMatchType': 'exact_catalog_match'},
        market_evidence=evidence, rental_duration_days=1, owner_trust_score=80)


def active(tier, exact=0):
    return {'comparable_active_count': 5, 'comparable_active_median': 70,
            'active_comparable_tier': tier, 'exact_active_count': exact,
            'market_freshness_days': 0}


def test_no_market_evidence_does_not_infer_or_show_precise_price(monkeypatch):
    model = bundle(monkeypatch)
    result = pricing.XGBoostPriceService().recommend(request({}))
    assert not result.available
    assert result.suggested_daily_price is None
    assert result.evidence_status == 'insufficient'
    assert result.product_specific_evidence is False
    assert model.calls == 0


@pytest.mark.parametrize('tier,scope', [
    ('category_wide', 'category_estimate'), ('subcategory_local', 'subcategory_estimate'),
    ('subcategory_brand_malaysia', 'brand_estimate'),
])
def test_broad_evidence_never_claims_product_specific_pricing(monkeypatch, tier, scope):
    bundle(monkeypatch)
    result = pricing.XGBoostPriceService().recommend(request(active(tier)))
    assert result.available
    assert result.pricing_scope == scope
    assert not result.product_specific_evidence
    assert result.confidence_label == 'low'
    assert result.confidence < 0.5
    assert any('Different products may receive the same estimate' in message for message in result.warnings)


def test_catalog_match_without_exact_price_evidence_is_still_broad(monkeypatch):
    bundle(monkeypatch)
    result = pricing.XGBoostPriceService().recommend(request(active('category_wide')))
    assert result.product_match['type'] == 'exact_catalog_match'
    assert not result.product_specific_evidence


def test_exact_completed_evidence_is_separate_from_catalog_recognition(monkeypatch):
    bundle(monkeypatch)
    result = pricing.XGBoostPriceService().recommend(request({
        'historical_rental_count': 5, 'historical_rental_median': 70,
        'historical_comparable_tier': 'exact_canonical_malaysia',
        'exact_completed_rental_count': 5, 'market_freshness_days': 0,
    }))
    assert result.product_specific_evidence
    assert result.pricing_scope == 'product_estimate'


def test_unknown_identity_and_synthetic_training_are_disclosed(monkeypatch):
    bundle(monkeypatch, {'synthetic': 5000, 'real': 19})
    result = pricing.XGBoostPriceService().recommend(request(active('exact_product_malaysia', 5), 'Unseen', 'Unseen'))
    assert result.identity_model_coverage == {'brand': 'unseen', 'product_model': 'unseen'}
    assert result.confidence_label == 'low'
    assert any('predominantly on synthetic/demo' in message for message in result.warnings)
    assert any('unique market value' in message for message in result.warnings)


def test_counts_without_usable_prices_are_not_market_evidence(monkeypatch):
    bundle(monkeypatch)
    result = pricing.XGBoostPriceService().recommend(request({'comparable_active_count': 10}))
    assert not result.available
