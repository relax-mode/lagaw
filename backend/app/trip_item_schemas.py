"""Manual trip-location association contracts for issue #26."""

from datetime import time
from decimal import Decimal
from typing import Annotated, Self
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_serializer, model_validator

from app.schemas import Location

Position = Annotated[int, Field(strict=True, ge=1, le=2147483647)]


class TripItemCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    location_id: UUID
    day_number: Position
    visit_order: Position


class TripItemResponse(TripItemCreate):
    id: UUID
    trip_id: UUID
    location: Location
    arrival_time: time | None = None
    departure_time: time | None = None
    estimated_travel_time: int | None = Field(default=None, ge=0)
    estimated_cost: Decimal | None = Field(default=None, ge=0, allow_inf_nan=False)
    recommendation_score: float | None = Field(default=None, ge=0, le=1, allow_inf_nan=False)
    recommendation_reason: str | None = None

    @field_serializer("estimated_cost")
    def serialize_cost(self, value):
        # PostgREST JSONB RPCs and table reads can use different numeric scales.
        # Expose the same centavo representation through generation and GET.
        return None if value is None else format(value, ".2f")

    @model_validator(mode="after")
    def matching_location(self) -> Self:
        if self.location.id != self.location_id:
            raise ValueError("Associated location does not match the item.")
        return self


class TripItemsPage(BaseModel):
    items: list[TripItemResponse]
    limit: int
    offset: int
