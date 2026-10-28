"""One PostgREST RPC commits the complete plan and trip estimate atomically."""

import httpx
from pydantic import Field

from app.database import DatabaseUnavailable
from app.recommendations.contracts import Contract
from app.trip_item_schemas import TripItemResponse
from app.trip_schemas import TripResponse


class ItineraryConflict(Exception):
    pass


class ItineraryMissing(Exception):
    pass


class ItineraryState(Contract):
    trip: TripResponse
    revision: str = Field(pattern=r"^[a-f0-9]{32}$")
    items: list[TripItemResponse]


class ItineraryDatabase:
    def __init__(self, client):
        self.client = client

    def rpc(self, name, payload):
        try:
            response = self.client.post(f"rpc/{name}", json=payload)
            if response.status_code == 409:
                raise ItineraryConflict
            error = response.json() if response.status_code == 404 else None
            if isinstance(error, dict) and error.get("code") == "PT404":
                raise ItineraryMissing
            response.raise_for_status()
            if response.status_code != 200:
                raise ValueError
            value = response.json()
            if value is None:
                raise ItineraryMissing
            result = ItineraryState.model_validate(value)
            if str(result.trip.id) != payload["p_trip"] or str(result.trip.user_id) != payload["p_owner"]:
                raise ValueError
            if any(row.trip_id != result.trip.id for row in result.items):
                raise ValueError
            if len({row.id for row in result.items}) != len(result.items):
                raise ValueError
            return result
        except (httpx.HTTPError, ValueError, TypeError):
            raise DatabaseUnavailable from None

    def snapshot(self, owner, trip_id):
        return self.rpc("itinerary_state", {"p_owner": str(owner), "p_trip": str(trip_id)})

    def save(self, owner, snapshot, options, visits, locations):
        return self.rpc("save_generated_itinerary", {
            "p_owner": str(owner), "p_trip": str(snapshot.trip.id),
            "p_revision": snapshot.revision, "p_replace": options.replace_existing,
            "p_items": [visit.model_dump(mode="json") for visit in visits],
            "p_locations": [location.model_dump(mode="json") for location in locations],
        })
