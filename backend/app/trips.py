"""Issue #23 endpoints with an explicit, token-protected demo-user context."""

import os
import secrets
from collections.abc import Iterator
from contextlib import contextmanager
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.database import DatabaseUnavailable, get_database
from app.trip_database import TripDatabase
from app.trip_schemas import TripCreate, TripResponse, TripsPage

demo_bearer = HTTPBearer(auto_error=False, scheme_name="TripDemoToken")
router = APIRouter(prefix="/api/v1/trips", tags=["trips"], responses={
    401: {"description": "Missing or invalid demo bearer token"},
    503: {"description": "Demo context or database unavailable"},
})


def get_trip_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(demo_bearer)],
) -> UUID:
    """Only server configuration selects the demo owner; clients cannot select users."""
    token = os.environ.get("TRIP_DEMO_TOKEN", "")
    try:
        user_id = UUID(os.environ.get("TRIP_DEMO_USER_ID", ""))
        if (
            len(token) < 32 or not token.isascii()
            or any(character.isspace() for character in token) or user_id.int == 0
        ):
            raise ValueError
    except ValueError:
        raise HTTPException(503, "Trip demo context is not configured.") from None
    if credentials is None or not secrets.compare_digest(
        credentials.credentials.encode("utf-8"), token.encode("ascii")
    ):
        raise HTTPException(
            401, "A valid trip demo bearer token is required.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user_id


def get_trip_database(
    user_id: Annotated[UUID, Depends(get_trip_user)],
) -> Iterator[TripDatabase]:
    try:
        with contextmanager(get_database)() as database:
            yield TripDatabase(database.client)
    except DatabaseUnavailable:
        raise HTTPException(
            503, "Trips are temporarily unavailable. Please try again later.",
        ) from None


TripOwner = Annotated[UUID, Depends(get_trip_user)]
TripStore = Annotated[TripDatabase, Depends(get_trip_database)]


@router.post("", response_model=TripResponse, status_code=201)
def create_trip(payload: TripCreate, user_id: TripOwner, database: TripStore):
    """Save a draft trip for the configured demo user. No itinerary is generated."""
    return database.create_trip(user_id, payload)


@router.get("", response_model=TripsPage)
def list_trips(
    user_id: TripOwner,
    database: TripStore,
    limit: Annotated[int, Query(ge=1, le=100)] = 10,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    return TripsPage(items=database.list_trips(user_id, limit, offset), limit=limit, offset=offset)


@router.get("/{trip_id}", response_model=TripResponse, responses={
    404: {"description": "Trip not found or belongs to another user"},
})
def retrieve_trip(trip_id: UUID, user_id: TripOwner, database: TripStore):
    trip = database.retrieve_trip(user_id, trip_id)
    if trip is None:
        raise HTTPException(404, "Trip not found.")
    return trip
