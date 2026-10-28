"""Trip CRUD scoped to a server-verified owner's profile."""

from collections.abc import Iterator
from contextlib import contextmanager
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from fastapi.exceptions import RequestValidationError
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import ValidationError

from app.auth import authenticate, unauthorized
from app.database import DatabaseUnavailable, get_database
from app.trip_database import TripDatabase, TripUpdateConflict
from app.trip_schemas import TripCreate, TripResponse, TripsPage, TripUpdate

access_bearer = HTTPBearer(auto_error=False, scheme_name="SupabaseAccessToken")
router = APIRouter(prefix="/api/v1/trips", tags=["trips"], responses={
    401: {"description": "Missing, invalid or expired access token"},
    403: {"description": "Email confirmation required"},
    409: {"description": "Existing profile needs an explicit linking decision"},
    503: {"description": "Authentication, profile or database unavailable"},
})


def get_trip_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(access_bearer)],
) -> UUID:
    """Clients supply an access token, never a trusted owner ID."""
    if credentials is None:
        raise unauthorized()
    return authenticate(credentials.credentials)


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
    """Save a draft trip for the verified owner. No itinerary is generated."""
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


@router.patch("/{trip_id}", response_model=TripResponse, responses={
    404: {"description": "Trip not found or belongs to another user"},
    409: {"description": "Database constraint conflict; reload the trip before retrying"},
})
def update_trip(trip_id: UUID, payload: TripUpdate, user_id: TripOwner, database: TripStore):
    """Update supplied fields only. Null clears optional labels; [] clears tags."""
    current = database.retrieve_trip(user_id, trip_id)
    if current is None:
        raise HTTPException(404, "Trip not found.")
    try:
        # Validate one-sided date/budget edits against their saved counterpart.
        TripCreate.model_validate({
            **current.model_dump(include=set(TripCreate.model_fields)),
            **payload.model_dump(exclude_unset=True),
        })
    except ValidationError as exc:
        raise RequestValidationError([
            {**error, "loc": ("body", *error["loc"])} for error in exc.errors()
        ]) from None
    try:
        trip = database.update_trip(user_id, trip_id, payload)
    except TripUpdateConflict:
        raise HTTPException(
            409, "Trip constraints changed or conflict. Reload the trip before retrying.",
        ) from None
    if trip is None:
        raise HTTPException(404, "Trip not found.")
    return trip


@router.delete("/{trip_id}", status_code=204, response_class=Response, responses={
    404: {"description": "Trip not found or belongs to another user"},
})
def delete_trip(trip_id: UUID, user_id: TripOwner, database: TripStore):
    """Permanently delete the trip and its itinerary items through the database FK."""
    if not database.delete_trip(user_id, trip_id):
        raise HTTPException(404, "Trip not found.")
    return Response(status_code=204)
