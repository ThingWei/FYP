"""Train and evaluate RentHub's Surprise SVD recommendation artifact."""

from __future__ import annotations

import argparse
import json
import math
import os
import tempfile
from pathlib import Path

import pandas as pd
import sklearn
import surprise
from surprise import Dataset, Reader, SVD, accuracy, dump

from .recommendation_dataset import prepare_recommendation_dataset


def temporal_user_split(
    frame: pd.DataFrame,
    test_fraction: float = 0.2,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    train_indexes: list[int] = []
    test_indexes: list[int] = []
    for _, group in frame.sort_values('observed_at').groupby('user_id'):
        if len(group) < 2:
            train_indexes.extend(group.index.tolist())
            continue
        test_count = max(1, int(round(len(group) * test_fraction)))
        test_count = min(test_count, len(group) - 1)
        train_indexes.extend(group.index[:-test_count].tolist())
        test_indexes.extend(group.index[-test_count:].tolist())
    train = frame.loc[train_indexes].reset_index(drop=True)
    test = frame.loc[test_indexes].reset_index(drop=True)
    train_pairs = set(zip(train.user_id, train.item_id))
    test_pairs = set(zip(test.user_id, test.item_id))
    if not train_pairs.isdisjoint(test_pairs):
        raise ValueError('Recommendation train/test interaction leakage detected')
    return train, test


def _fit(frame: pd.DataFrame, seed: int) -> SVD:
    dataset = Dataset.load_from_df(
        frame[['user_id', 'item_id', 'rating']],
        Reader(rating_scale=(1, 5)),
    )
    model = SVD(n_factors=60, n_epochs=30, random_state=seed)
    model.fit(dataset.build_full_trainset())
    return model


def _ranking_metrics(
    model: SVD,
    train: pd.DataFrame,
    test: pd.DataFrame,
    *,
    k: int = 5,
    relevance_threshold: float = 4,
) -> dict:
    all_items = sorted(set(train.item_id) | set(test.item_id))
    train_items = train.groupby('user_id')['item_id'].apply(set).to_dict()
    precision: list[float] = []
    recall: list[float] = []
    hits: list[float] = []
    evaluated = 0
    for user_id, held_out in test.groupby('user_id'):
        relevant = set(
            held_out.loc[
                held_out.rating >= relevance_threshold,
                'item_id',
            ],
        )
        if not relevant or user_id not in train_items:
            continue
        candidates = [
            item_id
            for item_id in all_items
            if item_id not in train_items[user_id]
        ]
        ranked = sorted(
            candidates,
            key=lambda item_id: model.predict(user_id, item_id).est,
            reverse=True,
        )[:k]
        if not ranked:
            continue
        match_count = len(set(ranked) & relevant)
        precision.append(match_count / len(ranked))
        recall.append(match_count / len(relevant))
        hits.append(1.0 if match_count else 0.0)
        evaluated += 1
    if not evaluated:
        return {
            'precisionAt5': None,
            'recallAt5': None,
            'hitRateAt5': None,
            'rankingUsers': 0,
            'rankingLimitation': (
                'No held-out users had both training history and a rating >= 4.'
            ),
        }
    return {
        'precisionAt5': sum(precision) / evaluated,
        'recallAt5': sum(recall) / evaluated,
        'hitRateAt5': sum(hits) / evaluated,
        'rankingUsers': evaluated,
        'rankingLimitation': None,
    }


def _atomic_dump(model: SVD, artifact: Path) -> None:
    artifact.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        prefix='recommendation-',
        suffix='.pkl',
        dir=artifact.parent,
        delete=False,
    ) as temporary:
        temporary_path = Path(temporary.name)
    try:
        dump.dump(str(temporary_path), algo=model)
        _, reloaded = dump.load(str(temporary_path))
        smoke = float(reloaded.predict('compatibility-user', 'compatibility-item').est)
        if not math.isfinite(smoke):
            raise ValueError('Reloaded recommendation artifact returned non-finite output')
        os.replace(temporary_path, artifact)
    finally:
        temporary_path.unlink(missing_ok=True)


def train_recommendation_artifact(
    *,
    real_export: Path | None,
    models_dir: Path,
    metrics_dir: Path,
    data_dir: Path,
    seed: int = 42,
    include_synthetic: bool = True,
    synthetic_users: int = 120,
    synthetic_items: int = 180,
    synthetic_interactions_per_user: int = 28,
) -> dict:
    frame, provenance = prepare_recommendation_dataset(
        real_export,
        seed=seed,
        include_synthetic=include_synthetic,
        synthetic_users=synthetic_users,
        synthetic_items=synthetic_items,
        synthetic_interactions_per_user=synthetic_interactions_per_user,
    )
    if len(frame) < 10 or frame.user_id.nunique() < 2 or frame.item_id.nunique() < 2:
        raise ValueError(
            'Recommendation training needs at least 10 interactions, 2 users, and 2 listings',
        )
    train, test = temporal_user_split(frame)
    if test.empty:
        raise ValueError('Recommendation evaluation needs held-out interactions')
    evaluation_model = _fit(train, seed)
    testset = list(test[['user_id', 'item_id', 'rating']].itertuples(
        index=False,
        name=None,
    ))
    predictions = evaluation_model.test(testset)
    metrics = {
        'dataset': 'marketplace-plus-labelled-synthetic-v2',
        'seed': seed,
        'splitStrategy': 'per-user chronological holdout',
        'trainInteractions': len(train),
        'testInteractions': len(test),
        'rmse': float(accuracy.rmse(predictions, verbose=False)),
        'mae': float(accuracy.mae(predictions, verbose=False)),
        **_ranking_metrics(evaluation_model, train, test),
        'provenance': provenance,
        'versions': {
            'surprise': surprise.__version__,
            'pandas': pd.__version__,
            'scikitLearn': sklearn.__version__,
        },
        'artifact': 'recommendation_svd.pkl',
    }
    final_model = _fit(frame, seed)
    _atomic_dump(final_model, models_dir / 'recommendation_svd.pkl')
    data_dir.mkdir(parents=True, exist_ok=True)
    metrics_dir.mkdir(parents=True, exist_ok=True)
    frame.to_csv(data_dir / 'recommendation_interactions.csv', index=False)
    (metrics_dir / 'recommendation_metrics.json').write_text(
        json.dumps(metrics, indent=2),
        encoding='utf-8',
    )
    return metrics


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    default_export = root.parent / 'api' / '.data' / 'recommendation_interactions.json'
    parser = argparse.ArgumentParser()
    parser.add_argument('--real-export', type=Path, default=default_export)
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--no-synthetic', action='store_true')
    parser.add_argument('--synthetic-users', type=int, default=120)
    parser.add_argument('--synthetic-items', type=int, default=180)
    parser.add_argument('--synthetic-interactions-per-user', type=int, default=28)
    args = parser.parse_args()
    metrics = train_recommendation_artifact(
        real_export=args.real_export,
        models_dir=root / 'models',
        metrics_dir=root / 'metrics',
        data_dir=root / 'data' / 'generated',
        seed=args.seed,
        include_synthetic=not args.no_synthetic,
        synthetic_users=args.synthetic_users,
        synthetic_items=args.synthetic_items,
        synthetic_interactions_per_user=args.synthetic_interactions_per_user,
    )
    print(json.dumps(metrics, indent=2))


if __name__ == '__main__':
    main()
