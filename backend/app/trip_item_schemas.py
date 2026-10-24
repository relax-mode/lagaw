"""Manual trip-location association contracts for issue #26."""

from typing import Annotated, Self
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator

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

    @model_validator(mode="after")
    def matching_location(self) -> Self:
        if self.location.id != self.location_id:
            raise ValueError("Associated location does not match the item.")
        return self


class TripItemsPage(BaseModel):
    items: list[TripItemResponse]
    limit: int
    offset: int
