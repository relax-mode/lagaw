"""Authenticated first-time onboarding profile API. No AI calls or ranking."""

from collections.abc import Iterator
from contextlib import contextmanager
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException

from app.database import DatabaseUnavailable, get_database
from app.onboarding_database import OnboardingDatabase
from app.onboarding_schemas import OnboardingPreferences
from app.trips import get_trip_user

router = APIRouter(prefix="/api/v1/me/preferences", tags=["onboarding"], responses={
    401: {"description": "Missing, invalid or expired access token"},
    403: {"description": "Email confirmation required"},
    409: {"description": "Existing profile needs explicit account linking"},
    404: {"description": "Linked profile is no longer available"},
    422: {"description": "Invalid onboarding preferences"},
    503: {"description": "Auth, profile or storage temporarily unavailable"},
})

Owner = Annotated[UUID, Depends(get_trip_user)]


def get_onboarding_database(owner_id: Owner) -> Iterator[OnboardingDatabase]:
    """Resolve the owner's verified profile before opening a service-role client."""
    try:
        with contextmanager(get_database)() as database:
            yield OnboardingDatabase(database.client)
    except DatabaseUnavailable:
        raise HTTPException(
            503, "Onboarding preferences are temporarily unavailable.",
        ) from None


Store = Annotated[OnboardingDatabase, Depends(get_onboarding_database)]


@router.get("", response_model=OnboardingPreferences)
def get_preferences(owner_id: Owner, store: Store) -> OnboardingPreferences:
    preferences = store.get(owner_id)
    if preferences is None:
        raise HTTPException(404, "Profile not found.")
    return preferences


@router.put("", response_model=OnboardingPreferences)
def save_preferences(
    payload: OnboardingPreferences, owner_id: Owner, store: Store,
) -> OnboardingPreferences:
    """Replace exactly the four preference fields, never a client-supplied owner."""
    saved = store.replace(owner_id, payload)
    if saved is None:
        raise HTTPException(404, "Profile not found.")
    return saved
