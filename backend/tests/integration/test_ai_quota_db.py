"""Database-backed quota concurrency; disposable PostgreSQL/PostgREST only."""

import os
from concurrent.futures import ThreadPoolExecutor

import httpx
import psycopg
import pytest
from trip_test_support import LOCAL_ORIGIN

pytestmark = pytest.mark.db


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


def test_daily_cap_and_client_role_denial(rest, users):
    for _ in range(3):
        assert reserve(users.owner, minute=5, day=3)["allowed"]
    refused = reserve(users.owner, minute=5, day=3)
    assert refused["allowed"] is False
    assert refused["exhausted_window"] == "day"
    assert 0 < refused["retry_after_seconds"] <= 86400

    # The `users` fixture already validates disposable-only DB/PostgREST targets.
    # CI supplies a SQLAlchemy URL (postgresql+psycopg://), not a libpq DSN.
    dsn = os.environ["DATABASE_URL"].replace("postgresql+psycopg://", "postgresql://", 1)
    with psycopg.connect(dsn) as connection, connection.cursor() as cursor:
        # Cursor is already open in the combined context manager.
        cursor.execute("""
                select has_function_privilege(
                    'anon', 'public.consume_ai_extraction_quota(uuid,integer,integer)', 'EXECUTE'
                ), has_function_privilege(
                    'authenticated', 'public.consume_ai_extraction_quota(uuid,integer,integer)', 'EXECUTE'
                ), has_table_privilege('anon', 'public.ai_extraction_quotas', 'SELECT')
            """)
        assert cursor.fetchone() == (False, False, False)
