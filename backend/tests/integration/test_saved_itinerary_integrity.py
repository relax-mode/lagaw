"""Trip and visit edits through the API and competing PostgreSQL sessions."""

import os
import time
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal

import psycopg
import pytest

pytestmark = pytest.mark.db


@pytest.fixture
def visit(rest):
    response = rest.get("locations", params={"select": "id", "is_active": "eq.true", "limit": 1})
    assert response.status_code == 200
    location, = response.json()
    return {"location_id": location["id"], "day_number": 2, "visit_order": 1}


def test_date_conflict_preserves_trip_and_visits_then_retry_succeeds(client, seed_trip, visit):
    trip_url = f"/api/v1/trips/{seed_trip()['id']}"
    items_url = f"{trip_url}/items"
    for day in (1, 2):
        assert client.post(items_url, json={**visit, "day_number": day}).status_code == 201
    before = client.get(trip_url).json()
    items = client.get(items_url).json()["items"]
    assert len(items) == 2

    shrink = {"end_date": before["start_date"]}
    conflict = client.patch(trip_url, json={**shrink, "title": "Must roll back"})
    assert conflict.status_code == 409
    detail = conflict.json()["detail"]
    assert detail["code"] == "trip_dates_conflict"
    assert "saved visits outside the trip" in detail["message"]
    assert client.get(trip_url).json() == before
    assert client.get(items_url).json()["items"] == items

    compatible = client.patch(trip_url, json={"end_date": "2026-11-03"})
    assert compatible.status_code == 200
    assert compatible.json() == {**before, "end_date": "2026-11-03"}
    assert client.get(items_url).json()["items"] == items

    assert client.delete(f"{items_url}/{items[1]['id']}").status_code == 204
    assert client.patch(trip_url, json=shrink).status_code == 200
    assert client.get(trip_url).json() == {**before, **shrink}
    assert client.get(items_url).json()["items"] == items[:1]


def test_lower_budget_clears_saved_estimate_and_preserves_visits(client, rest, seed_trip, visit):
    trip = seed_trip(budget_min=0)
    trip_url = f"/api/v1/trips/{trip['id']}"
    items_url = f"{trip_url}/items"
    item = rest.post("itinerary_items", json={
        **visit, "trip_id": trip["id"], "arrival_time": "09:00", "departure_time": "10:00",
        "estimated_cost": 200, "estimated_travel_time": 0,
        "recommendation_score": 0.9, "recommendation_reason": "Saved generated fixture",
    })
    assert item.status_code == 201
    assert rest.patch("trips", params={"id": f"eq.{trip['id']}"},
                      json={"estimated_total_cost": 200}).status_code == 204
    items = client.get(items_url).json()["items"]
    assert len(items) == 1
    boundary = client.patch(trip_url, json={"budget_max": "200.00"})
    assert boundary.status_code == 200
    assert Decimal(boundary.json()["estimated_total_cost"]) == Decimal("200.00")

    changed = client.patch(trip_url, json={"budget_max": "199.99"})
    assert changed.status_code == 200
    assert changed.json() == {**boundary.json(), "budget_max": "199.99", "estimated_total_cost": None}
    assert client.get(trip_url).json() == changed.json()
    assert client.get(items_url).json()["items"] == items
    assert client.get("/api/v1/trips").json()["items"] == [changed.json()]

    restored_budget = client.patch(trip_url, json={"budget_max": "500.50"})
    assert restored_budget.status_code == 200
    assert restored_budget.json()["estimated_total_cost"] is None
    assert client.get(items_url).json()["items"] == items


@pytest.mark.parametrize("visit_first", [True, False])
def test_competing_date_and_item_writes_serialize(client, seed_trip, visit, visit_first):
    trip = seed_trip()
    trip_url = f"/api/v1/trips/{trip['id']}"
    items_url = f"{trip_url}/items"
    shrink = {"end_date": trip["start_date"]}
    # seed_trip uses the disposable-only target guard before creating this fixture.
    dsn = os.environ["DATABASE_URL"].replace("postgresql+psycopg://", "postgresql://", 1)
    with ThreadPoolExecutor(1) as pool, psycopg.connect(dsn) as winner:
        if visit_first:
            winner.execute(
                "insert into public.itinerary_items(trip_id,location_id,day_number,visit_order) "
                "values (%s,%s,%s,%s)",
                (trip["id"], visit["location_id"], visit["day_number"], visit["visit_order"]),
            )
            loser = pool.submit(client.patch, trip_url, json=shrink)
        else:
            winner.execute("update public.trips set end_date = start_date where id = %s", (trip["id"],))
            loser = pool.submit(client.post, items_url, json=visit)

        wait_for_blocked_write(dsn, winner.info.backend_pid, loser)
        winner.commit()
        assert loser.result(timeout=5).status_code == 409

    saved = client.get(trip_url).json()
    items = client.get(items_url).json()["items"]
    assert saved["end_date"] == (trip["end_date"] if visit_first else trip["start_date"])
    assert [item["day_number"] for item in items] == ([2] if visit_first else [])


def test_manual_delete_waits_for_parent_without_locking_item(client, rest, users, seed_trip, visit):
    trip = seed_trip()
    items_url = f"/api/v1/trips/{trip['id']}/items"
    added = client.post(items_url, json=visit)
    assert added.status_code == 201
    item_id = added.json()["id"]

    foreign = rest.post("rpc/remove_itinerary_item", json={
        "p_owner": users.other, "p_trip": trip["id"], "p_item": item_id,
    })
    assert foreign.status_code == 200 and foreign.json() is False

    dsn = os.environ["DATABASE_URL"].replace("postgresql+psycopg://", "postgresql://", 1)
    with ThreadPoolExecutor(1) as pool, psycopg.connect(dsn) as generation:
        generation.execute("select id from public.trips where id = %s for update", (trip["id"],))
        deletion = pool.submit(client.delete, f"{items_url}/{item_id}")
        wait_for_blocked_write(dsn, generation.info.backend_pid, deletion)

        # Generation can still take the item lock it needs for replacement.
        locked = generation.execute(
            "select id from public.itinerary_items where id = %s for update nowait", (item_id,),
        ).fetchone()
        assert locked is not None
        generation.commit()
        assert deletion.result(timeout=5).status_code == 204

    assert client.get(items_url).json()["items"] == []


def wait_for_blocked_write(dsn, blocker_pid, request):
    with psycopg.connect(dsn, autocommit=True) as observer:
        deadline = time.monotonic() + 4
        while not observer.execute(
            "select exists(select 1 from pg_stat_activity where %s = any(pg_blocking_pids(pid)))",
            (blocker_pid,),
        ).fetchone()[0]:
            assert time.monotonic() < deadline and not request.done(), "No competing database write reached the lock"
            time.sleep(0.01)
