"""Persist onboarding preferences in existing public.users rows via backend Data API."""

from uuid import UUID

import httpx
from pydantic import TypeAdapter, ValidationError

from app.database import DatabaseUnavailable
from app.onboarding_schemas import OnboardingPreferences, SavedPreferenceRow

COLUMNS = "id,preferred_tags,default_budget_min,default_budget_max,traveler_type"
ROWS = TypeAdapter(list[SavedPreferenceRow])


class OnboardingDatabase:
    def __init__(self, client: httpx.Client):
        self.client = client

    @staticmethod
    def checked_row(response: httpx.Response, owner_id: UUID) -> SavedPreferenceRow | None:
        response.raise_for_status()
        rows = ROWS.validate_json(response.content)
        if len(rows) > 1 or any(row.id != owner_id for row in rows):
            raise ValueError("Unexpected profile response")
        return rows[0] if rows else None

    def get(self, owner_id: UUID) -> OnboardingPreferences | None:
        try:
            response = self.client.get("users", params={
                "select": COLUMNS, "id": f"eq.{owner_id}", "limit": 2,
            })
            row = self.checked_row(response, owner_id)
            return row.as_preferences() if row is not None else None
        except (httpx.HTTPError, ValidationError, ValueError, TypeError):
            raise DatabaseUnavailable from None

    def replace(
        self, owner_id: UUID, preferences: OnboardingPreferences,
    ) -> OnboardingPreferences | None:
        try:
            response = self.client.patch(
                "users",
                params={"select": COLUMNS, "id": f"eq.{owner_id}"},
                headers={"Prefer": "return=representation", "Content-Profile": "public"},
                json={
                    "preferred_tags": preferences.preferred_tags,
                    "default_budget_min": (
                        str(preferences.budget_min) if preferences.budget_min is not None else None
                    ),
                    "default_budget_max": (
                        str(preferences.budget_max) if preferences.budget_max is not None else None
                    ),
                    "traveler_type": preferences.travel_style,
                },
            )
            row = self.checked_row(response, owner_id)
            if response.status_code != 200:
                raise ValueError("Unexpected update response")
            return row.as_preferences() if row is not None else None
        except (httpx.HTTPError, ValidationError, ValueError, TypeError):
            raise DatabaseUnavailable from None
