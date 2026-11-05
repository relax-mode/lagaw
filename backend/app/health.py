"""Cheap public liveness and bounded database readiness for Cloud Run.

No AI provider call, no user-profile access and no credential reflection.
"""

from contextlib import contextmanager

import httpx
from fastapi.responses import JSONResponse

from app.database import DatabaseUnavailable, get_database


def liveness() -> dict[str, str]:
    """Process is serving requests; external services are deliberately not probed."""
    return {"status": "ok"}


def readiness() -> dict[str, str] | JSONResponse:
    """Confirm a bounded, read-only PostgREST query can reach the existing catalog."""
    try:
        with contextmanager(get_database)() as database:
            reply = database.client.get(
                "locations", params={"select": "id", "limit": 0}, timeout=2.0
            )
            reply.raise_for_status()
            if reply.status_code != 200 or reply.json() != []:
                raise ValueError
    except (DatabaseUnavailable, httpx.HTTPError, ValueError):
        return JSONResponse(status_code=503, content={"status": "not_ready"})
    return {"status": "ready"}
