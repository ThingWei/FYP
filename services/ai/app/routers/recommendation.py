from fastapi import APIRouter, HTTPException

from ..schemas import (
    ItemRecommendationRequest,
    PriceRecommendationRequest,
    PriceRecommendationResponse,
    Recommendation,
)
from ..services.adapters import HybridRecommendationService, XGBoostPriceService

router = APIRouter(prefix='/recommend', tags=['recommendation'])
recommendation_service = HybridRecommendationService()
price_service = XGBoostPriceService()


@router.post('/items', response_model=list[Recommendation])
def recommend_items(request: ItemRecommendationRequest):
    try:
        return recommendation_service.recommend(request)
    except RuntimeError as error:
        raise HTTPException(status_code=503, detail=str(error)) from error


@router.post('/price', response_model=PriceRecommendationResponse)
def recommend_price(request: PriceRecommendationRequest):
    return price_service.recommend(request)
