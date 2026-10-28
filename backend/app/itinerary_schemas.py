"""Generation uses saved trip preferences and the existing #53 options."""

from datetime import time
from decimal import Decimal
from typing import Literal, Self
from uuid import UUID

from pydantic import Field, model_validator

from app.preference_vocabulary import Duration, Pace
from app.recommendations.contracts import Contract
from app.trip_item_schemas import TripItemResponse
from app.trip_recommendation_schemas import TripRecommendationOptions


class GenerationOptions(Contract):
    recommendations: TripRecommendationOptions
    duration: Duration = "full_day"
    pace: Pace = "moderate"
    replace_existing: bool = Field(default=False, strict=True)
    expected_revision: str | None = Field(default=None, pattern=r"^[a-f0-9]{32}$")

    @model_validator(mode="after")
    def check_counts_and_confirmation(self) -> Self:
        if self.recommendations.planned_visits > self.recommendations.limit:
            raise ValueError("planned_visits cannot exceed the candidate limit (maximum 100).")
        if self.replace_existing != (self.expected_revision is not None):
            raise ValueError("Replacement requires replace_existing=true and expected_revision together.")
        return self


class PlannedVisit(Contract):
    location_id: UUID
    day_number: int = Field(ge=1)
    visit_order: int = Field(ge=1)
    arrival_time: time
    departure_time: time
    estimated_travel_time: int = Field(ge=0)
    estimated_cost: Decimal = Field(ge=0, max_digits=12, decimal_places=2)
    recommendation_score: float = Field(ge=0, le=1)
    recommendation_reason: str = Field(min_length=1, max_length=500)


class GenerationResult(Contract):
    schema_version: Literal["1"] = "1"
    trip_id: UUID
    timezone: Literal["Asia/Manila"] = "Asia/Manila"
    estimated_total_cost: Decimal
    revision: str
    items: list[TripItemResponse]
