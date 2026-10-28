"""Owner-scoped manual itinerary items; no generated schedule or ranking."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query, Response
from fastapi.exceptions import RequestValidationError

from app.trip_database import TripDatabase
from app.trip_item_database import TripItemConflict, TripItemDatabase
from app.trip_item_schemas import TripItemCreate, TripItemResponse, TripItemsPage
from app.trips import TripOwner, TripStore

router = APIRouter(prefix="/api/v1/trips", tags=["trip items"], responses={
    401: {"description": "Missing, invalid or expired Supabase access token"},
    404: {"description": "Trip, location, or item not found in the permitted context"},
    503: {"description": "Authentication or database unavailable"},
})


def require_owned_trip(database: TripDatabase, user_id: UUID, trip_id: UUID):
    # Ownership is immutable through the current Trip API. Check before every item
    # read/write; never reveal children or location existence for another owner's trip.
    trip = database.retrieve_trip(user_id, trip_id)
    if trip is None:
        raise HTTPException(404, "Trip not found.")
    return trip


@router.post("/{trip_id}/items", response_model=TripItemResponse, status_code=201,
             responses={409: {"description": "Occupied position or changed association"}})
def add_trip_item(
    trip_id: UUID, payload: TripItemCreate, user_id: TripOwner, database: TripStore,
):
    trip = require_owned_trip(database, user_id, trip_id)
    if payload.day_number > (trip.end_date - trip.start_date).days + 1:
        raise RequestValidationError([{
            "loc": ("body", "day_number"), "type": "value_error",
            "msg": "day_number must be within the trip's dates.",
        }])
    items = TripItemDatabase(database.client)
    if items.retrieve_location(payload.location_id) is None:
        raise HTTPException(404, "Active location not found.")
    try:
        return items.create_item(trip_id, payload)
    except TripItemConflict:
        raise HTTPException(
            409, "Itinerary position is occupied or the association changed. Reload before retrying.",
        ) from None


@router.get("/{trip_id}/items", response_model=TripItemsPage)
def list_trip_items(
    trip_id: UUID, user_id: TripOwner, database: TripStore,
    limit: Annotated[int, Query(ge=1, le=100)] = 10,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    require_owned_trip(database, user_id, trip_id)
    items = TripItemDatabase(database.client).list_items(trip_id, limit, offset)
    return TripItemsPage(items=items, limit=limit, offset=offset)


@router.delete("/{trip_id}/items/{item_id}", status_code=204, response_class=Response)
def remove_trip_item(trip_id: UUID, item_id: UUID, user_id: TripOwner, database: TripStore):
    require_owned_trip(database, user_id, trip_id)
    if not TripItemDatabase(database.client).delete_item(trip_id, item_id):
        raise HTTPException(404, "Itinerary item not found.")
    return Response(status_code=204)
