from typing import Any
from pydantic import BaseModel, Field

class VerificationRequest(BaseModel):
    image_url: str
    expected_type: str | None = None

class VerificationResponse(BaseModel):
    accepted: bool
    confidence: float = Field(ge=0, le=1)
    labels: list[str]
    reasons: list[str] = []
    adapter: str

class ItemRecommendationRequest(BaseModel):
    user_id: str
    limit: int = Field(default=10, ge=1, le=100)
    context: dict[str, Any] = {}

class Recommendation(BaseModel):
    item_id: str
    score: float
    reason: str

class PriceRecommendationRequest(BaseModel):
    item_profile: dict[str, Any]
    similar_active_average: float
    historical_completed_average: float
    supply_demand_ratio: float
    seasonal_day_factor: float
    rental_duration_days: int = Field(ge=1)
    owner_trust_score: float = Field(ge=0)

class PriceRecommendationResponse(BaseModel):
    suggested_daily_price: float
    lower_bound: float
    upper_bound: float
    confidence: float
    adapter: str

