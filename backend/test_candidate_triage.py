"""Offline discovery triage must not turn source claims into approvals."""

import csv
import importlib.util
from pathlib import Path

import pytest

spec = importlib.util.spec_from_file_location(
    "candidate_triage", Path(__file__).resolve().parents[1] / "scripts/audit_destination_candidates.py"
)
triage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(triage)


def write_csv(path, rows):
    fields = sorted(triage.REQUIRED)
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def row(**changes):
    result = dict.fromkeys(triage.REQUIRED, "unknown")
    result.update(source_id="one", name="Cafe", category="cafe", latitude="10.67",
                  longitude="122.95", locality="Bacolod City")
    result.update(changes)
    return result


def test_unverified_matches_and_branches_remain_blocked(tmp_path):
    path = tmp_path / "data.csv"
    write_csv(path, [row(), row(source_id="two", longitude="122.96", verification_status="approved")])
    result = triage.audit(path)
    assert result["classes"] == {"A": 0, "B": 0, "C": 2, "D": 0}
    assert result["same_name_coordinate_groups"] == 0
    assert "repeated_name_not_a_confirmed_duplicate" in result["records"][0]["flags"]


def test_invalid_coordinates_and_uncertain_locality_are_review_flags(tmp_path):
    path = tmp_path / "data.csv"
    write_csv(path, [row(latitude="nan", locality="Talisay")])
    result = triage.audit(path)
    assert result["invalid_coordinate_count"] == 1
    assert "locality_requires_review" in result["records"][0]["flags"]


def test_malformed_csv_is_rejected(tmp_path):
    path = tmp_path / "data.csv"
    path.write_text("name,latitude\nx,1\n", encoding="utf-8")
    with pytest.raises(ValueError, match="required columns"):
        triage.audit(path)


def test_unknown_is_not_present():
    assert not any(triage.present(value) for value in (None, "", "unknown", " NULL "))
    assert triage.present("0")
