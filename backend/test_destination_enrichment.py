"""S4-06 repeatable enrichment evidence and dry-run regression tests.

All fixtures are offline. Nothing connects to a hosted Supabase database.
"""

import importlib.util
import json
from copy import deepcopy
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
script = ROOT / "scripts/plan_destination_enrichment.py"
spec = importlib.util.spec_from_file_location("s406_enrichment", script)
planner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(planner)

SEED = json.loads((ROOT / "supabase/data/locations.json").read_text(encoding="utf-8"))
MANIFEST = json.loads(
    (ROOT / "supabase/data/destination-enrichment-s4-06.json").read_text(encoding="utf-8")
)
MUSEUM = next(row for row in SEED if row["name"] == "The Negros Museum")


def approved_fixture():
    """Synthetic approval ONLY; never included in committed manifest."""
    manifest = deepcopy(MANIFEST)
    item = manifest["candidates"][0]
    item["approval"] = {
        "approved": True,
        "reviewed_by": "synthetic-ci-reviewer",
        "reviewed_on": "2026-10-31",
        "operator_confirmation_ref": "synthetic-private-fixture-not-real",
    }
    item["status"] = "approved"
    return manifest, item


def test_manifest_is_source_checked_and_none_are_authorized():
    assert len(SEED) == 10
    items = planner.validate_manifest(MANIFEST, SEED)
    assert len(items) == 4
    assert all(not c["approval"]["approved"] for c in items)
    assert all(c["sources"] for c in items)
    assert all(c["checked_on"] == "2026-10-31" for c in items)
    assert {c["name"] for c in items} <= {row["name"] for row in SEED}


def test_no_sql_generated_from_current_unapproved_manifest():
    with pytest.raises(planner.EnrichmentError, match="No operator-confirmed"):
        planner.sql_plan(MANIFEST, SEED)


def test_simulated_application_is_idempotent_and_preserves_other_fields():
    manifest, approved = approved_fixture()
    planner.validate_manifest(manifest, SEED)
    original = deepcopy(MUSEUM)
    first, changed = planner.apply_if_unchanged(original, approved)
    assert changed is True
    assert first["opening_hours"] == approved["proposal"]["opening_hours"]
    assert first["estimated_cost_max"] == 150
    assert first["name"] == original["name"]
    assert first["image_url"] == original["image_url"]
    assert first["vibe_tags"] == original["vibe_tags"]
    assert original == MUSEUM
    second, changed_again = planner.apply_if_unchanged(first, approved)
    assert second == first
    assert changed_again is False


def test_administrator_edit_causes_abort_not_overwrite():
    _, approved = approved_fixture()
    edited = deepcopy(MUSEUM)
    edited["estimated_cost_max"] = 999
    with pytest.raises(planner.EnrichmentError, match="changed since review"):
        planner.apply_if_unchanged(edited, approved)
    assert edited["estimated_cost_max"] == 999


def test_guarded_sql_is_print_only_transaction_and_compares_all_touched_fields():
    manifest, approved = approved_fixture()
    sql = planner.sql_plan(manifest, SEED)
    assert sql.startswith("-- S4-06 REVIEW ONLY")
    assert "BEGIN;" in sql and sql.endswith("COMMIT;\\n".replace("\\n", "\n"))
    assert f"id = '{approved['id']}'::uuid" in sql
    assert "opening_hours IS NOT DISTINCT FROM" in sql
    assert "estimated_cost_min IS NOT DISTINCT FROM 70" in sql
    assert "estimated_cost_max IS NOT DISTINCT FROM 100" in sql
    assert "estimated_cost_min = 120" in sql
    assert "estimated_cost_max = 150" in sql
    assert "RAISE EXCEPTION 'S4-06 location is missing or changed since approval'" in sql
    assert "DO $s406_0$" in sql
    assert "END;\\n$s406_0$;".replace("\\n", "\n") in sql
    assert "INSERT" not in sql.upper() and "DELETE" not in sql.upper()


@pytest.mark.parametrize("change", [
    {"approval": {"approved": True}},
    {"status": "approved"},
    {"proposal": {"estimated_cost_min": 0}},
    {"expected": {"estimated_cost_min": None}},
    {"proposal": {"coordinates": [10, 122]}},
])
def test_unreviewed_or_invalid_candidate_fails_closed(change):
    manifest = deepcopy(MANIFEST)
    item = manifest["candidates"][0]
    item.update(change)
    with pytest.raises(planner.EnrichmentError):
        planner.validate_manifest(manifest, SEED)


@pytest.mark.parametrize("value", [-1, 2.123, "NaN", "Infinity", True, 10000000000])
def test_invalid_cost_rejected(value):
    with pytest.raises(planner.EnrichmentError):
        planner._money(value)


def test_verified_zero_requires_explicit_free_evidence():
    manifest, _ = approved_fixture()
    item = manifest["candidates"][0]
    item["proposal"]["estimated_cost_min"] = 0
    with pytest.raises(planner.EnrichmentError, match="Zero cost"):
        planner.validate_manifest(manifest, SEED)
    item["approval"]["explicit_free_admission_verified"] = True
    planner.validate_manifest(manifest, SEED)


@pytest.mark.parametrize("bad", [
    {"sunday": [{"open": "24:00", "close": "23:00"}]},
    {"sunday": [{"open": "09:00", "close": "09:00"}]},
    {"sunday": [{"open": "19:00", "close": "09:00"}]},
    {"sunday": [{"open": "09:00", "close": "13:00"},
                {"open": "12:00", "close": "14:00"}]},
    {"someday": [{"open": "09:00", "close": "17:00"}]},
    {},
])
def test_unusable_hours_are_rejected(bad):
    with pytest.raises(planner.EnrichmentError):
        planner._hours(bad)


def test_missing_map_pair_and_invalid_coordinates_rejected():
    for data in ({"latitude": 10.0}, {"longitude": 122.0}):
        with pytest.raises(planner.EnrichmentError):
            planner._validate_pair(data, "latitude", "longitude")
    for value in (-91, 91, True, None):
        with pytest.raises(planner.EnrichmentError):
            planner._validate_field("latitude", value)


def test_duplicate_or_unknown_destination_is_rejected():
    manifest = deepcopy(MANIFEST)
    manifest["candidates"].append(deepcopy(manifest["candidates"][0]))
    with pytest.raises(planner.EnrichmentError):
        planner.validate_manifest(manifest, SEED)
    manifest["candidates"].pop()
    manifest["candidates"][0]["name"] = "Fictional production venue"
    with pytest.raises(planner.EnrichmentError):
        planner.validate_manifest(manifest, SEED)


def test_no_mutation_of_source_manifest_by_validation_or_sql():
    source = deepcopy(MANIFEST)
    seed = deepcopy(SEED)
    planner.validate_manifest(MANIFEST, SEED)
    assert source == MANIFEST and seed == SEED
