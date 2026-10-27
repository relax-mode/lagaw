"""The CI evaluation gate must fail on quality regressions and pass otherwise."""

import copy
import json
from pathlib import Path

from compare_evaluation import compare

BASELINE = json.loads(
    (Path(__file__).resolve().parents[1] / "docs/evidence/week3-evaluation.json").read_text(encoding="utf-8")
)


def test_identical_report_holds_quality():
    lines, regressions = compare(BASELINE, copy.deepcopy(BASELINE))
    assert regressions == []
    assert "**Quality held:** no case, field check or metric regressed." in lines


def test_newly_failing_extraction_case_is_a_regression():
    current = copy.deepcopy(BASELINE)
    current["extraction"]["cases"][0]["passed"] = False
    _, regressions = compare(BASELINE, current)
    assert any(current["extraction"]["cases"][0]["id"] in message for message in regressions)


def test_missing_case_and_fewer_field_checks_are_regressions():
    current = copy.deepcopy(BASELINE)
    removed = current["content"]["cases"].pop()
    current["extraction"]["field_checks_passed"] -= 1
    _, regressions = compare(BASELINE, current)
    assert any(f"`{removed['id']}` missing" in message for message in regressions)
    assert any("field checks fell" in message for message in regressions)


def test_lower_recommendation_metric_is_a_regression():
    current = copy.deepcopy(BASELINE)
    current["hybrid"]["summary"]["hybrid"]["recall_at_3"] -= 0.1
    _, regressions = compare(BASELINE, current)
    assert any("hybrid recall_at_3 fell" in message for message in regressions)


def test_prompt_change_is_reported_without_failing_when_quality_holds():
    current = copy.deepcopy(BASELINE)
    current["identifiers"]["prompt_sha256"] = "changed"
    lines, regressions = compare(BASELINE, current)
    assert regressions == []
    assert any("`prompt_sha256`" in line for line in lines)
