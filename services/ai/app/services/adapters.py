from abc import ABC, abstractmethod
from ..schemas import VerificationRequest, VerificationResponse, Recommendation, PriceRecommendationRequest, PriceRecommendationResponse

class VerificationAdapter(ABC):
    @abstractmethod
    def verify(self, request: VerificationRequest) -> VerificationResponse: ...

class PlaceholderVerificationAdapter(VerificationAdapter):
    def __init__(self, kind: str): self.kind = kind
    def verify(self, request: VerificationRequest) -> VerificationResponse:
        confidence = 0.82 if request.image_url else 0.0
        return VerificationResponse(accepted=confidence >= 0.65, confidence=confidence, labels=[request.expected_type or self.kind], reasons=[] if confidence >= 0.65 else ['Low confidence'], adapter='placeholder')

class RecommendationAdapter:
    def recommend(self, user_id: str, limit: int) -> list[Recommendation]:
        return [Recommendation(item_id=f'demo-item-{i+1}', score=round(0.92-i*0.03, 2), reason='Hybrid preference and listing similarity') for i in range(min(limit, 5))]

class PriceAdapter:
    def recommend(self, request: PriceRecommendationRequest) -> PriceRecommendationResponse:
        base = (request.similar_active_average + request.historical_completed_average) / 2
        duration_discount = max(0.75, 1 - (request.rental_duration_days - 1) * 0.01)
        price = max(1, base * request.supply_demand_ratio * request.seasonal_day_factor * duration_discount)
        return PriceRecommendationResponse(suggested_daily_price=round(price, 2), lower_bound=round(price*.85, 2), upper_bound=round(price*1.15, 2), confidence=.72, adapter='placeholder')

