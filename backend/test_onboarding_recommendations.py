"""Cold-start HTTP integration with real content ranking and mocked Data API."""

from copy import deepcopy
from types import SimpleNamespace
from unittest.mock import patch
from uuid import UUID

import httpx
import pytest
from fastapi.testclient import TestClient

from app.auth import unauthorized

OWNER = UUID("a1030000-0000-4000-8000-000000000001")
OTHER = UUID("a1030000-0000-4000-8000-000000000002")
BASE = "/api/v1/me/recommendations"
OPTIONS = {"group_type": "solo", "per_person_visit_budget_max": "300", "limit": 10}
HTTP_CLIENT = httpx.Client


def location(index, tags, cost=100, groups=None):
    return {
        "id": f"b1030000-0000-4000-8000-{index:012d}", "name": f"Place {index}",
        "description": None, "category": "cafe", "vibe_tags": tags, "address": None,
        "latitude": None, "longitude": None, "opening_hours": {},
        "estimated_cost_min": cost, "estimated_cost_max": cost,
        "typical_visit_duration": 30, "suitable_group_types": groups or ["solo"],
        "image_url": None, "is_active": True,
    }


@pytest.fixture
def api(monkeypatch):
    with patch.dict("os.environ", {
        "SUPABASE_URL": "http://127.0.0.1:54321",
        "SUPABASE_SERVICE_ROLE_KEY": "sb_secret_offline_only",
    }, clear=True), patch("dotenv.load_dotenv"):
        from app.main import create_app

        monkeypatch.setattr("app.main.load_dotenv", lambda *a, **kw: None)
        monkeypatch.setattr("app.database.load_dotenv", lambda *a, **kw: None)
        # Fail the test if cold-start ranking tries to load an artifact or call the LLM.
        def forbidden(*args, **kwargs):
            pytest.fail("Cold-start route must not call provider or artifact loader")

        monkeypatch.setattr("app.trip_recommendations.load_artifact", forbidden)
        monkeypatch.setattr("app.deepseek.extract_preferences", forbidden)

        def authenticate(token):
            if token == "owner-a":
                return OWNER
            if token == "owner-b":
                return OTHER
            raise unauthorized()

        monkeypatch.setattr("app.trips.authenticate", authenticate)
        monkeypatch.setattr("app.recommendation_adapter.PAGE_SIZE", 2)
        state = SimpleNamespace(
            profiles={str(OWNER): ["cafe"], str(OTHER): ["nature"]},
            locations=[location(1, ["cafe"]), location(2, ["nature"]),
                       location(3, ["cafe"], 500), location(4, ["cafe"], None),
                       location(5, ["cafe"], groups=["family"])],
            requests=[], override=None,
        )

        def handle(request):
            state.requests.append(request)
            assert request.method == "GET"  # No writes, trip or interaction queries.
            if state.override:
                result = state.override(request)
                if result is not None:
                    return result
            if request.url.path == "/rest/v1/users":
                owner = request.url.params["id"].removeprefix("eq.")
                return httpx.Response(200, json=[{
                    "id": owner, "preferred_tags": state.profiles[owner],
                    "default_budget_min": None, "default_budget_max": None,
                    "traveler_type": None,
                }] if owner in state.profiles else [])
            assert request.url.path == "/rest/v1/locations"
            assert request.url.params["is_active"] == "eq.true"
            rows = [row for row in state.locations if row["is_active"]]
            if "id" in request.url.params:
                ids = request.url.params["id"]
                rows = [row for row in rows if row["id"] in ids]
            else:
                offset = int(request.url.params["offset"])
                rows = rows[offset:offset + int(request.url.params["limit"])]
            return httpx.Response(200, json=rows)

        monkeypatch.setattr("app.database.httpx.Client", lambda **kw: HTTP_CLIENT(
            transport=httpx.MockTransport(handle), **kw,
        ))
        with TestClient(create_app()) as client:
            yield client, state


def recommend(client, options=None, owner="a"):
    return client.post(BASE, json=OPTIONS if options is None else options,
                       headers={"Authorization": f"Bearer owner-{owner}"})


def test_saved_tags_personalize_without_trip_history_or_artifact(api):
    client, state = api
    a, b = recommend(client), recommend(client, owner="b")
    assert a.status_code == b.status_code == 200
    assert a.json()["items"][0]["location"]["name"] == "Place 1"
    assert b.json()["items"][0]["location"]["name"] == "Place 2"
    assert len(a.json()["items"]) == 2  # Unknown/expensive/group mismatch excluded.
    assert a.json()["mode"] == "content_only"
    assert a.json()["budget_scope"] == "per_person_per_visit"
    assert "Tags: cafe" in a.json()["items"][0]["recommendation_reason"]
    assert all(r.method == "GET" for r in state.requests)
    assert {r.url.params["id"] for r in state.requests if r.url.path.endswith("users")} == {
        f"eq.{OWNER}", f"eq.{OTHER}",
    }


def test_deterministic_order_and_limit(api):
    client, state = api
    state.locations = [location(2, ["cafe"]), location(1, ["cafe"])]
    first = recommend(client).json()
    state.locations.reverse()
    assert recommend(client).json() == first
    assert first["items"][0]["location"]["name"] == "Place 1"
    assert len(recommend(client, {**OPTIONS, "limit": 1}).json()["items"]) == 1


def test_empty_tags_fall_back_to_budget_headroom(api):
    client, state = api
    state.profiles[str(OWNER)] = []
    state.locations = [location(1, ["cafe"], 200), location(2, ["nature"], 50)]
    result = recommend(client).json()
    assert result["items"][0]["location"]["name"] == "Place 2"
    assert "not specified" in result["items"][0]["recommendation_reason"]


@pytest.mark.parametrize("rows", [[], [location(1, ["cafe"], None)],
                                     [location(1, ["cafe"], 500)]])
def test_empty_or_ineligible_catalog(api, rows):
    client, state = api
    state.locations = rows
    response = recommend(client)
    assert response.status_code == 200
    assert response.json()["items"] == []
    assert response.json()["empty_reason"] == "no_compatible_locations"


def test_zero_budget_allows_only_confirmed_free_places(api):
    client, state = api
    state.locations = [location(1, ["cafe"], 0), location(2, ["cafe"], 1)]
    response = recommend(client, {**OPTIONS, "per_person_visit_budget_max": "0"})
    assert response.status_code == 200
    assert len(response.json()["items"]) == 1


@pytest.mark.parametrize("changes", [
    {"group_type": "students"}, {"per_person_visit_budget_max": "-1"},
    {"per_person_visit_budget_max": "NaN"}, {"per_person_visit_budget_max": "1.001"},
    {"limit": True}, {"limit": 0}, {"limit": 101}, {"user_id": "private-submitted-value"},
    {"preferred_tags": ["cafe"]},
])
def test_invalid_inputs_are_sanitized(api, changes):
    client, state = api
    response = recommend(client, {**OPTIONS, **changes})
    assert response.status_code == 422
    assert "private-submitted-value" not in response.text
    assert all("input" not in error for error in response.json()["detail"])
    assert state.requests == []


def test_required_constraints_and_auth(api):
    client, state = api
    assert recommend(client, {}).status_code == 422
    assert client.post(BASE, json=OPTIONS).status_code == 401
    assert recommend(client, owner="invalid").status_code == 401
    assert not state.requests


def test_missing_profile_and_database_failure(api):
    client, state = api
    del state.profiles[str(OWNER)]
    assert recommend(client).status_code == 404
    state.override = lambda request: httpx.Response(500, text="private database details")
    response = recommend(client)
    assert response.status_code == 503
    assert "private database details" not in response.text


def test_catalog_changed_during_inference_drops_stale_result(api):
    client, state = api

    def changed(request):
        if request.url.path.endswith("locations") and "id" in request.url.params:
            rows = deepcopy(state.locations[:2])
            for row in rows:
                row["estimated_cost_max"] = 999
            return httpx.Response(200, json=rows)
        return None

    state.override = changed
    assert recommend(client).json()["items"] == []


def test_profile_change_during_inference_requires_reload(api):
    client, state = api

    def changed(request):
        if request.url.path.endswith("locations"):
            state.profiles[str(OWNER)] = ["nature"]

    state.override = changed
    assert recommend(client).status_code == 409


def test_engine_failure_is_sanitized(api, monkeypatch):
    client, _ = api

    def fail(*args):
        raise RuntimeError("private engine details")

    monkeypatch.setattr("app.onboarding_recommendations.ContentBasedRecommender.recommend", fail)
    response = recommend(client)
    assert response.status_code == 503
    assert "private engine details" not in response.text


def test_invalid_engine_output_is_rejected(api, monkeypatch):
    from app.recommendations.contracts import Recommendation, RecommendationResponse

    client, _ = api
    monkeypatch.setattr(
        "app.onboarding_recommendations.ContentBasedRecommender.recommend",
        lambda *args: RecommendationResponse(items=[Recommendation(
            location_id=OTHER, recommendation_score=1, recommendation_reason="Invalid venue",
        )]),
    )
    assert recommend(client).status_code == 503


def test_pagination_duplicate_is_rejected(api):
    client, state = api
    state.locations = [location(1, ["cafe"])] * 2
    assert recommend(client).status_code == 503


def test_openapi_contract_is_available(api):
    client, _ = api
    schema = client.get("/openapi.json").json()
    route = schema["paths"][BASE]["post"]
    assert route["security"] == [{"SupabaseAccessToken": []}]
    fields = schema["components"]["schemas"]["OnboardingRecommendationOptions"]
    assert set(fields["required"]) == {"group_type", "per_person_visit_budget_max"}
    assert fields["additionalProperties"] is False
