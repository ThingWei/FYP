"""Train reproducible price and collaborative-filtering artifacts.

The generated records are explicitly synthetic and are suitable for an FYP
prototype evaluation, not a production pricing policy.
"""

import argparse
import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder
from surprise import Dataset, Reader, SVD, accuracy, dump
from surprise.model_selection import train_test_split as surprise_split
from xgboost import XGBRegressor


CATEGORIES = {
    'Clothing': 28,
    'Vehicles': 165,
    'Devices': 75,
    'Books': 12,
    'Equipment': 95,
}
STATES = ['Kuala Lumpur', 'Selangor', 'Johor', 'Penang', 'Perak']
CONDITIONS = {'Fair': 0.72, 'Good': 0.84, 'Very good': 0.93, 'Excellent': 1.0, 'Like New': 1.08}


def price_data(rows: int, seed: int) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    output = []
    for _ in range(rows):
        category = rng.choice(list(CATEGORIES))
        condition = rng.choice(list(CONDITIONS))
        state = rng.choice(STATES)
        similar = CATEGORIES[category] * rng.uniform(0.75, 1.25)
        historical = CATEGORIES[category] * rng.uniform(0.8, 1.2)
        demand = rng.uniform(0.75, 1.45)
        seasonal = rng.uniform(0.85, 1.25)
        duration = int(rng.integers(1, 15))
        trust = rng.uniform(45, 100)
        rating = rng.uniform(2.5, 5)
        age = rng.uniform(0, 8)
        price = (
            0.42 * similar + 0.28 * historical + CATEGORIES[category] * 0.3
        ) * demand * seasonal * CONDITIONS[condition]
        price *= 1 + (trust - 70) / 500 + (rating - 3.5) / 20
        price *= max(0.7, 1 - age * 0.025) * max(0.82, 1 - (duration - 1) * 0.012)
        price += rng.normal(0, max(2, price * 0.06))
        output.append({
            'category': category,
            'subcategory': 'General',
            'condition': condition,
            'brand': rng.choice(['Generic', 'Sony', 'Canon', 'Samsung', 'Honda']),
            'state': state,
            'item_age_years': round(float(age), 2),
            'similar_active_average': round(float(similar), 2),
            'historical_completed_average': round(float(historical), 2),
            'supply_demand_ratio': round(float(demand), 3),
            'seasonal_day_factor': round(float(seasonal), 3),
            'rental_duration_days': duration,
            'owner_trust_score': round(float(trust), 2),
            'owner_average_rating': round(float(rating), 2),
            'daily_price': round(max(1, float(price)), 2),
        })
    return pd.DataFrame(output)


def train_price(frame: pd.DataFrame, models: Path, metrics_dir: Path, seed: int):
    target = frame.pop('daily_price')
    categorical = ['category', 'subcategory', 'condition', 'brand', 'state']
    preprocessor = ColumnTransformer([
        ('categorical', OneHotEncoder(handle_unknown='ignore'), categorical),
    ], remainder='passthrough')
    pipeline = Pipeline([
        ('features', preprocessor),
        ('model', XGBRegressor(
            n_estimators=280, max_depth=5, learning_rate=0.045,
            subsample=0.85, colsample_bytree=0.85,
            objective='reg:squarederror', random_state=seed,
        )),
    ])
    x_train, x_test, y_train, y_test = train_test_split(
        frame, target, test_size=0.2, random_state=seed,
    )
    pipeline.fit(x_train, y_train)
    prediction = pipeline.predict(x_test)
    metrics = {
        'dataset': 'deterministic-synthetic-v1',
        'rows': len(frame),
        'testRows': len(x_test),
        'mae': float(mean_absolute_error(y_test, prediction)),
        'rmse': float(mean_squared_error(y_test, prediction) ** 0.5),
        'r2': float(r2_score(y_test, prediction)),
        'seed': seed,
    }
    joblib.dump({'model': pipeline, 'metrics': metrics}, models / 'price_xgboost.joblib')
    (metrics_dir / 'price_metrics.json').write_text(json.dumps(metrics, indent=2), encoding='utf-8')


def train_recommendation(data_dir: Path, models: Path, metrics_dir: Path, seed: int):
    rng = np.random.default_rng(seed)
    rows = []
    for user in range(120):
        preference = int(rng.integers(0, 6))
        for item in rng.choice(180, size=28, replace=False):
            category = item % 6
            rating = np.clip(3.1 + (1.25 if category == preference else 0) + rng.normal(0, 0.75), 1, 5)
            rows.append({'user_id': f'u-{user}', 'item_id': f'l-{item}', 'rating': round(float(rating), 2)})
    frame = pd.DataFrame(rows)
    frame.to_csv(data_dir / 'recommendation_ratings.csv', index=False)
    dataset = Dataset.load_from_df(frame[['user_id', 'item_id', 'rating']], Reader(rating_scale=(1, 5)))
    trainset, testset = surprise_split(dataset, test_size=0.2, random_state=seed)
    model = SVD(n_factors=60, n_epochs=30, random_state=seed)
    model.fit(trainset)
    predictions = model.test(testset)
    metrics = {
        'dataset': 'deterministic-synthetic-v1',
        'ratings': len(frame),
        'testRatings': len(testset),
        'rmse': float(accuracy.rmse(predictions, verbose=False)),
        'mae': float(accuracy.mae(predictions, verbose=False)),
        'seed': seed,
    }
    dump.dump(str(models / 'recommendation_svd.pkl'), algo=model)
    (metrics_dir / 'recommendation_metrics.json').write_text(json.dumps(metrics, indent=2), encoding='utf-8')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--rows', type=int, default=5000)
    parser.add_argument('--seed', type=int, default=42)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    models = root / 'models'
    data_dir = root / 'data' / 'generated'
    metrics_dir = root / 'metrics'
    for directory in (models, data_dir, metrics_dir):
        directory.mkdir(parents=True, exist_ok=True)
    frame = price_data(args.rows, args.seed)
    frame.to_csv(data_dir / 'price_history.csv', index=False)
    train_price(frame.copy(), models, metrics_dir, args.seed)
    train_recommendation(data_dir, models, metrics_dir, args.seed)


if __name__ == '__main__':
    main()
