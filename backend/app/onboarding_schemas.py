"""Validated owner-scoped onboarding profile contract (not LLM extraction).

The write is full replacement: callers must send every field. Explicit null
clears the optional PHP budget pair and travel style; [] clears interest tags.
"""

from decimal import Decimal
from typing import Annotated, Literal, Self
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.preference_vocabulary import TravelTag
from app.trip_schemas import Money

# Reuse the approved pace vocabulary as the onboarding travel-style choices.
TravelStyle = Literal["slow", "moderate", "fast"]


class PreferenceContract(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)


class OnboardingPreferences(PreferenceContract):
    preferred_tags: list[TravelTag] = Field(max_length=30)
    budget_min: Money | None
    budget_max: Money | None
    travel_style: TravelStyle | None

    @model_validator(mode="after")
    def validate_range_and_tags(self) -> Self:
        if (self.budget_min is None) != (self.budget_max is None):
            raise ValueError("Both budget values must be set or both null.")
        if self.budget_min is not None and self.budget_min > self.budget_max:
            raise ValueError("budget_min must not exceed budget_max.")
        if len(set(self.preferred_tags)) != len(self.preferred_tags):
            raise ValueError("Duplicate preference tags are not allowed.")
        return self


class SavedPreferenceRow(PreferenceContract):
    id: UUID
    preferred_tags: list[TravelTag]
    default_budget_min: Annotated[Decimal, Field(ge=0, max_digits=12, decimal_places=2)] | None
    default_budget_max: Annotated[Decimal, Field(ge=0, max_digits=12, decimal_places=2)] | None
    traveler_type: TravelStyle | None

    @model_validator(mode="after")
    def validate_saved_range(self) -> Self:
        if (self.default_budget_min is None) != (self.default_budget_max is None):
            raise ValueError("Persisted budget must be a complete range or null.")
        if (self.default_budget_min is not None
                and self.default_budget_min > self.default_budget_max):
            raise ValueError("Invalid persisted budget order.")
        return self

    def as_preferences(self) -> OnboardingPreferences:
        return OnboardingPreferences(
            preferred_tags=self.preferred_tags,
            budget_min=self.default_budget_min,
            budget_max=self.default_budget_max,
            travel_style=self.traveler_type,
        )
