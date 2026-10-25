"""Behavioral evaluation of the baseline, using the S3-01 fixtures."""

import json
from pathlib import Path
from uuid import UUID

import pytest
from pydantic import ValidationError

from app.recommendations.content_based import (
    ContentBasedRecommender,
    recommend,
    score_location,
)
from app.recommendations.contracts import (
    LocationAttributes,
    Preferences,
    RecommendationRequest,
    RecommendationResponse,
    validate_response,
)
from app.recommendations.evaluate_content import evaluate
from app.recommendations.fixtures import FIXTURE_DIR, load_request
from app.recommendations.fixtures import fixture_id as fixture_string


def fixture_id(label):
    return UUID(fixture_string(label))


CASES = json.loads((FIXTURE_DIR / "evaluation_cases.json").read_text(encoding="utf-8"))
EXPECTED_TOP = {
    "budget_cafe": "Budget cafe test variant",
    "heritage": "The Negros Museum",
    "family_nature": "Free park test variant",
    "premium_food": "Premium dining test variant",
    "cold_start": "Free park test variant",
    "cold_start_no_tags": "Free park test variant",
    "accessibility_indoor": "Budget cafe test variant",
    "distance_and_duration": "Free park test variant",
    "empty_result": None,
    "explicit_exclusion": "Free park test variant",
}


@pytest.mark.parametrize("case", CASES, ids=lambda c: c["id"])
def test_fixture_behavior(case):
    request = RecommendationRequest.model_validate(case["input"])
    before = request.model_dump_json()
    response = recommend(request)
    assert response == validate_response(request, response)
    assert (
        RecommendationResponse.model_validate_json(response.model_dump_json())
        == response
    )
    assert request.model_dump_json() == before
    assert (
        response == recommend(request) == ContentBasedRecommender().recommend(request)
    )
    expected = EXPECTED_TOP[case["id"]]
    if expected is None:
        assert response.items == []
    else:
        assert response.items[0].location_id == fixture_id("location:" + expected)
    assert set(case["expected"]["eligible_examples"]) <= {
        str(item.location_id) for item in response.items
    }


def changed_request(request, **preferences):
    data = request.model_dump(mode="json")
    data["preferences"].update(preferences)
    return RecommendationRequest.model_validate(data)


def test_tags_change_ranking_at_same_budget():
    request = changed_request(
        load_request("cold_start"), preferred_tags=["cafe", "relaxing"]
    )
    assert recommend(request).items[0].location_id == fixture_id(
        "location:Budget cafe test variant"
    )
    nature = changed_request(request, preferred_tags=["nature"])
    assert recommend(nature).items[0].location_id == fixture_id(
        "location:Free park test variant"
    )


def test_categories_change_ranking_without_tags():
    request = changed_request(
        load_request(), preferred_tags=[], preferred_categories=["museum"]
    )
    assert recommend(request).items[0].location_id == fixture_id(
        "location:The Negros Museum"
    )
    request = changed_request(request, preferred_categories=["cafe"])
    assert recommend(request).items[0].location_id == fixture_id(
        "location:Budget cafe test variant"
    )


def test_component_normalization_and_duplicate_tags():
    request = changed_request(
        load_request(),
        preferred_tags=["cafe", "nature", "cafe"],
        preferred_categories=["cafe"],
    )
    cafe = next(
        row for row in request.locations if row.name == "Budget cafe test variant"
    )
    explanation = score_location(request.preferences, cafe)
    assert explanation.tag_score == 0.5
    assert explanation.category_score == 1
    assert explanation.budget_score == pytest.approx(0.8)
    assert explanation.score == pytest.approx(0.67)  # .60*.5 + .25*1 + .15*.8
    assert explanation.matched_tags == ("cafe",)
    assert explanation.group_match


def test_budget_ceiling_headroom_and_zero_budget():
    request = changed_request(load_request("premium_food"), budget_max="1199")
    dining = fixture_id("location:Premium dining test variant")
    assert dining not in {item.location_id for item in recommend(request).items}
    request = changed_request(request, budget_max="1200")
    assert recommend(request).items[0].location_id == dining
    request = changed_request(
        request, preferred_tags=[], preferred_categories=[], budget_max="1500"
    )
    rows = recommend(request).items
    assert rows[0].location_id == fixture_id("location:Free park test variant")
    assert rows[0].recommendation_score == 1
    assert next(
        row.recommendation_score for row in rows if row.location_id == dining
    ) == pytest.approx(0.2)
    free = changed_request(request, budget_max="0")
    assert len(recommend(free).items) == 1
    assert recommend(free).items[0].recommendation_score == 1
    # A budget minimum is not a minimum spend requirement.
    minimum = changed_request(request, budget_min="500")
    assert recommend(minimum) == recommend(request)


def test_unknown_cost_and_group_mismatch_are_removed():
    request = load_request()
    cafe = next(
        row for row in request.locations if row.name == "Budget cafe test variant"
    )
    for changes in [
        {"estimated_cost_max": None},
        {"suitable_group_types": ["couple"]},
        {"is_active": False},
    ]:
        invalid = LocationAttributes.model_validate(cafe.model_dump() | changes)
        assert score_location(request.preferences, invalid) is None
        data = request.model_dump(mode="json")
        data["locations"] = [invalid.model_dump(mode="json")]
        assert recommend(RecommendationRequest.model_validate(data)).items == []


@pytest.mark.parametrize("case_id", ["accessibility_indoor", "distance_and_duration"])
def test_missing_optional_location_facts_fail_required_constraints(case_id):
    request = load_request(case_id)
    data = request.model_dump(mode="json")
    for row in data["locations"]:
        row.update(
            coordinates=None,
            step_free_access=None,
            setting=None,
            typical_visit_duration=None,
        )
    assert recommend(RecommendationRequest.model_validate(data)).items == []


def test_empty_catalog_and_omitted_optional_preferences():
    preferences = Preferences(
        user_id=fixture_id("empty-user"),
        preferred_tags=[],
        budget_min="0",
        budget_max="100",
        group_type="solo",
    )
    assert (
        recommend(RecommendationRequest(preferences=preferences, locations=[])).items
        == []
    )
    request = load_request()
    minimal = {
        key: value
        for key, value in request.preferences.model_dump(mode="json").items()
        if key
        in {"user_id", "preferred_tags", "budget_min", "budget_max", "group_type"}
    }
    response = recommend(
        RecommendationRequest(preferences=minimal, locations=request.locations)
    )
    assert response.items


@pytest.mark.parametrize("limit", [1, 2, 100])
def test_limit_and_stable_order_after_catalog_reversal(limit):
    request = load_request("premium_food")
    request.limit = limit
    forward = recommend(request)
    assert len(forward.items) == min(limit, 4)
    request.locations.reverse()
    assert recommend(request) == forward


def test_ties_use_uuid_not_catalog_order():
    request = changed_request(
        load_request(), preferred_tags=[], preferred_categories=[]
    )
    cafe = next(
        row for row in request.locations if row.name == "Budget cafe test variant"
    )
    first = LocationAttributes.model_validate(
        cafe.model_dump() | {"id": fixture_id("tie:first")}
    )
    second = LocationAttributes.model_validate(
        cafe.model_dump() | {"id": fixture_id("tie:second")}
    )
    request.locations = [first, second]
    result = recommend(request)
    assert [str(row.location_id) for row in result.items] == sorted(
        [str(first.id), str(second.id)]
    )
    request.locations.reverse()
    assert recommend(request) == result


def test_duplicate_candidates_rejected_even_after_model_mutation():
    request = load_request()
    request.locations.append(request.locations[0])
    with pytest.raises(ValidationError, match="duplicate location IDs"):
        recommend(request)


def test_left_swipes_excluded_positive_history_does_not_change_content_scores():
    request = load_request("heritage")
    with_history = recommend(request)
    data = request.model_dump(mode="json")
    data["interactions"] = [
        event
        for event in data["interactions"]
        if event["interaction_type"] == "left_swipe"
    ]
    assert recommend(RecommendationRequest.model_validate(data)) == with_history
    event = dict(data["interactions"][0])
    event["location_id"] = str(with_history.items[0].location_id)
    data["interactions"] = [event]
    assert event["location_id"] not in {
        str(row.location_id)
        for row in recommend(RecommendationRequest.model_validate(data)).items
    }


def test_reason_is_truthful_and_bounded_with_maximum_tags():
    request = load_request()
    tags = ["t" + str(index).zfill(49) for index in range(30)]
    request = changed_request(request, preferred_tags=tags)
    request.locations = [
        LocationAttributes.model_validate(
            request.locations[10].model_dump() | {"vibe_tags": tags}
        )
    ]
    row = recommend(request).items[0]
    assert len(row.recommendation_reason) <= 500
    assert "(+27 more)" in row.recommendation_reason
    assert "category: not specified" in row.recommendation_reason
    assert "group: solo" in row.recommendation_reason


def test_saved_evaluation_evidence_matches_current_behavior():
    path = (
        Path(__file__).resolve().parents[1]
        / "docs/evidence/content-based-evaluation.json"
    )
    saved = json.loads(path.read_text(encoding="utf-8"))
    saved.pop("benchmark")
    current = evaluate()
    assert saved == current == evaluate()
    assert current["case_count"] == 10
    assert all(
        case["eligible_examples_returned"]
        and case["empty_result_correct"]
        and case["reproducible"]
        for case in current["cases"]
    )
