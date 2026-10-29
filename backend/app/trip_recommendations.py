"""Read-only saved-trip recommendation endpoint; no DeepSeek or scheduling."""

import logging
import os
from collections.abc import Iterator
from contextlib import contextmanager
from functools import lru_cache
from pathlib import Path
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException

from app.database import DatabaseUnavailable, get_database
from app.recommendation_adapter import (
    InvalidTripPreferences,
    RecommendationAdapter,
    RecommendationUnavailable,
)
from app.recommendations.contracts import Recommender
from app.recommendations.hybrid import ArtifactReport, HybridRecommender, load_artifact
from app.trip_recommendation_schemas import (
    TripRecommendationOptions,
    TripRecommendationResult,
)
from app.trips import TripOwner, get_trip_user

router = APIRouter(prefix="/api/v1/trips", tags=["recommendations"])
# Uvicorn configures this logger at INFO, so the startup line reaches Cloud Run logs.
logger = logging.getLogger("uvicorn.error")


@lru_cache(maxsize=1)
def get_recommendation_engine() -> Recommender:
    """Load the model once per process and log exactly one identifier-free line.

    Called at application startup (see app.main) and again, from cache, per request.
    No path means content-only by design; a path that cannot be used is also
    content-only but is logged with its reason. Training never happens here.
    """
    path = os.environ.get("MODEL_FILE_PATH", "").strip()
    if not path:
        engine, report = HybridRecommender(), ArtifactReport("not_configured")
    else:
        # An unset pin skips only the digest check; a blank pin is treated as unset.
        pin = os.environ.get("MODEL_FILE_SHA256", "").strip() or None
        engine, report = load_artifact(Path(path), provenance="real", expected_sha256=pin)
    (logger.info if report.loaded or report.reason == "not_configured" else logger.warning)(
        report.log_line())
    return engine


def get_recommendation_adapter(
    user_id: Annotated[UUID, Depends(get_trip_user)],
) -> Iterator[RecommendationAdapter]:
    try:
        with contextmanager(get_database)() as database:
            yield RecommendationAdapter(database.client)
    except DatabaseUnavailable:
        raise HTTPException(503, "Recommendations are temporarily unavailable. Please try again later.") from None


@router.post("/{trip_id}/recommendations", response_model=TripRecommendationResult, responses={
    401: {"description": "Missing, invalid or expired Supabase access token"},
    404: {"description": "Trip not found or belongs to another owner"},
    409: {"description": "Trip changed during inference; reload before retrying"},
    422: {"description": "Invalid options or unsupported saved preferences"},
    503: {"description": "Demo context, database or recommendation engine unavailable"},
})
def recommend_trip(
    trip_id: UUID, options: TripRecommendationOptions, user_id: TripOwner,
    adapter: Annotated[RecommendationAdapter, Depends(get_recommendation_adapter)],
    engine: Annotated[Recommender, Depends(get_recommendation_engine)],
):
    # A synchronous route dispatches database access and CPU inference to FastAPI's
    # thread pool rather than blocking its async event loop.
    trip = adapter.trips.retrieve_trip(user_id, trip_id)
    if trip is None:
        raise HTTPException(404, "Trip not found.")
    try:
        result = adapter.recommend(trip, options, engine)
    except InvalidTripPreferences:
        raise HTTPException(422, "Use approved saved tags and group type, and supported category constraints.") from None
    except RecommendationUnavailable:
        raise HTTPException(503, "Recommendations are temporarily unavailable. Please try again later.") from None
    current = adapter.trips.retrieve_trip(user_id, trip_id)
    if current is None:
        raise HTTPException(404, "Trip not found.")
    if current != trip:
        raise HTTPException(409, "Trip changed. Reload it before requesting recommendations again.")
    return result
