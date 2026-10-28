"""HTTP wrapper around the unchanged S3-01 inference contracts."""

from typing import Literal, Self
from uuid import UUID

from pydantic import Field, model_validator

from app.recommendations.contracts import (
    Contract,
    Coordinates,
    Money,
    Recommendation,
    Tags,
)
from app.schemas import Location


class RequestCoordinates(Coordinates):
    latitude: float = Field(ge=-90, le=90, strict=True)
    longitude: float = Field(ge=-180, le=180, strict=True)


class TripRecommendationOptions(Contract):
    # Counts are explicit: a group label and trip dates cannot establish them.
    party_size: int = Field(ge=1, le=100, strict=True)
    planned_visits: int = Field(ge=1, le=1000, strict=True)
    limit: int = Field(default=10, ge=1, le=100, strict=True)
    preferred_categories: Tags = Field(default_factory=list)
    setting: Literal["indoor", "outdoor"] | None = None
    requires_step_free_access: bool = Field(default=False, strict=True)
    max_visit_duration_minutes: int | None = Field(default=None, gt=0, strict=True)
    origin: RequestCoordinates | None = None
    max_distance_km: float | None = Field(default=None, gt=0, strict=True)
    excluded_location_ids: list[UUID] = Field(default_factory=list, max_length=100)

    @model_validator(mode="after")
    def require_distance_origin(self) -> Self:
        if self.max_distance_km is not None and self.origin is None:
            raise ValueError("max_distance_km requires origin.")
        return self


class RecommendationBudget(Contract):
    scope: Literal["per_person_per_visit"] = "per_person_per_visit"
    party_size: int
    planned_visits: int
    budget_min: Money
    budget_max: Money


class TripRecommendation(Recommendation):
    location: Location


class TripRecommendationResult(Contract):
    schema_version: Literal["1"] = "1"
    trip_id: UUID
    budget: RecommendationBudget
    items: list[TripRecommendation]
    empty_reason: Literal["no_compatible_locations"] | None = None
