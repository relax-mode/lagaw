"""Reproducible cold-start evidence and limits of source catalog relevance."""

from copy import deepcopy

import pytest

from app.recommendations import evaluate_cold_start as suite
from app.recommendations.cold_start_fixtures import DATASET_PATH, build_fixtures


@pytest.fixture(scope="module")
def report():
    return suite.evaluate()


@pytest.mark.parametrize("catalog", ["source_catalog", "controlled"])
@pytest.mark.parametrize("case", build_fixtures()["cases"], ids=lambda row: row["id"])
def test_realistic_cold_start_behavior(report, catalog, case):
    group = next(group for group in report["catalogs"] if group["catalog"] == catalog)
    result = next(row for row in group["cases"] if row["case"] == case["id"])
    assert result["passed"], result
    assert result["interaction_count"] == 0


def test_fixture_and_report_reproduction(report):
    assert suite.read_json(DATASET_PATH) == build_fixtures()
    assert report == suite.evaluate()
    assert report == suite.read_json(suite.ROOT / "docs/evidence/cold-start-evaluation.json")
    assert report["passed"]


def test_catalog_order_does_not_change_evidence(report):
    source = suite.read_json(suite.SOURCE_PATH)
    reversed_report = suite.evaluate(source=list(reversed(source)))
    assert reversed_report["catalogs"] == report["catalogs"]


def test_source_missing_costs_cannot_be_hidden_by_fictional_controls(report):
    assert report["source_catalog_coverage"] == {
        "locations": 10, "active": 10, "known_upper_cost": 1,
        "coordinate_pairs": 6, "nonempty_hours": 2, "tagged": 10,
        "positive_visit_duration": 10,
    }
    source = report["catalogs"][0]
    cafe = next(row for row in source["cases"] if row["case"] == "budget_cafe_solo")
    assert cafe["matching_tag_candidates"] > 0
    assert cafe["eligible_matching_tag_candidates"] == 0
    assert cafe["top_has_requested_tag"] is False
    assert cafe["ineligible_counts"]["unknown_upper_cost"] == 9
    assert {item["name"] for row in source["cases"] for item in row["ranking"]} == {
        "The Negros Museum",
    }


def test_all_empty_source_is_valid():
    report = suite.evaluate(source=[])
    assert all(row["result_count"] == 0 for row in report["catalogs"][0]["cases"])
    # Authored source expectations deliberately flag this coverage regression.
    assert report["passed"] is False


def test_preference_changes_and_budget_bias_are_visible(report):
    rows = {row["case"]: row for row in report["catalogs"][1]["cases"]}
    assert rows["budget_cafe_solo"]["ranking"][0]["name"] == "Fictional budget cafe"
    assert rows["heritage_couple"]["ranking"][0]["name"] == "Fictional heritage gallery"
    assert rows["food_budget"]["ranking"][0]["name"] == rows["food_high_budget"]["ranking"][0]["name"]
    assert rows["food_relaxing_high_budget"]["ranking"][0]["name"] == "Fictional premium dining"
    # Affordable but nonmatching venues can still be returned: no relevance threshold.
    assert rows["very_low_budget_cafe"]["result_count"] == 1
    assert rows["very_low_budget_cafe"]["top_has_requested_tag"] is False


def test_wrong_expected_ranking_causes_cli_failure(monkeypatch, tmp_path):
    dataset = deepcopy(build_fixtures())
    dataset["cases"][0]["expected_top"]["controlled"] = "Wrong expected place"
    actual_evaluate = suite.evaluate
    monkeypatch.setattr(suite, "evaluate", lambda: actual_evaluate(dataset=dataset))
    output = tmp_path / "report.json"
    assert suite.main(["--output", str(output)]) == 1
    assert suite.read_json(output)["passed"] is False


@pytest.mark.parametrize("change", ["revision", "duplicate", "empty"])
def test_invalid_suite_rejected(change):
    dataset = deepcopy(build_fixtures())
    if change == "revision":
        dataset["revision"] = "unsupported"
    elif change == "duplicate":
        dataset["cases"].append(dataset["cases"][0])
    else:
        dataset["cases"] = []
    with pytest.raises(ValueError):
        suite.evaluate(dataset=dataset)


def test_no_environment_or_network_used(monkeypatch):
    def forbidden(*args, **kwargs):
        pytest.fail("Offline evaluator must not use network, environment or training")

    monkeypatch.setattr("os.getenv", forbidden)
    monkeypatch.setattr("dotenv.load_dotenv", forbidden)
    monkeypatch.setattr("httpx.Client", forbidden)
    monkeypatch.setattr("urllib.request.urlopen", forbidden)
    monkeypatch.setattr("app.recommendations.collaborative.train", forbidden)
    assert suite.evaluate()["passed"]
