"""Inputs a hostile tester sends to break the API: each must be a clean 4xx.

Every case here was reproduced against the deployed staging API on 2026-11-27,
where it returned 503 ("temporarily unavailable") or 500 before this fix.
"""

import json
from decimal import Decimal

import pytest
from pydantic import ValidationError

from app.interaction_schemas import InteractionCreate
from test_auth import LOCATION, PAYLOAD, api  # noqa: F401  (pytest fixture)


@pytest.mark.parametrize("field,value", [
    ("title", "a\x00b"), ("title", "\ud800"), ("group_type", "x\x00"),
    ("transportation_mode", "\udfff"), ("preferred_tags", ["ok", "bad\x00"]),
])
def test_unstorable_text_is_rejected_before_the_database(api, field, value):  # noqa: F811
    client, state = api
    body = json.dumps({**PAYLOAD, field: value}).encode()
    response = client.post("/api/v1/trips", content=body,
                           headers={"Content-Type": "application/json"})
    assert response.status_code == 422
    assert state.trips == []


@pytest.mark.parametrize("dates", [
    {"start_date": "0001-01-01", "end_date": "9999-12-31"},
    {"start_date": "1999-12-31", "end_date": "2000-01-01"},
    {"start_date": "2026-01-01", "end_date": "2027-01-02"},
])
def test_absurd_trip_dates_are_rejected_on_create(api, dates):  # noqa: F811
    client, state = api
    response = client.post("/api/v1/trips", json={**PAYLOAD, **dates})
    assert response.status_code == 422
    assert response.json()["detail"][0]["loc"] == ["body", "end_date"]
    assert state.trips == []


def test_trip_of_exactly_366_days_is_allowed(api):  # noqa: F811
    client, _ = api
    response = client.post("/api/v1/trips", json={
        **PAYLOAD, "start_date": "2028-01-01", "end_date": "2028-12-31"})
    assert response.status_code == 201


def test_patch_cannot_stretch_a_trip_past_the_limit(api):  # noqa: F811
    client, state = api
    trip_id = client.post("/api/v1/trips", json=PAYLOAD).json()["id"]
    response = client.patch(f"/api/v1/trips/{trip_id}", json={"end_date": "9999-12-31"})
    assert response.status_code == 422
    assert state.trips[0]["end_date"] == PAYLOAD["end_date"]
    # Unrelated edits to a trip saved before the limit still work.
    state.trips[0].update(start_date="0001-01-01", end_date="9999-12-31")
    assert client.patch(f"/api/v1/trips/{trip_id}", json={"title": "Renamed"}).status_code == 200
    assert client.get(f"/api/v1/trips/{trip_id}").status_code == 200


@pytest.mark.parametrize("path", [
    "/api/v1/trips?offset=9223372036854775808", "/api/v1/trips?offset=100001",
    "/api/v1/interactions?offset=100001", "/locations?offset=9223372036854775808",
])
def test_huge_offsets_are_validation_errors(api, path):  # noqa: F811
    client, state = api
    response = client.get(path)
    assert response.status_code == 422
    # Auth may look up the profile row, but no page query is ever sent.
    assert not any(r.url.path.endswith(("/trips", "/user_location_interactions", "/locations"))
                   for r in state.requests)


def test_oversized_declared_body_is_rejected_before_parsing(api):  # noqa: F811
    client, state = api
    response = client.post("/api/v1/trips", content=b"{" + b" " * 70_000 + b"}",
                           headers={"Content-Type": "application/json"})
    assert response.status_code == 413
    assert response.json() == {"detail": "Request body is too large."}
    assert state.requests == []


def test_oversized_streamed_body_is_rejected(api):  # noqa: F811
    client, state = api

    def chunks():
        for _ in range(20):
            yield b" " * 5_000

    response = client.post("/api/v1/trips", content=chunks(),
                           headers={"Content-Type": "application/json"})
    assert response.status_code == 413
    assert state.requests == []


def test_normal_body_still_reaches_the_route(api):  # noqa: F811
    client, state = api
    assert client.post("/api/v1/trips", json=PAYLOAD).status_code == 201
    assert len(state.trips) == 1


def test_oversized_body_rejection_keeps_cors_headers(api):  # noqa: F811
    client, _ = api
    response = client.post("/api/v1/trips", content=b" " * 70_000, headers={
        "Content-Type": "application/json", "Origin": "http://localhost:3000"})
    assert response.status_code == 413
    assert response.headers["access-control-allow-origin"] == "http://localhost:3000"


@pytest.mark.parametrize("prompt", ["cafes\x00", "cafes \ud83d"])
def test_unstorable_extraction_prompt_never_reaches_quota_or_provider(api, prompt):  # noqa: F811
    client, state = api
    body = json.dumps({"prompt": prompt}).encode()
    response = client.post("/api/v1/preferences/extract", content=body,
                           headers={"Content-Type": "application/json"})
    assert response.status_code == 422
    assert response.json()["detail"]["manual_fallback"] is True
    assert not any("rpc" in r.url.path for r in state.requests)


def test_rating_precision_is_bounded():
    assert InteractionCreate(location_id=LOCATION, interaction_type="rating",
                             rating_value=Decimal("4.5")).rating_value == Decimal("4.5")
    with pytest.raises(ValidationError):
        InteractionCreate(location_id=LOCATION, interaction_type="rating",
                          rating_value=Decimal("3.123456789012345678"))
