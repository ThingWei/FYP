"""Read-only pricing audit. No retraining, exports, seeds or price rules."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from urllib.error import URLError
from urllib.request import Request, urlopen

from app.schemas import PriceRecommendationRequest
from app.services.pricing import XGBoostPriceService, _artifact


AGES = [0, 1, 3, 5, 8]


def controlled_request(brand: str, model: str, age: float = 1):
    return PriceRecommendationRequest(
        item_profile={
            'category': 'Devices', 'subcategory': 'Smartphones',
            'condition': 'Excellent', 'brand': brand, 'product_model': model,
            'state': 'Kuala Lumpur', 'item_age_years': age,
            'productMatchType': 'exact_catalog_match',
        },
        market_evidence={
            'comparable_active_count': 4, 'comparable_active_median': 85,
            'comparable_active_mean': 85, 'comparable_active_iqr': 10,
            'historical_rental_count': 1, 'historical_rental_median': 85,
            'historical_rental_mean': 85, 'historical_rental_iqr': 0,
            'exact_active_count': 0, 'exact_completed_rental_count': 0,
            'marketplace_completed_rental_count': 1,
            'demo_seed_completed_rental_count': 0,
            'active_comparable_tier': 'subcategory_malaysia',
            'historical_comparable_tier': 'category_wide',
            'market_freshness_days': 5, 'demand_supply_ratio': 0.25,
        },
        rental_duration_days=1, owner_trust_score=80,
        owner_average_rating=4.5, owner_completed_rentals=20,
        prediction_month=10,
    )


def request_json(url: str, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    with urlopen(Request(url, data=data, headers={'Content-Type': 'application/json'}), timeout=10) as response:
        return json.load(response)


def audit(ai_url: str):
    bundle, path, error = _artifact()
    if bundle is None:
        return {'artifactAvailable': False, 'reason': 'Compatible artifact unavailable'}
    metrics_path = Path(__file__).resolve().parents[2] / 'metrics' / 'price_metrics.json'
    saved_metrics = json.loads(metrics_path.read_text()) if metrics_path.is_file() else {}
    metrics = bundle.get('metrics', {})
    service = XGBoostPriceService()
    identities = [('Apple', 'iPhone 17 Pro Max'), ('Samsung', 'Galaxy S25 Ultra'),
                  ('Unseen brand A', 'Unseen model A'), ('Unseen brand B', 'Unseen model B')]
    comparisons = []
    for brand, model in identities:
        result = service.recommend(controlled_request(brand, model)).model_dump()
        comparisons.append({key: result.get(key) for key in (
            'suggested_daily_price', 'model_source', 'identity_model_coverage', 'pricing_scope')}
            | {'brand': brand, 'model': model})
    age_results = []
    for age in AGES:
        result = service.recommend(controlled_request(*identities[0], age)).model_dump()
        age_results.append({'ageYears': age, 'dailyPrice': result.get('suggested_daily_price')})
    running = {'reachable': False}
    try:
        health = request_json(f'{ai_url.rstrip("/")}/health')
        probe = controlled_request(*identities[0])
        remote = request_json(f'{ai_url.rstrip("/")}/recommend/price', probe.model_dump())
        local = service.recommend(probe).model_dump()
        running = {
            'reachable': True,
            'reportedPathMatchesLocal': Path(health.get('price_model_status', {}).get('path', '')) == path,
            'modelVersionMatchesLocal': remote.get('model_version') == local.get('model_version'),
            'controlledPredictionMatchesLocal': remote.get('suggested_daily_price') == local.get('suggested_daily_price'),
            'sourceTypesMatchLocal': remote.get('evaluation', {}).get('datasetSourceTypes') == metrics.get('dataset', {}).get('sourceTypes'),
        }
    except (URLError, TimeoutError, ValueError, OSError):
        running['limitation'] = 'Running service could not be verified; results below use the local configured artifact.'
    importance = metrics.get('featureImportance', {})
    return {
        'artifactAvailable': True,
        'artifactSha256': hashlib.sha256(path.read_bytes()).hexdigest(),
        'modelVersion': bundle['model_version'],
        'savedMetricsMatchArtifact': metrics == saved_metrics,
        'sourceTypes': metrics.get('dataset', {}).get('sourceTypes'),
        'targetSources': metrics.get('dataset', {}).get('targetSources'),
        'realLabelEvaluation': metrics.get('sourceTypes', {}).get('real'),
        'runningService': running,
        'fixedEvidence': {'activeMedian': 85, 'historicalMedian': 85, 'activeCount': 4, 'historicalCount': 1},
        'identityComparisons': comparisons,
        'agePredictions': age_results,
        'permutationMeanMaeIncrease': {key: importance.get('permutationMeanMaeIncrease', {}).get(key)
                                       for key in ('brand', 'product_model', 'item_age_years')},
        'purpose': 'controlled_inference_not_verified_market_prices',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ai-url', default='http://127.0.0.1:8001')
    args = parser.parse_args()
    print(json.dumps(audit(args.ai_url), indent=2))


if __name__ == '__main__':
    main()
