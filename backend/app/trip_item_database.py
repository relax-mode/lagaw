"""Manual associations in the existing itinerary_items table via Supabase."""

from uuid import UUID

import httpx
from pydantic import TypeAdapter

from app.database import LOCATION_COLUMNS, DatabaseUnavailable
from app.schemas import Location
from app.trip_item_schemas import TripItemCreate, TripItemResponse

ITEM_COLUMNS = (
    "id,trip_id,location_id,day_number,visit_order,arrival_time,departure_time,"
    "estimated_travel_time,estimated_cost,recommendation_score,recommendation_reason"
)
ITEM_SELECT = f"{ITEM_COLUMNS},location:locations({LOCATION_COLUMNS})"
ITEM_LIST = TypeAdapter(list[TripItemResponse])
LOCATION_LIST = TypeAdapter(list[Location])


class TripItemConflict(Exception):
    """Position conflict or a parent reference changed during an association."""


class TripItemDatabase:
    def __init__(self, client: httpx.Client):
        self.client = client

    @staticmethod
    def read_rows(response, trip_id: UUID, maximum: int):
        response.raise_for_status()
        rows = ITEM_LIST.validate_json(response.content)
        if len(rows) > maximum or any(row.trip_id != trip_id for row in rows):
            raise ValueError
        if len({row.id for row in rows}) != len(rows):
            raise ValueError
        return rows

    def retrieve_location(self, location_id: UUID) -> Location | None:
        try:
            response = self.client.get("locations", params={
                "select": LOCATION_COLUMNS, "id": f"eq.{location_id}",
                "is_active": "eq.true", "limit": 1,
            })
            response.raise_for_status()
            rows = LOCATION_LIST.validate_json(response.content)
            if len(rows) > 1 or any(
                row.id != location_id or not row.is_active for row in rows
            ):
                raise ValueError
            return rows[0] if rows else None
        except (httpx.HTTPError, ValueError):
            raise DatabaseUnavailable from None

    def create_item(self, trip_id: UUID, payload: TripItemCreate) -> TripItemResponse:
        try:
            response = self.client.post(
                "itinerary_items", params={"select": ITEM_SELECT},
                headers={"Prefer": "return=representation", "Content-Profile": "public"},
                json={**payload.model_dump(mode="json"), "trip_id": str(trip_id)},
            )
            # PostgreSQL serializes conflicting positions, including concurrent POSTs.
            # FK conflicts can occur if a validated parent is deleted before this write.
            if response.status_code == 409:
                error = response.json()
                if isinstance(error, dict) and error.get("code") in ("23505", "23503"):
                    raise TripItemConflict
            rows = self.read_rows(response, trip_id, 1)
            if response.status_code != 201 or len(rows) != 1:
                raise ValueError
            row = rows[0]
            if any(
                getattr(row, field) != value for field, value in payload.model_dump().items()
            ):
                raise ValueError
            return row
        except (httpx.HTTPError, ValueError):
            raise DatabaseUnavailable from None

    def list_items(self, trip_id: UUID, limit: int, offset: int) -> list[TripItemResponse]:
        try:
            response = self.client.get("itinerary_items", params={
                "select": ITEM_SELECT, "trip_id": f"eq.{trip_id}",
                "order": "day_number.asc,visit_order.asc,id.asc",
                "limit": limit, "offset": offset,
            })
            return self.read_rows(response, trip_id, limit)
        except (httpx.HTTPError, ValueError):
            raise DatabaseUnavailable from None

    def delete_item(self, trip_id: UUID, item_id: UUID) -> bool:
        try:
            response = self.client.delete(
                "itinerary_items",
                params={"select": "id,trip_id", "trip_id": f"eq.{trip_id}", "id": f"eq.{item_id}"},
                headers={"Prefer": "return=representation", "Content-Profile": "public"},
            )
            response.raise_for_status()
            rows = response.json()
            if response.status_code != 200 or not isinstance(rows, list) or (
                rows and rows != [{"id": str(item_id), "trip_id": str(trip_id)}]
            ):
                raise ValueError
            return bool(rows)
        except (httpx.HTTPError, ValueError):
            raise DatabaseUnavailable from None
