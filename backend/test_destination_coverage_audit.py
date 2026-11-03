"""Offline security and coverage checks for S4-05 public inventory."""
import importlib.util
import io
import json
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "destination_coverage_audit.py"
SPEC = importlib.util.spec_from_file_location("destination_coverage_audit", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def location(identifier: str) -> dict:
    return {
        "id": identifier,
        "name": "Example venue",
        "address": "Bacolod",
        "category": "museum",
        "vibe_tags": ["heritage"],
        "latitude": 10.67,
        "longitude": 122.95,
        "opening_hours": {"monday": [{"open": "09:00", "close": "17:00"}]},
        "estimated_cost_min": "120",
        "estimated_cost_max": "150",
        "typical_visit_duration": 60,
    }


class FakeOpener:
    def __init__(self, pages):
        self.pages = pages
        self.urls = []

    def open(self, request, timeout):
        assert request.method == "GET"
        assert timeout == 15
        assert "Authorization" not in request.headers
        self.urls.append(request.full_url)
        return io.BytesIO(json.dumps(self.pages[len(self.urls) - 1]).encode())


def test_coverage_counts_unknown_without_inventing_free():
    first, second = location("a"), location("b")
    second.update(latitude=None, longitude=None, opening_hours={},
                  estimated_cost_min=None, estimated_cost_max=None)
    result = MODULE.coverage([first, second])
    assert result["active_location_count"] == 2
    assert result["field_counts"]["bounded_cost"] == 1
    assert result["field_counts"]["coordinate_pair"] == 1
    assert result["field_counts"]["field_complete_only"] == 1
    assert result["field_coverage_percent"]["opening_hours"] == 50.0


def test_invalid_prices_and_boolean_values_not_counted():
    item = location("a")
    for invalid in (True, -1, float("nan")):
        item["estimated_cost_max"] = invalid
        assert MODULE.coverage([item])["field_counts"]["bounded_cost"] == 0


def test_coordinates_use_real_latitude_longitude_bounds():
    item = location("a")
    item.update(latitude=-10, longitude=-122)
    assert MODULE.coverage([item])["field_counts"]["coordinate_pair"] == 1
    item["longitude"] = 190
    assert MODULE.coverage([item])["field_counts"]["coordinate_pair"] == 0


def test_fetch_uses_only_fixed_public_get_endpoint():
    opener = FakeOpener([{"items": [location("a")]}])
    assert len(MODULE.fetch_rows("production", opener)) == 1
    assert opener.urls == [
        "https://lagaw-api-i5kvldluga-as.a.run.app/locations?limit=100&offset=0"
    ]


def test_fetch_rejects_duplicate_ids_across_pages():
    opener = FakeOpener([
        {"items": [location(str(i)) for i in range(100)]},
        {"items": [location("0")]},
    ])
    with pytest.raises(ValueError, match="Duplicate"):
        MODULE.fetch_rows("development", opener)


def test_fetch_rejects_unexpected_payload():
    with pytest.raises(TypeError, match="response shape"):
        MODULE.fetch_rows("production", FakeOpener([{"unrelated": []}]))


def test_fetch_rejects_non_destinations():
    with pytest.raises(TypeError, match="destination identity"):
        MODULE.fetch_rows("development", FakeOpener([{"items": [{"name": "No id"}]}]))


def test_fetch_rejects_unknown_environment():
    with pytest.raises(ValueError, match="Unknown environment"):
        MODULE.fetch_rows("unknown", FakeOpener([]))


def test_coverage_empty_set_is_valid():
    assert MODULE.coverage([])["field_coverage_percent"]["bounded_cost"] == 0.0
