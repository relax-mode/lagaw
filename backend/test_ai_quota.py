"""Offline HTTP quota tests: DeepSeek is always mocked."""
import os
from collections import defaultdict
from unittest.mock import Mock, patch
from uuid import UUID

import httpx
import pytest
from fastapi.testclient import TestClient

with patch.dict(os.environ, {}, clear=True), patch("dotenv.load_dotenv"):
    from app.main import create_app

from app.ai_quota import (
    QuotaDecision,
    QuotaStore,
    QuotaUnavailable,
    get_quota_store,
    quota_limits,
)
from app.deepseek import Preferences

URL = "/api/v1/preferences/extract"
BEARER = "t" * 48
OWNER = "14000000-0000-4000-8000-000000000001"
OTHER = "14000000-0000-4000-8000-000000000002"


class SharedQuota:
    """Simulates shared decisions offline; real DB concurrency has a separate db test."""
    def __init__(self):
        self.minute = 1
        self.day = 1
        self.minutes = defaultdict(int)
        self.days = defaultdict(int)

    def consume(self, owner):
        if self.days[(owner, self.day)] >= 3:
            return QuotaDecision(allowed=False, retry_after_seconds=3000,
                                 exhausted_window="day")
        if self.minutes[(owner, self.minute)] >= 2:
            return QuotaDecision(allowed=False, retry_after_seconds=17,
                                 exhausted_window="minute")
        self.minutes[(owner, self.minute)] += 1
        self.days[(owner, self.day)] += 1
        return QuotaDecision(allowed=True, retry_after_seconds=0, exhausted_window=None)


def test_two_app_instances_users_429_reset_and_provider_suppression(monkeypatch):
    with patch.dict(os.environ, {
        "TRIP_AUTH_MODE": "demo", "SUPABASE_URL": "http://127.0.0.1:54321",
        "TRIP_DEMO_USER_ID": OWNER, "TRIP_DEMO_TOKEN": BEARER,
    }, clear=True), patch("app.main.load_dotenv"):
        shared = SharedQuota()
        provider = Mock(return_value=Preferences(
            budget_level="low", tags=["cafe"], duration="afternoon", pace="slow"
        ))
        monkeypatch.setattr("app.preference_extraction.extract_preferences", provider)
        app1, app2 = create_app(), create_app()
        app1.dependency_overrides[get_quota_store] = lambda: shared
        app2.dependency_overrides[get_quota_store] = lambda: shared
        with TestClient(app1, headers={"Authorization": f"Bearer {BEARER}"}) as a, TestClient(
            app2, headers={"Authorization": f"Bearer {BEARER}"}
        ) as b:
            assert a.post(URL, json={"prompt": "cafe"}).status_code == 200
            assert b.post(URL, json={"prompt": "cafe"}).status_code == 200
            blocked = a.post(URL, json={"prompt": "private-input"})
            assert blocked.status_code == 429
            assert blocked.headers["retry-after"] == "17"
            assert blocked.json()["detail"]["code"] == "extraction_quota_exceeded"
            assert blocked.json()["detail"]["manual_fallback"] is True
            assert "private-input" not in blocked.text
            assert provider.call_count == 2
            shared.minute += 1
            assert b.post(URL, json={"prompt": "cafe"}).status_code == 200
            blocked = a.post(URL, json={"prompt": "cafe"})
            assert blocked.status_code == 429
            assert blocked.headers["retry-after"] == "3000"
            assert provider.call_count == 3
            monkeypatch.setenv("TRIP_DEMO_USER_ID", OTHER)
            assert a.post(URL, json={"prompt": "cafe"}).status_code == 200
            shared.day += 1
            shared.minute += 1
            monkeypatch.setenv("TRIP_DEMO_USER_ID", OWNER)
            assert b.post(URL, json={"prompt": "cafe"}).status_code == 200
            assert provider.call_count == 5
            a.headers.pop("Authorization")
            assert a.post(URL, json={"prompt": "cafe"}).status_code == 401
            assert provider.call_count == 5


def test_postgrest_rpc_shape_and_fail_closed(monkeypatch):
    import app.database as db

    fake = {"status": 200, "rows": [
        {"allowed": True, "retry_after_seconds": 0, "exhausted_window": None}
    ]}
    calls = []

    def handler(request):
        calls.append(request)
        assert request.url.path == "/rest/v1/rpc/consume_ai_extraction_quota"
        assert request.headers["apikey"].startswith("sb_secret_")
        assert "authorization" not in request.headers
        import json
        assert json.loads(request.content) == {
            "p_profile_id": OWNER, "p_per_minute": 5, "p_per_day": 40,
        }
        return httpx.Response(fake["status"], json=fake["rows"])

    original = httpx.Client
    monkeypatch.setattr(db.httpx, "Client", lambda **kw: original(
        transport=httpx.MockTransport(handler), **kw
    ))
    monkeypatch.setattr(db, "load_dotenv", lambda *a, **kw: None)
    with patch.dict(os.environ, {
        "SUPABASE_URL": "https://example.invalid",
        "SUPABASE_SERVICE_ROLE_KEY": "sb_secret_" + "fixture",
    }, clear=True):
        assert QuotaStore().consume(UUID(OWNER)).allowed
        fake["rows"] = [{"allowed": False, "retry_after_seconds": 25,
                         "exhausted_window": "minute"}]
        assert QuotaStore().consume(UUID(OWNER)).retry_after_seconds == 25
        for invalid in ([], [{"allowed": True, "retry_after_seconds": 1,
                               "exhausted_window": None}]):
            fake["rows"] = invalid
            with pytest.raises(QuotaUnavailable):
                QuotaStore().consume(UUID(OWNER))
        fake["status"] = 503
        with pytest.raises(QuotaUnavailable) as error:
            QuotaStore().consume(UUID(OWNER))
        assert "fixture" not in str(error.value)
        assert len(calls) == 5


@pytest.mark.parametrize("minute,day", [
    ("0", "40"), ("11", "40"), ("5", "0"), ("5", "201"),
    ("five", "40"), ("5", "bad"),
])
def test_invalid_limits_fail_closed(monkeypatch, minute, day):
    monkeypatch.setenv("AI_EXTRACT_PER_MINUTE", minute)
    monkeypatch.setenv("AI_EXTRACT_PER_DAY", day)
    with pytest.raises(QuotaUnavailable):
        quota_limits()


def test_default_limits(monkeypatch):
    monkeypatch.delenv("AI_EXTRACT_PER_MINUTE", raising=False)
    monkeypatch.delenv("AI_EXTRACT_PER_DAY", raising=False)
    assert quota_limits() == (5, 40)


def test_quota_unavailable_fails_closed_without_provider_call(monkeypatch):
    with patch.dict(os.environ, {
        "TRIP_AUTH_MODE": "demo", "SUPABASE_URL": "http://127.0.0.1:54321",
        "TRIP_DEMO_USER_ID": OWNER, "TRIP_DEMO_TOKEN": BEARER,
    }, clear=True), patch("app.main.load_dotenv"):
        provider = Mock(side_effect=AssertionError("Paid provider must not be called"))
        monkeypatch.setattr("app.preference_extraction.extract_preferences", provider)
        app = create_app()
        quota = Mock()
        quota.consume.side_effect = QuotaUnavailable
        app.dependency_overrides[get_quota_store] = lambda: quota
        with TestClient(app, headers={"Authorization": f"Bearer {BEARER}"}) as client:
            response = client.post(URL, json={"prompt": "sensitive travel plans"})
            assert response.status_code == 503
            assert response.json() == {"detail": {
                "code": "extraction_unavailable",
                "message": "Preference extraction is unavailable.",
                "manual_fallback": True,
            }}
            assert "sensitive travel plans" not in response.text
            provider.assert_not_called()
