"""Credential-free boundary and reproducibility checks, discovered by existing CI."""

import json
from pathlib import Path

import pytest
from pydantic import ValidationError

from app.recommendations.contracts import (
    Interaction,
    LocationAttributes,
    Preferences,
    RecommendationRequest,
    RecommendationResponse,
    satisfies_constraints,
    validate_response,
)
from app.recommendations.fixtures import (
    FIXTURE_DIR,
    build_fixtures,
    fixture_id,
    load_request,
)


def read(name):
    return json.loads((FIXTURE_DIR / name).read_text(encoding="utf-8"))


def test_fixture_reproducibility_and_references():
    source = Path(__file__).resolve().parents[1] / "supabase/data/locations.json"
    generated = build_fixtures(json.loads(source.read_text(encoding="utf-8")))
    assert generated == build_fixtures(json.loads(source.read_text(encoding="utf-8")))
    for name, data in generated.items():
        assert read(name) == data, f"Regenerate stale {name}"
    locations = [
        LocationAttributes.model_validate(row) for row in read("locations.json")
    ]
    travelers = [Preferences.model_validate(row) for row in read("travelers.json")]
    events = [Interaction.model_validate(row) for row in read("interactions.json")]
    assert len({row.id for row in locations}) == len(locations)
    assert len({row.user_id for row in travelers}) == len(travelers)
    assert len({row.id for row in events}) == len(events)
    assert {e.interaction_type for e in events} == {
        "left_swipe",
        "right_swipe",
        "save",
        "rating",
    }
    assert all(e.provenance == "synthetic" for e in events)
    assert all(e.user_id in {t.user_id for t in travelers} for e in events)
    assert all(e.location_id in {row.id for row in locations} for e in events)
    assert sum(not any(e.user_id == t.user_id for e in events) for t in travelers) == 2


@pytest.mark.parametrize("case", read("evaluation_cases.json"), ids=lambda c: c["id"])
def test_evaluation_inputs_and_eligible_examples(case):
    request = RecommendationRequest.model_validate(case["input"])
    assert (
        RecommendationRequest.model_validate_json(request.model_dump_json()) == request
    )
    eligible = {
        row.id
        for row in request.locations
        if satisfies_constraints(request.preferences, row)
    }
    rejected = {
        event.location_id
        for event in request.interactions
        if event.interaction_type == "left_swipe"
    }
    expected = set(case["expected"]["eligible_examples"])
    assert expected <= {str(value) for value in eligible - rejected}
    if case["id"] == "empty_result":
        assert eligible == set()
    assert validate_response(request, RecommendationResponse(items=[])).items == []


@pytest.mark.parametrize(
    "changes",
    [
        {"budget_min": "501"},
        {"budget_max": "-1"},
        {"budget_max": "NaN"},
        {"budget_max": "1.001"},
        {"group_type": "unsupported"},
        {"preferred_tags": ["Not normalized"]},
        {"max_distance_km": 1},
        {"unknown": True},
        {"max_visit_duration_minutes": 0},
    ],
)
def test_invalid_preferences(changes):
    data = load_request().preferences.model_dump(mode="json") | changes
    with pytest.raises(ValidationError):
        Preferences.model_validate(data)


@pytest.mark.parametrize(
    "changes",
    [
        {"rating_value": "6"},
        {"rating_value": "0"},
        {"created_at": "2026-10-25T00:00:00"},
        {"provenance": "unknown"},
        {"interaction_value": "Infinity"},
        {"interaction_type": "rating", "rating_value": None},
    ],
)
def test_invalid_interactions(changes):
    with pytest.raises(ValidationError):
        Interaction.model_validate(read("interactions.json")[0] | changes)


def test_request_rejects_duplicate_and_foreign_events():
    data = load_request("budget_cafe").model_dump(mode="json")
    data["locations"].append(data["locations"][0])
    with pytest.raises(ValidationError):
        RecommendationRequest.model_validate(data)
    data = load_request("budget_cafe").model_dump(mode="json")
    data["interactions"][0]["user_id"] = fixture_id("other-user")
    with pytest.raises(ValidationError):
        RecommendationRequest.model_validate(data)


@pytest.mark.parametrize(
    "score,reason",
    [(1.1, "match"), (-0.1, "match"), (float("nan"), "match"), (0.5, " ")],
)
def test_invalid_output_fields(score, reason):
    with pytest.raises(ValidationError):
        RecommendationResponse(
            items=[
                {
                    "location_id": fixture_id("location:Free park test variant"),
                    "recommendation_score": score,
                    "recommendation_reason": reason,
                }
            ]
        )


def result(location_id, score=0.8):
    return {
        "location_id": location_id,
        "recommendation_score": score,
        "recommendation_reason": "Matches the selected travel tags.",
    }


def test_output_boundary_rejects_invalid_results():
    request = load_request()
    park = fixture_id("location:Free park test variant")
    museum = fixture_id("location:The Negros Museum")
    valid = RecommendationResponse(items=[result(park)])
    assert validate_response(request, valid) == valid
    for rows in [
        [result(park), result(park)],
        [result(fixture_id("unknown"))],
        [result(fixture_id("location:Inactive cafe test variant"))],
        [result(park, 0.2), result(museum, 0.8)],
        [result(fixture_id("location:Premium dining test variant"))],
    ]:
        with pytest.raises(ValueError):
            validate_response(request, RecommendationResponse(items=rows))
    request.limit = 1
    with pytest.raises(ValueError):
        validate_response(
            request, RecommendationResponse(items=[result(park), result(museum)])
        )


def test_constraint_unknowns_and_exclusions_fail_closed():
    request = load_request("accessibility_indoor")
    cafe = next(
        row for row in request.locations if row.name == "Budget cafe test variant"
    )
    assert satisfies_constraints(request.preferences, cafe)
    for changes in [
        {"step_free_access": None},
        {"setting": None},
        {"estimated_cost_max": None},
        {"suitable_group_types": []},
    ]:
        changed = LocationAttributes.model_validate(cafe.model_dump() | changes)
        assert not satisfies_constraints(request.preferences, changed)
    request.preferences.excluded_location_ids = [cafe.id]
    with pytest.raises(ValueError):
        validate_response(request, RecommendationResponse(items=[result(cafe.id)]))
    request = load_request("budget_cafe")
    left = next(
        e.location_id
        for e in request.interactions
        if e.interaction_type == "left_swipe"
    )
    with pytest.raises(ValueError):
        validate_response(request, RecommendationResponse(items=[result(left)]))


def test_distance_and_duration_boundaries():
    request = load_request("distance_and_duration")
    park = next(
        row for row in request.locations if row.name == "Free park test variant"
    )
    assert satisfies_constraints(request.preferences, park)
    for changes in [
        {"coordinates": None},
        {"coordinates": {"latitude": 0, "longitude": 0}},
        {"typical_visit_duration": None},
        {"typical_visit_duration": 31},
    ]:
        changed = LocationAttributes.model_validate(park.model_dump() | changes)
        assert not satisfies_constraints(request.preferences, changed)


@pytest.mark.parametrize(
    "changes",
    [
        {"estimated_cost_min": "101", "estimated_cost_max": "100"},
        {"estimated_cost_max": "Infinity"},
        {"typical_visit_duration": 0},
        {"coordinates": {"latitude": 91, "longitude": 0}},
    ],
)
def test_invalid_location_attributes(changes):
    with pytest.raises(ValidationError):
        LocationAttributes.model_validate(read("locations.json")[0] | changes)
