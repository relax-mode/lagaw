"""Offline API, ownership, failure and recommendation handoff checks for #52."""

import json
from decimal import Decimal
from unittest.mock import patch
from uuid import UUID, uuid4

import httpx
import pytest
from fastapi.testclient import TestClient

from app.database import DatabaseUnavailable, LocationDatabase
from app.interaction_database import InteractionDatabase
from app.recommendations.contracts import RecommendationRequest, validate_response
from app.recommendations.fixtures import load_request

OWNER, OTHER, LOCATION = (str(uuid4()) for _ in range(3))
TOKEN = "issue52-offline-demo-token-0000000000000"
URL = "/api/v1/interactions"


def event(**changes):
    return {
        "id": str(uuid4()), "user_id": OWNER, "location_id": LOCATION,
        "interaction_type": "save", "interaction_value": "1", "rating_value": None,
        "created_at": "2026-10-28T00:00:00+00:00", **changes,
    }


@pytest.fixture
def harness(monkeypatch):
    monkeypatch.setenv("TRIP_DEMO_USER_ID", OWNER)
    monkeypatch.setenv("TRIP_DEMO_TOKEN", TOKEN)
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "")
    with patch("dotenv.load_dotenv"):
        from app.main import create_app
    monkeypatch.setattr("app.main.load_dotenv", lambda *args, **kwargs: None)
    state = {"rows": [], "requests": [], "active": True, "override": None}

    def handle(request):
        state["requests"].append(request)
        if state["override"] is not None:
            return state["override"](request)
        if request.url.path == "/locations":
            assert request.url.params["id"] == f"eq.{LOCATION}"
            assert request.url.params["is_active"] == "eq.true"
            return httpx.Response(200, json=[{"id": LOCATION, "is_active": True}]
                                  if state["active"] else [])
        assert request.url.path == "/user_location_interactions"
        assert "provenance" not in request.url.params["select"]
        if request.method == "POST":
            body = json.loads(request.content)
            assert body["user_id"] == OWNER
            assert "id" not in body and "created_at" not in body and "provenance" not in body
            row = event(**body)
            state["rows"].append(row)
            return httpx.Response(201, json=[row])
        assert request.url.params["user_id"] == f"eq.{OWNER}"
        rows = [row for row in state["rows"] if row["user_id"] == OWNER]
        if "id" in request.url.params:
            rows = [row for row in rows if f"eq.{row['id']}" == request.url.params["id"]]
        else:
            assert request.url.params["order"] == "created_at.asc,id.asc"
        offset = int(request.url.params.get("offset", 0))
        return httpx.Response(200, json=rows[offset:offset + int(request.url.params["limit"])])

    with httpx.Client(base_url="https://offline.invalid/", transport=httpx.MockTransport(handle)) as rest:
        def connection():
            yield LocationDatabase(rest)
        monkeypatch.setattr("app.interactions.get_database", connection)
        state["database"] = InteractionDatabase(rest)
        with TestClient(create_app(), headers={"Authorization": f"Bearer {TOKEN}"}) as client:
            yield client, state


@pytest.mark.parametrize("kind,rating,signal", [
    ("left_swipe", None, "-1"), ("right_swipe", None, "1"),
    ("save", None, "1"), ("rating", 1, "1"), ("rating", "3.75", "1"), ("rating", 5, "1"),
])
def test_valid_events_and_repeats(harness, kind, rating, signal):
    api, state = harness
    body = {"location_id": LOCATION, "interaction_type": kind}
    if rating is not None:
        body["rating_value"] = rating
    first, second = (api.post(URL, json=body) for _ in range(2))
    assert first.status_code == second.status_code == 201
    one, two = first.json(), second.json()
    assert one["id"] != two["id"]
    assert one["user_id"] == OWNER and one["provenance"] == "real"
    assert one["interaction_value"] == signal
    assert one["rating_value"] == (str(rating) if rating is not None else None)
    assert api.get(URL + f"/{one['id']}").json() == one
    page = api.get(URL).json()
    assert page == {"schema_version": "1", "items": [one, two], "limit": 10, "offset": 0}
    assert len(state["rows"]) == 2


@pytest.mark.parametrize("changes", [
    {"location_id": "bad"}, {"location_id": 42}, {"location_id": None},
    {"interaction_type": "like"}, {"interaction_type": 1}, {"interaction_type": None},
    {"interaction_type": "rating"}, {"interaction_type": "rating", "rating_value": None},
    *({"interaction_type": "rating", "rating_value": value}
      for value in (0, 0.99, 5.01, -1, True, "NaN", "Infinity", [], {})),
    {"rating_value": 3}, {"user_id": OTHER}, {"interaction_value": 99},
    {"id": str(uuid4())}, {"created_at": "2026-10-01T00:00:00Z"},
    {"provenance": "synthetic"},
])
def test_invalid_writes_have_no_database_effect(harness, changes):
    api, state = harness
    result = api.post(URL, json={"location_id": LOCATION, "interaction_type": "save", **changes})
    assert result.status_code == 422
    assert all(set(error) == {"loc", "msg", "type"} for error in result.json()["detail"])
    assert not state["rows"] and not state["requests"]


@pytest.mark.parametrize("body", [{}, [], None, "secret-user-input"])
def test_invalid_body(harness, body):
    api, state = harness
    result = api.post(URL, content=json.dumps(body), headers={"Content-Type": "application/json"})
    assert result.status_code == 422
    assert "secret-user-input" not in result.text
    assert not state["requests"]


def test_malformed_json_and_nonfinite_rating_are_sanitized(harness):
    api, state = harness
    for body in ('{"private":"secret-body",',
                 '{"location_id":"' + LOCATION + '","interaction_type":"rating","rating_value":NaN}'):
        result = api.post(URL, content=body, headers={"Content-Type": "application/json"})
        assert result.status_code == 422
        assert "secret-body" not in result.text and '"input"' not in result.text
    assert not state["requests"]


@pytest.mark.parametrize("suffix", ["?limit=0", "?limit=101", "?offset=-1", "?limit=bad", "/bad"])
def test_invalid_read_parameters(harness, suffix):
    api, state = harness
    assert api.get(URL + suffix).status_code == 422
    assert not state["requests"]


def test_owner_scoped_history_and_retrieval(harness):
    api, state = harness
    own, other = event(), event(user_id=OTHER)
    state["rows"] = [own, other]
    assert [row["id"] for row in api.get(URL + f"?user_id={OTHER}").json()["items"]] == [own["id"]]
    for identifier in (other["id"], str(uuid4())):
        assert api.get(URL + f"/{identifier}").status_code == 404
    # No editing/deleting event routes or user-addressed write routes exist.
    assert api.patch(URL + f"/{other['id']}", json={"rating_value": 5}).status_code == 405
    assert api.post(URL + f"/{OTHER}", json={}).status_code == 405
    assert state["rows"] == [own, other]


@pytest.mark.parametrize("method,suffix", [("GET", ""), ("POST", ""),
                                         ("GET", "/recommendation-input"), ("GET", f"/{uuid4()}")])
@pytest.mark.parametrize("authorization", ["", "Bearer wrong", "Basic abc"])
def test_unauthenticated_requests_never_reach_database(harness, method, suffix, authorization):
    api, state = harness
    result = api.request(method, URL + suffix, headers={"Authorization": authorization},
                         json={"location_id": LOCATION, "interaction_type": "save"})
    assert result.status_code == 401 and result.headers["www-authenticate"] == "Bearer"
    assert not state["requests"]


def test_disabled_context(harness, monkeypatch):
    api, state = harness
    monkeypatch.delenv("TRIP_DEMO_USER_ID")
    assert api.get(URL).status_code == 503
    assert not state["requests"]


def test_missing_or_inactive_location_does_not_insert(harness):
    api, state = harness
    state["active"] = False
    result = api.post(URL, json={"location_id": LOCATION, "interaction_type": "save"})
    assert result.status_code == 404
    assert not state["rows"] and len(state["requests"]) == 1


@pytest.mark.parametrize("status,payload", [
    (401, {"message": "provider-secret"}), (409, {"code": "23503", "message": "provider-secret"}),
    (500, {"message": "provider-secret"}), (200, {}), (200, [event(user_id=OTHER)]),
    (200, [event(rating_value=3)]), (200, [event(created_at="2026-10-28T00:00:00")]),
])
def test_bad_database_history_fails_closed(harness, status, payload):
    api, state = harness
    state["override"] = lambda request: httpx.Response(status, json=payload)
    result = api.get(URL)
    assert result.status_code == 503
    assert result.json() == {"detail": "Interactions are temporarily unavailable. Please try again later."}
    assert "provider-secret" not in result.text and OTHER not in result.text


def test_connection_failure_is_sanitized(harness, monkeypatch):
    api, state = harness
    def broken():
        raise DatabaseUnavailable
        yield  # pragma: no cover
    monkeypatch.setattr("app.interactions.get_database", broken)
    assert api.get(URL).status_code == 503
    assert not state["requests"]


def test_timeout_and_invalid_json_are_sanitized(harness):
    api, state = harness
    def timeout(request):
        raise httpx.ReadTimeout("provider-secret", request=request)
    for handler in (timeout, lambda request: httpx.Response(200, content=b"provider-secret")):
        state["override"] = handler
        result = api.get(URL)
        assert result.status_code == 503 and "provider-secret" not in result.text


@pytest.mark.parametrize("changes", [{"user_id": OTHER}, {"location_id": str(uuid4())},
                                    {"interaction_type": "left_swipe"}, {"interaction_value": 42}])
def test_invalid_write_representation_is_not_returned(harness, changes):
    api, state = harness
    def override(request):
        if request.method == "GET":
            return httpx.Response(200, json=[{"id": LOCATION, "is_active": True}])
        return httpx.Response(201, json=[event(**changes)])
    state["override"] = override
    assert api.post(URL, json={"location_id": LOCATION, "interaction_type": "save"}).status_code == 503


def test_pagination_and_complete_exclusions(harness):
    api, state = harness
    state["rows"] = [event() for _ in range(101)]
    state["rows"][-1] = event(interaction_type="left_swipe", interaction_value="-1")
    assert len(api.get(URL + "?limit=1&offset=1").json()["items"]) == 1
    result = api.get(URL + "/recommendation-input")
    assert result.status_code == 200
    assert len(result.json()["interactions"]) == 101
    assert result.json()["excluded_location_ids"] == [LOCATION]
    # A later positive event does not undo the S3-01 conservative rejection.
    state["rows"].append(event(interaction_type="right_swipe"))
    assert api.get(URL + "/recommendation-input").json()["excluded_location_ids"] == [LOCATION]


def test_input_limit_and_duplicate_pages_fail_closed(harness, monkeypatch):
    api, state = harness
    state["rows"] = [event() for _ in range(101)]
    monkeypatch.setattr("app.interaction_database.MAX_INPUT_EVENTS", 100)
    assert api.get(URL + "/recommendation-input").status_code == 503
    state["rows"] = [event()] * 2
    assert api.get(URL).status_code == 503


def test_same_schema_feeds_recommender_without_foreign_catalog_events(harness):
    _, state = harness
    request = load_request("cold_start")
    candidate = request.locations[0]
    state["rows"] = [event(location_id=str(candidate.id), interaction_type="left_swipe",
                           interaction_value="-1"), event()]
    adapted = state["database"].recommendation_input(UUID(OWNER), {item.id for item in request.locations})
    payload = request.model_dump()
    payload["preferences"]["user_id"] = UUID(OWNER)
    payload["interactions"] = adapted.interactions
    typed = RecommendationRequest.model_validate(payload)
    assert len(typed.interactions) == 1
    assert typed.interactions[0].provenance == "real"
    assert typed.interactions[0].interaction_value == Decimal(-1)
    from app.recommendations.contracts import RecommendationResponse
    with pytest.raises(ValueError, match="excluded"):
        validate_response(typed, RecommendationResponse(items=[{
            "location_id": candidate.id, "recommendation_score": 1,
            "recommendation_reason": "Excluded place",
        }]))


def test_empty_history_is_a_valid_cold_start(harness):
    api, _ = harness
    assert api.get(URL + "/recommendation-input").json() == {
        "schema_version": "1", "interactions": [], "excluded_location_ids": [],
    }
