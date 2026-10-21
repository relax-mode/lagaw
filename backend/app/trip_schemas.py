"""Trip API contracts for issue #23; money is represented as exact decimals."""

import re
from datetime import date
from decimal import Decimal
from typing import Annotated, Self
from uuid import UUID

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    StringConstraints,
    field_validator,
    model_validator,
)

Money = Annotated[Decimal, Field(ge=0, max_digits=12, decimal_places=2)]
Label = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=50)]


class TripCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)

    title: str = Field(min_length=1, max_length=200)
    start_date: date
    end_date: date
    budget_min: Money
    budget_max: Money
    transportation_mode: Label | None = None
    group_type: Label | None = None
    preferred_tags: list[Label] = Field(default_factory=list, max_length=30)

    @field_validator("title", mode="before")
    @classmethod
    def trim_title(cls, value):
        return value.strip() if isinstance(value, str) else value

    @field_validator("start_date", "end_date", mode="before")
    @classmethod
    def require_calendar_date(cls, value):
        if type(value) is date:
            return value
        if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
            raise ValueError("Use a calendar date in YYYY-MM-DD format.")
        return value

    @model_validator(mode="after")
    def check_ranges(self) -> Self:
        if self.end_date < self.start_date:
            raise ValueError("end_date must be on or after start_date.")
        if self.budget_max < self.budget_min:
            raise ValueError("budget_max must be greater than or equal to budget_min.")
        return self


class TripResponse(TripCreate):
    id: UUID
    user_id: UUID
    status: str = Field(min_length=1)
    estimated_total_cost: Money | None


class TripsPage(BaseModel):
    items: list[TripResponse]
    limit: int
    offset: int
