"""Read-only cold-start ranking from owner-scoped onboarding tags."""

from collections.abc import Iterator
from contextlib import contextmanager
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import Field

from app.database import DatabaseUnavailable, get_database
from app.onboarding_database import OnboardingDatabase
from app.recommendation_adapter import RecommendationAdapter, location_attributes
from app.recommendations.content_based import ContentBasedRecommender
from app.recommendations.contracts import (
    Contract,
    Group,
    Money,
    Preferences,
    RecommendationRequest,
    validate_response,
)
from app.trip_recommendation_schemas import TripRecommendation
from app.trips import get_trip_user

router = APIRouter(prefix="/api/v1/me/recommendations", tags=["recommendations"])
Owner = Annotated[UUID, Depends(get_trip_user)]


class OnboardingRecommendationOptions(Contract):
    group_type: Group
    per_person_visit_budget_max: Money
    limit: int = Field(default=10, ge=1, le=100, strict=True)


class OnboardingRecommendationResult(Contract):
    schema_version: Literal["1"] = "1"
    mode: Literal["content_only"] = "content_only"
    budget_scope: Literal["per_person_per_visit"] = "per_person_per_visit"
    items: list[TripRecommendation]
    empty_reason: Literal["no_compatible_locations"] | None = None


def get_onboarding_catalog(owner_id: Owner) -> Iterator[RecommendationAdapter]:
    # Reuse bounded pagination and fresh-row checks, never its trip/history methods.
    try:
        with contextmanager(get_database)() as database:
            yield RecommendationAdapter(database.client)
    except DatabaseUnavailable:
        raise HTTPException(503, "Recommendations are temporarily unavailable.") from None


@router.post("", response_model=OnboardingRecommendationResult, responses={
    401: {"description": "Missing, invalid or expired access token"},
    403: {"description": "Email confirmation required"},
    404: {"description": "Profile not found"},
    409: {"description": "Profile linking requires review or preferences changed"},
    422: {"description": "Invalid recommendation options"},
    503: {"description": "Profile, catalog or ranking unavailable"},
})
def recommend_onboarding(
    options: OnboardingRecommendationOptions, owner_id: Owner,
    catalog: Annotated[RecommendationAdapter, Depends(get_onboarding_catalog)],
) -> OnboardingRecommendationResult:
    profile_store = OnboardingDatabase(catalog.client)
    profile = profile_store.get(owner_id)
    if profile is None:
        raise HTTPException(404, "Profile not found.")
    try:
        locations = catalog.catalog()
        request = RecommendationRequest(
            preferences=Preferences(
                user_id=owner_id, preferred_tags=sorted(set(profile.preferred_tags)),
                budget_min=0, budget_max=options.per_person_visit_budget_max,
                group_type=options.group_type,
            ),
            locations=[location_attributes(row) for row in locations],
            interactions=[], limit=options.limit,
        )
    except ValueError:
        raise HTTPException(503, "Recommendations are temporarily unavailable.") from None
    try:
        response = ContentBasedRecommender().recommend(request.model_copy(deep=True))
        validate_response(request, response)
    except Exception:  # noqa: BLE001 - Keep internal model diagnostics private.
        raise HTTPException(503, "Recommendations are temporarily unavailable.") from None

    # Drop edited/deactivated venues rather than return stale scores or reasons.
    original = {row.id: row for row in locations}
    current = {row.id: row for row in catalog.current_locations(
        {item.location_id for item in response.items},
    ) if row == original[row.id]}
    latest = profile_store.get(owner_id)
    if latest is None:
        raise HTTPException(404, "Profile not found.")
    if latest != profile:
        raise HTTPException(409, "Preferences changed. Reload before requesting recommendations again.")
    items = [TripRecommendation(**item.model_dump(), location=current[item.location_id])
             for item in response.items if item.location_id in current]
    return OnboardingRecommendationResult(
        items=items, empty_reason=None if items else "no_compatible_locations",
    )
