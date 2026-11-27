"""Trip CRUD contracts; money is represented as exact decimals."""

import re
from datetime import date
from decimal import Decimal
from typing import Annotated, Self
from uuid import UUID

from pydantic import (
    AfterValidator,
    BaseModel,
    BeforeValidator,
    ConfigDict,
    Field,
    StringConstraints,
    model_validator,
)

Money = Annotated[Decimal, Field(ge=0, max_digits=12, decimal_places=2)]
_UNSTORABLE = re.compile("[\x00\ud800-\udfff]")


def reject_unstorable_text(value: str) -> str:
    """PostgreSQL text cannot hold NUL, and lone surrogates cannot be UTF-8 encoded.

    Without this check they reach the database and surface as a misleading 503.
    """
    if _UNSTORABLE.search(value):
        raise ValueError("Text contains unsupported characters.")
    return value


StorableText = AfterValidator(reject_unstorable_text)
Label = Annotated[
    str, StringConstraints(strip_whitespace=True, min_length=1, max_length=50), StorableText,
]


def trim_title(value):
    return value.strip() if isinstance(value, str) else value


def require_calendar_date(value):
    if type(value) is date:
        return value
    if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        raise ValueError("Use a calendar date in YYYY-MM-DD format.")
    return value


Title = Annotated[
    str, BeforeValidator(trim_title), Field(min_length=1, max_length=200), StorableText,
]
CalendarDate = Annotated[date, BeforeValidator(require_calendar_date)]


# Sanity bounds for saved trips; the app's date picker stays well inside them.
EARLIEST_TRIP_YEAR = 2000
LATEST_TRIP_YEAR = 2100
MAX_TRIP_DAYS = 366


def trip_date_problem(start_date: date, end_date: date) -> str | None:
    """Reject absurd ranges (e.g. year 1 to 9999) on writes only.

    Kept out of the model validators so rows saved before this check still load.
    """
    for value in (start_date, end_date):
        if not EARLIEST_TRIP_YEAR <= value.year <= LATEST_TRIP_YEAR:
            return f"Trip dates must be between {EARLIEST_TRIP_YEAR} and {LATEST_TRIP_YEAR}."
    if (end_date - start_date).days + 1 > MAX_TRIP_DAYS:
        return f"A trip can last at most {MAX_TRIP_DAYS} days."
    return None


class TripCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)

    title: Title
    start_date: CalendarDate
    end_date: CalendarDate
    budget_min: Money
    budget_max: Money
    transportation_mode: Label | None = None
    group_type: Label | None = None
    preferred_tags: list[Label] = Field(default_factory=list, max_length=30)

    @model_validator(mode="after")
    def check_ranges(self) -> Self:
        if self.end_date < self.start_date:
            raise ValueError("end_date must be on or after start_date.")
        if self.budget_max < self.budget_min:
            raise ValueError("budget_max must be greater than or equal to budget_min.")
        return self


class TripUpdate(BaseModel):
    """Omitted fields stay unchanged; only nullable labels accept explicit null."""

    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)

    # Defaults permit omission; supplied null is rejected for these non-null types.
    title: Title = Field(default=None)
    start_date: CalendarDate = Field(default=None)
    end_date: CalendarDate = Field(default=None)
    budget_min: Money = Field(default=None)
    budget_max: Money = Field(default=None)
    transportation_mode: Label | None = None
    group_type: Label | None = None
    preferred_tags: list[Label] = Field(default=None, max_length=30)

    @model_validator(mode="after")
    def require_changes(self) -> Self:
        if not self.model_fields_set:
            raise ValueError("Supply at least one trip field to update.")
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
