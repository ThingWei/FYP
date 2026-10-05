from datetime import datetime
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
    review_threshold: float = Field(default=0.8, ge=0, le=1)
    minimum_age: int = Field(default=18, ge=18, le=100)


class VerificationResponse(BaseModel):
    accepted: bool
    outcome: Literal[
        'approved', 'approved_candidate', 'warning', 'manual_review',
        'rescan_required', 'rejected', 'unavailable'
    ]
    confidence: float = Field(ge=0, le=1)
    labels: list[str] = Field(default_factory=list)
    reasons: list[str] = Field(default_factory=list)
    adapter: str
    model_versions: dict[str, str] = Field(default_factory=dict)
    quality: dict[str, Any] = Field(default_factory=dict)
    ocr_text: str = ''
    extracted_fields: dict[str, Any] = Field(default_factory=dict)
    risk_indicators: list[str] = Field(default_factory=list)


class DocumentFrameRequest(BaseModel):
    content_base64: str
    content_type: Literal['image/jpeg', 'image/png'] = 'image/jpeg'
    expected_type: Literal['mykad', 'passport', 'driving_licence']


class DocumentFrameResponse(BaseModel):
    available: bool
    detected: bool
    ready: bool
    confidence: float = Field(ge=0, le=1)
    guidance: str
    quality: dict[str, Any] = Field(default_factory=dict)
    bounding_box: list[float] | None = None
    adapter: str


class RecommendationCandidate(BaseModel):
    item_id: str
    title: str
    category: str
    subcategory: str = ''
    brand: str = ''
    product_model: str = ''
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
    interaction_type: Literal[
        'saved',
        'booking',
        'completed_rental',
        'published_review',
        'synthetic_preference',
    ] = 'saved'
    observed_at: datetime | None = None
    source_type: Literal['marketplace', 'demo_seed', 'synthetic'] = 'marketplace'


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
    schema_version: Literal['renthub-price-v2'] = 'renthub-price-v2'
    item_profile: dict[str, Any]
    market_evidence: dict[str, Any] = Field(default_factory=dict)
    similar_active_average: float | None = Field(default=None, ge=0)
    historical_completed_average: float | None = Field(default=None, ge=0)
    supply_demand_ratio: float | None = Field(default=None, ge=0)
    seasonal_day_factor: float | None = Field(default=None, gt=0)
    rental_duration_days: int = Field(ge=1)
    owner_trust_score: float = Field(ge=0, le=100)
    owner_average_rating: float = Field(default=0, ge=0, le=5)
    owner_completed_rentals: int = Field(default=0, ge=0)
    prediction_month: int = Field(default=1, ge=1, le=12)


class PriceRecommendationResponse(BaseModel):
    available: bool
    suggested_daily_price: float | None = None
    lower_bound: float | None = None
    upper_bound: float | None = None
    confidence: float = Field(ge=0, le=1)
    confidence_label: str = 'low'
    currency: str = 'MYR'
    adapter: str
    model_source: str = 'unavailable'
    model_version: str | None = None
    explanation: list[str] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
    evidence: dict[str, Any] = Field(default_factory=dict)
    product_match: dict[str, Any] = Field(default_factory=dict)
    evaluation: dict[str, Any] = Field(default_factory=dict)
    similar_listing_average: float | None = None
    historical_average: float | None = None
    error: str | None = None
