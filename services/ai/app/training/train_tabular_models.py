"""Train reproducible, calibrated pricing and recommendation artifacts."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
import sklearn
import xgboost
from sklearn.compose import ColumnTransformer
from sklearn.impute import SimpleImputer
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.model_selection import GroupShuffleSplit
from sklearn.inspection import permutation_importance
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder
from xgboost import XGBRegressor

from .pricing_dataset import (
    CATEGORICAL_FEATURES,
    FEATURES,
    NUMERIC_FEATURES,
    prepare_dataset,
)
from .train_recommendation import train_recommendation_artifact


SCHEMA_VERSION = 'renthub-price-v2'
CATEGORY_MODEL_MIN_TRAIN_ROWS = 500
CATEGORY_MODEL_MIN_VALIDATION_ROWS = 75
CATEGORY_MODEL_REQUIRED_IMPROVEMENT = 0.02
CALIBRATION_QUANTILE = 0.9
TARGET_SOURCE_WEIGHTS = {
    'completed_rental': 1.0,
    'accepted_booking': 0.75,
    'active_asking': 0.45,
    'synthetic_seed': 0.35,
    'demo_seed_completed_rental': 0.35,
    'demo_seed_accepted_booking': 0.25,
    'demo_seed_active_asking': 0.15,
}


def _pipeline(seed: int, monotone_age: bool = False) -> Pipeline:
    categorical = Pipeline([
        ('imputer', SimpleImputer(strategy='constant', fill_value='Unknown')),
        ('encoder', OneHotEncoder(handle_unknown='ignore', sparse_output=False)),
    ])
    numeric = Pipeline([('imputer', SimpleImputer(strategy='median'))])
    features = ColumnTransformer([
        ('categorical', categorical, CATEGORICAL_FEATURES),
        ('numeric', numeric, NUMERIC_FEATURES),
    ]).set_output(transform='pandas')
    return Pipeline([
        ('features', features),
        ('model', XGBRegressor(
            n_estimators=360,
            max_depth=6,
            learning_rate=0.035,
            min_child_weight=3,
            subsample=0.85,
            colsample_bytree=0.85,
            reg_lambda=1.2,
            objective='reg:squarederror',
            random_state=seed,
            n_jobs=1,
            monotone_constraints=(
                {'numeric__item_age_years': -1} if monotone_age else None
            ),
        )),
    ])


def _metric_block(actual, predicted) -> dict:
    return {
        'rows': int(len(actual)),
        'mae': float(mean_absolute_error(actual, predicted)),
        'rmse': float(mean_squared_error(actual, predicted) ** 0.5),
        'r2': float(r2_score(actual, predicted)) if len(actual) >= 2 else None,
    }


def _split(frame: pd.DataFrame, seed: int):
    groups = frame['group_id'].astype(str)
    first = GroupShuffleSplit(n_splits=1, test_size=0.30, random_state=seed)
    train_idx, holdout_idx = next(first.split(frame, groups=groups))
    holdout = frame.iloc[holdout_idx].reset_index(drop=True)
    second = GroupShuffleSplit(n_splits=1, test_size=0.50, random_state=seed + 1)
    valid_idx, test_idx = next(
        second.split(holdout, groups=holdout['group_id'].astype(str)),
    )
    return (
        frame.iloc[train_idx].reset_index(drop=True),
        holdout.iloc[valid_idx].reset_index(drop=True),
        holdout.iloc[test_idx].reset_index(drop=True),
    )


def _baseline_predict(train: pd.DataFrame, target: pd.DataFrame) -> np.ndarray:
    global_median = float(train['daily_price'].median())
    medians = train.groupby(['category', 'subcategory'])['daily_price'].median()
    return np.array([
        float(medians.get((row.category, row.subcategory), global_median))
        for row in target.itertuples()
    ])


def _sample_weights(frame: pd.DataFrame) -> np.ndarray:
    return frame['target_source'].map(TARGET_SOURCE_WEIGHTS).fillna(0.25).to_numpy()


def _feature_importance(model: Pipeline, frame: pd.DataFrame, seed: int) -> dict:
    sample = frame.sample(min(len(frame), 1000), random_state=seed)
    permutation = permutation_importance(
        model,
        sample[FEATURES],
        sample['daily_price'],
        scoring='neg_mean_absolute_error',
        n_repeats=5,
        random_state=seed,
        n_jobs=1,
    )
    permutation_values = {
        feature: float(value)
        for feature, value in zip(FEATURES, permutation.importances_mean)
    }
    transformed_names = model.named_steps['features'].get_feature_names_out()
    native_values = model.named_steps['model'].feature_importances_
    native = sorted(
        (
            {'feature': str(feature), 'importance': float(value)}
            for feature, value in zip(transformed_names, native_values)
        ),
        key=lambda item: item['importance'],
        reverse=True,
    )
    return {
        'method': 'held-out permutation MAE increase; native XGBoost gain',
        'permutationMeanMaeIncrease': permutation_values,
        'itemAgePermutationMeanMaeIncrease': permutation_values['item_age_years'],
        'itemAgeNativeImportance': next(
            (
                item['importance'] for item in native
                if item['feature'].endswith('__item_age_years')
            ),
            0.0,
        ),
        'topNativeFeatures': native[:20],
    }


def _atomic_joblib(payload: dict, target: Path):
    target.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(dir=target.parent, suffix='.joblib.tmp')
    os.close(descriptor)
    try:
        joblib.dump(payload, temporary)
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def _fresh_process_smoke(artifact: Path, frame: pd.DataFrame):
    representatives = (
        frame.groupby('category', sort=True, group_keys=False)
        .head(1)[FEATURES]
        .copy()
    )
    unknown = representatives.iloc[[0]].copy()
    unknown.loc[:, 'brand'] = 'Previously unseen brand'
    unknown.loc[:, 'product_model'] = None
    representatives = pd.concat([representatives, unknown], ignore_index=True)
    records = representatives.astype(object).where(
        pd.notna(representatives), None,
    ).to_dict(orient='records')
    code = (
        'import json, joblib, numpy as np, pandas as pd, sys; '
        'bundle=joblib.load(sys.argv[1]); rows=json.loads(sys.argv[2]); '
        'features=bundle["feature_schema"]["ordered"]; '
        'values=bundle["global_model"].predict(pd.DataFrame(rows, columns=features)); '
        'assert len(values)==len(rows) and np.isfinite(values).all()'
    )
    subprocess.run(
        [sys.executable, '-c', code, str(artifact), json.dumps(records)],
        check=True,
        capture_output=True,
        text=True,
    )


def train_price(frame: pd.DataFrame, models: Path, metrics_dir: Path, seed: int, summary: dict):
    started = time.perf_counter()
    train, validation, test = _split(frame, seed)
    global_model = _pipeline(seed)
    global_model.fit(
        train[FEATURES],
        train['daily_price'],
        model__sample_weight=_sample_weights(train),
    )
    validation_prediction = global_model.predict(validation[FEATURES])
    test_prediction = global_model.predict(test[FEATURES])
    baseline_prediction = _baseline_predict(train, test)
    global_residuals = np.abs(validation['daily_price'].to_numpy() - validation_prediction)
    calibration = {
        'quantile': CALIBRATION_QUANTILE,
        'globalAbsoluteResidual': float(np.quantile(global_residuals, CALIBRATION_QUANTILE)),
        'categories': {},
    }
    category_models = {}
    category_metrics = {}
    for category in sorted(frame['category'].unique()):
        train_category = train[train['category'] == category]
        validation_category = validation[validation['category'] == category]
        test_category = test[test['category'] == category]
        if len(test_category):
            category_metrics[category] = _metric_block(
                test_category['daily_price'],
                global_model.predict(test_category[FEATURES]),
            )
        if len(validation_category) >= CATEGORY_MODEL_MIN_VALIDATION_ROWS:
            residuals = np.abs(
                validation_category['daily_price'].to_numpy() -
                global_model.predict(validation_category[FEATURES])
            )
            calibration['categories'][category] = float(
                np.quantile(residuals, CALIBRATION_QUANTILE),
            )
        if (
            len(train_category) < CATEGORY_MODEL_MIN_TRAIN_ROWS or
            len(validation_category) < CATEGORY_MODEL_MIN_VALIDATION_ROWS
        ):
            continue
        monotone_age = category in {'Devices', 'Vehicles'}
        candidate = _pipeline(seed, monotone_age=monotone_age)
        candidate.fit(
            train_category[FEATURES],
            train_category['daily_price'],
            model__sample_weight=_sample_weights(train_category),
        )
        candidate_mae = mean_absolute_error(
            validation_category['daily_price'],
            candidate.predict(validation_category[FEATURES]),
        )
        global_mae = mean_absolute_error(
            validation_category['daily_price'],
            global_model.predict(validation_category[FEATURES]),
        )
        meets_accuracy_threshold = (
            candidate_mae <= global_mae * (1 - CATEGORY_MODEL_REQUIRED_IMPROVEMENT)
            or (monotone_age and candidate_mae <= global_mae * 1.02)
        )
        if meets_accuracy_threshold:
            category_models[category] = candidate
            candidate_residuals = np.abs(
                validation_category['daily_price'].to_numpy() -
                candidate.predict(validation_category[FEATURES])
            )
            calibration['categories'][category] = float(
                np.quantile(candidate_residuals, CALIBRATION_QUANTILE),
            )
            category_metrics[category]['selectedCategoryModel'] = True
            category_metrics[category]['validationMae'] = float(candidate_mae)
            if len(test_category):
                category_metrics[category].update(_metric_block(
                    test_category['daily_price'],
                    candidate.predict(test_category[FEATURES]),
                ))
        elif category in category_metrics:
            category_metrics[category]['selectedCategoryModel'] = False

    final_test_prediction = test_prediction.copy()
    for category, category_model in category_models.items():
        mask = test['category'].to_numpy() == category
        final_test_prediction[mask] = category_model.predict(test.loc[mask, FEATURES])
    half_widths = np.array([
        calibration['categories'].get(category, calibration['globalAbsoluteResidual'])
        for category in test['category']
    ])
    coverage = float(np.mean(
        (test['daily_price'].to_numpy() >= final_test_prediction - half_widths) &
        (test['daily_price'].to_numpy() <= final_test_prediction + half_widths)
    ))
    feature_importance = _feature_importance(global_model, test, seed)
    feature_importance['itemAgePermutationByCategory'] = {
        category: _feature_importance(
            category_models.get(category, global_model),
            test[test['category'] == category],
            seed,
        )['itemAgePermutationMeanMaeIncrease']
        for category in sorted(test['category'].unique())
        if len(test[test['category'] == category]) >= 20
    }
    metrics = {
        'schemaVersion': SCHEMA_VERSION,
        'dataset': summary,
        'split': {
            'strategy': 'grouped-by-product-model',
            'trainRows': len(train),
            'validationRows': len(validation),
            'testRows': len(test),
        },
        'globalModel': _metric_block(test['daily_price'], test_prediction),
        'selectedModelStrategy': _metric_block(test['daily_price'], final_test_prediction),
        'baseline': _metric_block(test['daily_price'], baseline_prediction),
        'categories': category_metrics,
        'sourceTypes': {
            source: _metric_block(
                test[test['source_type'] == source]['daily_price'],
                global_model.predict(test[test['source_type'] == source][FEATURES]),
            )
            for source in sorted(test['source_type'].unique())
            if len(test[test['source_type'] == source]) >= 2
        },
        'predictionInterval': {
            'quantile': CALIBRATION_QUANTILE,
            'testCoverage': coverage,
        },
        'seed': seed,
        'targetSourceWeights': TARGET_SOURCE_WEIGHTS,
        'featureImportance': feature_importance,
        'trainingSeconds': round(time.perf_counter() - started, 3),
        'versions': {
            'sklearn': sklearn.__version__,
            'xgboost': xgboost.__version__,
            'pandas': pd.__version__,
            'numpy': np.__version__,
        },
    }
    bundle = {
        'schema_version': SCHEMA_VERSION,
        'model_version': f'{SCHEMA_VERSION}-{summary["fingerprintSha256"][:12]}',
        'trained_at': datetime.now(timezone.utc).isoformat(),
        'global_model': global_model,
        'category_models': category_models,
        'feature_schema': {
            'categorical': CATEGORICAL_FEATURES,
            'numeric': NUMERIC_FEATURES,
            'ordered': FEATURES,
        },
        'supported_categories': sorted(frame['category'].unique()),
        'calibration': calibration,
        'metrics': metrics,
        'training_data_fingerprint': summary['fingerprintSha256'],
    }
    artifact = models / 'price_xgboost.joblib'
    _atomic_joblib(bundle, artifact)
    _fresh_process_smoke(artifact, train)
    metrics_dir.mkdir(parents=True, exist_ok=True)
    (metrics_dir / 'price_metrics.json').write_text(
        json.dumps(metrics, indent=2), encoding='utf-8',
    )
    return metrics


def train_recommendation(
    data_dir: Path,
    models: Path,
    metrics_dir: Path,
    seed: int,
    real_export: Path | None = None,
):
    return train_recommendation_artifact(
        real_export=real_export,
        models_dir=models,
        metrics_dir=metrics_dir,
        data_dir=data_dir,
        seed=seed,
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--synthetic-rows', type=int, default=5000)
    parser.add_argument('--real-export', type=Path)
    parser.add_argument('--recommendation-export', type=Path)
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--skip-recommendation', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    models = root / 'models'
    data_dir = root / 'data' / 'generated'
    metrics_dir = root / 'metrics'
    for directory in (models, data_dir, metrics_dir):
        directory.mkdir(parents=True, exist_ok=True)
    frame, summary = prepare_dataset(args.real_export, args.synthetic_rows, args.seed)
    frame.to_csv(data_dir / 'price_history.csv', index=False)
    (data_dir / 'price_data_quality.json').write_text(
        json.dumps(summary, indent=2), encoding='utf-8',
    )
    train_price(frame.copy(), models, metrics_dir, args.seed, summary)
    if not args.skip_recommendation:
        train_recommendation(
            data_dir,
            models,
            metrics_dir,
            args.seed,
            args.recommendation_export,
        )


if __name__ == '__main__':
    main()
