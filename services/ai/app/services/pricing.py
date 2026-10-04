import math
import os
from functools import lru_cache
from pathlib import Path

from ..schemas import PriceRecommendationRequest, PriceRecommendationResponse


SCHEMA_VERSION = 'renthub-price-v2'


@lru_cache(maxsize=1)
def _artifact():
    default_path = Path(__file__).resolve().parents[2] / 'models' / 'price_xgboost.joblib'
    path = Path(os.getenv('PRICE_MODEL_PATH', str(default_path)))
    if not path.is_file():
        return None, path, f'Trained price model is unavailable at {path}'
    try:
        import joblib
        bundle = joblib.load(path)
    except Exception as error:  # pragma: no cover - exact loader errors vary
        return None, path, f'Price artifact could not be loaded: {error}'
    if bundle.get('schema_version') != SCHEMA_VERSION:
        return None, path, 'Price artifact schema is incompatible; retraining is required'
    required = {'global_model', 'feature_schema', 'calibration', 'model_version'}
    if not required.issubset(bundle):
        return None, path, 'Price artifact bundle is incomplete; retraining is required'
    return bundle, path, None


def _number(value):
    if value is None:
        return None
    parsed = float(value)
    return parsed if math.isfinite(parsed) else None


def _confidence(prediction, half_width, evidence, row, supported, match_type):
    active = int(evidence.get('comparable_active_count') or 0)
    historical = int(evidence.get('historical_rental_count') or 0)
    evidence_score = min(1.0, math.log1p(active + historical) / math.log1p(40))
    reliability = max(0.0, 1 - half_width / max(prediction, 1))
    freshness_value = evidence.get('market_freshness_days')
    freshness_days = max(0.0, float(365 if freshness_value is None else freshness_value))
    freshness = math.exp(-freshness_days / 180)
    important = ['subcategory', 'condition', 'brand', 'product_model', 'state']
    completeness = sum(bool(row.get(key) and row[key] != 'Unknown') for key in important) / len(important)
    score = 0.45 * reliability + 0.35 * evidence_score + 0.1 * freshness + 0.1 * completeness
    match_quality = {
        'exact_catalog_match': 1.0,
        'fuzzy_catalog_match': 0.85,
        'catalog_brand_match_model_manual': 0.65,
        'manual_entry': 0.45,
    }.get(match_type, 0.45)
    score *= 0.75 + 0.25 * match_quality
    if row['category'] not in supported:
        score *= 0.65
    score = round(max(0, min(0.95, score)), 4)
    label = 'high' if score >= 0.75 else 'medium' if score >= 0.5 else 'low'
    return score, label


class XGBoostPriceService:
    def recommend(self, request: PriceRecommendationRequest) -> PriceRecommendationResponse:
        bundle, path, error = _artifact()
        evidence = request.market_evidence
        if bundle is None:
            return PriceRecommendationResponse(
                available=False,
                confidence=0,
                confidence_label='low',
                adapter='xgboost-v2',
                model_source='unavailable',
                error=error,
                warnings=['A compatible trained pricing artifact is not installed.'],
                evidence=evidence,
                similar_listing_average=request.similar_active_average,
                historical_average=request.historical_completed_average,
            )
        profile = request.item_profile
        match_type = str(profile.get('productMatchType') or 'manual_entry')
        product_match = {
            'type': match_type,
            'brand': str(profile.get('brand') or ''),
            'model': str(profile.get('product_model') or ''),
            'canonicalProductId': profile.get('canonicalProductId'),
            'source': profile.get('catalogSource'),
        }
        row = {
            'category': str(profile.get('category') or 'Unknown'),
            'subcategory': str(profile.get('subcategory') or 'Unknown'),
            'condition': str(profile.get('condition') or 'Unknown'),
            'brand': str(profile.get('brand') or 'Unknown'),
            'product_model': str(profile.get('product_model') or 'Unknown'),
            'state': str(profile.get('state') or 'Unknown'),
            'item_age_years': _number(profile.get('item_age_years')),
            'rental_duration_days': request.rental_duration_days,
            'comparable_active_count': int(evidence.get('comparable_active_count') or 0),
            'comparable_active_median': _number(evidence.get('comparable_active_median')),
            'comparable_active_mean': _number(evidence.get('comparable_active_mean')),
            'comparable_active_iqr': _number(evidence.get('comparable_active_iqr')),
            'historical_rental_count': int(evidence.get('historical_rental_count') or 0),
            'historical_rental_median': _number(evidence.get('historical_rental_median')),
            'historical_rental_mean': _number(evidence.get('historical_rental_mean')),
            'historical_rental_iqr': _number(evidence.get('historical_rental_iqr')),
            'market_freshness_days': _number(evidence.get('market_freshness_days')),
            'demand_supply_ratio': _number(evidence.get('demand_supply_ratio')),
            'owner_trust_score': request.owner_trust_score,
            'owner_average_rating': request.owner_average_rating,
            'owner_completed_rentals': request.owner_completed_rentals,
            'prediction_month': request.prediction_month,
        }
        expected = bundle['feature_schema']['ordered']
        if set(row) != set(expected):
            return PriceRecommendationResponse(
                available=False,
                confidence=0,
                adapter='xgboost-v2',
                model_source='incompatible_schema',
                model_version=bundle['model_version'],
                error='Inference feature schema does not match the trained artifact',
                warnings=['Retrain the artifact with the current feature contract.'],
                evidence=evidence,
            )
        import pandas as pd
        category_models = bundle.get('category_models', {})
        model = category_models.get(row['category'], bundle['global_model'])
        model_source = 'category_xgboost' if row['category'] in category_models else 'global_xgboost'
        prediction = float(model.predict(pd.DataFrame([row], columns=expected))[0])
        if not math.isfinite(prediction):
            return PriceRecommendationResponse(
                available=False,
                confidence=0,
                adapter='xgboost-v2',
                model_source=model_source,
                model_version=bundle['model_version'],
                error='Pricing model returned a non-finite value',
                evidence=evidence,
            )
        prediction = max(1.0, prediction)
        calibration = bundle['calibration']
        half_width = float(
            calibration.get('categories', {}).get(
                row['category'], calibration['globalAbsoluteResidual'],
            ),
        )
        lower = max(1.0, prediction - half_width)
        upper = max(prediction, prediction + half_width)
        supported = set(bundle.get('supported_categories', []))
        confidence, confidence_label = _confidence(
            prediction, half_width, evidence, row, supported, match_type,
        )
        warnings = []
        if row['category'] not in supported:
            warnings.append('The category was not represented in the training data.')
        if row['brand'] == 'Unknown' or row['product_model'] == 'Unknown':
            warnings.append('Brand or exact product information is missing.')
        if int(evidence.get('historical_rental_count') or 0) == 0:
            warnings.append('No matching completed-rental evidence was available.')
        if match_type == 'manual_entry':
            warnings.append('The product was entered manually, so broader market evidence was used.')
        elif match_type == 'catalog_brand_match_model_manual':
            warnings.append('The brand was recognised but the model was entered manually.')
        elif match_type == 'fuzzy_catalog_match':
            warnings.append('The product was selected from a fuzzy catalog match.')
        metrics = bundle.get('metrics', {})
        return PriceRecommendationResponse(
            available=True,
            suggested_daily_price=round(prediction, 2),
            lower_bound=round(lower, 2),
            upper_bound=round(upper, 2),
            confidence=confidence,
            confidence_label=confidence_label,
            currency='MYR',
            adapter='xgboost-v2',
            model_source=model_source,
            model_version=bundle['model_version'],
            evaluation={
                'schemaVersion': metrics.get('schemaVersion'),
                'globalModel': metrics.get('globalModel', {}),
                'selectedModelStrategy': metrics.get('selectedModelStrategy', {}),
                'baseline': metrics.get('baseline', {}),
                'predictionInterval': metrics.get('predictionInterval', {}),
                'datasetSourceTypes': metrics.get('dataset', {}).get('sourceTypes', {}),
            },
            explanation=[
                (
                    f'Product recognised as {row["brand"]} {row["product_model"]}.'
                    if match_type in {'exact_catalog_match', 'fuzzy_catalog_match'}
                    else 'Pricing used a manually entered product identity.'
                ),
                f'Selected {model_source.replace("_", " ")} for {row["category"]}.',
                f'Used {evidence.get("exact_active_count", 0)} exact and {evidence.get("similar_active_count", row["comparable_active_count"])} similar active listing(s).',
                f'Used {evidence.get("exact_completed_rental_count", 0)} exact and {evidence.get("similar_completed_rental_count", row["historical_rental_count"])} similar completed rental(s).',
                f'The range uses the {int(calibration.get("quantile", 0.9) * 100)}th-percentile held-out absolute residual.',
            ],
            warnings=warnings,
            evidence=evidence,
            product_match=product_match,
            similar_listing_average=row['comparable_active_mean'],
            historical_average=row['historical_rental_mean'],
        )
