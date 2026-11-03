"""#116 public liveness and bounded PostgREST readiness (offline only)."""

import os
from types import SimpleNamespace
from unittest.mock import Mock, patch

import httpx
import pytest
from fastapi.testclient import TestClient

with patch.dict(os.environ, {}, clear=True), patch("dotenv.load_dotenv"):
    from app.main import create_app

from app.database import DatabaseUnavailable, get_database

REQUEST = httpx.Request("GET", "https://test.invalid/rest/v1/locations")


@pytest.fixture
def api(monkeypatch):
    monkeypatch.setattr("app.main.load_dotenv", lambda *a, **kw: None)
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "")
    with TestClient(create_app()) as client:
        yield client


def test_public_liveness_does_not_depend_on_database(api, monkeypatch):
    def unavailable():
        raise DatabaseUnavailable
        yield

    monkeypatch.setattr("app.health.get_database", unavailable)
    result = api.get("/health")
    assert result.status_code == 200 and result.json() == {"status": "ok"}
    ready = api.get("/ready")
    assert ready.status_code == 503 and ready.json() == {"status": "not_ready"}


def test_readiness_uses_bounded_read_only_catalog_probe(api, monkeypatch):
    db = Mock()
    db.client.get.return_value = httpx.Response(200, json=[], request=REQUEST)
    calls = []

    def available():
        calls.append(True)
        yield SimpleNamespace(client=db.client)

    monkeypatch.setattr("app.health.get_database", available)
    result = api.get("/ready")
    assert result.status_code == 200 and result.json() == {"status": "ready"}
    db.client.get.assert_called_once_with(
        "locations", params={"select": "id", "limit": 0}, timeout=2.0
    )
    assert calls == [True]
    assert api.get("/health").json() == {"status": "ok"}


@pytest.mark.parametrize("outcome", [
    httpx.Response(503, text="private database credentials", request=REQUEST),
    httpx.Response(200, json={"private": "bad"}, request=REQUEST),
    httpx.Response(200, json=[{"id": 5}], request=REQUEST),
    httpx.Response(500, text="stacktrace", request=REQUEST),
    httpx.ReadTimeout("private credentials"),
    httpx.ConnectError("private network details"),
])
def test_readiness_dependencies_fail_closed(api, monkeypatch, outcome):
    client = Mock()
    if isinstance(outcome, Exception):
        client.get.side_effect = outcome
    else:
        client.get.return_value = outcome

    def available():
        yield SimpleNamespace(client=client)

    monkeypatch.setattr("app.health.get_database", available)
    result = api.get("/ready")
    assert result.status_code == 503
    assert result.json() == {"status": "not_ready"}
    assert "private" not in result.text
    assert "stacktrace" not in result.text


def test_locations_reject_invalid_parameters_without_echoing_input(api):
    api.app.dependency_overrides[get_database] = lambda: Mock()
    result = api.get("/locations?limit=private-input")
    assert result.status_code == 422
    assert "private-input" not in result.text
    assert "input" not in result.json()["detail"][0]
    assert result.json()["detail"][0]["loc"][-1] == "limit"


def test_openapi_exposes_correct_routes_and_security(api):
    schema = api.get("/openapi.json").json()
    assert schema["paths"]["/health"]["get"]["responses"]["200"]
    assert schema["paths"]["/ready"]["get"]["responses"]["503"]
    assert "security" not in schema["paths"]["/health"]["get"]
    assert "security" not in schema["paths"]["/ready"]["get"]
    assert schema["paths"]["/api/v1/preferences/extract"]["post"]["security"] == [
        {"SupabaseAccessToken": []}
    ]
    assert schema["paths"]["/locations"]["get"]["responses"]["200"]
