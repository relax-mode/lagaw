"""Persist swipes, saves and ratings using the existing controlled demo owner."""

from collections.abc import Iterator
from contextlib import contextmanager
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query

from app.database import DatabaseUnavailable, get_database
from app.interaction_database import ActiveLocationNotFound, InteractionDatabase
from app.interaction_schemas import (
    InteractionCreate,
    InteractionHistory,
    InteractionInput,
)
from app.recommendations.contracts import Interaction
from app.trips import TripOwner, get_trip_user

router = APIRouter(prefix="/api/v1/interactions", tags=["interactions"], responses={
    401: {"description": "Missing or invalid demo bearer token"},
    503: {"description": "Demo context or interaction database unavailable"},
})


def get_interaction_database(
    user_id: Annotated[UUID, Depends(get_trip_user)],
) -> Iterator[InteractionDatabase]:
    try:
        with contextmanager(get_database)() as database:
            yield InteractionDatabase(database.client)
    except DatabaseUnavailable:
        raise HTTPException(
            503, "Interactions are temporarily unavailable. Please try again later.",
        ) from None


InteractionStore = Annotated[InteractionDatabase, Depends(get_interaction_database)]


@router.post("", response_model=Interaction, status_code=201, responses={
    404: {"description": "Active location not found"},
})
def create_interaction(payload: InteractionCreate, user_id: TripOwner, database: InteractionStore):
    try:
        return database.create_interaction(user_id, payload)
    except ActiveLocationNotFound:
        raise HTTPException(404, "Active location not found.") from None


@router.get("", response_model=InteractionHistory)
def list_interactions(
    user_id: TripOwner, database: InteractionStore,
    limit: Annotated[int, Query(ge=1, le=100)] = 10,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    return InteractionHistory(
        items=database.list_interactions(user_id, limit, offset), limit=limit, offset=offset,
    )


@router.get("/recommendation-input", response_model=InteractionInput)
def recommendation_input(user_id: TripOwner, database: InteractionStore):
    """Complete owner history and conservative S3-01 rejection IDs; no model runs."""
    return database.recommendation_input(user_id)


@router.get("/{event_id}", response_model=Interaction, responses={
    404: {"description": "Interaction not found or belongs to another user"},
})
def retrieve_interaction(event_id: UUID, user_id: TripOwner, database: InteractionStore):
    event = database.retrieve_interaction(user_id, event_id)
    if event is None:
        raise HTTPException(404, "Interaction not found.")
    return event
