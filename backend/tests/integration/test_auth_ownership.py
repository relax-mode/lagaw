"""Verified-identity mapping against disposable PostgreSQL/PostgREST only.

The external Auth server is substituted; profile creation, unique constraints,
CRUD and owner filtering are real. Cryptographic verification is covered offline.
"""

from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient

from app.auth import profile_owner
from app.database import LocationDatabase

pytestmark = pytest.mark.db


@pytest.fixture
def verified_api(application, rest, monkeypatch):
    subject_a, subject_b = uuid4(), uuid4()
    subjects = {"synthetic-user-a": subject_a, "synthetic-user-b": subject_b}

    def identity(token):
        from app.auth import unauthorized
        if token not in subjects:
            raise unauthorized()
        subject = subjects[token]
        return subject, f"issue79-{subject}@example.invalid"

    def connection():
        yield LocationDatabase(rest)

    monkeypatch.setenv("TRIP_AUTH_MODE", "supabase")
    monkeypatch.setattr("app.auth.verify_identity", identity)
    monkeypatch.setattr("app.auth.get_database", connection)
    monkeypatch.setattr("app.interactions.get_database", connection)
    monkeypatch.setattr("app.trip_recommendations.get_database", connection)
    query = {"auth_user_id": f"in.({subject_a},{subject_b})"}
    try:
        with TestClient(application, headers={"Authorization": "Bearer synthetic-user-a"}) as api:
            yield api, subject_a, subject_b
    finally:
        assert rest.delete("users", params=query).status_code in (200, 204)
        assert rest.get("users", params={**query, "select": "id"}).json() == []


def test_real_profile_creation_is_idempotent_and_two_users_are_isolated(
    verified_api, rest, payload, users, seed_trip,
):
    api, subject_a, _subject_b = verified_api
    legacy_trip = seed_trip()
    baseline = deepcopy(rest.get("users", params={"id": f"eq.{users.owner}"}).json())
    created = api.post("/api/v1/trips", json=payload)
    assert created.status_code == 201
    trip_a = created.json()
    for _ in range(2):
        assert api.get("/api/v1/trips").json()["items"] == [trip_a]
    rows = rest.get("users", params={"auth_user_id": f"eq.{subject_a}"}).json()
    assert len(rows) == 1 and rows[0]["id"] == trip_a["user_id"] != str(subject_a)
    api.headers["Authorization"] = "Bearer synthetic-user-b"
    assert api.get("/api/v1/trips").json()["items"] == []
    for method in ("GET", "PATCH", "DELETE"):
        kwargs = {"json": {"title": "not mine"}} if method == "PATCH" else {}
        assert api.request(method, f"/api/v1/trips/{trip_a['id']}", **kwargs).status_code == 404
    assert api.get(f"/api/v1/trips/{trip_a['id']}/items").status_code == 404
    assert api.post(f"/api/v1/trips/{trip_a['id']}/recommendations",
                    json={"party_size": 1, "planned_visits": 1}).status_code == 404
    assert api.post(f"/api/v1/trips/{trip_a['id']}/generate-itinerary",
                    json={"recommendations": {"party_size": 1, "planned_visits": 1}}).status_code == 404
    trip_b = api.post("/api/v1/trips", json=payload).json()
    assert trip_b["user_id"] != trip_a["user_id"]
    assert rest.get("trips", params={"id": f"eq.{legacy_trip['id']}"}).json() == [legacy_trip]
    assert rest.get("users", params={"id": f"eq.{users.owner}"}).json() == baseline
    assert api.patch(f"/api/v1/trips/{trip_b['id']}", json={"title": "my trip"}).status_code == 200
    assert api.delete(f"/api/v1/trips/{trip_b['id']}").status_code == 204


def test_duplicate_first_requests_create_one_profile(verified_api, rest):
    _api, subject_a, _subject_b = verified_api
    with ThreadPoolExecutor(max_workers=4) as workers:
        owners = list(workers.map(lambda _: profile_owner(subject_a,
                          f"issue79-{subject_a}@example.invalid"), range(4)))
    assert len(set(owners)) == 1
    rows = rest.get("users", params={"auth_user_id": f"eq.{subject_a}"}).json()
    assert len(rows) == 1 and UUID(rows[0]["id"]) == owners[0]


def test_existing_email_collision_preserves_profile_and_trip(
    verified_api, rest, users, seed_trip,
):
    api, subject_a, _subject_b = verified_api
    assert rest.patch("users", params={"id": f"eq.{users.owner}"},
                      json={"email": f"issue79-{subject_a}@example.invalid"}).status_code == 204
    trip = seed_trip()
    profile = rest.get("users", params={"id": f"eq.{users.owner}"}).json()
    assert api.get("/api/v1/trips").status_code == 409
    assert rest.get("users", params={"id": f"eq.{users.owner}"}).json() == profile
    assert rest.get("trips", params={"id": f"eq.{trip['id']}"}).json() == [trip]
    assert rest.get("users", params={"auth_user_id": f"eq.{subject_a}"}).json() == []


def test_verified_identity_cannot_read_other_users_interactions(verified_api, rest, users):
    api, _subject_a, _subject_b = verified_api
    location, event = str(uuid4()), str(uuid4())
    try:
        assert rest.post("locations", json={"id": location, "name": "Issue 79 fixture",
                                           "category": "heritage"}).status_code == 201
        assert rest.post("user_location_interactions", json={
            "id": event, "user_id": users.other, "location_id": location,
            "interaction_type": "save", "interaction_value": 1,
        }).status_code == 201
        assert api.get("/api/v1/interactions").json()["items"] == []
        assert api.get(f"/api/v1/interactions/{event}").status_code == 404
        result = api.post("/api/v1/interactions", json={"location_id": location,
                                                      "interaction_type": "save"})
        assert result.status_code == 201
        own = result.json()
        assert own["user_id"] != users.other
        api.headers["Authorization"] = "Bearer synthetic-user-b"
        assert api.get(f"/api/v1/interactions/{own['id']}").status_code == 404
        assert api.get("/api/v1/interactions/recommendation-input").json()["interactions"] == []
    finally:
        # Exact owned fixture cleanup, including any newly created user events.
        assert rest.delete("user_location_interactions", params={"location_id": f"eq.{location}"}).status_code in (200, 204)
        assert rest.delete("locations", params={"id": f"eq.{location}"}).status_code in (200, 204)
