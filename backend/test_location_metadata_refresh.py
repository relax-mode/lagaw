"""Offline metadata refresh tests: target gates, concurrency, preservation, reruns."""

import importlib.util
import json
from copy import deepcopy
from pathlib import Path

import httpx
import pytest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("refresh", ROOT / "scripts/refresh_location_metadata.py")
refresh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(refresh)


def mock_client(store, writes):
    def handler(request):
        assert request.method in {"GET", "PATCH"}
        assert request.url.host == "test.invalid"
        if request.method == "GET":
            ids = request.url.params["id"][4:-1].split(",")
            return httpx.Response(200, json=[deepcopy(r) for r in store.values() if r["id"] in ids])
        identifier = request.url.params["id"][3:]
        row = store[identifier]
        for key, condition in request.url.params.items():
            if key == "id":
                continue
            if condition == "is.null":
                assert row[key] is None
            else:
                value = condition[3:]
                assert row[key] == (json.loads(value) if value.startswith("{") else value)
        patch = json.loads(request.content)
        row.update(patch)
        writes.append(deepcopy(patch))
        return httpx.Response(200, json=[deepcopy(row)])
    return httpx.Client(base_url="https://test.invalid", transport=httpx.MockTransport(handler))


def test_refresh_and_repeat_preserve_images_ids_and_other_metadata():
    plan = refresh.load_plan()
    store = {r["id"]: deepcopy(r) for r in plan["baseline"]["development"]}
    before, writes = deepcopy(store), []
    with mock_client(store, writes) as client:
        assert refresh.apply_plan(client, plan, "development")["changed"] == 7
        assert refresh.apply_plan(client, plan, "development")["changed"] == 0
    assert len(writes) == 7 and len(store) == 10
    for identifier, row in store.items():
        for field in ["image_url", "id", "name", "vibe_tags", "category", "typical_visit_duration"]:
            assert row[field] == before[identifier][field]
    for name in ["Panaad Park and Sports Complex", "Negros Occidental Provincial Capitol", "The Negros Museum"]:
        row = next(r for r in store.values() if r["name"] == name)
        assert row == before[row["id"]]


def test_admin_edit_anywhere_blocks_all_writes_during_preflight():
    plan = refresh.load_plan()
    store = {r["id"]: deepcopy(r) for r in plan["baseline"]["development"]}
    store[plan["entries"][-1]["id"]]["estimated_cost_max"] = 999
    writes = []
    with mock_client(store, writes) as client, pytest.raises(refresh.RefreshBlocked):
        refresh.apply_plan(client, plan, "development")
    assert writes == []


def test_stale_conditional_patch_does_not_claim_success():
    plan = refresh.load_plan()
    count = 0
    def handle(request):
        nonlocal count
        count += 1
        if request.method == "GET":
            ids = {e["id"] for e in plan["entries"]}
            return httpx.Response(200, json=[r for r in plan["baseline"]["development"] if r["id"] in ids])
        return httpx.Response(200, json=[])
    with (httpx.Client(base_url="https://test.invalid", transport=httpx.MockTransport(handle)) as client,
          pytest.raises(refresh.RefreshBlocked, match="Concurrent")):
        refresh.apply_plan(client, plan, "development")
    assert count == 2


def test_supplied_coordinates_round_to_database_precision():
    plan = refresh.load_plan()
    coords = [e["proposal"] for e in plan["entries"] if "latitude" in e["proposal"]]
    assert len(coords) == 4
    assert all(round(p["latitude"], 6) == p["latitude"] and round(p["longitude"], 6) == p["longitude"]
               for p in coords)


def test_qualified_sources_and_deferred_reports_are_separate():
    plan = refresh.load_plan()
    assert len(plan["deferred"]) == 2
    assert all(e["qualification"] and e["confidence"].startswith("user_supplied") for e in plan["entries"])
    assert not any(e["name"] in {"Panaad Park and Sports Complex", "Negros Occidental Provincial Capitol"}
                   for e in plan["entries"])


def test_production_requires_same_manifest_development_receipt(tmp_path, monkeypatch):
    monkeypatch.setattr(refresh, "RECEIPT", tmp_path / "absent.json")
    monkeypatch.setattr(httpx, "Client", lambda **kw: pytest.fail("Production networking attempted"))
    assert refresh.main(["--environment", "production", "--execute"]) == 1


def test_sql_is_transactional_repeatable_and_preserves_unmanaged_fields():
    sql = refresh.sql_plan(refresh.load_plan(), "production")
    assert "BEGIN;" in sql and sql.endswith("COMMIT;\n")
    assert sql.count("UPDATE public.locations") == 7
    assert sql.count("RAISE EXCEPTION") == 7
    assert "image_url =" not in sql and "INSERT" not in sql and "DELETE" not in sql
    assert "IS NOT DISTINCT FROM" in sql


def test_offline_dry_run_never_loads_dotenv_or_connects(monkeypatch):
    monkeypatch.setattr("dotenv.load_dotenv", lambda *a, **kw: pytest.fail("dotenv read"))
    monkeypatch.setattr(httpx, "Client", lambda **kw: pytest.fail("network"))
    assert refresh.main(["--environment", "development"]) == 0
