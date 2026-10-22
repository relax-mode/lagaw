"""Trip CRUD through Supabase's PostgreSQL Data API, always scoped by owner."""

from uuid import UUID

import httpx
from pydantic import TypeAdapter

from app.database import DatabaseUnavailable
from app.trip_schemas import TripCreate, TripResponse, TripUpdate

TRIP_COLUMNS = ",".join(TripResponse.model_fields)
TRIP_LIST = TypeAdapter(list[TripResponse])


class TripUpdateConflict(Exception):
    """A database check rejected an update, including a concurrent range change."""


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

    def update_trip(
        self, user_id: UUID, trip_id: UUID, payload: TripUpdate,
    ) -> TripResponse | None:
        try:
            response = self.client.patch(
                "trips",
                params={
                    "select": TRIP_COLUMNS,
                    "user_id": f"eq.{user_id}",
                    "id": f"eq.{trip_id}",
                },
                headers={"Prefer": "return=representation", "Content-Profile": "public"},
                json=payload.model_dump(mode="json", exclude_unset=True),
            )
            # PostgreSQL checks protect the final row even if another caller edits
            # its dates/budgets between our read and write. A failed statement is atomic.
            if response.status_code == 400:
                error = response.json()
                if isinstance(error, dict) and error.get("code") == "23514":
                    raise TripUpdateConflict
            rows = self.read_rows(response, user_id, 1, trip_id)
            if response.status_code != 200:
                raise ValueError
            return rows[0] if rows else None
        except (httpx.HTTPError, ValueError):
            raise DatabaseUnavailable from None

    def delete_trip(self, user_id: UUID, trip_id: UUID) -> bool:
        try:
            response = self.client.delete(
                "trips",
                params={
                    "select": "id,user_id",
                    "user_id": f"eq.{user_id}",
                    "id": f"eq.{trip_id}",
                },
                headers={"Prefer": "return=representation", "Content-Profile": "public"},
            )
            response.raise_for_status()
            rows = response.json()
            if response.status_code != 200 or not isinstance(rows, list) or (
                rows and rows != [{"id": str(trip_id), "user_id": str(user_id)}]
            ):
                raise ValueError
            # The existing trip_id FK cascades deletion in this same DB transaction.
            return bool(rows)
        except (httpx.HTTPError, ValueError):
            raise DatabaseUnavailable from None
