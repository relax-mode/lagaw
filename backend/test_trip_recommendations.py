"""Offline HTTP/adapter checks with real contracts, engines and mocked database I/O."""

import hashlib
import json
import logging
from copy import deepcopy
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch
from uuid import UUID, uuid4

import httpx
import pytest
from fastapi.testclient import TestClient

from app.database import LocationDatabase
from app.recommendation_adapter import RecommendationAdapter
from app.recommendations.contracts import RecommendationResponse
from app.recommendations.hybrid import MAX_ARTIFACT_BYTES, HybridRecommender
from app.trip_recommendations import get_recommendation_engine

OWNER, OTHER, TRIP, VENUE, SECOND = (str(uuid4()) for _ in range(5))
TOKEN = "issue53-offline-private-synthetic-token-0000"
URL = f"/api/v1/trips/{TRIP}/recommendations"
OPTIONS = {"party_size": 2, "planned_visits": 3}


def location(identifier=VENUE, **changes):
    return {
        "id": identifier, "name": "Verified cafe", "description": "Database description",
        "category": "cafe", "vibe_tags": ["cafe"], "address": "Database address",
        "latitude": 10.67, "longitude": 122.95, "opening_hours": {},
        "estimated_cost_min": 10, "estimated_cost_max": 50,
        "typical_visit_duration": 30, "suitable_group_types": ["friends"],
        "image_url": None, "is_active": True, **changes,
    }


def recommendation(identifier=VENUE, **changes):
    return {"location_id": identifier, "recommendation_score": 0.9,
            "recommendation_reason": "Verified matches", **changes}


@pytest.fixture
def harness(monkeypatch):
    monkeypatch.setenv("TRIP_DEMO_USER_ID", OWNER)
    monkeypatch.setenv("TRIP_DEMO_TOKEN", TOKEN)
    monkeypatch.setenv("TRIP_AUTH_MODE", "demo")
    monkeypatch.setenv("SUPABASE_URL", "http://127.0.0.1:54321")
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "")
    monkeypatch.delenv("MODEL_FILE_PATH", raising=False)
    with patch("dotenv.load_dotenv"):
        from app.main import create_app
    monkeypatch.setattr("app.main.load_dotenv", lambda *args, **kwargs: None)
    state = SimpleNamespace(
        trip={"id": TRIP, "user_id": OWNER, "title": "Saved manual trip",
              "start_date": "2026-11-01", "end_date": "2026-11-02",
              "budget_min": "100.01", "budget_max": "600.01",
              "group_type": "friends", "preferred_tags": ["cafe"],
              "transportation_mode": "walking", "status": "draft", "estimated_total_cost": None},
        locations=[location(), location(SECOND, estimated_cost_max=80)],
        events=[], requests=[], override=None, engine=None,
    )

    def handle(request):
        state.requests.append(request)
        assert request.method == "GET", "Recommendation processing must be read-only"
        if state.override:
            overridden = state.override(request)
            if overridden is not None:
                return overridden
        params = request.url.params
        if request.url.path == "/trips":
            assert params["user_id"] == f"eq.{OWNER}" and params["id"] == f"eq.{TRIP}"
            return httpx.Response(200, json=[state.trip] if state.trip and state.trip["user_id"] == OWNER else [])
        if request.url.path == "/locations":
            rows = [row for row in state.locations if row["is_active"]]
            if "id" in params:
                ids = params["id"][4:-1].split(",")
                rows = [row for row in rows if row["id"] in ids]
            offset, limit = int(params.get("offset", 0)), int(params["limit"])
            return httpx.Response(200, json=rows[offset:offset + limit])
        assert request.url.path == "/user_location_interactions"
        assert params["user_id"] == f"eq.{OWNER}"
        rows = [row for row in state.events if row["user_id"] == OWNER]
        offset, limit = int(params["offset"]), int(params["limit"])
        return httpx.Response(200, json=rows[offset:offset + limit])

    with httpx.Client(base_url="https://offline.invalid/", transport=httpx.MockTransport(handle)) as rest:
        def connection():
            yield LocationDatabase(rest)
        monkeypatch.setattr("app.trip_recommendations.get_database", connection)
        application = create_app()

        class Engine:
            def recommend(self, request):
                return state.engine(request) if state.engine else HybridRecommender().recommend(request)

        application.dependency_overrides[get_recommendation_engine] = Engine
        state.application, state.rest = application, rest
        with TestClient(application, headers={"Authorization": f"Bearer {TOKEN}"}) as api:
            yield api, state


def test_saved_manual_preferences_cold_start_and_stable_database_details(harness, monkeypatch):
    api, state = harness
    monkeypatch.delenv("DEEPSEEK_API_KEY", raising=False)
    provider = Mock(side_effect=AssertionError("DeepSeek must not be called"))
    monkeypatch.setattr("app.preference_extraction.extract_preferences", provider)
    before = deepcopy(state.trip)
    response = api.post(URL, json=OPTIONS)
    assert response.status_code == 200
    data = response.json()
    assert data["schema_version"] == "1" and data["trip_id"] == TRIP
    assert data["budget"] == {"scope": "per_person_per_visit", **OPTIONS,
                              "budget_min": "16.66", "budget_max": "100.00"}
    assert [row["location_id"] for row in data["items"]] == [VENUE, SECOND]
    assert data["items"][0]["location"] == state.locations[0]
    assert 0 <= data["items"][0]["recommendation_score"] <= 1
    assert "cafe" in data["items"][0]["recommendation_reason"]
    assert data["empty_reason"] is None and state.trip == before
    provider.assert_not_called()


@pytest.mark.parametrize("changes", [
    {"party_size": 0}, {"party_size": True}, {"planned_visits": 0}, {"planned_visits": 1.5},
    {"limit": 0}, {"limit": 101}, {"limit": True}, {"requires_step_free_access": "yes"},
    {"max_distance_km": 1}, {"max_distance_km": "NaN"}, {"max_distance_km": "Infinity"},
    {"origin": {"latitude": 100, "longitude": 0}}, {"max_visit_duration_minutes": 0},
    {"max_distance_km": True, "origin": {"latitude": 0, "longitude": 0}},
    {"origin": {"latitude": True, "longitude": 0}},
    {"setting": "mixed"}, {"user_id": OTHER}, {"preferred_tags": ["food"]},
    {"budget_max": 999}, {"unknown": "sensitive-client-value"},
])
def test_invalid_options_are_sanitized_without_data_access(harness, changes):
    api, state = harness
    response = api.post(URL, json={**OPTIONS, **changes})
    assert response.status_code == 422
    assert all(set(error) == {"loc", "msg", "type"} for error in response.json()["detail"])
    assert "sensitive-client-value" not in response.text
    assert state.requests == []


@pytest.mark.parametrize("body", [{}, [], None, "invalid"])
def test_counts_are_required(harness, body):
    api, state = harness
    assert api.post(URL, json=body).status_code == 422
    assert state.requests == []


@pytest.mark.parametrize("changes", [
    {"requires_step_free_access": True}, {"setting": "indoor"},
    {"max_visit_duration_minutes": 1},
    {"origin": {"latitude": 0, "longitude": 0}, "max_distance_km": 1},
    {"excluded_location_ids": [VENUE, SECOND]},
])
def test_restrictive_filters_return_successful_empty_result(harness, changes):
    api, _ = harness
    response = api.post(URL, json={**OPTIONS, **changes})
    assert response.status_code == 200
    assert response.json()["items"] == []
    assert response.json()["empty_reason"] == "no_compatible_locations"


def test_unknown_budget_group_and_coordinates_fail_closed(harness):
    api, state = harness
    state.locations = [location(estimated_cost_max=None), location(SECOND, suitable_group_types=["solo"])]
    assert api.post(URL, json=OPTIONS).json()["items"] == []
    state.locations = [location(latitude=None)]
    assert api.post(URL, json={**OPTIONS, "origin": {"latitude": 10.67, "longitude": 122.95},
                               "max_distance_km": 2}).json()["items"] == []


def test_budget_is_allocated_and_distance_is_straight_line(harness):
    api, state = harness
    state.locations[1]["estimated_cost_max"] = 101
    response = api.post(URL, json={**OPTIONS, "origin": {"latitude": 10.67, "longitude": 122.95},
                                   "max_distance_km": 0.01})
    assert [row["location_id"] for row in response.json()["items"]] == [VENUE]


@pytest.mark.parametrize("field,value", [("group_type", None), ("group_type", "unsupported"),
                                         ("preferred_tags", ["coffee"])])
def test_unsupported_saved_preferences_are_recoverable(harness, field, value):
    api, state = harness
    state.trip[field] = value
    assert api.post(URL, json=OPTIONS).status_code == 422


def test_unknown_category_is_rejected(harness):
    api, _ = harness
    assert api.post(URL, json={**OPTIONS, "preferred_categories": ["invented"]}).status_code == 422


def event(user=OWNER, **changes):
    return {"id": str(uuid4()), "user_id": user, "location_id": VENUE,
            "interaction_type": "left_swipe", "interaction_value": -1, "rating_value": None,
            "created_at": "2026-10-28T00:00:00Z", **changes}


def test_only_owner_events_feed_model_and_any_left_swipe_excludes(harness):
    api, state = harness
    state.events = [event(), event(interaction_type="save", interaction_value=1), event(OTHER)]
    captured = []

    def engine(request):
        captured.append(request)
        return {"items": [recommendation(), recommendation(SECOND, recommendation_score=0.8)]}

    state.engine = engine
    response = api.post(URL, json=OPTIONS)
    assert response.status_code == 200
    assert [row["location_id"] for row in response.json()["items"]] == [SECOND]
    assert len(captured[0].interactions) == 2
    assert all(row.user_id == UUID(OWNER) and row.provenance == "real" for row in captured[0].interactions)


def test_duplicate_unknown_inactive_rejected_and_incompatible_model_ids_are_removed(harness):
    api, state = harness
    inactive, costly = str(uuid4()), str(uuid4())
    state.locations += [location(inactive, is_active=False), location(costly, estimated_cost_max=1000)]
    state.events = [event(location_id=SECOND)]
    state.engine = lambda request: {"items": [recommendation(identifier) for identifier in
                                              (VENUE, VENUE, str(uuid4()), inactive, costly, SECOND)]}
    result = api.post(URL, json=OPTIONS)
    assert result.status_code == 200
    assert [row["location_id"] for row in result.json()["items"]] == [VENUE]


@pytest.mark.parametrize("raw", [
    None, [], {}, {"items": "bad"}, {"items": [recommendation("not-a-uuid")]},
    *({"items": [recommendation(recommendation_score=score)]}
      for score in (-0.1, 1.1, float("nan"), float("inf"), float("-inf"), True, "0.9")),
    {"items": [recommendation(recommendation_reason=" ")]},
    {"items": [recommendation(extra="untrusted")]},
    {"items": [recommendation(recommendation_score=0.1), recommendation(SECOND)]},
    {"schema_version": "2", "items": []},
])
def test_malformed_model_output_fails_safely_without_writes(harness, raw):
    api, state = harness
    before = deepcopy(state.trip)
    state.engine = lambda request: raw
    result = api.post(URL, json=OPTIONS)
    assert result.status_code == 503
    assert result.json() == {"detail": "Recommendations are temporarily unavailable. Please try again later."}
    assert state.trip == before


def test_mutated_model_instance_is_revalidated(harness):
    api, state = harness
    raw = RecommendationResponse.model_validate({"items": [recommendation()]})
    raw.items[0].recommendation_score = float("nan")
    state.engine = lambda request: raw
    assert api.post(URL, json=OPTIONS).status_code == 503


def test_model_cannot_mutate_trusted_preferences(harness):
    api, state = harness

    def engine(request):
        request.preferences.budget_max = 100000
        return {"items": [recommendation()]}

    state.locations[0]["estimated_cost_max"] = 1000
    state.engine = engine
    assert api.post(URL, json=OPTIONS).json()["items"] == []


def test_limit_is_applied_and_excess_model_output_rejected(harness):
    api, state = harness
    assert len(api.post(URL, json={**OPTIONS, "limit": 1}).json()["items"]) == 1
    state.engine = lambda request: {"items": [recommendation(), recommendation(SECOND)]}
    assert api.post(URL, json={**OPTIONS, "limit": 1}).status_code == 503


@pytest.mark.parametrize("failure", [ValueError, RuntimeError, OSError])
def test_model_exception_is_sanitized(harness, failure):
    api, state = harness

    def engine(request):
        raise failure("private-model-diagnostics")

    state.engine = engine
    result = api.post(URL, json=OPTIONS)
    assert result.status_code == 503 and "private-model" not in result.text


@pytest.mark.parametrize("change", ["inactive", "edited", "deleted", "left_swiped"])
def test_live_database_state_is_rechecked_after_model(harness, change):
    api, state = harness

    def engine(request):
        if change == "inactive":
            state.locations[0]["is_active"] = False
        elif change == "edited":
            state.locations[0]["name"] = "New name"
        elif change == "deleted":
            state.locations = state.locations[1:]
        else:
            state.events.append(event())
        return {"items": [recommendation()]}

    state.engine = engine
    assert api.post(URL, json=OPTIONS).json()["items"] == []


@pytest.mark.parametrize("change,status", [("missing", 404), ("other", 404), ("edited", 409)])
def test_trip_is_rechecked_after_model(harness, change, status):
    api, state = harness

    def engine(request):
        if change == "missing":
            state.trip = None
        elif change == "other":
            state.trip["user_id"] = OTHER
        else:
            state.trip["preferred_tags"] = ["food"]
        return {"items": [recommendation()]}

    state.engine = engine
    assert api.post(URL, json=OPTIONS).status_code == status


@pytest.mark.parametrize("owner", [OTHER, None])
def test_missing_and_other_owner_trip_return_same_404(harness, owner):
    api, state = harness
    if owner is None:
        state.trip = None
    else:
        state.trip["user_id"] = owner
    assert api.post(URL, json=OPTIONS).json() == {"detail": "Trip not found."}
    assert len(state.requests) == 1


def test_authentication_and_disabled_demo(harness, monkeypatch):
    api, state = harness
    assert api.post(URL, json=OPTIONS, headers={"Authorization": ""}).status_code == 401
    assert state.requests == []
    monkeypatch.delenv("TRIP_DEMO_USER_ID")
    assert api.post(URL, json=OPTIONS).status_code == 503
    assert state.requests == []


@pytest.mark.parametrize("path", ["/trips", "/locations", "/user_location_interactions"])
@pytest.mark.parametrize("kind", ["error", "malformed", "timeout"])
def test_database_failures_are_sanitized(harness, path, kind):
    api, state = harness

    def override(request):
        if request.url.path == path:
            if kind == "timeout":
                raise httpx.ReadTimeout("private-database-diagnostics")
            return httpx.Response(500 if kind == "error" else 200, json={"private": "diagnostics"})

    state.override = override
    result = api.post(URL, json=OPTIONS)
    assert result.status_code == 503 and "diagnostics" not in result.text


def test_complete_candidate_pagination_and_duplicate_page_refusal(harness):
    api, state = harness
    state.locations = [location(str(uuid4())) for _ in range(101)]
    result = api.post(URL, json={**OPTIONS, "limit": 100})
    assert result.status_code == 200 and len(result.json()["items"]) == 100
    assert any(request.url.params.get("offset") == "100" for request in state.requests)
    state.locations[100]["id"] = state.locations[0]["id"]
    assert api.post(URL, json=OPTIONS).status_code == 503


def test_empty_catalog(harness):
    api, state = harness
    state.locations = []
    assert api.post(URL, json=OPTIONS).json()["items"] == []


def write_model(path, **changes):
    from app.recommendations.collaborative import CollaborativeModel

    # A controlled real-provenance model exercises supported-user/item blending.
    model = CollaborativeModel(
        provenance="real", training_digest="a" * 64, training_event_ids=[uuid4()],
        user_ids=[UUID(OWNER), uuid4(), uuid4()], item_ids=[UUID(VENUE), UUID(SECOND), uuid4()],
        user_counts=[3, 3, 3], item_counts=[3, 3, 3],
        user_factors=[[1.0], [0.5], [0.2]], item_factors=[[0.8], [0.4], [0.1]],
        rank=1, numpy_version="2.0.0", **changes,
    )
    model.save(path)
    return hashlib.sha256(path.read_bytes()).hexdigest()


@pytest.fixture
def serve(harness, monkeypatch, caplog):
    """Switch the harness from its stub engine to the real startup loader."""
    api, state = harness
    state.application.dependency_overrides.pop(get_recommendation_engine)

    def start(path, digest=None):
        monkeypatch.setenv("MODEL_FILE_PATH", str(path))
        if digest is None:
            monkeypatch.delenv("MODEL_FILE_SHA256", raising=False)
        else:
            monkeypatch.setenv("MODEL_FILE_SHA256", digest)
        get_recommendation_engine.cache_clear()
        caplog.clear()
        # Entering the app runs its lifespan: the model loads before any request.
        with (
            caplog.at_level(logging.INFO, logger="uvicorn.error"),
            TestClient(state.application, headers=api.headers) as started,
        ):
            loaded = [r.getMessage() for r in caplog.records if "recommendation_model" in r.getMessage()]
            result = started.post(URL, json=OPTIONS)
        return result, loaded

    get_recommendation_engine.cache_clear()
    yield start, state
    get_recommendation_engine.cache_clear()


def test_model_loads_at_startup_and_logs_one_safe_line(serve, tmp_path):
    start, _ = serve
    path = tmp_path / "real-model.json"
    digest = write_model(path)
    result, lines = start(path, digest)
    assert result.status_code == 200
    assert all("Hybrid: content=" in row["recommendation_reason"] for row in result.json()["items"])
    assert get_recommendation_engine().model is not None
    assert lines == [(
        "recommendation_model status=present reason=loaded version=signed-svd-v1 provenance=real "
        f"training_digest={'a' * 64} users=3 items=3 pairs=9 file_sha256={digest}"
    )]
    assert not any(value in lines[0] for value in (OWNER, VENUE, SECOND, TRIP))


def test_startup_loads_before_first_request_and_requests_do_not_reload(serve, tmp_path, monkeypatch):
    _, state = serve
    path = tmp_path / "real-model.json"
    write_model(path)
    reads = []
    original = Path.open
    monkeypatch.setattr(Path, "open", lambda self, *a, **k: (reads.append(self), original(self, *a, **k))[1])
    monkeypatch.setenv("MODEL_FILE_PATH", str(path))
    get_recommendation_engine.cache_clear()
    with TestClient(state.application) as api:
        assert reads == [path]  # Loaded by startup alone: no request has been made.
        for _ in range(3):
            assert api.post(URL, json=OPTIONS, headers={"Authorization": f"Bearer {TOKEN}"}).status_code == 200
    assert reads == [path]


def test_matching_pin_is_case_insensitive(serve, tmp_path):
    start, _ = serve
    path = tmp_path / "real-model.json"
    digest = write_model(path)
    result, lines = start(path, f"  {digest.upper()} ")
    assert result.status_code == 200 and "status=present" in lines[0]


@pytest.mark.parametrize("case, reason", [
    ("missing", "missing"), ("corrupt", "corrupt"), ("empty", "corrupt"), ("wrong_version", "wrong_version"),
    ("array", "wrong_version"), ("invalid", "invalid_artifact"), ("synthetic", "provenance_mismatch"),
    ("digest", "digest_mismatch"), ("bad_pin", "invalid_expected_digest"), ("too_large", "too_large"),
    ("directory", "unreadable"),
])
def test_unusable_artifacts_serve_the_content_baseline_with_a_logged_reason(serve, tmp_path, case, reason):
    start, _ = serve
    path = tmp_path / "artifact.json"
    digest = None
    if case == "directory":
        path.mkdir()
    elif case == "synthetic":
        write_model(path)
        data = json.loads(path.read_text())
        data["provenance"] = "synthetic"
        path.write_text(json.dumps(data))
    elif case != "missing":
        digest = write_model(path)
        data = json.loads(path.read_text())
        if case == "corrupt":
            path.write_text("not-json")
        elif case == "empty":
            path.write_text("")
        elif case == "wrong_version":
            path.write_text(json.dumps({**data, "model_version": "signed-svd-v0"}))
        elif case == "array":
            path.write_text("[]")
        elif case == "invalid":
            data["user_factors"][0][0] = "nan"
            path.write_text(json.dumps(data))
        elif case == "too_large":
            path.write_text(" " * (MAX_ARTIFACT_BYTES + 1))
        elif case == "digest":
            digest = "0" * 64
        elif case == "bad_pin":
            digest = "not-a-digest"
    if case in {"corrupt", "empty", "wrong_version", "array", "invalid", "too_large"}:
        digest = hashlib.sha256(path.read_bytes()).hexdigest()  # Correctly pinned, still unusable.
    baseline, _ = start(tmp_path / "nothing-mounted.json")
    result, lines = start(path, digest)
    assert result.status_code == 200
    assert get_recommendation_engine().model is None
    assert result.json() == baseline.json()
    assert not any("Hybrid:" in row["recommendation_reason"] for row in result.json()["items"])
    assert len(lines) == 1 and f"status=absent reason={reason} " in lines[0]
    assert "version=none provenance=none training_digest=none users=0 items=0 pairs=0" in lines[0]


def test_unconfigured_path_is_content_only_and_logged_as_such(serve, monkeypatch, caplog):
    monkeypatch.delenv("MODEL_FILE_PATH", raising=False)
    get_recommendation_engine.cache_clear()
    with caplog.at_level(logging.INFO, logger="uvicorn.error"):
        assert get_recommendation_engine().model is None
    assert [r.getMessage() for r in caplog.records if "recommendation_model" in r.getMessage()] == [(
        "recommendation_model status=absent reason=not_configured version=none provenance=none "
        "training_digest=none users=0 items=0 pairs=0 file_sha256=none"
    )]


def test_known_hybrid_artifact_scores_reach_api_after_validation(serve, tmp_path):
    start, _ = serve
    path = tmp_path / "real-model.json"
    write_model(path)
    baseline, _ = start(tmp_path / "nothing-mounted.json")
    result, _ = start(path)
    assert result.status_code == 200
    assert all("Hybrid: content=" in row["recommendation_reason"] for row in result.json()["items"])
    assert [row["recommendation_score"] for row in result.json()["items"]] != [
        row["recommendation_score"] for row in baseline.json()["items"]]


def test_catalog_guard_rejects_oversized_snapshot(harness, monkeypatch):
    api, _ = harness
    monkeypatch.setattr("app.recommendation_adapter.MAX_CANDIDATES", 1)
    assert api.post(URL, json=OPTIONS).status_code == 503


def test_current_lookup_rejects_unrequested_database_rows(harness):
    _, state = harness
    state.override = lambda request: httpx.Response(200, json=state.locations) if "id" in request.url.params else None
    from app.database import DatabaseUnavailable
    with pytest.raises(DatabaseUnavailable):
        RecommendationAdapter(state.rest).current_locations({UUID(VENUE)})
