"""Offline HTTP generation contract and persistence boundary failures."""

from copy import deepcopy
from unittest.mock import Mock
from uuid import UUID, uuid4

import httpx
import pytest

from app.database import DatabaseUnavailable
from app.itinerary_database import (
    ItineraryConflict,
    ItineraryDatabase,
    ItineraryMissing,
    ItineraryState,
)
from app.itinerary_planner import WEEKDAYS
from app.trip_item_schemas import TripItemResponse
from test_trip_recommendations import OWNER, TRIP, harness  # noqa: F401 - Reuse isolated API fixture.

URL = f"/api/v1/trips/{TRIP}/generate-itinerary"
OPTIONS = {"recommendations": {"party_size": 2, "planned_visits": 2}, "pace": "moderate"}


@pytest.fixture
def generation(harness, monkeypatch):  # noqa: F811 - Imported pytest fixture.
    api, state = harness
    for row in state.locations:
        row["opening_hours"] = {day: [{"open": "09:00", "close": "18:00"}] for day in WEEKDAYS}
    state.store = Mock()
    state.store.snapshot.return_value = ItineraryState(trip=state.trip, revision="a" * 32, items=[])

    def save(owner, snapshot, options, visits, locations):
        assert owner == UUID(OWNER)
        catalog = {location.id: location for location in locations}
        items = [TripItemResponse(**visit.model_dump(), id=uuid4(), trip_id=snapshot.trip.id,
                                  location=catalog[visit.location_id]) for visit in visits]
        return ItineraryState(trip=snapshot.trip.model_copy(update={
            "estimated_total_cost": sum(visit.estimated_cost for visit in visits),
        }), revision="b" * 32, items=items)

    state.store.save.side_effect = save
    monkeypatch.setattr("app.itinerary_generation.ItineraryDatabase", lambda client: state.store)
    yield api, state


def test_success_uses_saved_trip_and_validated_adapter_and_one_save(generation):
    api, state = generation
    response = api.post(URL, json=OPTIONS)
    assert response.status_code == 200
    data = response.json()
    assert data["timezone"] == "Asia/Manila" and data["revision"] == "b" * 32
    assert data["estimated_total_cost"] == "260.00"
    assert len(data["items"]) == 2 and all(i["recommendation_reason"] for i in data["items"])
    assert data["items"][1]["arrival_time"] == "09:45:00"
    state.store.save.assert_called_once()


def test_existing_items_require_confirmation_before_model_or_catalog(generation):
    api, state = generation
    first = api.post(URL, json=OPTIONS).json()
    snapshot = state.store.snapshot.return_value
    snapshot.items = [TripItemResponse.model_validate(first["items"][0])]
    state.requests.clear()
    state.store.save.reset_mock()
    response = api.post(URL, json=OPTIONS)
    assert response.status_code == 409
    assert response.json()["detail"]["revision"] == "a" * 32
    assert response.json()["detail"]["code"] == "replacement_confirmation_required"
    assert state.requests == []
    state.store.save.assert_not_called()


def test_explicit_confirmation_and_stale_revision(generation):
    api, _state = generation
    for revision, status in (("b" * 32, 409), ("a" * 32, 200)):
        response = api.post(URL, json={**OPTIONS, "replace_existing": True, "expected_revision": revision})
        assert response.status_code == status


@pytest.mark.parametrize("failure,status", [(ItineraryMissing, 404), (ItineraryConflict, 409),
                                            (DatabaseUnavailable, 503)])
def test_snapshot_and_atomic_save_errors_are_sanitized(generation, failure, status):
    api, state = generation
    state.store.snapshot.side_effect = failure
    response = api.post(URL, json=OPTIONS)
    assert response.status_code == status
    state.store.save.assert_not_called()
    state.store.snapshot.side_effect = None
    state.store.save.side_effect = failure
    assert api.post(URL, json=OPTIONS).status_code == status


@pytest.mark.parametrize("change,status", [
    ({"budget_max": "1.00", "budget_min": "0.00"}, 409),
    ({"transportation_mode": "unknown"}, 422), ({"end_date": "2027-11-02"}, 422),
    ({"group_type": None}, 422),
])
def test_impossible_or_unsupported_saved_trip_never_saves(generation, change, status):
    api, state = generation
    snapshot = state.store.snapshot.return_value.model_dump()
    snapshot["trip"].update(change)
    state.store.snapshot.return_value = ItineraryState.model_validate(snapshot)
    response = api.post(URL, json=OPTIONS)
    assert response.status_code == status
    state.store.save.assert_not_called()


@pytest.mark.parametrize("model_result", [
    {"items": []}, {"items": [{"location_id": str(uuid4()), "recommendation_score": "bad",
                               "recommendation_reason": "Malformed output"}]},
])
def test_empty_or_malformed_results_never_save(generation, model_result):
    api, state = generation
    state.engine = lambda request: model_result
    response = api.post(URL, json=OPTIONS)
    assert response.status_code == (409 if not model_result["items"] else 503)
    state.store.save.assert_not_called()


def test_unavailable_hours_and_insufficient_time_never_save(generation):
    api, state = generation
    for row in state.locations:
        row["opening_hours"] = {}
    assert api.post(URL, json=OPTIONS).status_code == 409
    state.store.save.assert_not_called()
    for row in state.locations:
        row["opening_hours"] = {day: [{"open": "09:00", "close": "18:00"}] for day in WEEKDAYS}
        row["typical_visit_duration"] = 181
    assert api.post(URL, json={**OPTIONS, "duration": "morning"}).status_code == 409
    state.store.save.assert_not_called()


@pytest.mark.parametrize("body", [
    {}, {**OPTIONS, "replace_existing": True}, {**OPTIONS, "expected_revision": "a" * 32},
    {**OPTIONS, "user_id": OWNER}, {**OPTIONS, "pace": "invalid"},
    {"recommendations": {"party_size": 2, "planned_visits": 101, "limit": 100}},
])
def test_invalid_generation_requests_are_sanitized_before_database(generation, body):
    api, state = generation
    response = api.post(URL, json=body)
    assert response.status_code == 422
    assert all(set(error) == {"loc", "msg", "type"} for error in response.json()["detail"])
    state.store.snapshot.assert_not_called()
    assert state.requests == []


def test_generation_requires_bearer(generation):
    api, state = generation
    assert api.post(URL, json=OPTIONS, headers={"Authorization": ""}).status_code == 401
    state.store.snapshot.assert_not_called()


@pytest.mark.parametrize("status,body,exception", [
    (409, {"code": "PT409"}, ItineraryConflict),
    (404, {"code": "PT404"}, ItineraryMissing),
    (404, {"code": "PGRST202", "message": "Private details"}, DatabaseUnavailable),
    (200, None, ItineraryMissing), (500, {}, DatabaseUnavailable),
    (200, {"trip": {}}, DatabaseUnavailable), (200, [], DatabaseUnavailable),
])
def test_rpc_failure_mapping_without_provider_diagnostics(status, body, exception):
    with (
        httpx.Client(base_url="https://offline.invalid/", transport=httpx.MockTransport(
            lambda request: httpx.Response(status, content=b"null") if body is None else httpx.Response(status, json=body),
        )) as client,
        pytest.raises(exception),
    ):
        ItineraryDatabase(client).snapshot(OWNER, TRIP)


def test_rpc_rejects_cross_owner_trip_and_cross_trip_items(generation):
    _, state = generation
    snapshot = state.store.snapshot.return_value.model_dump(mode="json")
    for change in ({"user_id": str(uuid4())}, {"id": str(uuid4())}):
        bad = deepcopy(snapshot)
        bad["trip"].update(change)
        with (
            httpx.Client(base_url="https://offline.invalid/", transport=httpx.MockTransport(
                lambda request, value=bad: httpx.Response(200, json=value),
            )) as client,
            pytest.raises(DatabaseUnavailable),
        ):
            ItineraryDatabase(client).snapshot(OWNER, TRIP)
