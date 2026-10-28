"""Owner-scoped generation reuses #53 validation and #26 persisted associations."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException

from app.database import DatabaseUnavailable
from app.itinerary_database import (
    ItineraryConflict,
    ItineraryDatabase,
    ItineraryMissing,
)
from app.itinerary_planner import (
    PlanningConflict,
    UnsupportedPlanningTrip,
    plan_itinerary,
)
from app.itinerary_schemas import GenerationOptions, GenerationResult
from app.recommendation_adapter import (
    InvalidTripPreferences,
    RecommendationAdapter,
    RecommendationUnavailable,
)
from app.recommendations.contracts import Recommender
from app.trip_recommendations import (
    get_recommendation_adapter,
    get_recommendation_engine,
)
from app.trips import TripOwner

router = APIRouter(prefix="/api/v1/trips", tags=["itinerary generation"])


@router.post("/{trip_id}/generate-itinerary", response_model=GenerationResult, responses={
    401: {"description": "Missing, invalid or expired Supabase access token"},
    404: {"description": "Trip not found or inaccessible"},
    409: {"description": "Replacement confirmation, concurrent edit or infeasible schedule; saved data preserved"},
    422: {"description": "Invalid options, saved preferences, transportation mode or trip length"},
    503: {"description": "Database, model or generation migration unavailable"},
})
def generate_itinerary(
    trip_id: UUID, options: GenerationOptions, user_id: TripOwner,
    adapter: Annotated[RecommendationAdapter, Depends(get_recommendation_adapter)],
    engine: Annotated[Recommender, Depends(get_recommendation_engine)],
):
    store = ItineraryDatabase(adapter.client)
    try:
        state = store.snapshot(user_id, trip_id)
        if state.items and not options.replace_existing:
            raise HTTPException(409, {"code": "replacement_confirmation_required", "revision": state.revision,
                                      "message": "Confirm replacing all existing itinerary items, including manual items."})
        if options.replace_existing and options.expected_revision != state.revision:
            raise HTTPException(409, {"code": "itinerary_changed", "message": "Reload before confirming replacement."})
        ranked = adapter.recommend(state.trip, options.recommendations, engine)
        visits, total = plan_itinerary(state.trip, options, ranked)
        selected = {visit.location_id for visit in visits}
        saved = store.save(user_id, state, options, visits,
                           [item.location for item in ranked.items if item.location_id in selected])
        if saved.trip.estimated_total_cost != total or len(saved.items) != len(visits):
            raise DatabaseUnavailable
        return GenerationResult(trip_id=trip_id, estimated_total_cost=total,
                                revision=saved.revision, items=saved.items)
    except ItineraryMissing:
        raise HTTPException(404, "Trip not found.") from None
    except ItineraryConflict:
        raise HTTPException(409, {"code": "itinerary_changed", "message": "Saved trip, itinerary or destination changed. Reload and retry."}) from None
    except InvalidTripPreferences:
        raise HTTPException(422, "Use approved saved tags and group type, and supported category constraints.") from None
    except UnsupportedPlanningTrip:
        raise HTTPException(422, "Generation requires a supported saved transportation mode and a trip of at most 31 days.") from None
    except PlanningConflict as error:
        raise HTTPException(409, {"code": error.reason, "scheduled_visits": error.scheduled,
                                  "requested_visits": options.recommendations.planned_visits,
                                  "skipped": error.skipped, "message": "No complete feasible itinerary. Saved data preserved."}) from None
    except RecommendationUnavailable:
        raise HTTPException(503, "Recommendations are temporarily unavailable. Please try again later.") from None
