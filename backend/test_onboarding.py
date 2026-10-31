"""Offline owner-scoped onboarding API tests; no accounts or hosted writes."""

import json
import os
from copy import deepcopy
from types import SimpleNamespace
from unittest.mock import patch
from uuid import UUID

import httpx
import pytest
from fastapi.testclient import TestClient

from app.auth import unauthorized

OWNER = UUID("a1020000-0000-4000-8000-000000000001")
OTHER = UUID("a1020000-0000-4000-8000-000000000002")
BASE = "/api/v1/me/preferences"
HTTP_CLIENT = httpx.Client
VALID = {
    "preferred_tags": ["cafe", "heritage"],
    "budget_min": "0",
    "budget_max": "500.00",
    "travel_style": "slow",
}


@pytest.fixture
def api(monkeypatch):
    with patch.dict(os.environ, {
        "SUPABASE_URL": "http://127.0.0.1:54321",
        "SUPABASE_SERVICE_ROLE_KEY": "sb_secret_offline_only",
        "CORS_ALLOWED_ORIGINS": "http://localhost:3000",
    }, clear=True):
        with patch("dotenv.load_dotenv"):
            from app.main import create_app

        monkeypatch.setattr("app.main.load_dotenv", lambda *a, **k: None)
        monkeypatch.setattr("app.database.load_dotenv", lambda *a, **k: None)

        def fake_authenticate(value):
            if value == "synthetic-owner-a":
                return OWNER
            if value == "synthetic-owner-b":
                return OTHER
            raise unauthorized()

        monkeypatch.setattr("app.trips.authenticate", fake_authenticate)
        state = SimpleNamespace(
            rows={
                str(OWNER): {
                    "id": str(OWNER), "preferred_tags": ["cafe"],
                    "default_budget_min": None, "default_budget_max": None,
                    "traveler_type": None,
                    "name": "Existing name", "email": "a@example.invalid",
                },
                str(OTHER): {
                    "id": str(OTHER), "preferred_tags": ["nature"],
                    "default_budget_min": "20", "default_budget_max": "100",
                    "traveler_type": "fast",
                    "name": "Another traveler", "email": "b@example.invalid",
                },
            },
            requests=[], override=None,
        )

        def handle(request):
            state.requests.append(request)
            assert request.url.path == "/rest/v1/users"
            assert request.method in ("GET", "PATCH")
            assert request.url.params["select"] == (
                "id,preferred_tags,default_budget_min,default_budget_max,traveler_type"
            )
            assert set(request.url.params).issubset({"id", "select", "limit"})
            if state.override is not None:
                return state.override(request)
            owner = request.url.params["id"].removeprefix("eq.")
            rows = ([state.rows[owner]] if owner in state.rows else [])
            if request.method == "PATCH":
                assert "limit" not in request.url.params
                assert request.headers["prefer"] == "return=representation"
                assert request.headers["content-profile"] == "public"
                for row in rows:
                    row.update(json.loads(request.content))
            else:
                assert request.url.params["limit"] == "2"
            # Do not leak name/email fields to the public API.
            return httpx.Response(200, json=[
                {key: val for key, val in row.items()
                 if key in ("id", "preferred_tags", "default_budget_min",
                            "default_budget_max", "traveler_type")}
                for row in rows
            ])

        monkeypatch.setattr("app.database.httpx.Client", lambda **kw: HTTP_CLIENT(
            transport=httpx.MockTransport(handle), **kw,
        ))
        client = TestClient(create_app())
        try:
            yield client, state
        finally:
            client.close()


def auth(owner="a"):
    return {"Authorization": f"Bearer synthetic-owner-{owner}"}


def test_get_initial_profile_and_owner_isolation(api):
    client, state = api
    a = client.get(BASE, headers=auth("a"))
    b = client.get(BASE, headers=auth("b"))
    assert a.status_code == b.status_code == 200
    assert a.json() == {
        "preferred_tags": ["cafe"], "budget_min": None,
        "budget_max": None, "travel_style": None,
    }
    assert b.json() == {
        "preferred_tags": ["nature"], "budget_min": "20",
        "budget_max": "100", "travel_style": "fast",
    }
    assert [r.url.params["id"] for r in state.requests] == [
        f"eq.{OWNER}", f"eq.{OTHER}",
    ]
    assert "a@example.invalid" not in a.text
    assert "b@example.invalid" not in b.text


def test_save_persists_and_does_not_change_other_profile_or_fields(api):
    client, state = api
    original_other = deepcopy(state.rows[str(OTHER)])
    result = client.put(BASE, headers=auth(), json=VALID)
    assert result.status_code == 200, result.text
    assert result.json() == VALID
    request = state.requests[-1]
    assert request.method == "PATCH"
    assert request.url.params["id"] == f"eq.{OWNER}"
    assert json.loads(request.content) == {
        "preferred_tags": ["cafe", "heritage"],
        "default_budget_min": "0", "default_budget_max": "500.00",
        "traveler_type": "slow",
    }
    assert state.rows[str(OTHER)] == original_other
    assert state.rows[str(OWNER)]["name"] == "Existing name"
    assert client.get(BASE, headers=auth()).json() == VALID


def test_explicit_null_and_empty_list_clear_only_preference_fields(api):
    client, state = api
    result = client.put(BASE, headers=auth(), json={
        "preferred_tags": [], "budget_min": None, "budget_max": None,
        "travel_style": None,
    })
    assert result.status_code == 200
    assert result.json()["preferred_tags"] == []
    assert result.json()["budget_min"] is None
    assert state.rows[str(OWNER)]["default_budget_max"] is None


@pytest.mark.parametrize("invalid", [
    {"preferred_tags": ["coffee"]},
    {"preferred_tags": ["cafe", "cafe"]},
    {"preferred_tags": "cafe"},
    {"preferred_tags": ["cafe"] * 31},
    {"budget_min": None, "budget_max": "1"},
    {"budget_min": "1", "budget_max": None},
    {"budget_min": "500", "budget_max": "1"},
    {"budget_min": "-1"},
    {"budget_min": "NaN"},
    {"budget_max": "Infinity"},
    {"budget_max": "500.001"},
    {"budget_max": True},
    {"travel_style": "hacker"},
    {"travel_style": "unspecified"},
    {"travel_style": 10},
    {"user_id": str(OTHER)},
    {"id": str(OTHER)},
    {"email": "changed@example.invalid"},
])
def test_invalid_input_cannot_write(api, invalid):
    client, state = api
    result = client.put(BASE, headers=auth(), json={**VALID, **invalid})
    assert result.status_code == 422, (invalid, result.text)
    assert state.requests == []
    assert all(set(error) == {"loc", "msg", "type"} for error in result.json()["detail"])


@pytest.mark.parametrize("payload", [
    {}, {"preferred_tags": []}, {"budget_min": "0"},
])
def test_put_requires_all_fields_to_prevent_accidental_clears(api, payload):
    client, state = api
    assert client.put(BASE, headers=auth(), json=payload).status_code == 422
    assert state.requests == []


@pytest.mark.parametrize("method", ["get", "put"])
@pytest.mark.parametrize("credentials", [{}, {"Authorization": "Bearer wrong"},
                                          {"Authorization": "Basic unexpected"}])
def test_auth_required_before_database(api, method, credentials):
    client, state = api
    response = getattr(client, method)(
        BASE, headers=credentials, **({"json": VALID} if method == "put" else {}),
    )
    assert response.status_code == 401
    assert response.headers.get("www-authenticate") == "Bearer"
    assert state.requests == []


def test_other_owner_cannot_write_first_owners_profile(api):
    client, state = api
    before = deepcopy(state.rows[str(OWNER)])
    result = client.put(BASE, headers=auth("b"), json=VALID)
    assert result.status_code == 200
    assert state.rows[str(OWNER)] == before
    assert state.requests[-1].url.params["id"] == f"eq.{OTHER}"


def test_profile_not_found_is_404_without_mutation(api):
    client, state = api
    del state.rows[str(OWNER)]
    assert client.get(BASE, headers=auth()).status_code == 404
    assert client.put(BASE, headers=auth(), json=VALID).status_code == 404


@pytest.mark.parametrize("body", [
    {"private": "provider diagnostics"},
    [{"id": str(OTHER), "preferred_tags": ["nature"],
      "default_budget_min": None, "default_budget_max": None, "traveler_type": None}],
    [{"id": str(OWNER), "preferred_tags": ["not-allowed"],
      "default_budget_min": None, "default_budget_max": None, "traveler_type": None}],
    [{"id": str(OWNER), "preferred_tags": ["nature"],
      "default_budget_min": "100", "default_budget_max": None, "traveler_type": None}],
])
def test_malformed_or_cross_owner_data_fails_closed(api, body):
    client, state = api
    state.override = lambda request: httpx.Response(200, json=body)
    for method in ("get", "put"):
        response = getattr(client, method)(
            BASE, headers=auth(), **({"json": VALID} if method == "put" else {}),
        )
        assert response.status_code == 503
        assert response.json() == {
            "detail": "Onboarding preferences are temporarily unavailable.",
        }
        assert "private" not in response.text


def test_network_and_database_errors_safe(api):
    client, state = api
    for status in (400, 401, 409, 422, 500, 503):
        state.override = lambda request, code=status: httpx.Response(
            code, text="provider-private-diagnostic",
        )
        response = client.get(BASE, headers=auth())
        assert response.status_code == 503
        assert "provider-private-diagnostic" not in response.text
    state.override = lambda request: (_ for _ in ()).throw(
        httpx.ReadTimeout("private timeout"),
    )
    assert client.put(BASE, headers=auth(), json=VALID).status_code == 503


def test_unconfigured_service_key_is_safe(api):
    client, state = api
    os.environ["SUPABASE_SERVICE_ROLE_KEY"] = ""
    response = client.get(BASE, headers=auth())
    assert response.status_code == 503
    assert state.requests == []


def test_openapi_contract_is_distinct_from_extraction(api):
    client, _ = api
    spec = client.get("/openapi.json").json()
    route = spec["paths"][BASE]
    assert "get" in route and "put" in route
    assert route["get"]["security"][0].get("SupabaseAccessToken") == []
    assert "/api/v1/preferences/extract" in spec["paths"]
