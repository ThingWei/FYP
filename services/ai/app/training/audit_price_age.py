"""Audit item-age sensitivity of a trained RentHub pricing artifact."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import joblib
import pandas as pd


AGES = [0, 1, 3, 5, 8]


def controlled_predictions(bundle: dict, category: str = 'Devices') -> dict:
    profile = {
        'category': category,
        'subcategory': {
            'Devices': 'Smartphones',
            'Vehicles': 'Cars',
            'Books': 'Fiction',
            'Equipment': 'Tools',
            'Clothing': 'Formal wear',
        }.get(category, 'Unknown'),
        'condition': 'Excellent',
        'brand': 'Controlled brand',
        'product_model': 'Controlled model',
        'state': 'Kuala Lumpur',
        'item_age_years': 0,
        'rental_duration_days': 3,
        'comparable_active_count': 8,
        'comparable_active_median': 100,
        'comparable_active_mean': 102,
        'comparable_active_iqr': 12,
        'historical_rental_count': 10,
        'historical_rental_median': 95,
        'historical_rental_mean': 96,
        'historical_rental_iqr': 10,
        'market_freshness_days': 5,
        'demand_supply_ratio': 1.25,
        'owner_trust_score': 80,
        'owner_average_rating': 4.5,
        'owner_completed_rentals': 20,
        'prediction_month': 10,
    }
    rows = []
    for age in AGES:
        row = dict(profile)
        row['item_age_years'] = age
        rows.append(row)
    model = bundle.get('category_models', {}).get(category, bundle['global_model'])
    frame = pd.DataFrame(rows, columns=bundle['feature_schema']['ordered'])
    predictions = model.predict(frame)
    metrics = bundle.get('metrics', {}).get('featureImportance', {})
    return {
        'category': category,
        'modelSource': (
            'category_xgboost'
            if category in bundle.get('category_models', {})
            else 'global_xgboost'
        ),
        'fixedEvidence': {
            'activeMedian': profile['comparable_active_median'],
            'historicalMedian': profile['historical_rental_median'],
        },
        'predictions': [
            {'itemAgeYears': age, 'suggestedDailyPrice': round(float(value), 2)}
            for age, value in zip(AGES, predictions)
        ],
        'itemAgeNativeImportance': metrics.get('itemAgeNativeImportance'),
        'itemAgePermutationMeanMaeIncrease': metrics.get(
            'itemAgePermutationMeanMaeIncrease',
        ),
        'itemAgePermutationForCategory': metrics.get(
            'itemAgePermutationByCategory', {},
        ).get(category),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--artifact', type=Path)
    parser.add_argument('--category', default='Devices')
    args = parser.parse_args()
    default = Path(__file__).resolve().parents[2] / 'models' / 'price_xgboost.joblib'
    bundle = joblib.load(args.artifact or default)
    print(json.dumps(controlled_predictions(bundle, args.category), indent=2))


if __name__ == '__main__':
    main()
