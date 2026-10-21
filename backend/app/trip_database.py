"""Persist and read owner-scoped trips through Supabase's PostgreSQL Data API."""

from uuid import UUID

import httpx
from pydantic import TypeAdapter

from app.database import DatabaseUnavailable
from app.trip_schemas import TripCreate, TripResponse

TRIP_COLUMNS = ",".join(TripResponse.model_fields)
TRIP_LIST = TypeAdapter(list[TripResponse])


class TripDatabase:
    def __init__(self, client: httpx.Client):
        self.client = client

    @staticmethod
    def read_rows(response, user_id, maximum, trip_id=None):
        response.raise_for_status()
        rows = TRIP_LIST.validate_json(response.content)
        if len(rows) > maximum or any(
            row.user_id != user_id or (trip_id is not None and row.id != trip_id)
            for row in rows
        ):
            raise ValueError
        return rows

    def create_trip(self, user_id: UUID, payload: TripCreate) -> TripResponse:
        try:
            response = self.client.post(
                "trips",
                params={"select": TRIP_COLUMNS},
                headers={"Prefer": "return=representation", "Content-Profile": "public"},
                json={**payload.model_dump(mode="json"), "user_id": str(user_id)},
            )
            rows = self.read_rows(response, user_id, 1)
            if len(rows) != 1 or response.status_code != 201:
                raise ValueError
            return rows[0]
        except (httpx.HTTPError, ValueError):
            raise DatabaseUnavailable from None

    def list_trips(self, user_id: UUID, limit: int, offset: int) -> list[TripResponse]:
        try:
            response = self.client.get(
                "trips",
                params={
                    "select": TRIP_COLUMNS,
                    "user_id": f"eq.{user_id}",
                    "order": "start_date.asc,id.asc",
                    "limit": limit,
                    "offset": offset,
                },
            )
            return self.read_rows(response, user_id, limit)
        except (httpx.HTTPError, ValueError):
            raise DatabaseUnavailable from None

    def retrieve_trip(self, user_id: UUID, trip_id: UUID) -> TripResponse | None:
        try:
            response = self.client.get(
                "trips",
                params={
                    "select": TRIP_COLUMNS,
                    "user_id": f"eq.{user_id}",
                    "id": f"eq.{trip_id}",
                    "limit": 1,
                },
            )
            rows = self.read_rows(response, user_id, 1, trip_id)
            return rows[0] if rows else None
        except (httpx.HTTPError, ValueError):
            raise DatabaseUnavailable from None
