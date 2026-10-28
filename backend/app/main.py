"""Lagaw's FastAPI entry point."""

import os
from pathlib import Path
from typing import Annotated
from urllib.parse import urlsplit

from dotenv import load_dotenv
from fastapi import Depends, FastAPI, Query, Request
from fastapi.exception_handlers import request_validation_exception_handler
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.database import DatabaseUnavailable, LocationDatabase, get_database
from app.interactions import router as interactions_router
from app.preference_extraction import router as preference_extraction_router
from app.schemas import LocationsPage
from app.trip_items import router as trip_items_router
from app.trip_recommendations import router as trip_recommendations_router
from app.trips import router as trips_router

ROOT = Path(__file__).resolve().parents[2]


async def database_unavailable(request: Request, exc: DatabaseUnavailable) -> JSONResponse:
    return JSONResponse(
        status_code=503,
        content={"detail": "Locations are temporarily unavailable. Please try again later."},
    )


async def validation_error(request: Request, exc: RequestValidationError):
    if request.url.path.startswith("/api/v1/preferences"):
        return JSONResponse(status_code=422, content={"detail": {
            "code": "invalid_request", "message": "The travel request is invalid.",
            "manual_fallback": True,
        }})
    if request.url.path.startswith(("/api/v1/trips", "/api/v1/interactions")):
        # Omit submitted values and validator context, including tokens and NaN.
        return JSONResponse(status_code=422, content={"detail": [
            {"loc": error["loc"], "msg": error["msg"], "type": error["type"]}
            for error in exc.errors()
        ]})
    return await request_validation_exception_handler(request, exc)


def list_locations(
    database: Annotated[LocationDatabase, Depends(get_database)],
    limit: Annotated[int, Query(ge=1, le=100)] = 10,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> LocationsPage:
    """List active destinations, ordered by name and UUID, from PostgreSQL."""
    return LocationsPage(
        items=database.list_locations(limit, offset), limit=limit, offset=offset,
    )


def get_cors_origins() -> list[str]:
    """Read exact browser origins; an unset allowlist permits no cross-origin reads."""
    origins = [
        value.strip() for value in os.environ.get("CORS_ALLOWED_ORIGINS", "").split(",")
        if value.strip()
    ]
    for origin in origins:
        try:
            parsed = urlsplit(origin)
            valid = (
                parsed.scheme in ("http", "https") and parsed.hostname
                and not parsed.username and not parsed.password
                and origin == f"{parsed.scheme}://{parsed.netloc}"
                and "*" not in origin and not any(char.isspace() for char in origin)
            )
            # Accessing port also rejects malformed or out-of-range port numbers.
            _ = parsed.port
        except ValueError:
            valid = False
        if not valid:
            raise ValueError(
                "CORS_ALLOWED_ORIGINS must contain comma-separated HTTP(S) origins "
                "without paths, credentials, or wildcards."
            ) from None
    return origins


def create_app() -> FastAPI:
    """Configure each backend environment at startup, before serving requests."""
    load_dotenv(ROOT / ".env", override=False)
    application = FastAPI(title="Lagaw API", version="0.1.0")
    application.add_middleware(
        CORSMiddleware,
        allow_origins=get_cors_origins(),
        allow_credentials=False,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
        allow_headers=["Authorization", "Content-Type"],
    )
    application.add_exception_handler(DatabaseUnavailable, database_unavailable)
    application.add_exception_handler(RequestValidationError, validation_error)
    application.include_router(trips_router)
    application.include_router(interactions_router)
    application.include_router(trip_items_router)
    application.include_router(trip_recommendations_router)
    application.include_router(preference_extraction_router)
    application.add_api_route(
        "/locations", list_locations, methods=["GET"], response_model=LocationsPage,
        tags=["locations"], responses={
            503: {"description": "Database configuration, connectivity, or response failure"},
        },
    )
    return application


app = create_app()
