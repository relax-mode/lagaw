"""Deterministic schedules, conservative costs and fail-closed catalog facts."""

from datetime import date, time
from decimal import Decimal
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.itinerary_planner import (
    WEEKDAYS,
    PlanningConflict,
    UnsupportedPlanningTrip,
    opening_intervals,
    plan_itinerary,
    travel,
)
from app.itinerary_schemas import GenerationOptions
from app.trip_recommendation_schemas import TripRecommendation, TripRecommendationResult
from app.trip_schemas import TripResponse
from test_trip_recommendations import location


def trip(**changes):
    return TripResponse.model_validate({
        "id": str(uuid4()), "user_id": str(uuid4()), "title": "Planner fixture",
        "start_date": "2026-11-02", "end_date": "2026-11-03",
        "budget_min": "0.00", "budget_max": "1000.00", "preferred_tags": ["cafe"],
        "group_type": "friends", "transportation_mode": "walking", "status": "draft",
        "estimated_total_cost": None, **changes,
    })


def options(count=2, **changes):
    return GenerationOptions.model_validate({
        "recommendations": {"party_size": 1, "planned_visits": count, "limit": 10}, **changes,
    })


def destination(**changes):
    return TripRecommendation.model_validate({
        "location_id": changes.get("id", str(uuid4())), "recommendation_score": 0.9,
        "recommendation_reason": "Deterministic fixture",
        "location": location(**changes),
    })


def ranked(saved_trip, items):
    # Align association IDs while preserving each deterministic score/reason.
    for item in items:
        item.location_id = item.location.id
    return TripRecommendationResult(
        trip_id=saved_trip.id, items=items,
        budget={"party_size": 1, "planned_visits": 2, "budget_min": 0, "budget_max": 500},
    )


def venue(**changes):
    return destination(id=str(uuid4()), opening_hours={
        day: [{"open": "09:00", "close": "18:00"}] for day in WEEKDAYS
    }, **changes)


def test_order_travel_buffer_scores_and_exact_party_total():
    saved = trip()
    first, second = venue(), venue(latitude=10.671)
    config = options(recommendations={"party_size": 2, "planned_visits": 2})
    visits, total = plan_itinerary(saved, config, ranked(saved, [first, second]))
    assert [v.location_id for v in visits] == [first.location_id, second.location_id]
    assert visits[0].arrival_time == time(9)
    assert visits[0].departure_time == time(9, 30)
    assert visits[1].arrival_time > time(9, 45)  # travel plus moderate pace break
    assert visits[1].estimated_travel_time > 0
    assert all(v.recommendation_reason == "Deterministic fixture" for v in visits)
    assert total == Decimal("200.00") == sum(v.estimated_cost for v in visits)


def test_multiday_first_fit_sorts_chronologically_and_resets_origin():
    saved = trip()
    monday = venue()
    monday.location.opening_hours = {"monday": [{"open": "09:00", "close": "10:00"}]}
    tuesday = venue()
    tuesday.location.opening_hours = {"tuesday": [{"open": "09:00", "close": "10:00"}]}
    visits, _ = plan_itinerary(saved, options(), ranked(saved, [tuesday, monday]))
    assert [(v.day_number, v.visit_order, v.location_id) for v in visits] == [
        (1, 1, monday.location_id), (2, 1, tuesday.location_id),
    ]
    assert all(v.arrival_time == time(9) and v.estimated_travel_time == 0 for v in visits)


@pytest.mark.parametrize("hours", [
    {}, {"monday": []}, {"Monday": [{"open": "09:00", "close": "18:00"}]},
    {"monday": [{"open": "20:00", "close": "02:00"}]},
    {"monday": [{"open": "09:00", "close": "09:00"}]},
    {"monday": [{"open": "9:00", "close": "18:00"}]},
    {"monday": [{"open": "09:00", "close": "24:00"}]},
    {"monday": [{"open": "09:00", "close": "18:00", "holiday": "yes"}]},
    {"monday": [{"open": "09:00", "close": "12:00"}, {"open": "11:00", "close": "14:00"}]},
])
def test_closed_unknown_malformed_and_unsupported_hours_fail_closed(hours):
    saved = trip(end_date="2026-11-02")
    item = venue()
    item.location.opening_hours = hours
    with pytest.raises(PlanningConflict):
        plan_itinerary(saved, options(1), ranked(saved, [item]))


def test_split_hours_wait_and_exact_closing_boundary():
    saved, item = trip(), venue()
    item.location.opening_hours = {"monday": [{"open": "09:00", "close": "09:15"},
                                               {"open": "13:00", "close": "13:30"}]}
    visits, _ = plan_itinerary(saved, options(1), ranked(saved, [item]))
    assert visits[0].arrival_time == time(13) and visits[0].departure_time == time(13, 30)


@pytest.mark.parametrize("changes", [
    {"estimated_cost_max": None}, {"typical_visit_duration": None},
    {"latitude": None, "longitude": None},
])
def test_required_unknown_facts_are_not_treated_as_zero(changes):
    saved = trip()
    with pytest.raises(PlanningConflict):
        plan_itinerary(saved, options(1), ranked(saved, [venue(**changes)]))


def test_insufficient_budget_or_time_does_not_return_partial_plan():
    saved = trip(budget_max="40.00", end_date="2026-11-02")
    with pytest.raises(PlanningConflict) as failure:
        plan_itinerary(saved, options(), ranked(saved, [venue(), venue()]))
    assert failure.value.scheduled == 0
    saved.budget_max = Decimal(1000)
    with pytest.raises(PlanningConflict) as failure:
        plan_itinerary(saved, options(duration="morning"),
                       ranked(saved, [venue(typical_visit_duration=180), venue()]))
    assert failure.value.scheduled == 1


def test_duration_and_pace_apply_without_shortening_visits():
    saved, item = trip(), venue(typical_visit_duration=60)
    visits, _ = plan_itinerary(saved, options(1, duration="afternoon", pace="slow"), ranked(saved, [item]))
    assert visits[0].arrival_time == time(13) and visits[0].departure_time == time(14, 30)


def test_explicit_origin_travel_and_fares_consume_budget():
    saved, item = trip(transportation_mode="public_transport", budget_max="50.00"), venue()
    config = options(1, recommendations={"party_size": 1, "planned_visits": 1,
                                         "origin": {"latitude": 10.68, "longitude": 122.95}})
    with pytest.raises(PlanningConflict):
        plan_itinerary(saved, config, ranked(saved, [item]))
    saved.budget_max = Decimal(1000)
    visits, total = plan_itinerary(saved, config, ranked(saved, [item]))
    minutes, fare = travel((10.68, 122.95), item.location, "public_transport", 1)
    assert minutes > 0 and visits[0].estimated_travel_time == minutes
    assert total == Decimal(50) + fare > Decimal(50)


def test_no_results_and_unsupported_saved_constraints():
    saved = trip()
    with pytest.raises(PlanningConflict, match="no_suitable_recommendations"):
        plan_itinerary(saved, options(1), ranked(saved, []))
    for changes in ({"transportation_mode": None}, {"transportation_mode": "teleport"},
                    {"end_date": "2026-12-03"}):
        with pytest.raises(UnsupportedPlanningTrip):
            plan_itinerary(trip(**changes), options(1), ranked(saved, [venue()]))


@pytest.mark.parametrize("changes", [
    {"replace_existing": True}, {"expected_revision": "a" * 32},
    {"replace_existing": "yes"}, {"expected_revision": "bad"},
    {"recommendations": {"party_size": 1, "planned_visits": 11}},
    {"pace": "relaxed"}, {"duration": "weekend"}, {"user_id": str(uuid4())},
])
def test_invalid_counts_confirmations_and_unknown_fields(changes):
    with pytest.raises(ValidationError):
        options(**changes)


def test_opening_day_is_local_calendar_date():
    assert opening_intervals({"monday": [{"open": "09:00", "close": "10:00"}]},
                             date(2026, 11, 2)) == [(540, 600)]
