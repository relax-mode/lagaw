"""Shared Supabase/PostgREST quota reservation for billable DeepSeek extraction.

No in-process counters: all Cloud Run instances reserve against the same database.
The SQL RPC enforces both windows atomically; attempts remain charged on provider failure
so retries cannot bypass an exhausted budget.
"""

import os
from contextlib import contextmanager
from typing import Literal
from uuid import UUID

import httpx
from pydantic import BaseModel, ConfigDict, TypeAdapter

from app.database import DatabaseUnavailable, get_database

DEFAULT_PER_MINUTE = 5
DEFAULT_PER_DAY = 40


class QuotaUnavailable(Exception):
    """Infrastructure/configuration failure: fail closed before paid invocation."""


class QuotaDecision(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    allowed: bool
    retry_after_seconds: int
    exhausted_window: Literal["minute", "day"] | None


RESULT = TypeAdapter(list[QuotaDecision])


def quota_limits() -> tuple[int, int]:
    """Bound configurable limits so a typo cannot silently disable protection."""
    try:
        minute = int(os.environ.get("AI_EXTRACT_PER_MINUTE", str(DEFAULT_PER_MINUTE)))
        day = int(os.environ.get("AI_EXTRACT_PER_DAY", str(DEFAULT_PER_DAY)))
        if minute not in range(1, 11) or day not in range(1, 201):
            raise ValueError
    except ValueError:
        raise QuotaUnavailable from None
    return minute, day


class QuotaStore:
    def consume(self, profile_id: UUID) -> QuotaDecision:
        minute, day = quota_limits()
        try:
            with contextmanager(get_database)() as database:
                response = database.client.post(
                    "rpc/consume_ai_extraction_quota",
                    json={
                        "p_profile_id": str(profile_id),
                        "p_per_minute": minute,
                        "p_per_day": day,
                    },
                    headers={"Content-Profile": "public", "Accept-Profile": "public"},
                )
                response.raise_for_status()
                result = RESULT.validate_json(response.content)
                if len(result) != 1 or response.status_code != 200:
                    raise ValueError
                decision = result[0]
                if (decision.allowed and (decision.retry_after_seconds != 0
                                          or decision.exhausted_window is not None)):
                    raise ValueError
                if (not decision.allowed and (decision.retry_after_seconds < 1
                    or decision.exhausted_window is None)):
                    raise ValueError
                return decision
        except (DatabaseUnavailable, httpx.HTTPError, ValueError):
            raise QuotaUnavailable from None


def get_quota_store() -> QuotaStore:
    return QuotaStore()
