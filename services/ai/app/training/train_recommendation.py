"""Train and evaluate RentHub's Surprise SVD recommendation artifact."""

from __future__ import annotations

import argparse
import hashlib
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
    candidate_items: set | None = None,
) -> dict:
    all_items = sorted(candidate_items if candidate_items is not None else set(train.item_id) | set(test.item_id))
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


def _scores(model, train, test, *, candidate_items=None):
    context = {'candidateListings': len(candidate_items if candidate_items is not None else set(train.item_id) | set(test.item_id)),
               'heldOutUsers': int(test.user_id.nunique()),
               'coldStartUsers': len(set(test.user_id) - set(train.user_id)),
               'coldStartListings': len(set(test.item_id) - set(train.item_id))}
    if test.empty:
        return {**context, 'status': 'no_holdout', 'testInteractions': 0, 'rmse': None,
                'mae': None, **_ranking_metrics(model, train, test, candidate_items=candidate_items)}
    predictions = model.test(list(test[['user_id', 'item_id', 'rating']].itertuples(index=False, name=None)))
    return {**context, 'status': 'evaluated', 'testInteractions': len(test),
            'rmse': float(accuracy.rmse(predictions, verbose=False)),
            'mae': float(accuracy.mae(predictions, verbose=False)),
            **_ranking_metrics(model, train, test, candidate_items=candidate_items)}


def _by_source(model, train, test, frame):
    return {source: _scores(model, train, test.loc[test.source_type == source],
                           candidate_items=set(frame.loc[frame.source_type == source, 'item_id']))
            for source in ['marketplace', 'demo_seed', 'synthetic']}


def _marketplace_experiment(frame, seed):
    real = frame.loc[frame.source_type == 'marketplace'].reset_index(drop=True)
    counts = {'interactions': len(real), 'users': int(real.user_id.nunique()),
              'listings': int(real.item_id.nunique())}
    if len(real) < 10 or real.user_id.nunique() < 2 or real.item_id.nunique() < 2:
        return {**counts, 'status': 'insufficient_data', 'rmse': None, 'mae': None,
                'reason': 'Needs at least 10 marketplace interactions, 2 users and 2 listings; this is a technical minimum, not evidence of reliable accuracy.'}
    train, test = temporal_user_split(real)
    if test.empty:
        return {**counts, 'status': 'no_holdout', 'rmse': None, 'mae': None}
    model = _fit(train, seed)
    mean = float(train.rating.mean())
    return {**counts, **_scores(model, train, test), 'trainInteractions': len(train),
            'trainingSources': ['marketplace'],
            'trainMeanBaseline': {'mae': float((test.rating - mean).abs().mean()),
                                  'rmse': float(((test.rating - mean) ** 2).mean() ** 0.5)},
            'limitation': 'Small implicit-feedback holdout; not an online user study or hybrid-feed evaluation.'}


def _existing_artifact_diagnostic(artifact, train, test, frame):
    if artifact is None or not artifact.is_file():
        return {'status': 'unavailable', 'reason': 'No local baseline artifact'}
    try:
        # Only load a locally trusted Surprise pickle, never a submitted file.
        fingerprint = hashlib.sha256(artifact.read_bytes()).hexdigest()
        _, model = dump.load(str(artifact))
        known = {(model.trainset.to_raw_uid(u), model.trainset.to_raw_iid(i))
                 for u, i, _ in model.trainset.all_ratings()}
        overlap = sum((u, i) in known for u, i in zip(test.user_id, test.item_id))
        if overlap:
            return {'status': 'not_comparable_seen_holdout', 'artifactSha256': fingerprint,
                    'seenHoldoutPairs': overlap, 'testInteractions': len(test),
                    'reason': 'Existing artifact already trained on held-out pairs; no independent comparison is reported.'}
        return {'status': 'diagnostic_only', 'artifactSha256': fingerprint,
                'seenHoldoutPairs': 0, 'metrics': _scores(model, train, test),
                'evaluationBySource': _by_source(model, train, test, frame),
                'reason': 'Baseline training chronology is unknown; no model promotion or accuracy claim.'}
    except Exception:
        return {'status': 'unavailable', 'reason': 'Local artifact incompatible or unreadable'}


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
    evaluate_only: bool = False,
    baseline_artifact: Path | None = None,
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
        if evaluate_only:
            return {'mode': 'evaluation_only', 'status': 'insufficient_data',
                    'provenance': provenance, 'marketplaceOnly': _marketplace_experiment(frame, seed),
                    'artifactWritten': False}
        raise ValueError(
            'Recommendation training needs at least 10 interactions, 2 users, and 2 listings',
        )
    train, test = temporal_user_split(frame)
    if test.empty:
        if evaluate_only:
            return {'mode': 'evaluation_only', 'status': 'no_holdout',
                    'provenance': provenance, 'marketplaceOnly': _marketplace_experiment(frame, seed),
                    'artifactWritten': False}
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
        'mode': 'evaluation_only' if evaluate_only else 'training_and_deployment',
        'evaluationBySource': _by_source(evaluation_model, train, test, frame),
        'marketplaceOnly': _marketplace_experiment(frame, seed),
        'limitations': [
            'Combined scores mix provenance; use source cohorts and marketplaceOnly for evidence assessment.',
            'Per-user chronological holdout is not a global time cutoff; other users may have later training activity.',
            'Ratings encode implicit actions, not independently measured satisfaction.',
            'This evaluates collaborative SVD, not the full content/proximity/availability feed.',
            'No automatic model selection or deployment follows evaluation.',
        ],
    }
    if evaluate_only:
        metrics['existingArtifact'] = _existing_artifact_diagnostic(
            baseline_artifact or models_dir / 'recommendation_svd.pkl', train, test, frame,
        )
        metrics['artifactWritten'] = False
        return metrics
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
    parser.add_argument('--evaluate-only', action='store_true', help='Fit temporary evaluation models; do not change deployed artifacts, metrics or datasets')
    parser.add_argument('--baseline-artifact', type=Path, help='Locally trusted Surprise artifact for diagnostic comparison only')
    parser.add_argument('--report', type=Path, help='New evaluation JSON file; existing files are never overwritten')
    args = parser.parse_args()
    if args.report and not args.evaluate_only:
        parser.error('--report requires --evaluate-only')
    if args.report:
        protected = [root / 'models', root / 'metrics', root / 'data']
        if any(args.report.resolve().is_relative_to(directory.resolve()) for directory in protected):
            parser.error('Evaluation reports must be outside deployed models, metrics and data directories')
        if args.report.exists():
            parser.error('Report already exists; choose a new file')
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
        evaluate_only=args.evaluate_only,
        baseline_artifact=args.baseline_artifact,
    )
    if args.report:
        # Exclusive create also prevents races with another evaluation process.
        with args.report.open('x', encoding='utf-8') as output:
            json.dump(metrics, output, indent=2)
    print(json.dumps(metrics, indent=2))


if __name__ == '__main__':
    main()
