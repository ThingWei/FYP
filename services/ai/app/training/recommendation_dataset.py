"""Canonical, provenance-labelled recommendation interaction datasets."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
import pandas as pd


INTERACTION_PRECEDENCE = {
    'saved': 1,
    'booking': 2,
    'completed_rental': 3,
    'published_review': 4,
    'synthetic_preference': 1,
}
VALID_SOURCE_TYPES = {'marketplace', 'demo_seed', 'synthetic'}


def _synthetic_rows(
    *,
    seed: int,
    users: int,
    items: int,
    interactions_per_user: int,
) -> list[dict]:
    rng = np.random.default_rng(seed)
    rows = []
    origin = pd.Timestamp('2024-01-01T00:00:00Z')
    for user_index in range(users):
        preference = int(rng.integers(0, 6))
        choices = rng.choice(
            items,
            size=min(interactions_per_user, items),
            replace=False,
        )
        for sequence, item_index in enumerate(choices):
            category = int(item_index) % 6
            rating = np.clip(
                3.1
                + (1.25 if category == preference else 0)
                + rng.normal(0, 0.75),
                1,
                5,
            )
            rows.append({
                'user_id': f'synthetic-u-{user_index}',
                'item_id': f'synthetic-l-{int(item_index)}',
                'rating': round(float(rating), 2),
                'interaction_type': 'synthetic_preference',
                'observed_at': origin + pd.Timedelta(
                    days=user_index,
                    minutes=sequence,
                ),
                'source_type': 'synthetic',
            })
    return rows


def _load_export(path: Path | None) -> list[dict]:
    if path is None or not path.is_file():
        return []
    payload = json.loads(path.read_text(encoding='utf-8'))
    rows = payload.get('rows', payload if isinstance(payload, list) else [])
    return [{
        'user_id': row.get('userId', row.get('user_id')),
        'item_id': row.get('listingId', row.get('item_id')),
        'rating': row.get('rating'),
        'interaction_type': row.get(
            'interactionType',
            row.get('interaction_type'),
        ),
        'observed_at': row.get('observedAt', row.get('observed_at')),
        'source_type': row.get('sourceType', row.get('source_type')),
    } for row in rows]


def _canonicalize(rows: list[dict]) -> tuple[pd.DataFrame, int]:
    frame = pd.DataFrame(rows, columns=[
        'user_id',
        'item_id',
        'rating',
        'interaction_type',
        'observed_at',
        'source_type',
    ])
    if frame.empty:
        return frame, 0
    frame['user_id'] = frame['user_id'].fillna('').astype(str).str.strip()
    frame['item_id'] = frame['item_id'].fillna('').astype(str).str.strip()
    frame['rating'] = pd.to_numeric(frame['rating'], errors='coerce')
    frame['observed_at'] = pd.to_datetime(
        frame['observed_at'],
        errors='coerce',
        utc=True,
    )
    frame['interaction_type'] = frame['interaction_type'].fillna('').astype(str)
    frame['source_type'] = frame['source_type'].fillna('').astype(str)
    valid = (
        frame['user_id'].ne('')
        & frame['item_id'].ne('')
        & frame['rating'].between(1, 5)
        & frame['observed_at'].notna()
        & frame['interaction_type'].isin(INTERACTION_PRECEDENCE)
        & frame['source_type'].isin(VALID_SOURCE_TYPES)
    )
    discarded = int((~valid).sum())
    frame = frame.loc[valid].copy()
    frame['precedence'] = frame['interaction_type'].map(INTERACTION_PRECEDENCE)
    frame = frame.sort_values(
        ['user_id', 'item_id', 'precedence', 'observed_at'],
    ).drop_duplicates(['user_id', 'item_id'], keep='last')
    frame = frame.drop(columns='precedence').sort_values(
        ['user_id', 'observed_at', 'item_id'],
    ).reset_index(drop=True)
    return frame, discarded


def prepare_recommendation_dataset(
    real_export: Path | None,
    *,
    seed: int = 42,
    synthetic_users: int = 120,
    synthetic_items: int = 180,
    synthetic_interactions_per_user: int = 28,
    include_synthetic: bool = True,
) -> tuple[pd.DataFrame, dict]:
    real_rows = _load_export(real_export)
    rows = list(real_rows)
    if include_synthetic:
        rows.extend(_synthetic_rows(
            seed=seed,
            users=synthetic_users,
            items=synthetic_items,
            interactions_per_user=synthetic_interactions_per_user,
        ))
    frame, discarded = _canonicalize(rows)
    csv_bytes = frame.to_csv(index=False).encode('utf-8')
    summary = {
        'schemaVersion': 'renthub-recommendation-interactions-v1',
        'users': int(frame['user_id'].nunique()) if not frame.empty else 0,
        'listings': int(frame['item_id'].nunique()) if not frame.empty else 0,
        'interactions': int(len(frame)),
        'realMarketplaceInteractions': int(
            (frame['source_type'] == 'marketplace').sum()
        ) if not frame.empty else 0,
        'demoSeedInteractions': int(
            (frame['source_type'] == 'demo_seed').sum()
        ) if not frame.empty else 0,
        'syntheticInteractions': int(
            (frame['source_type'] == 'synthetic').sum()
        ) if not frame.empty else 0,
        'discardedInvalidRows': discarded,
        'sourceDistribution': frame['source_type'].value_counts().to_dict(),
        'interactionDistribution': (
            frame['interaction_type'].value_counts().to_dict()
        ),
        'ratingDistribution': {
            str(key): int(value)
            for key, value in frame['rating'].round().value_counts().sort_index().items()
        },
        'fingerprintSha256': hashlib.sha256(csv_bytes).hexdigest(),
    }
    return frame, summary
