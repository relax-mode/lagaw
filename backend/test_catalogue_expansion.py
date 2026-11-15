"""Offline checks for the insert-only catalogue expansion and deployment gates."""

import hashlib
import importlib.util
import json
from copy import deepcopy
from pathlib import Path

import httpx
import pytest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("catalogue_expansion", ROOT / "scripts/add_catalogue_locations.py")
expansion = importlib.util.module_from_spec(spec)
spec.loader.exec_module(expansion)


def client_for(store, batches, fail=False):
    def handle(request):
        assert request.url.host == "test.invalid"
        if request.method == "GET":
            return httpx.Response(200, json=list(store.values()))
        assert request.method == "POST"  # Never PATCH/DELETE/upsert existing records.
        assert "resolution=merge-duplicates" not in request.headers.get("prefer", "")
        rows = json.loads(request.content)
        batches.append(deepcopy(rows))
        if fail:
            return httpx.Response(409, json={"message": "conflicting identifier"})
        assert not any(row["id"] in store for row in rows)
        store.update({row["id"]: deepcopy(row) for row in rows})
        return httpx.Response(201, json=rows)
    return httpx.Client(base_url="https://test.invalid", transport=httpx.MockTransport(handle))


def test_manifest_contains_exact_requested_values_and_no_images_or_personal_attribution():
    plan = expansion.load_plan()
    rows = {entry["number"]: entry["record"] for entry in plan["entries"]}
    assert len(rows) == 20
    assert (rows[2]["latitude"], rows[2]["longitude"]) == (10.663345, 122.966446)
    assert (rows[13]["estimated_cost_min"], rows[13]["estimated_cost_max"]) == (50, 2800)
    assert rows[20]["estimated_cost_min"] is None and rows[20]["estimated_cost_max"] is None
    assert set(rows[20]["opening_hours"]) == {"tuesday", "thursday", "friday", "saturday", "sunday"}
    assert set(rows[13]["opening_hours"]) == {"friday", "saturday", "sunday"}
    assert all(row["image_url"] is None and "andrew" not in row["description"].lower() for row in rows.values())
    assert rows[17]["opening_hours"]["monday"] == [{"open": "11:00", "close": "23:59"}]


@pytest.mark.parametrize("environment", ["development", "production"])
def test_single_batch_then_noop_preserves_existing_ten(environment):
    plan = expansion.load_plan()
    store = {row["id"]: deepcopy(row) for row in plan["baseline"][environment]}
    baseline, batches = deepcopy(store), []
    with client_for(store, batches) as client:
        assert expansion.apply_plan(client, plan, environment)["inserted"] == 20
        assert expansion.apply_plan(client, plan, environment)["inserted"] == 0
    assert len(store) == 30 and len(batches) == 1 and len(batches[0]) == 20
    assert {identity: store[identity] for identity in baseline} == baseline


def test_preflight_baseline_edit_blocks_before_insert():
    plan = expansion.load_plan()
    store = {row["id"]: deepcopy(row) for row in plan["baseline"]["development"]}
    next(iter(store.values()))["image_url"] = "https://example.invalid/new-photo.jpg"
    batches = []
    with client_for(store, batches) as client, pytest.raises(expansion.ExpansionBlocked, match="changed"):
        expansion.apply_plan(client, plan, "development")
    assert batches == []


def test_preflight_existing_expansion_edit_blocks_before_insert():
    plan = expansion.load_plan()
    store = {row["id"]: deepcopy(row) for row in plan["baseline"]["development"]}
    edited = deepcopy(plan["entries"][0]["record"])
    edited["estimated_cost_max"] = 999
    store[edited["id"]] = edited
    batches = []
    with client_for(store, batches) as client, pytest.raises(expansion.ExpansionBlocked, match="edited"):
        expansion.apply_plan(client, plan, "development")
    assert batches == []


def test_unrecognized_record_including_duplicate_name_blocks_all_writes():
    plan = expansion.load_plan()
    store = {row["id"]: deepcopy(row) for row in plan["baseline"]["development"]}
    other = deepcopy(plan["entries"][0]["record"])
    other["id"] = "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"
    store[other["id"]] = other
    batches = []
    with client_for(store, batches) as client, pytest.raises(expansion.ExpansionBlocked, match="Unrecognized"):
        expansion.apply_plan(client, plan, "development")
    assert batches == []


def test_partial_matching_batch_inserts_only_missing_rows():
    plan = expansion.load_plan()
    store = {row["id"]: deepcopy(row) for row in plan["baseline"]["development"]}
    for entry in plan["entries"][:3]:
        store[entry["record"]["id"]] = deepcopy(entry["record"])
    batches = []
    with client_for(store, batches) as client:
        result = expansion.apply_plan(client, plan, "development")
    assert result["inserted"] == 17 and result["already_present"] == 3
    assert len(batches) == 1 and len(batches[0]) == 17


def test_insert_conflict_is_not_retried_as_an_upsert():
    plan = expansion.load_plan()
    store = {row["id"]: deepcopy(row) for row in plan["baseline"]["development"]}
    before, batches = deepcopy(store), []
    with client_for(store, batches, fail=True) as client, pytest.raises(httpx.HTTPStatusError):
        expansion.apply_plan(client, plan, "development")
    assert store == before and len(batches) == 1


def test_production_gate_rejects_missing_or_stale_development_receipt(tmp_path, monkeypatch):
    path = tmp_path / "receipt.json"
    monkeypatch.setattr(expansion, "RECEIPT", path)
    with pytest.raises(OSError):
        expansion.require_development()
    receipt = {"manifest_sha256": "stale", "first_run": {
        "existing_ten_preserved": True, "total_locations": 30}, "rerun": {"inserted": 0}}
    path.write_text(json.dumps(receipt))
    with pytest.raises(expansion.ExpansionBlocked):
        expansion.require_development()
    receipt["manifest_sha256"] = hashlib.sha256(expansion.MANIFEST.read_bytes()).hexdigest()
    path.write_text(json.dumps(receipt))
    expansion.require_development()


def test_sql_uses_guarded_transaction_and_never_updates_or_deletes():
    sql = expansion.sql_plan(expansion.load_plan(), "production")
    assert sql.startswith("-- Target ONLY production: https://zjnuqqtbapbpudsjbpif.supabase.co")
    assert "BEGIN;" in sql and sql.endswith("COMMIT;\n")
    assert "LOCK TABLE public.locations IN SHARE ROW EXCLUSIVE MODE;" in sql
    assert "jsonb_populate_record(NULL::public.locations, desired)" in sql
    assert "Destination name collision" in sql and "Existing destination changed" in sql
    assert "UPDATE public.locations" not in sql and "DELETE FROM" not in sql


def test_default_mode_is_offline(monkeypatch, capsys):
    def refuse_network(*args, **kwargs):
        raise AssertionError("Offline validation must not construct a network client")
    monkeypatch.setattr(expansion.httpx, "Client", refuse_network)
    assert expansion.main(["--environment", "development"]) == 0
    assert json.loads(capsys.readouterr().out)["writes"] == 0
