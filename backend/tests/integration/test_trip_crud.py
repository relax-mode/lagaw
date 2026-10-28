"""Issue #29: HTTP behavior plus real PostgreSQL persistence and owner FKs."""

from decimal import Decimal
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient

BASE = "/api/v1/trips"
pytestmark = pytest.mark.db


def test_create_persists_under_server_selected_user(client, users, payload, stored_trip):
    response = client.post(BASE, json={**payload, "title": "  Issue 29 synthetic trip  "})
    assert response.status_code == 201
    trip = response.json()
    assert UUID(trip["id"]).int != 0
    assert trip["user_id"] == users.owner
    assert trip["status"] == "draft"
    assert trip["estimated_total_cost"] is None
    assert trip["title"] == payload["title"]
    assert isinstance(trip["budget_max"], str)
    assert Decimal(trip["budget_max"]) == Decimal("500.50")
    row, = stored_trip(trip["id"])
    assert row["user_id"] == users.owner
    assert row["title"] == payload["title"]
    assert row["preferred_tags"] == payload["preferred_tags"]
    assert Decimal(str(row["budget_max"])) == Decimal("500.50")


def test_same_day_zero_budget_and_defaults(client, payload, stored_trip):
    minimal = {key: payload[key] for key in ("title", "start_date", "end_date")}
    minimal.update(end_date=minimal["start_date"], budget_min=0, budget_max=0)
    response = client.post(BASE, json=minimal)
    assert response.status_code == 201
    trip = response.json()
    assert trip["transportation_mode"] is None
    assert trip["group_type"] is None
    assert trip["preferred_tags"] == []
    row, = stored_trip(trip["id"])
    assert row["start_date"] == row["end_date"]
    assert row["budget_min"] == row["budget_max"] == 0


def test_list_pagination_order_and_owner_isolation(client, users, seed_trip):
    owned = [
        seed_trip(start_date="2026-11-02"),
        seed_trip(start_date="2026-11-01"),
        seed_trip(start_date="2026-11-01"),
    ]
    foreign = seed_trip(users.other)
    expected = [row["id"] for row in sorted(owned, key=lambda row: (row["start_date"], row["id"]))]
    response = client.get(BASE)
    assert response.status_code == 200
    assert [row["id"] for row in response.json()["items"]] == expected
    assert foreign["id"] not in expected
    page = client.get(BASE, params={"limit": 2, "offset": 1})
    assert page.status_code == 200
    assert page.json()["limit"] == 2
    assert page.json()["offset"] == 1
    assert [row["id"] for row in page.json()["items"]] == expected[1:3]
    empty = client.get(BASE, params={"offset": 100})
    assert empty.status_code == 200
    assert empty.json() == {"items": [], "limit": 10, "offset": 100}


def test_empty_user_has_no_trips(client):
    response = client.get(BASE)
    assert response.status_code == 200
    assert response.json() == {"items": [], "limit": 10, "offset": 0}


def test_retrieve_survives_a_new_api_client(client, application, seed_trip):
    saved = seed_trip()
    first = client.get(f"{BASE}/{saved['id']}")
    assert first.status_code == 200
    with TestClient(application, headers=dict(client.headers)) as fresh_client:
        second = fresh_client.get(f"{BASE}/{saved['id']}")
    assert second.status_code == 200
    assert second.json() == first.json()
    assert second.json()["title"] == saved["title"]


def test_partial_update_preserves_other_fields(client, seed_trip, stored_trip):
    trip_id = seed_trip()["id"]
    original = client.get(f"{BASE}/{trip_id}").json()
    response = client.patch(f"{BASE}/{trip_id}", json={"title": "  Updated issue 29  "})
    assert response.status_code == 200
    assert response.json() == {**original, "title": "Updated issue 29"}
    assert client.get(f"{BASE}/{trip_id}").json() == response.json()
    row, = stored_trip(trip_id)
    assert row["title"] == "Updated issue 29"
    assert row["user_id"] == original["user_id"]


def test_full_update_and_optional_clearing_persist(client, seed_trip, stored_trip):
    trip_id = seed_trip()["id"]
    changes = {
        "title": "Issue 29 full update", "start_date": "2026-11-03",
        "end_date": "2026-11-04", "budget_min": "200.25", "budget_max": "800.75",
        "transportation_mode": "taxi", "group_type": "friends",
        "preferred_tags": ["food", "heritage"],
    }
    response = client.patch(f"{BASE}/{trip_id}", json=changes)
    assert response.status_code == 200
    for field, value in changes.items():
        assert response.json()[field] == value
    row, = stored_trip(trip_id)
    for field, value in changes.items():
        if field.startswith("budget_"):
            assert Decimal(str(row[field])) == Decimal(value)
        else:
            assert row[field] == value
    cleared = {"transportation_mode": None, "group_type": None, "preferred_tags": []}
    response = client.patch(f"{BASE}/{trip_id}", json=cleared)
    assert response.status_code == 200
    assert client.get(f"{BASE}/{trip_id}").json() == response.json()
    row, = stored_trip(trip_id)
    for field, value in cleared.items():
        assert row[field] == value
    assert row["title"] == changes["title"]


def test_delete_removes_only_selected_trip(client, users, seed_trip, stored_trip, rest):
    deleted = seed_trip()
    retained = seed_trip()
    foreign = seed_trip(users.other)
    response = client.delete(f"{BASE}/{deleted['id']}")
    assert response.status_code == 204
    assert response.content == b""
    assert stored_trip(deleted["id"]) == []
    assert len(stored_trip(retained["id"])) == 1
    assert client.get(f"{BASE}/{deleted['id']}").status_code == 404
    assert client.delete(f"{BASE}/{deleted['id']}").status_code == 404
    assert [row["id"] for row in client.get(BASE).json()["items"]] == [retained["id"]]
    for table, row_id in (("users", users.owner), ("trips", foreign["id"])):
        remaining = rest.get(table, params={"id": f"eq.{row_id}", "select": "id"})
        assert remaining.status_code == 200
        assert remaining.json() == [{"id": row_id}]


@pytest.mark.parametrize("method", ["GET", "PATCH", "DELETE"])
def test_other_owner_and_missing_trip_have_same_404(client, users, seed_trip, rest, method):
    foreign = seed_trip(users.other)
    kwargs = {"json": {"title": "Must not change"}} if method == "PATCH" else {}
    for trip_id in (foreign["id"], str(uuid4())):
        response = client.request(method, f"{BASE}/{trip_id}", **kwargs)
        assert response.status_code == 404
        assert response.json() == {"detail": "Trip not found."}
    saved = rest.get("trips", params={"id": f"eq.{foreign['id']}", "select": "*"})
    assert saved.status_code == 200
    assert saved.json() == [foreign]


@pytest.mark.parametrize("method", ["GET", "PATCH", "DELETE"])
def test_malformed_uuid_returns_422(client, seed_trip, stored_trip, method):
    saved = seed_trip()
    kwargs = {"json": {"title": "Invalid ID"}} if method == "PATCH" else {}
    response = client.request(method, f"{BASE}/not-a-uuid", **kwargs)
    assert response.status_code == 422
    assert stored_trip(saved["id"]) == [saved]


@pytest.mark.parametrize("query", [
    {"limit": 0}, {"limit": 101}, {"limit": "invalid"},
    {"offset": -1}, {"offset": "invalid"},
])
def test_invalid_pagination_returns_422(client, query):
    assert client.get(BASE, params=query).status_code == 422


@pytest.mark.parametrize("changes", [
    {"title": " "}, {"title": None}, {"title": "x" * 201},
    {"start_date": "2026-02-30"}, {"start_date": "2026-11-01T00:00:00"},
    {"end_date": "2026-10-31"}, {"budget_min": -1}, {"budget_max": -1},
    {"budget_min": "501"}, {"budget_max": "99"}, {"budget_max": "NaN"},
    {"budget_max": "Infinity"}, {"budget_max": "500.501"},
    {"budget_max": "10000000000"}, {"budget_min": None},
    {"preferred_tags": "cafe"}, {"status": "archived"},
])
def test_invalid_create_does_not_persist(client, payload, changes, rest, users):
    response = client.post(BASE, json={**payload, **changes})
    assert response.status_code == 422
    assert all("input" not in error and "ctx" not in error for error in response.json()["detail"])
    saved = rest.get("trips", params={"user_id": f"eq.{users.owner}", "select": "id"})
    assert saved.status_code == 200
    assert saved.json() == []


@pytest.mark.parametrize("field", ["title", "start_date", "end_date", "budget_min", "budget_max"])
def test_missing_required_field_returns_422(client, payload, field):
    del payload[field]
    assert client.post(BASE, json=payload).status_code == 422
    assert client.get(BASE).json()["items"] == []


def test_client_cannot_choose_owner(client, users, payload):
    response = client.post(BASE, json={**payload, "user_id": users.other})
    assert response.status_code == 422
    assert client.get(BASE).json()["items"] == []


@pytest.mark.parametrize("changes", [
    {}, {"title": " "}, {"title": None}, {"budget_min": -1},
    {"budget_max": "NaN"}, {"budget_max": "Infinity"},
    {"budget_max": "500.501"}, {"budget_max": "10000000000"},
    {"budget_min": "500.51"}, {"budget_max": "99.99"},
    {"start_date": "2026-11-03"}, {"end_date": "2026-10-31"},
    {"end_date": "2026-02-30"}, {"preferred_tags": None},
    {"status": "archived"}, {"estimated_total_cost": "99"},
    {"user_id": "29000000-0000-4000-8000-000000000099"},
])
def test_invalid_update_preserves_database_row(client, seed_trip, stored_trip, changes):
    original = seed_trip()
    response = client.patch(f"{BASE}/{original['id']}", json=changes)
    assert response.status_code == 422
    assert stored_trip(original["id"]) == [original]


@pytest.mark.parametrize("method", ["POST", "PATCH"])
@pytest.mark.parametrize("body", ["broken json", "[]", "null", '{"budget_min": NaN}'])
def test_malformed_body_does_not_change_database(client, seed_trip, stored_trip, method, body):
    original = seed_trip()
    path = BASE if method == "POST" else f"{BASE}/{original['id']}"
    response = client.request(method, path, content=body, headers={"Content-Type": "application/json"})
    assert response.status_code == 422
    assert stored_trip(original["id"]) == [original]
    assert [row["id"] for row in client.get(BASE).json()["items"]] == [original["id"]]


@pytest.mark.parametrize("method,suffix", [
    ("POST", ""), ("GET", ""), ("GET", "/trip"), ("PATCH", "/trip"), ("DELETE", "/trip"),
])
@pytest.mark.parametrize("authorization", ["", "Bearer wrong", "Basic wrong"])
def test_all_crud_routes_require_authorization(
    client, seed_trip, stored_trip, payload, method, suffix, authorization,
):
    original = seed_trip()
    path = BASE + suffix.replace("trip", original["id"])
    kwargs = {"json": payload} if method == "POST" else (
        {"json": {"title": "Unauthorized update"}} if method == "PATCH" else {}
    )
    response = client.request(method, path, headers={"Authorization": authorization}, **kwargs)
    assert response.status_code == 401
    assert response.headers["WWW-Authenticate"] == "Bearer"
    assert stored_trip(original["id"]) == [original]


def test_database_rejects_trip_without_existing_user(rest, users, payload):
    trip_id = str(uuid4())
    query = {"id": f"eq.{trip_id}"}
    try:
        response = rest.post("trips", json={
            **payload, "id": trip_id, "user_id": str(uuid4()),
        })
        assert response.status_code == 409
        assert response.json()["code"] == "23503"
        saved = rest.get("trips", params={**query, "select": "id"})
        assert saved.status_code == 200
        assert saved.json() == []
    finally:
        # Also clean up if a broken/missing FK unexpectedly accepts the insert.
        assert rest.delete("trips", params=query).status_code in (200, 204)


def test_api_handles_missing_user_foreign_key_safely(client, users, monkeypatch, payload, rest):
    missing_owner = str(uuid4())
    monkeypatch.setenv("TRIP_DEMO_USER_ID", missing_owner)
    query = {"user_id": f"eq.{missing_owner}"}
    try:
        response = client.post(BASE, json=payload)
        assert response.status_code == 503
        assert response.json() == {
            "detail": "Trips are temporarily unavailable. Please try again later.",
        }
        saved = rest.get("trips", params={**query, "select": "id"})
        assert saved.status_code == 200
        assert saved.json() == []
    finally:
        assert rest.delete("trips", params=query).status_code in (200, 204)


@pytest.mark.parametrize("changes", [
    {"budget_min": -1}, {"budget_min": 600},
    {"budget_max": "NaN"}, {"end_date": "2026-10-31"},
])
def test_postgresql_enforces_budget_and_date_constraints(rest, users, payload, changes):
    response = rest.post("trips", json={
        **payload, **changes, "id": str(uuid4()), "user_id": users.owner,
    })
    assert response.status_code == 400
    assert response.json()["code"] == "23514"
    saved = rest.get("trips", params={"user_id": f"eq.{users.owner}", "select": "id"})
    assert saved.status_code == 200
    assert saved.json() == []


def test_deleting_user_cascades_only_that_users_trips(rest, users, seed_trip):
    owned = [seed_trip(), seed_trip()]
    foreign = seed_trip(users.other)
    linked = rest.get("trips", params={
        "select": "id,user_id,users!inner(id)", "user_id": f"eq.{users.owner}",
    })
    assert linked.status_code == 200
    assert {row["id"] for row in linked.json()} == {row["id"] for row in owned}
    assert all(row["users"] == {"id": users.owner} for row in linked.json())
    deleted = rest.delete("users", params={"id": f"eq.{users.owner}"})
    assert deleted.status_code in (200, 204)
    remaining = rest.get("trips", params={"user_id": f"eq.{users.owner}", "select": "id"})
    assert remaining.status_code == 200
    assert remaining.json() == []
    retained = rest.get("trips", params={"id": f"eq.{foreign['id']}", "select": "*"})
    assert retained.status_code == 200
    assert retained.json() == [foreign]
