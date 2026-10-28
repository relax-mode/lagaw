"""Real API fixtures restricted to disposable PostgreSQL and PostgREST."""

import os
import time
from types import SimpleNamespace
from uuid import uuid4

import httpx
import pytest
from trip_test_support import LOCAL_ORIGIN, require_disposable_services

DEMO_TOKEN = "issue29-synthetic-test-token-only-00000000"


@pytest.fixture(scope="session")
def rest():
    # No dotenv loading, hosted credentials or configurable request destination.
    try:
        require_disposable_services(
            os.environ.get("DATABASE_URL", ""), os.environ.get("CI_POSTGREST_URL", ""),
        )
    except ValueError as exc:
        pytest.fail(str(exc), pytrace=False)
    with httpx.Client(
        base_url=LOCAL_ORIGIN, trust_env=False, timeout=5, follow_redirects=False,
        headers={"Accept-Profile": "public", "Content-Profile": "public"},
    ) as client:
        deadline = time.monotonic() + 30
        while True:
            try:
                ready = client.get("trips", params={"select": "id", "limit": 0})
                if ready.status_code == 200 and ready.json() == []:
                    break
            except (httpx.HTTPError, ValueError):
                pass
            if time.monotonic() >= deadline:
                pytest.fail("Disposable PostgREST is unavailable on 127.0.0.1:53000.", pytrace=False)
            time.sleep(0.25)
        yield client


@pytest.fixture
def payload():
    return {
        "title": "Issue 29 synthetic trip",
        "start_date": "2026-11-01", "end_date": "2026-11-02",
        "budget_min": "100.00", "budget_max": "500.50",
        "transportation_mode": "walking", "group_type": "solo",
        "preferred_tags": ["heritage", "cafe"],
    }


@pytest.fixture
def users(rest):
    # Register cleanup BEFORE the first committed fixture write.
    owner, other = str(uuid4()), str(uuid4())
    query = {"id": f"in.({owner},{other})"}
    trip_query = {"user_id": f"in.({owner},{other})"}
    try:
        for user_id in (owner, other):
            response = rest.post("users", json={
                "id": user_id, "name": "Issue 29 synthetic user",
                "email": f"issue29-{user_id}@example.invalid",
            })
            assert response.status_code == 201, "Could not create isolated user fixture"
        yield SimpleNamespace(owner=owner, other=other)
    finally:
        # HTTP requests commit independently; an outer rollback cannot undo them.
        # Check the cascade, then attempt exact cleanup even if it is broken.
        errors = []
        try:
            deleted = rest.delete("users", params=query)
            if deleted.status_code not in (200, 204):
                errors.append("Fixture user deletion failed")
            for table, params in (("users", query), ("trips", trip_query)):
                remaining = rest.get(table, params={**params, "select": "id"})
                if remaining.status_code != 200 or remaining.json() != []:
                    errors.append(f"Fixture {table} remain after cleanup")
        finally:
            if errors:
                for table, params in (("trips", trip_query), ("users", query)):
                    response = rest.delete(table, params=params)
                    assert response.status_code in (200, 204), "Fallback fixture cleanup failed"
        assert not errors, "; ".join(errors)


@pytest.fixture
def seed_trip(rest, users, payload):
    def create(owner=None, **changes):
        owner = owner or users.owner
        assert owner in (users.owner, users.other)
        response = rest.post(
            "trips", headers={"Prefer": "return=representation"},
            json={**payload, **changes, "id": str(uuid4()), "user_id": owner},
        )
        assert response.status_code == 201, "Could not seed isolated trip"
        return response.json()[0]

    return create


@pytest.fixture
def application(rest, users, monkeypatch):
    # Exercise real routing, authorization, validation and TripDatabase. Only
    # its connection provider changes: standalone PostgREST has no /rest/v1.
    import app.database
    import app.trips

    monkeypatch.setenv("TRIP_DEMO_USER_ID", users.owner)
    monkeypatch.setenv("TRIP_DEMO_TOKEN", DEMO_TOKEN)
    monkeypatch.setenv("TRIP_AUTH_MODE", "demo")
    monkeypatch.setenv("SUPABASE_URL", "http://127.0.0.1:54321")
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "")
    monkeypatch.setattr("dotenv.load_dotenv", lambda *args, **kwargs: None)
    monkeypatch.setattr(app.database, "load_dotenv", lambda *args, **kwargs: None)

    from app.main import create_app

    monkeypatch.setattr("app.main.load_dotenv", lambda *args, **kwargs: None)

    def connection():
        yield app.database.LocationDatabase(rest)

    monkeypatch.setattr(app.trips, "get_database", connection)
    return create_app()


@pytest.fixture
def client(application):
    from fastapi.testclient import TestClient

    with TestClient(application, headers={"Authorization": f"Bearer {DEMO_TOKEN}"}) as test_client:
        yield test_client


@pytest.fixture
def stored_trip(rest, users):
    def read(trip_id):
        response = rest.get("trips", params={
            "id": f"eq.{trip_id}", "user_id": f"eq.{users.owner}", "select": "*",
        })
        assert response.status_code == 200
        return response.json()

    return read
