"""Owner-scoped, append-only events in the existing PostgreSQL table."""

from uuid import UUID

import httpx
from pydantic import TypeAdapter

from app.database import DatabaseUnavailable
from app.interaction_schemas import InteractionCreate, InteractionInput
from app.recommendations.contracts import Interaction

TABLE = "user_location_interactions"
COLUMNS = ",".join(field for field in Interaction.model_fields if field != "provenance")
EVENTS = TypeAdapter(list[Interaction])
PAGE_SIZE = 100
MAX_INPUT_EVENTS = 10_000


class ActiveLocationNotFound(Exception):
    """A missing and an inactive destination have the same public result."""


class InteractionDatabase:
    def __init__(self, client: httpx.Client):
        self.client = client

    @staticmethod
    def read_rows(response, user_id: UUID, maximum: int, event_id: UUID | None = None):
        response.raise_for_status()
        raw = response.json()
        if not isinstance(raw, list) or any(not isinstance(row, dict) for row in raw):
            raise ValueError
        # Provenance belongs to the module boundary, never a new database column.
        rows = EVENTS.validate_python([{**row, "provenance": "real"} for row in raw])
        if len(rows) > maximum or len({row.id for row in rows}) != len(rows) or any(
            row.user_id != user_id or (event_id is not None and row.id != event_id)
            for row in rows
        ):
            raise ValueError
        return rows

    def create_interaction(self, user_id: UUID, payload: InteractionCreate) -> Interaction:
        try:
            target = self.client.get("locations", params={
                "select": "id,is_active", "id": f"eq.{payload.location_id}",
                "is_active": "eq.true", "limit": 1,
            })
            target.raise_for_status()
            locations = target.json()
            if locations == []:
                raise ActiveLocationNotFound
            if not isinstance(locations, list) or len(locations) != 1 or (
                locations[0] != {"id": str(payload.location_id), "is_active": True}
                or locations[0].get("is_active") is not True
            ):
                raise ValueError
            response = self.client.post(
                TABLE, params={"select": COLUMNS},
                headers={"Prefer": "return=representation", "Content-Profile": "public"},
                json={**payload.persistence_values(), "user_id": str(user_id)},
            )
            rows = self.read_rows(response, user_id, 1)
            if response.status_code != 201 or len(rows) != 1:
                raise ValueError
            row = rows[0]
            if any(getattr(row, field) != value for field, value in payload.model_dump().items()):
                raise ValueError
            expected_signal = -1 if payload.interaction_type == "left_swipe" else 1
            if row.interaction_value != expected_signal:
                raise ValueError
            return row
        except (httpx.HTTPError, ValueError):
            raise DatabaseUnavailable from None

    def list_interactions(self, user_id: UUID, limit: int, offset: int) -> list[Interaction]:
        try:
            response = self.client.get(TABLE, params={
                "select": COLUMNS, "user_id": f"eq.{user_id}",
                "order": "created_at.asc,id.asc", "limit": limit, "offset": offset,
            })
            return self.read_rows(response, user_id, limit)
        except (httpx.HTTPError, ValueError):
            raise DatabaseUnavailable from None

    def retrieve_interaction(self, user_id: UUID, event_id: UUID) -> Interaction | None:
        try:
            response = self.client.get(TABLE, params={
                "select": COLUMNS, "user_id": f"eq.{user_id}",
                "id": f"eq.{event_id}", "limit": 1,
            })
            rows = self.read_rows(response, user_id, 1, event_id)
            return rows[0] if rows else None
        except (httpx.HTTPError, ValueError):
            raise DatabaseUnavailable from None

    def recommendation_input(
        self, user_id: UUID, location_ids: set[UUID] | None = None,
    ) -> InteractionInput:
        """Load complete history, optionally projected onto the inference catalog.

        Never silently truncate exclusions at one HTTP/database page. Fail closed
        on excessive history or inconsistent pages; ranking stays in the AI module.
        """
        events = []
        seen = set()
        offset = 0
        while True:
            page = self.list_interactions(user_id, PAGE_SIZE, offset)
            if any(row.id in seen for row in page) or offset + len(page) > MAX_INPUT_EVENTS:
                raise DatabaseUnavailable
            seen.update(row.id for row in page)
            events.extend(row for row in page if location_ids is None or row.location_id in location_ids)
            offset += len(page)
            if len(page) < PAGE_SIZE:
                break
        return InteractionInput(
            interactions=events,
            excluded_location_ids=sorted({
                row.location_id for row in events if row.interaction_type == "left_swipe"
            }),
        )
