from fastapi import APIRouter
from ..schemas import ItemRecommendationRequest, Recommendation, PriceRecommendationRequest, PriceRecommendationResponse
from ..services.adapters import RecommendationAdapter, PriceAdapter
router = APIRouter(prefix='/recommend', tags=['recommendation'])
@router.post('/items', response_model=list[Recommendation])
def recommend_items(request: ItemRecommendationRequest): return RecommendationAdapter().recommend(request.user_id, request.limit)
@router.post('/price', response_model=PriceRecommendationResponse)
def recommend_price(request: PriceRecommendationRequest): return PriceAdapter().recommend(request)

