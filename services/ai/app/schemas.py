from typing import Any, Literal

from pydantic import BaseModel, Field


class EncodedImage(BaseModel):
    content_base64: str
    content_type: str = 'image/jpeg'
    filename: str = 'image.jpg'


class VerificationRequest(BaseModel):
    images: list[EncodedImage] = Field(default_factory=list)
    image_url: str | None = None
    expected_type: str | None = None
    expected_category: str | None = None
    profile_name: str | None = None


class VerificationResponse(BaseModel):
    accepted: bool
    outcome: Literal['approved', 'warning', 'manual_review', 'rejected', 'unavailable']
    confidence: float = Field(ge=0, le=1)
    labels: list[str] = Field(default_factory=list)
    reasons: list[str] = Field(default_factory=list)
    adapter: str
    model_versions: dict[str, str] = Field(default_factory=dict)
    quality: dict[str, Any] = Field(default_factory=dict)
    ocr_text: str = ''
    extracted_fields: dict[str, Any] = Field(default_factory=dict)
    risk_indicators: list[str] = Field(default_factory=list)


class RecommendationCandidate(BaseModel):
    item_id: str
    title: str
    category: str
    description: str = ''
    location: str = ''
    condition: str = ''
    price: float = Field(ge=0)
    rating: float = Field(default=0, ge=0, le=5)
    popularity: float = Field(default=0, ge=0)
    available: bool = True


class UserInteraction(BaseModel):
    user_id: str
    item_id: str
    rating: float = Field(ge=1, le=5)


class ItemRecommendationRequest(BaseModel):
    user_id: str
    limit: int = Field(default=10, ge=1, le=100)
    candidates: list[RecommendationCandidate] = Field(default_factory=list)
    interactions: list[UserInteraction] = Field(default_factory=list)
    context: dict[str, Any] = Field(default_factory=dict)


class Recommendation(BaseModel):
    item_id: str
    score: float = Field(ge=0, le=1)
    content_score: float = Field(ge=0, le=1)
    collaborative_score: float = Field(ge=0, le=1)
    reason: str
    adapter: str


class PriceRecommendationRequest(BaseModel):
    item_profile: dict[str, Any]
    similar_active_average: float = Field(ge=0)
    historical_completed_average: float = Field(ge=0)
    supply_demand_ratio: float = Field(gt=0)
    seasonal_day_factor: float = Field(gt=0)
    rental_duration_days: int = Field(ge=1)
    owner_trust_score: float = Field(ge=0, le=100)
    owner_average_rating: float = Field(default=0, ge=0, le=5)


class PriceRecommendationResponse(BaseModel):
    available: bool
    suggested_daily_price: float | None = None
    lower_bound: float | None = None
    upper_bound: float | None = None
    confidence: float = Field(ge=0, le=1)
    adapter: str
    model_version: str | None = None
    explanation: list[str] = Field(default_factory=list)
    similar_listing_average: float
    historical_average: float
    error: str | None = None
