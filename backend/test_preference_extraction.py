"""HTTP-level extraction checks: dummy config and mocked provider transport only."""

import json
import os
from pathlib import Path
from typing import get_args
from unittest.mock import Mock, patch

import httpx
import pytest
from fastapi.testclient import TestClient

with patch.dict(os.environ, {}, clear=True), patch("dotenv.load_dotenv"):
    from app.main import create_app

from app.preference_extraction import ExtractionResponse
from app.preference_vocabulary import TravelTag
from app.trip_schemas import TripResponse
from app.trips import get_trip_database

CLIENT = httpx.Client
BASE = "/api/v1/preferences/extract"
TOKEN = "offline-extraction-demo-token-12345678901234567890"
OWNER = "23000000-0000-4000-8000-000000000001"
DEFAULT = {
    "budget_level": "low",
    "tags": ["cafe"],
    "duration": "afternoon",
    "pace": "slow",
}
CASES = json.loads(
    (Path(__file__).parent / "fixtures/extraction/cases.json").read_text(
        encoding="utf-8"
    )
)


def envelope(content=DEFAULT, finish="stop"):
    return {
        "choices": [
            {"finish_reason": finish, "message": {"content": json.dumps(content)}}
        ]
    }


@pytest.fixture
def api(monkeypatch):
    with (
        patch.dict(
            os.environ,
            {
                "TRIP_DEMO_USER_ID": OWNER,
                "TRIP_DEMO_TOKEN": TOKEN,
                "DEEPSEEK_API_KEY": "dummy-extraction-key-only",
            },
            clear=True,
        ),
        patch("app.main.load_dotenv"),
        patch("app.deepseek.load_dotenv"),
    ):
        app = create_app()
        # A fake existing saved trip: extraction has no store dependency to mutate it.
        saved = TripResponse(
            id="23000000-0000-4000-8000-000000000003",
            user_id=OWNER,
            title="Existing trip",
            start_date="2026-11-01",
            end_date="2026-11-01",
            budget_min="0",
            budget_max="500",
            preferred_tags=["heritage"],
            status="draft",
            estimated_total_cost=None,
        )
        store = Mock()
        store.retrieve_trip.return_value = saved
        app.dependency_overrides[get_trip_database] = lambda: store
        calls = []
        reply = Mock(return_value=httpx.Response(200, json=envelope()))

        def handler(request):
            calls.append(request)
            assert request.url == "https://api.deepseek.com/chat/completions"
            assert (
                request.method == "POST"
            )  # All network is the mocked extraction request.
            return reply(request)

        with TestClient(app, headers={"Authorization": f"Bearer {TOKEN}"}) as client:
            monkeypatch.setattr(
                "app.deepseek.httpx.Client",
                lambda **kw: CLIENT(
                    transport=httpx.MockTransport(handler),
                    **kw,
                ),
            )
            yield client, reply, calls, store, saved


def assert_safe(response):
    for private in (
        "dummy-extraction-key-only",
        TOKEN,
        "private provider details",
        "do-not-echo-me",
    ):
        assert private not in response.text


@pytest.mark.parametrize("case", CASES, ids=lambda c: c["id"])
def test_evaluation_cases(api, case):
    client, reply, calls, store, saved = api
    before = client.get(f"/api/v1/trips/{saved.id}").json()
    reply.return_value = httpx.Response(200, json=envelope(case["provider"]))
    response = client.post(
        BASE,
        json={
            "prompt": case["prompt"],
            "explicit_preferences": case["explicit_preferences"],
        },
    )
    assert response.status_code == 200
    result = ExtractionResponse.model_validate(response.json())
    draft = result.preferences.model_dump(mode="json")
    for key, value in case["expected"].items():
        assert draft[key] == value
    assert result.requires_confirmation
    assert draft["budget_scope"] == "trip_total"
    assert result.missing_fields == (
        [] if draft["budget_min"] is not None else ["budget", "group_type"]
    )
    assert len(calls) == 1
    assert json.loads(calls[0].content)["messages"][-1]["content"] == case["prompt"]
    assert client.get(f"/api/v1/trips/{saved.id}").json() == before
    store.create_trip.assert_not_called()
    store.update_trip.assert_not_called()
    assert_safe(response)


@pytest.mark.parametrize(
    "payload",
    [
        {},
        {"prompt": ""},
        {"prompt": "   "},
        {"prompt": "x" * 2001},
        {"prompt": 123},
        {"prompt": None},
        [],
        {"prompt": "do-not-echo-me", "extra": True},
        {"prompt": "coffee", "explicit_preferences": {"preferred_tags": ["unknown"]}},
        {"prompt": "coffee", "explicit_preferences": {"budget_min": "100"}},
        {
            "prompt": "coffee",
            "explicit_preferences": {"budget_min": "100", "budget_max": "99"},
        },
        {
            "prompt": "coffee",
            "explicit_preferences": {"budget_min": "0", "budget_max": "NaN"},
        },
        {
            "prompt": "coffee",
            "explicit_preferences": {"budget_min": "0", "budget_max": "1.001"},
        },
        {"prompt": "coffee", "explicit_preferences": {"duration": "week"}},
        {"prompt": "coffee", "explicit_preferences": {"pace": "racing"}},
        {"prompt": "coffee", "explicit_preferences": {"user_id": OWNER}},
    ],
)
def test_invalid_requests_do_not_call_provider(api, payload):
    client, _, calls, store, _ = api
    response = client.post(BASE, json=payload)
    assert response.status_code == 422
    assert response.json()["detail"]["code"] == "invalid_request"
    assert response.json()["detail"]["manual_fallback"] is True
    assert calls == []
    store.create_trip.assert_not_called()
    store.update_trip.assert_not_called()
    assert_safe(response)


def test_malformed_json_and_maximum_prompt(api):
    client, _, calls, _, _ = api
    response = client.post(
        BASE,
        content='{"prompt":"do-not-echo-me",',
        headers={"Content-Type": "application/json"},
    )
    assert response.status_code == 422
    assert_safe(response)
    assert calls == []
    assert client.post(BASE, json={"prompt": "x" * 2000}).status_code == 200
    assert len(calls) == 1


@pytest.mark.parametrize(
    "status,expected,code",
    [
        (400, 502, "extraction_failed"),
        (401, 503, "extraction_unavailable"),
        (402, 503, "extraction_unavailable"),
        (403, 503, "extraction_unavailable"),
        (404, 503, "extraction_unavailable"),
        (429, 429, "extraction_rate_limited"),
        (500, 503, "extraction_unavailable"),
        (503, 503, "extraction_unavailable"),
    ],
)
def test_provider_http_failures_are_safe_and_leave_trip_unchanged(
    api, status, expected, code
):
    client, reply, calls, store, saved = api
    before = client.get(f"/api/v1/trips/{saved.id}").json()
    reply.return_value = httpx.Response(status, text="private provider details")
    response = client.post(BASE, json={"prompt": "do-not-echo-me"})
    assert response.status_code == expected
    assert response.json()["detail"]["code"] == code
    assert response.json()["detail"]["manual_fallback"] is True
    assert_safe(response)
    assert len(calls) == 1  # No paid automatic retries.
    assert client.get(f"/api/v1/trips/{saved.id}").json() == before
    store.create_trip.assert_not_called()
    store.update_trip.assert_not_called()


@pytest.mark.parametrize(
    "error,status,code",
    [
        (httpx.ReadTimeout("private provider details"), 504, "extraction_timeout"),
        (httpx.ConnectError("private provider details"), 503, "extraction_unavailable"),
    ],
)
def test_transport_failures(api, error, status, code):
    client, reply, _, store, _ = api
    reply.side_effect = error
    response = client.post(BASE, json={"prompt": "do-not-echo-me"})
    assert response.status_code == status
    assert response.json()["detail"]["code"] == code
    store.create_trip.assert_not_called()
    store.update_trip.assert_not_called()
    assert_safe(response)


@pytest.mark.parametrize(
    "body",
    [
        {},
        {"choices": []},
        envelope(DEFAULT, "length"),
        envelope(DEFAULT, "content_filter"),
        envelope(DEFAULT | {"tags": ["unknown"]}),
        envelope(DEFAULT | {"tags": ["coffee"]}),
        envelope(DEFAULT | {"budget_level": "luxury"}),
        envelope(DEFAULT | {"duration": "week"}),
        envelope(DEFAULT | {"pace": "racing"}),
        envelope(DEFAULT | {"extra": True}),
        envelope({"tags": []}),
        {"choices": [{"finish_reason": "stop", "message": {"content": "not-json"}}]},
    ],
)
def test_invalid_provider_output(api, body):
    client, reply, _, _, _ = api
    reply.return_value = httpx.Response(200, json=body)
    response = client.post(BASE, json={"prompt": "coffee"})
    assert response.status_code == 502
    assert response.json()["detail"]["code"] == "invalid_extraction_output"
    assert_safe(response)


@pytest.mark.parametrize(
    "setting,value", [("DEEPSEEK_API_KEY", ""), ("DEEPSEEK_TIMEOUT_MS", "invalid")]
)
def test_configuration_failure_before_provider(api, monkeypatch, setting, value):
    client, _, calls, _, _ = api
    monkeypatch.setenv(setting, value)
    response = client.post(BASE, json={"prompt": "coffee"})
    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "extraction_unavailable"
    assert calls == []


def test_existing_access_context_required(api, monkeypatch):
    client, _, calls, _, _ = api
    for authorization in (None, "Bearer incorrect-token"):
        client.headers.pop("Authorization", None)
        if authorization:
            client.headers["Authorization"] = authorization
        response = client.post(BASE, json={"prompt": "coffee"})
        assert response.status_code == 401
    monkeypatch.setenv("TRIP_DEMO_USER_ID", "invalid")
    assert client.post(BASE, json={"prompt": "coffee"}).status_code == 503
    assert calls == []


def test_tag_vocabulary_matches_approved_catalog():
    path = Path(__file__).resolve().parents[1] / "supabase/data/locations.json"
    tags = {
        tag
        for row in json.loads(path.read_text(encoding="utf-8"))
        for tag in row["vibe_tags"]
    }
    assert tags == set(get_args(TravelTag))


def test_openapi_has_versioned_route_and_existing_security(api):
    schema = api[0].get("/openapi.json").json()
    operation = schema["paths"][BASE]["post"]
    assert operation["security"] == [{"TripDemoToken": []}]
    assert operation["responses"]["200"]["content"]["application/json"]["schema"][
        "$ref"
    ].endswith("ExtractionResponse")
