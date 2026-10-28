"""Offline Auth boundary: signed synthetic JWTs, fake Auth server and Data API.

No real key, account, dotenv contents or hosted data is required. The fake Auth
server cryptographically verifies tokens instead of accepting arbitrary strings.
"""

import json
import os
import time
from copy import deepcopy
from types import SimpleNamespace
from unittest.mock import patch
from uuid import UUID, uuid4

import httpx
import jwt
import pytest
from fastapi.testclient import TestClient

from app.auth import DEVELOPMENT_URL, profile_owner

AUTH_URL = "https://auth-test.invalid"
SIGNING_KEY = "synthetic-test-signing-key-never-used-outside-tests-000000"
SUBJECT = "79000000-0000-4000-8000-000000000001"
OTHER = "79000000-0000-4000-8000-000000000002"
LOCATION = "79000000-0000-4000-8000-000000000003"
TRIP = "79000000-0000-4000-8000-000000000004"
EVENT = "79000000-0000-4000-8000-000000000005"
PAYLOAD = {"title": "Synthetic Auth trip", "start_date": "2026-11-01",
           "end_date": "2026-11-01", "budget_min": "0", "budget_max": "500",
           "preferred_tags": []}
HTTP_CLIENT = httpx.Client


def token(subject=SUBJECT, key=SIGNING_KEY, **changes):
    return jwt.encode({"sub": subject, "iss": f"{AUTH_URL}/auth/v1", "aud": "authenticated",
                       "role": "authenticated", "iat": int(time.time()) - 1,
                       "exp": int(time.time()) + 300, **changes}, key, algorithm="HS256")


@pytest.fixture
def api(monkeypatch):
    with patch.dict(os.environ, {"SUPABASE_URL": AUTH_URL,
                                "SUPABASE_SERVICE_ROLE_KEY": "sb_secret_offline_only",
                                "CORS_ALLOWED_ORIGINS": "http://localhost:3000"}, clear=True):
        with patch("dotenv.load_dotenv"):
            from app.main import create_app
        monkeypatch.setattr("app.main.load_dotenv", lambda *a, **k: None)
        monkeypatch.setattr("app.database.load_dotenv", lambda *a, **k: None)
        state = SimpleNamespace(requests=[], profiles=[], trips=[], events=[], auth_status=200,
                                auth_override=None, db_override=None, race=False)

        def handle(request):
            state.requests.append(request)
            if request.url.path == "/auth/v1/user":
                assert request.headers["apikey"] == "sb_secret_offline_only"
                assert request.headers["authorization"].startswith("Bearer ")
                if state.auth_status != 200:
                    return httpx.Response(state.auth_status, text="private provider body")
                try:
                    claims = jwt.decode(request.headers["authorization"][7:], SIGNING_KEY,
                                        algorithms=["HS256"], audience="authenticated")
                except jwt.PyJWTError:
                    return httpx.Response(401, json={"message": "invalid signature or expiry"})
                user = {"id": claims["sub"], "email": f"{claims['sub']}@example.invalid",
                        "aud": "authenticated", "role": "authenticated", "is_anonymous": False,
                        "email_confirmed_at": "2026-10-29T00:00:00Z"}
                return httpx.Response(200, json=state.auth_override if state.auth_override is not None else user)
            if state.db_override:
                reply = state.db_override(request)
                if reply is not None:
                    return reply
            table = request.url.path.removeprefix("/rest/v1/")
            params = request.url.params
            if table == "users":
                if request.method == "GET":
                    rows = [p for p in state.profiles
                            if f"eq.{p.get('auth_user_id')}" == params["auth_user_id"]]
                    return httpx.Response(200, json=rows)
                assert request.method == "POST"
                body = json.loads(request.content)
                assert set(body) == {"auth_user_id", "email", "name"}
                assert params["on_conflict"] == "auth_user_id"
                assert "resolution=ignore-duplicates" in request.headers["prefer"]
                if not any(p.get("auth_user_id") == body["auth_user_id"] for p in state.profiles):
                    if any(p["email"] == body["email"] for p in state.profiles):
                        return httpx.Response(409, json={"code": "23505"})
                    state.profiles.append({**body, "id": str(uuid4()), "preferred_tags": ["cafe"]})
                return httpx.Response(201)
            if table == "trips":
                if request.method == "POST":
                    body = json.loads(request.content)
                    row = {**body, "id": str(uuid4()), "status": "draft", "estimated_total_cost": None}
                    state.trips.append(row)
                    return httpx.Response(201, json=[row])
                assert "user_id" in params
                rows = [r for r in state.trips if f"eq.{r['user_id']}" == params["user_id"]
                        and ("id" not in params or f"eq.{r['id']}" == params["id"])]
                if request.method == "PATCH":
                    for row in rows:
                        row.update(json.loads(request.content))
                if request.method == "DELETE":
                    state.trips = [r for r in state.trips if r not in rows]
                    rows = [{"id": r["id"], "user_id": r["user_id"]} for r in rows]
                return httpx.Response(200, json=rows)
            if table == "user_location_interactions":
                assert request.method == "GET" and "user_id" in params
                return httpx.Response(200, json=[r for r in state.events
                    if f"eq.{r['user_id']}" == params["user_id"]
                    and ("id" not in params or f"eq.{r['id']}" == params["id"])])
            raise AssertionError("Unexpected outbound operation")

        monkeypatch.setattr("httpx.Client", lambda **kw: HTTP_CLIENT(
            transport=httpx.MockTransport(handle), **kw))
        with TestClient(create_app(), headers={"Authorization": f"Bearer {token()}"}) as client:
            yield client, state


def test_verified_subject_maps_idempotently_without_overwriting_profile(api):
    client, state = api
    for _ in range(2):
        assert client.get("/api/v1/trips").status_code == 200
    assert len(state.profiles) == 1
    profile = state.profiles[0]
    assert profile["auth_user_id"] == SUBJECT and profile["id"] != SUBJECT
    assert profile["preferred_tags"] == ["cafe"]
    assert sum(r.url.path == "/auth/v1/user" for r in state.requests) == 2
    assert sum(r.method == "POST" and r.url.path.endswith("/users") for r in state.requests) == 1


@pytest.mark.parametrize("change", [
    {"exp": 1}, {"exp": None}, {"iss": "https://another-project.invalid/auth/v1"},
    {"aud": "anon"}, {"role": "service_role"}, {"sub": "not-a-uuid"},
    {"sub": str(UUID(int=0))}, {"nbf": 9999999999}, {"iat": 9999999999},
    {"iat": None}, {"aud": None}, {"iss": ""}, {"sub": None},
    {"exp": float("inf")}, {"iat": float("inf")},
])
def test_invalid_claims_never_reach_auth_or_database(api, change):
    client, state = api
    result = client.get("/api/v1/trips", headers={"Authorization": f"Bearer {token(**change)}"})
    assert result.status_code == 401
    assert result.headers["www-authenticate"] == "Bearer"
    assert state.requests == []


@pytest.mark.parametrize("authorization", ["", "Basic abc", "Bearer malformed",
    "Bearer " + token(key="wrong-synthetic-key-of-at-least-32-bytes"),
    "Bearer " + jwt.encode({"sub": SUBJECT}, "", algorithm="none"),
    "Bearer " + token(exp=1)])
@pytest.mark.parametrize("method,path", [
    ("GET", "/api/v1/trips"), ("POST", "/api/v1/trips"),
    ("GET", f"/api/v1/trips/{TRIP}"), ("PATCH", f"/api/v1/trips/{TRIP}"),
    ("DELETE", f"/api/v1/trips/{TRIP}"), ("GET", f"/api/v1/trips/{TRIP}/items"),
    ("POST", f"/api/v1/trips/{TRIP}/items"),
    ("DELETE", f"/api/v1/trips/{TRIP}/items/{EVENT}"),
    ("POST", f"/api/v1/trips/{TRIP}/recommendations"),
    ("POST", f"/api/v1/trips/{TRIP}/generate-itinerary"),
    ("GET", "/api/v1/interactions"), ("POST", "/api/v1/interactions"),
    ("GET", f"/api/v1/interactions/{EVENT}"),
    ("GET", "/api/v1/interactions/recommendation-input"),
    ("POST", "/api/v1/preferences/extract"),
])
def test_protected_routes_reject_invalid_sessions_without_data_access(api, authorization, method, path):
    client, state = api
    result = client.request(method, path, headers={"Authorization": authorization}, json={})
    assert result.status_code == 401
    assert not state.profiles and not state.trips
    assert all(r.url.path == "/auth/v1/user" for r in state.requests)


@pytest.mark.parametrize("status,expected", [(400, 401), (401, 401), (403, 401), (404, 401),
                                           (422, 401), (429, 503), (500, 503), (302, 503)])
def test_auth_provider_failures_are_closed_and_redacted(api, status, expected):
    client, state = api
    state.auth_status = status
    result = client.get("/api/v1/trips")
    assert result.status_code == expected
    assert "private" not in result.text and "sb_secret" not in result.text
    assert not state.profiles
    assert len(state.requests) == 1


@pytest.mark.parametrize("error", [httpx.ConnectError, httpx.ReadTimeout])
def test_auth_network_failure_never_opens_profile_or_trip_access(api, monkeypatch, error):
    client, state = api
    def fail(*args, **kwargs):
        raise error("private provider body")
    monkeypatch.setattr(HTTP_CLIENT, "get", fail)
    result = client.get("/api/v1/trips")
    assert result.status_code == 503 and "private" not in result.text
    assert not state.profiles and not state.trips


@pytest.mark.parametrize("key,value", [("SUPABASE_URL", "https://user:password@unsafe.invalid"),
    ("SUPABASE_URL", "https://unsafe.invalid/path"), ("SUPABASE_SERVICE_ROLE_KEY", ""),
    ("TRIP_AUTH_MODE", "typo")])
def test_bad_auth_configuration_fails_closed(api, monkeypatch, key, value):
    client, state = api
    monkeypatch.setenv(key, value)
    assert client.get("/api/v1/trips").status_code == 503
    assert not state.requests


@pytest.mark.parametrize("field", ["sub", "iss", "aud", "exp", "iat", "role"])
def test_required_claims_cannot_be_omitted(api, field):
    client, state = api
    claims = jwt.decode(token(), options={"verify_signature": False})
    del claims[field]
    invalid = jwt.encode(claims, SIGNING_KEY, algorithm="HS256")
    assert client.get("/api/v1/trips", headers={"Authorization": f"Bearer {invalid}"}).status_code == 401
    assert not state.requests


@pytest.mark.parametrize("user", [[], {}, {"id": SUBJECT}])
def test_malformed_auth_success_does_not_authorize(api, user):
    client, state = api
    state.auth_override = user
    assert client.get("/api/v1/trips").status_code == 401
    assert not state.profiles


def test_profile_outage_never_exposes_provider_details_or_trips(api):
    client, state = api
    state.db_override = lambda r: httpx.Response(500, text="private database credentials")
    result = client.get("/api/v1/trips")
    assert result.status_code == 503 and "private" not in result.text
    assert not state.profiles and not state.trips


@pytest.mark.parametrize("changes,expected", [
    ({"id": OTHER}, 401), ({"email_confirmed_at": None}, 403),
    ({"aud": "anon"}, 401), ({"role": "service_role"}, 401),
    ({"is_anonymous": True}, 401), ({"email": None}, 401),
])
def test_verified_user_must_match_subject_and_confirm_email(api, changes, expected):
    client, state = api
    state.auth_override = {"id": SUBJECT, "email": "test@example.invalid", "aud": "authenticated",
                           "role": "authenticated", "is_anonymous": False,
                           "email_confirmed_at": "2026-10-29T00:00:00Z", **changes}
    result = client.get("/api/v1/trips")
    assert result.status_code == expected and not state.profiles


def test_two_users_cannot_read_mutate_or_delete_each_others_trips_or_events(api):
    client, state = api
    trip = client.post("/api/v1/trips", json=PAYLOAD).json()
    original = deepcopy(state.trips)
    owner = state.profiles[0]["id"]
    state.events.append({"id": EVENT, "user_id": owner, "location_id": LOCATION,
                         "interaction_type": "save", "interaction_value": "1", "rating_value": None,
                         "created_at": "2026-10-29T00:00:00Z"})
    client.headers["Authorization"] = f"Bearer {token(OTHER)}"
    assert client.get("/api/v1/trips").json()["items"] == []
    assert client.get("/api/v1/interactions").json()["items"] == []
    assert client.get("/api/v1/interactions/recommendation-input").json()["interactions"] == []
    assert client.get(f"/api/v1/interactions/{EVENT}").status_code == 404
    path = f"/api/v1/trips/{trip['id']}"
    for method, suffix, body in [("GET", "", None), ("PATCH", "", {"title": "stolen"}),
                                 ("DELETE", "", None), ("GET", "/items", None),
                                 ("POST", "/recommendations", {"party_size": 1, "planned_visits": 1})]:
        assert client.request(method, path + suffix, json=body).status_code == 404
    assert state.trips == original and len(state.profiles) == 2
    other_trip = client.post("/api/v1/trips", json=PAYLOAD).json()
    assert other_trip["user_id"] == state.profiles[1]["id"] != owner
    assert client.patch(f"/api/v1/trips/{other_trip['id']}", json={"title": "mine"}).status_code == 200
    assert client.delete(f"/api/v1/trips/{other_trip['id']}").status_code == 204


def test_matching_legacy_email_never_claims_or_changes_existing_data(api):
    client, state = api
    state.profiles.append({"id": OTHER, "auth_user_id": None, "name": "Legacy demo",
                           "email": f"{SUBJECT}@example.invalid", "preferred_tags": ["heritage"]})
    state.trips.append({**PAYLOAD, "id": TRIP, "user_id": OTHER})
    baseline = deepcopy((state.profiles, state.trips))
    result = client.get("/api/v1/trips")
    assert result.status_code == 409
    assert result.json()["detail"]["code"] == "profile_link_required"
    assert (state.profiles, state.trips) == baseline


def test_matching_legacy_profile_id_does_not_grant_ownership(api):
    client, state = api
    legacy = {"id": SUBJECT, "auth_user_id": None, "email": "demo@example.invalid", "name": "Demo"}
    state.profiles.append(deepcopy(legacy))
    state.trips.append({**PAYLOAD, "id": TRIP, "user_id": SUBJECT})
    assert client.get("/api/v1/trips").json()["items"] == []
    assert state.profiles[0] == legacy and state.profiles[1]["id"] != SUBJECT


def test_concurrent_profile_insert_is_idempotent_and_preserves_winning_profile(api):
    _client, state = api
    winner = {"id": OTHER, "auth_user_id": SUBJECT, "email": "winner@example.invalid", "name": "Existing"}

    def insert_before_post(request):
        if request.method == "POST" and request.url.path.endswith("/users"):
            state.profiles.append(deepcopy(winner))
    state.db_override = insert_before_post
    assert profile_owner(UUID(SUBJECT), f"{SUBJECT}@example.invalid") == UUID(OTHER)
    assert state.profiles == [winner]


@pytest.mark.parametrize("rows", [None, {}, [{"id": OTHER, "auth_user_id": OTHER}],
                                  [{"id": OTHER, "auth_user_id": SUBJECT}] * 2])
def test_malformed_or_wrong_identity_profile_response_is_not_authorized(api, rows):
    client, state = api
    state.db_override = lambda r: httpx.Response(200, json=rows)
    assert client.get("/api/v1/trips").status_code == 503


def test_client_owner_fields_are_rejected_and_owner_headers_are_ignored(api):
    client, state = api
    assert client.post("/api/v1/trips", json={**PAYLOAD, "user_id": OTHER}).status_code == 422
    result = client.post("/api/v1/trips", json=PAYLOAD, headers={"X-User-ID": OTHER})
    assert result.status_code == 201 and result.json()["user_id"] == state.profiles[0]["id"]


def test_demo_values_do_not_enable_demo_access_by_default(api, monkeypatch):
    client, state = api
    monkeypatch.setenv("TRIP_DEMO_TOKEN", "old-demo-token-0000000000000000000000000")
    monkeypatch.setenv("TRIP_DEMO_USER_ID", OTHER)
    assert client.get("/api/v1/trips", headers={"Authorization":
        "Bearer old-demo-token-0000000000000000000000000"}).status_code == 401
    assert not state.requests


@pytest.mark.parametrize("url,status", [(DEVELOPMENT_URL, 200),
    ("http://127.0.0.1:54321", 200), ("https://zjnuqqtbapbpudsjbpif.supabase.co", 503),
    ("https://another-project.invalid", 503)])
def test_explicit_demo_mode_is_limited_to_nonproduction(api, monkeypatch, url, status):
    client, state = api
    monkeypatch.setenv("SUPABASE_URL", url)
    monkeypatch.setenv("TRIP_AUTH_MODE", "demo")
    monkeypatch.setenv("TRIP_DEMO_TOKEN", "demo-synthetic-00000000000000000000000000")
    monkeypatch.setenv("TRIP_DEMO_USER_ID", OTHER)
    result = client.get("/api/v1/trips", headers={"Authorization":
        "Bearer demo-synthetic-00000000000000000000000000"})
    assert result.status_code == status
    assert not state.profiles
    assert all(r.url.path != "/auth/v1/user" for r in state.requests)


def test_public_locations_keep_existing_unauthenticated_contract(api):
    client, state = api
    state.db_override = lambda r: httpx.Response(200, json=[]) if r.url.path.endswith("/locations") else None
    assert client.get("/locations", headers={"Authorization": ""}).status_code == 200
    assert not state.profiles
