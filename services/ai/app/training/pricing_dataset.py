"""Canonical, provenance-aware pricing dataset preparation.

Real observations are exported by the Express/Mongoose data-export command.
Synthetic observations are explicitly labelled FYP bootstrap data and are
never represented as completed marketplace rentals.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
import pandas as pd


SEED = 42
CATEGORIES = {
    'Clothing': ['Formal wear', 'Costumes', 'Traditional wear'],
    'Vehicles': ['Cars', 'Motorcycles', 'Bicycles'],
    'Devices': ['Smartphones', 'Cameras', 'Computers', 'Audio', 'Gaming'],
    'Books': ['Fiction', 'Textbooks', 'Reference books'],
    'Equipment': ['Event equipment', 'Tools', 'Sports equipment'],
}
BRANDS = {
    'Clothing': ['Generic', 'Padini', 'Zalia', 'H&M'],
    'Vehicles': ['Perodua', 'Proton', 'Honda', 'Yamaha'],
    'Devices': ['Apple', 'Samsung', 'Sony', 'Canon', 'Dell'],
    'Books': ['Penguin', 'HarperCollins', 'Oxford', 'Pearson'],
    'Equipment': ['Bosch', 'Makita', 'DJI', 'Yamaha'],
}
STATES = ['Kuala Lumpur', 'Selangor', 'Johor', 'Penang', 'Perak']
CONDITIONS = ['Fair', 'Good', 'Very good', 'Excellent', 'Like New']

CATEGORICAL_FEATURES = [
    'category', 'subcategory', 'condition', 'brand', 'product_model', 'state',
]
NUMERIC_FEATURES = [
    'item_age_years', 'rental_duration_days', 'comparable_active_count',
    'comparable_active_median', 'comparable_active_mean', 'comparable_active_iqr',
    'historical_rental_count', 'historical_rental_median',
    'historical_rental_mean', 'historical_rental_iqr', 'market_freshness_days',
    'demand_supply_ratio', 'owner_trust_score', 'owner_average_rating',
    'owner_completed_rentals', 'prediction_month',
]
FEATURES = CATEGORICAL_FEATURES + NUMERIC_FEATURES
REQUIRED_COLUMNS = FEATURES + [
    'daily_price', 'source_type', 'target_source', 'observed_at', 'group_id',
]


def _synthetic_rows(rows: int, seed: int) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    output: list[dict] = []
    model_catalogue = {
        category: [
            f'{brand} {subcategory} {variant}'
            for brand in BRANDS[category]
            for subcategory in subcategories
            for variant in range(1, 7)
        ]
        for category, subcategories in CATEGORIES.items()
    }
    replacement_ranges = {
        'Clothing': (60, 850), 'Vehicles': (900, 95_000),
        'Devices': (250, 12_000), 'Books': (18, 380),
        'Equipment': (180, 18_000),
    }
    utilization_ranges = {
        'Clothing': (0.025, 0.075), 'Vehicles': (0.004, 0.016),
        'Devices': (0.015, 0.055), 'Books': (0.025, 0.09),
        'Equipment': (0.012, 0.05),
    }
    condition_retention = dict(zip(CONDITIONS, [0.58, 0.72, 0.84, 0.94, 1.0]))
    start = pd.Timestamp('2024-01-01', tz='UTC')
    for _ in range(rows):
        category = str(rng.choice(list(CATEGORIES)))
        subcategory = str(rng.choice(CATEGORIES[category]))
        brand = str(rng.choice(BRANDS[category]))
        condition = str(rng.choice(CONDITIONS))
        state = str(rng.choice(STATES))
        model = str(rng.choice(model_catalogue[category]))
        age = float(rng.uniform(0, 10))
        duration = int(rng.integers(1, 22))
        replacement = float(rng.uniform(*replacement_ranges[category]))
        utilization = float(rng.uniform(*utilization_ranges[category]))
        latent_market = replacement * utilization * condition_retention[condition]
        latent_market *= max(0.55, 1 - age * float(rng.uniform(0.015, 0.045)))
        latent_market *= float(rng.lognormal(0, 0.12))
        active_count = int(rng.integers(0, 35))
        history_count = int(rng.integers(0, 55))
        active_median = latent_market * float(rng.uniform(0.88, 1.14))
        history_median = latent_market * float(rng.uniform(0.9, 1.1))
        active_iqr = active_median * float(rng.uniform(0.08, 0.35))
        history_iqr = history_median * float(rng.uniform(0.06, 0.28))
        observed_at = start + pd.Timedelta(days=int(rng.integers(0, 900)))
        market_anchor = np.nanmedian([
            active_median if active_count else np.nan,
            history_median if history_count else np.nan,
            latent_market,
        ])
        duration_effect = float(rng.uniform(0.82, 1.0)) if duration > 5 else 1.0
        daily_price = max(
            1, market_anchor * duration_effect * float(rng.lognormal(0, 0.08)),
        )
        output.append({
            'category': category, 'subcategory': subcategory,
            'condition': condition, 'brand': brand, 'product_model': model,
            'state': state, 'item_age_years': round(age, 3),
            'rental_duration_days': duration,
            'comparable_active_count': active_count,
            'comparable_active_median': round(active_median, 2) if active_count else np.nan,
            'comparable_active_mean': round(active_median * rng.uniform(0.97, 1.04), 2) if active_count else np.nan,
            'comparable_active_iqr': round(active_iqr, 2) if active_count >= 4 else np.nan,
            'historical_rental_count': history_count,
            'historical_rental_median': round(history_median, 2) if history_count else np.nan,
            'historical_rental_mean': round(history_median * rng.uniform(0.97, 1.04), 2) if history_count else np.nan,
            'historical_rental_iqr': round(history_iqr, 2) if history_count >= 4 else np.nan,
            'market_freshness_days': int(rng.integers(0, 181)),
            'demand_supply_ratio': round(history_count / max(active_count, 1), 4),
            'owner_trust_score': round(float(rng.uniform(35, 100)), 2),
            'owner_average_rating': round(float(rng.uniform(0, 5)), 2),
            'owner_completed_rentals': int(rng.integers(0, 160)),
            'prediction_month': int(observed_at.month),
            'daily_price': round(float(daily_price), 2),
            'source_type': 'synthetic', 'target_source': 'synthetic_seed',
            'observed_at': observed_at.isoformat(),
            'group_id': f'synthetic:{category}:{model}',
        })
    return pd.DataFrame(output)


def _real_rows(path: Path | None) -> pd.DataFrame:
    if path is None or not path.is_file():
        return pd.DataFrame(columns=REQUIRED_COLUMNS)
    payload = json.loads(path.read_text(encoding='utf-8'))
    frame = pd.DataFrame(payload if isinstance(payload, list) else payload.get('rows', []))
    for column in REQUIRED_COLUMNS:
        if column not in frame:
            frame[column] = np.nan
    return frame[REQUIRED_COLUMNS]


def validate_dataset(frame: pd.DataFrame) -> dict:
    missing = [column for column in REQUIRED_COLUMNS if column not in frame]
    if missing:
        raise ValueError(f'Missing pricing columns: {missing}')
    if frame.empty:
        raise ValueError('Pricing dataset is empty')
    frame['daily_price'] = pd.to_numeric(frame['daily_price'], errors='coerce')
    invalid_target = (~np.isfinite(frame['daily_price'])) | (frame['daily_price'] <= 0)
    if invalid_target.any():
        raise ValueError(f'Invalid daily-price rows: {int(invalid_target.sum())}')
    duplicate_count = int(frame.duplicated(
        subset=['group_id', 'observed_at', 'daily_price', 'target_source'],
    ).sum())
    if duplicate_count:
        raise ValueError(f'Duplicate pricing observations: {duplicate_count}')
    dates = pd.to_datetime(
        frame['observed_at'], utc=True, errors='coerce', format='mixed',
    )
    if dates.isna().any():
        raise ValueError(f'Invalid observed_at rows: {int(dates.isna().sum())}')
    q1 = float(frame['daily_price'].quantile(0.25))
    q3 = float(frame['daily_price'].quantile(0.75))
    iqr = q3 - q1
    outlier_count = int((frame['daily_price'] > q3 + 3 * iqr).sum()) if iqr > 0 else 0
    return {
        'rows': int(len(frame)),
        'sourceTypes': frame['source_type'].value_counts(dropna=False).to_dict(),
        'targetSources': frame['target_source'].value_counts(dropna=False).to_dict(),
        'categories': frame['category'].value_counts(dropna=False).to_dict(),
        'target': {
            'minimum': float(frame['daily_price'].min()),
            'median': float(frame['daily_price'].median()),
            'maximum': float(frame['daily_price'].max()),
        },
        'nullRates': {
            column: round(float(frame[column].isna().mean()), 4)
            for column in FEATURES
        },
        'duplicates': duplicate_count,
        'highOutliersAboveThreeIqr': outlier_count,
    }


def prepare_dataset(real_export: Path | None, synthetic_rows: int, seed: int = SEED):
    real = _real_rows(real_export)
    frames = [real.dropna(axis=1, how='all')] if not real.empty else []
    if synthetic_rows:
        frames.append(_synthetic_rows(synthetic_rows, seed))
    if not frames:
        raise ValueError('No real or synthetic pricing observations were supplied')
    frame = pd.concat(frames, ignore_index=True)
    frame = frame.dropna(subset=['category', 'daily_price', 'observed_at', 'group_id'])
    frame = frame.drop_duplicates(
        subset=['group_id', 'observed_at', 'daily_price', 'target_source'],
    ).reset_index(drop=True)
    summary = validate_dataset(frame)
    fingerprint_source = frame.sort_values(
        ['group_id', 'observed_at'], kind='stable',
    ).to_csv(index=False).encode()
    summary['fingerprintSha256'] = hashlib.sha256(fingerprint_source).hexdigest()
    summary['seed'] = seed
    return frame, summary
