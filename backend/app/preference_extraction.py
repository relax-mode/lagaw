"""Confirmation-only extraction API. This module has no persistence dependency."""

from typing import Annotated, Literal, Self

from fastapi import APIRouter, HTTPException
from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    StringConstraints,
    ValidationError,
    model_validator,
)

from app.deepseek import DeepSeekFailure, extract_preferences
from app.deepseek import Preferences as ProviderPreferences
from app.preference_vocabulary import BudgetLevel, Duration, Pace, TravelTag
from app.recommendations.contracts import Group, Money
from app.trips import TripOwner


class ExtractionContract(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)


class ExplicitPreferences(ExtractionContract):
    """Only supported form values; [] intentionally clears tags, None means no override."""

    preferred_tags: list[TravelTag] | None = Field(default=None, max_length=30)
    budget_level: BudgetLevel | None = None
    budget_min: Money | None = None
    budget_max: Money | None = None
    group_type: Group | None = None
    duration: Duration | None = None
    pace: Pace | None = None

    @model_validator(mode="after")
    def validate_budget(self) -> Self:
        if (self.budget_min is None) != (self.budget_max is None):
            raise ValueError("Supply both budget_min and budget_max, or neither.")
        if self.budget_min is not None and self.budget_min > self.budget_max:
            raise ValueError("budget_min must not exceed budget_max.")
        return self


class ExtractionRequest(ExtractionContract):
    prompt: Annotated[
        str, StringConstraints(strict=True, min_length=1, max_length=2000)
    ]
    explicit_preferences: ExplicitPreferences = Field(
        default_factory=ExplicitPreferences
    )

    @model_validator(mode="after")
    def validate_prompt(self) -> Self:
        if not self.prompt.strip():
            raise ValueError("Supply a nonblank travel request.")
        return self


class PreferenceDraft(ExtractionContract):
    preferred_tags: list[TravelTag] = Field(max_length=30)
    budget_level: BudgetLevel
    budget_min: Money | None
    budget_max: Money | None
    budget_scope: Literal["trip_total"] = "trip_total"
    group_type: Group | None
    duration: Duration
    pace: Pace


class ExtractionResponse(ExtractionContract):
    schema_version: Literal["1"] = "1"
    preferences: PreferenceDraft
    requires_confirmation: Literal[True] = True
    missing_fields: list[Literal["budget", "group_type"]]


router = APIRouter(
    prefix="/api/v1/preferences",
    tags=["preferences"],
    responses={
        401: {"description": "Missing, invalid or expired Supabase access token"},
        422: {"description": "Invalid request; provider not called"},
        429: {"description": "Extraction rate limited; use the manual trip form"},
        502: {"description": "Invalid extraction output or provider request failure"},
        503: {
            "description": "Access context, extraction configuration or provider unavailable"
        },
        504: {"description": "Extraction timed out"},
    },
)

# Do not expose provider bodies, credentials, prompts, or arbitrary exception messages.
FAILURES = {
    "invalid_request": (422, "invalid_request", "The travel request is invalid."),
    "missing_api_key": (
        503,
        "extraction_unavailable",
        "Preference extraction is unavailable.",
    ),
    "invalid_configuration": (
        503,
        "extraction_unavailable",
        "Preference extraction is unavailable.",
    ),
    "authentication_failed": (
        503,
        "extraction_unavailable",
        "Preference extraction is unavailable.",
    ),
    "insufficient_balance": (
        503,
        "extraction_unavailable",
        "Preference extraction is unavailable.",
    ),
    "access_denied": (
        503,
        "extraction_unavailable",
        "Preference extraction is unavailable.",
    ),
    "model_unavailable": (
        503,
        "extraction_unavailable",
        "Preference extraction is unavailable.",
    ),
    "rate_limited": (
        429,
        "extraction_rate_limited",
        "Preference extraction is busy. Try later.",
    ),
    "provider_timeout": (504, "extraction_timeout", "Preference extraction timed out."),
    "provider_rejected_request": (
        502,
        "extraction_failed",
        "Preference extraction could not complete.",
    ),
    "invalid_provider_output": (
        502,
        "invalid_extraction_output",
        "Preference extraction returned invalid preferences.",
    ),
    "provider_unavailable": (
        503,
        "extraction_unavailable",
        "Preference extraction is unavailable.",
    ),
    "network_error": (
        503,
        "extraction_unavailable",
        "Preference extraction is unavailable.",
    ),
}


def normalize_preferences(
    extracted: ProviderPreferences,
    explicit: ExplicitPreferences,
) -> ExtractionResponse:
    """Map canonical provider tags to S3-01 names and preserve explicit form choices."""
    # Validate even instances constructed/mutated outside the helper's normal path.
    extracted = ProviderPreferences.model_validate_json(extracted.model_dump_json())
    tags = (
        explicit.preferred_tags
        if explicit.preferred_tags is not None
        else extracted.tags
    )
    # Provider schema already admits only canonical location tags. Deduplicate and order.
    draft = PreferenceDraft(
        preferred_tags=sorted(set(tags)),
        budget_level=explicit.budget_level
        if explicit.budget_level is not None
        else extracted.budget_level,
        budget_min=explicit.budget_min,
        budget_max=explicit.budget_max,
        group_type=explicit.group_type,
        duration=explicit.duration
        if explicit.duration is not None
        else extracted.duration,
        pace=explicit.pace if explicit.pace is not None else extracted.pace,
    )
    missing = []
    if draft.budget_min is None:
        missing.append("budget")
    if draft.group_type is None:
        missing.append("group_type")
    return ExtractionResponse(preferences=draft, missing_fields=missing)


@router.post("/extract", response_model=ExtractionResponse)
def extract_preference_draft(payload: ExtractionRequest, user_id: TripOwner):
    """Extract a draft for confirmation; never create or modify a trip."""
    try:
        extracted = extract_preferences(payload.prompt.strip())
        return normalize_preferences(extracted, payload.explicit_preferences)
    except (DeepSeekFailure, ValidationError) as exc:
        code = (
            str(exc) if isinstance(exc, DeepSeekFailure) else "invalid_provider_output"
        )
        status, public_code, message = FAILURES.get(
            code, FAILURES["provider_unavailable"]
        )
        raise HTTPException(
            status,
            detail={
                "code": public_code,
                "message": message,
                "manual_fallback": True,
            },
        ) from None
