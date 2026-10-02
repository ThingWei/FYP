import os
from functools import lru_cache
from pathlib import Path

from ..schemas import PriceRecommendationRequest, PriceRecommendationResponse


@lru_cache(maxsize=1)
def _artifact():
    default_path = Path(__file__).resolve().parents[2] / 'models' / 'price_xgboost.joblib'
    path = Path(os.getenv('PRICE_MODEL_PATH', str(default_path)))
    if not path.is_file():
        return None, None, path
    import joblib
    bundle = joblib.load(path)
    return bundle['model'], bundle.get('metrics', {}), path


class XGBoostPriceService:
    def recommend(self, request: PriceRecommendationRequest) -> PriceRecommendationResponse:
        model, metrics, path = _artifact()
        if model is None:
            return PriceRecommendationResponse(
                available=False,
                confidence=0,
                adapter='xgboost-v1',
                error=f'Trained price model is unavailable at {path}',
                similar_listing_average=request.similar_active_average,
                historical_average=request.historical_completed_average,
            )
        profile = request.item_profile
        row = {
            'category': str(profile.get('category', 'Unknown')),
            'subcategory': str(profile.get('subcategory', 'General')),
            'condition': str(profile.get('condition', 'Good')),
            'brand': str(profile.get('brand', 'Unknown')),
            'state': str(profile.get('state', 'Kuala Lumpur')),
            'item_age_years': float(profile.get('item_age_years', 1)),
            'similar_active_average': request.similar_active_average,
            'historical_completed_average': request.historical_completed_average,
            'supply_demand_ratio': request.supply_demand_ratio,
            'seasonal_day_factor': request.seasonal_day_factor,
            'rental_duration_days': request.rental_duration_days,
            'owner_trust_score': request.owner_trust_score,
            'owner_average_rating': request.owner_average_rating,
        }
        import pandas as pd
        prediction = max(1.0, float(model.predict(pd.DataFrame([row]))[0]))
        mae = float(metrics.get('mae', prediction * 0.15))
        confidence = max(0.4, min(0.95, 1 - mae / max(prediction, 1)))
        lower = max(1, prediction - 1.25 * mae)
        upper = prediction + 1.25 * mae
        return PriceRecommendationResponse(
            available=True,
            suggested_daily_price=round(prediction, 2),
            lower_bound=round(lower, 2),
            upper_bound=round(upper, 2),
            confidence=round(confidence, 4),
            adapter='xgboost-v1',
            model_version=path.name,
            evaluation={
                key: metrics[key]
                for key in ('dataset', 'rows', 'testRows', 'mae', 'rmse', 'r2', 'seed')
                if key in metrics
            },
            explanation=[
                f"Compared with active {row['category']} listings in {row['state']}",
                f"Historical completed-rental average: RM {request.historical_completed_average:.2f}",
                f"Supply/demand multiplier: {request.supply_demand_ratio:.2f}",
                f"Duration considered: {request.rental_duration_days} day(s)",
                f"Owner trust and rating: {request.owner_trust_score:.0f}/100, {request.owner_average_rating:.1f}/5",
            ],
            similar_listing_average=request.similar_active_average,
            historical_average=request.historical_completed_average,
        )
