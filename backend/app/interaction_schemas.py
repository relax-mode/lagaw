"""Versioned interaction writes and S3-01-compatible reads."""

from decimal import Decimal
from typing import Literal, Self
from uuid import UUID

from pydantic import Field, model_validator

from app.recommendations.contracts import Contract, Interaction, InteractionType


class InteractionCreate(Contract):
    location_id: UUID
    interaction_type: InteractionType
    rating_value: Decimal | None = Field(default=None, ge=1, le=5)

    @model_validator(mode="after")
    def check_rating(self) -> Self:
        if (self.interaction_type == "rating") != (self.rating_value is not None):
            raise ValueError("rating_value is required only for rating events")
        return self

    def persistence_values(self) -> dict:
        return {
            **self.model_dump(mode="json"),
            "interaction_value": "-1" if self.interaction_type == "left_swipe" else "1",
        }


class InteractionHistory(Contract):
    schema_version: Literal["1"] = "1"
    items: list[Interaction]
    limit: int
    offset: int


class InteractionInput(Contract):
    schema_version: Literal["1"] = "1"
    interactions: list[Interaction]
    excluded_location_ids: list[UUID]
