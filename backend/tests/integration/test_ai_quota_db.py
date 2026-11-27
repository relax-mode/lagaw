"""Database-backed quota concurrency; disposable PostgreSQL/PostgREST only."""

import os
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import Mock

import httpx
import psycopg
import pytest
from trip_test_support import LOCAL_ORIGIN

from app.database import LocationDatabase

pytestmark = pytest.mark.db


@pytest.fixture(autouse=True)
def budget_db(rest):
    # The rest fixture has checked both disposable targets before this connection.
    dsn = os.environ["DATABASE_URL"].replace("postgresql+psycopg://", "postgresql://", 1)
    with psycopg.connect(dsn, autocommit=True) as connection:
        try:
            connection.execute("insert into public.ai_extraction_budget(attempt_limit) values (100)")
            yield connection
        finally:
            connection.execute("delete from public.ai_extraction_budget where singleton")


def reserve(profile, minute=10, day=20):
    with httpx.Client(base_url=LOCAL_ORIGIN, trust_env=False, timeout=20) as client:
        response = client.post("rpc/consume_ai_extraction_quota", json={
            "p_profile_id": profile, "p_per_minute": minute, "p_per_day": day,
        })
    assert response.status_code == 200
    result = response.json()
    assert isinstance(result, list) and len(result) == 1
    return result[0]


def test_simultaneous_reservations_are_atomic(rest, users):
    with ThreadPoolExecutor(max_workers=12) as pool:
        results = list(pool.map(lambda _: reserve(users.owner), range(24)))
    assert sum(row["allowed"] for row in results) == 10
    assert all(not row["allowed"] and row["retry_after_seconds"] > 0
               for row in results if not row["allowed"])
    assert reserve(users.other)["allowed"]
    invalid = rest.post("rpc/consume_ai_extraction_quota", json={
        "p_profile_id": users.other, "p_per_minute": 11, "p_per_day": 20,
    })
    assert invalid.status_code >= 400


def test_daily_cap_and_client_role_denial(users, budget_db):
    for _ in range(3):
        assert reserve(users.owner, minute=5, day=3)["allowed"]
    refused = reserve(users.owner, minute=5, day=3)
    assert refused["allowed"] is False
    assert refused["exhausted_window"] == "day"
    assert 0 < refused["retry_after_seconds"] <= 86400

    privileges = budget_db.execute("""
        select has_function_privilege(
            'anon', 'public.consume_ai_extraction_quota(uuid,integer,integer)', 'EXECUTE'
        ), has_function_privilege(
            'authenticated', 'public.consume_ai_extraction_quota(uuid,integer,integer)', 'EXECUTE'
        ), has_table_privilege('anon', 'public.ai_extraction_quotas', 'SELECT'),
           has_table_privilege('authenticated', 'public.ai_extraction_budget', 'SELECT'),
           has_column_privilege('service_role', 'public.ai_extraction_budget', 'attempt_limit', 'UPDATE')
        """).fetchone()
    assert privileges == (False, False, False, False, False)


def test_aggregate_reservations_are_atomic_across_profiles(users, budget_db):
    budget_db.execute("update public.ai_extraction_budget set attempt_limit = 7 where singleton")
    with ThreadPoolExecutor(max_workers=12) as pool:
        results = list(pool.map(reserve, [users.owner, users.other] * 10))
    assert sum(row["allowed"] for row in results) == 7
    assert all(row["exhausted_window"] == "day" for row in results if not row["allowed"])
    assert budget_db.execute("select request_count from public.ai_extraction_budget").fetchone() == (7,)
    assert budget_db.execute("""
        select sum(request_count) from public.ai_extraction_quotas where profile_id in (%s,%s)
        and window_kind = 'day'
    """, (users.owner, users.other)).fetchone() == (7,)

    budget_db.execute("update public.ai_extraction_budget set window_start = window_start - interval '24 hours'")
    assert reserve(users.other)["allowed"]
    assert budget_db.execute("select request_count from public.ai_extraction_budget").fetchone() == (1,)


@pytest.mark.parametrize("status", [429, 503])
def test_extraction_reservation_denial_never_calls_provider(client, rest, users, budget_db, monkeypatch, status):
    provider = Mock(side_effect=AssertionError("Paid provider must not be called"))
    monkeypatch.setattr("app.preference_extraction.extract_preferences", provider)

    def connection():
        yield LocationDatabase(rest)

    monkeypatch.setattr("app.ai_quota.get_database", connection)
    if status == 429:
        # Simulate an existing attempt before the first aggregate reservation.
        budget_db.execute("update public.ai_extraction_budget set attempt_limit = 1 where singleton")
        budget_db.execute("""
            insert into public.ai_extraction_quotas values
                (%s, 'day', date_trunc('day', clock_timestamp(), 'UTC'), 1)
        """, (users.other,))
        code = "extraction_quota_exceeded"
    else:
        budget_db.execute("delete from public.ai_extraction_budget where singleton")
        code = "extraction_unavailable"

    response = client.post("/api/v1/preferences/extract", json={"prompt": "Cafe and photography"})
    assert response.status_code == status
    assert response.json()["detail"]["code"] == code
    assert response.json()["detail"]["manual_fallback"] is True
    if status == 429:
        assert 0 < int(response.headers["Retry-After"]) <= 86400
        assert budget_db.execute("select request_count from public.ai_extraction_budget").fetchone() == (1,)
    provider.assert_not_called()
