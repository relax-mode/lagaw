"""Versioned offline evaluation acceptance and regression detection."""

import copy
import json

import pytest

import evaluate_week3 as suite


@pytest.mark.parametrize("case", suite.extraction_cases(), ids=lambda case: case["id"])
def test_http_fixture_acceptance_and_saved_data(case):
    result, _ = suite.run_extraction_case(case)
    assert result["passed"], result["failures"]
    assert result["checks"]["saved_trip_unchanged"]
    assert result["checks"]["no_trip_writes"]
    assert result["checks"]["sanitized_response"]


def test_fixture_revision_counts_and_explicit_expected_fields():
    manifest = suite.read_json(suite.MANIFEST)
    cases = suite.extraction_cases()
    assert manifest["fixture_revision"] == "week3-eval-v1"
    assert manifest["live_provider_evaluation"] == "not_performed"
    assert len(cases) == len({case["id"] for case in cases}) == 27
    successes = [case for case in cases if case["status"] == 200]
    assert len(successes) >= 10
    assert {
        "non_travel_input",
        "adversarial_instruction",
        "ambiguous_budget_and_duration",
        "unsupported_tag",
        "conflicting_numeric_budget",
    } <= {case["id"] for case in cases}
    assert {case["provider"]["budget_level"] for case in successes} == {
        "low",
        "medium",
        "high",
        "unspecified",
    }
    for case in successes:
        assert set(case["expected"]) == {
            "preferred_tags",
            "budget_level",
            "duration",
            "pace",
            "budget_min",
            "budget_max",
            "group_type",
        }


def test_bad_expectation_is_reported_as_a_field_failure():
    case = copy.deepcopy(suite.extraction_cases()[0])
    case["expected"]["pace"] = "fast"
    result, _ = suite.run_extraction_case(case)
    assert not result["passed"]
    assert result["failures"] == ["field:pace"]


def test_configuration_is_captured_from_actual_mocked_request():
    _, captured = suite.run_extraction_case(suite.extraction_cases()[0])
    payload = captured[0]["payload"]
    assert payload["model"] == "deepseek-flash"
    assert payload["response_format"] == {"type": "json_object"}
    assert payload["thinking"] == {"type": "disabled"}
    assert payload["max_tokens"] == 512
    assert payload["stream"] is False
    assert "Extract trip preferences only" in payload["messages"][0]["content"]
    assert captured[0]["timeout"] == {
        "connect": 30,
        "read": 30,
        "write": 30,
        "pool": 30,
    }


def test_report_identifiers_and_recommendation_comparison_match_baseline():
    report = suite.run_evaluation()
    saved = suite.read_json(suite.BASELINE)
    # Exclude machine/runtime observations from deterministic baseline comparison.
    assert report["fixture_revision"] == saved["fixture_revision"]
    assert report["identifiers"] == saved["identifiers"], (
        "Prompt/configuration/fixture drift: review baseline"
    )
    assert report["extraction"] == saved["extraction"]
    assert report["content"] == saved["content"]
    for model in ("content", "hybrid"):
        assert report["hybrid"]["summary"][model] == pytest.approx(
            saved["hybrid"]["summary"][model], abs=1e-6
        )
    assert report["hybrid"]["training_digest"] == saved["hybrid"]["training_digest"]
    assert (
        report["extraction"]["field_checks_passed"]
        == report["extraction"]["field_checks_total"]
        == 84
    )
    assert report["extraction"]["passed"] == 27
    assert report["content"]["case_count"] == 10
    assert report["hybrid"]["evaluation_users"] == 24
    assert report["failures"] == []
    assert report["live_provider_evaluation"] == "not_performed"
    serialized = json.dumps(report)
    assert "dummy-week3-key-only" not in serialized
    assert suite.TOKEN not in serialized
    assert suite.PRIVATE not in serialized


def test_cli_returns_failure_and_writes_sanitized_report(monkeypatch, tmp_path):
    output = tmp_path / "results/evaluation.json"
    monkeypatch.setattr(
        suite.sys, "argv", ["evaluate_week3.py", "--output", str(output)]
    )
    monkeypatch.setattr(
        suite,
        "run_evaluation",
        lambda: {
            "extraction": {"passed": 0, "case_count": 1},
            "content": {"case_count": 0},
            "failures": [{"id": "example", "checks": ["field:pace"]}],
        },
    )
    assert suite.main() == 1
    assert suite.read_json(output)["failures"][0]["checks"] == ["field:pace"]
