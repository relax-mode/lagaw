"""Guarded, qualified metadata refresh; offline unless --execute is explicit."""

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))
sys.path.insert(0, str(ROOT / "scripts"))

from app.schemas import Location
from destination_images import admin_headers
from plan_destination_enrichment import _hours, _money, _sql_literal

MANIFEST = ROOT / "supabase/data/location-metadata-refresh-2026-11-15.json"
RECEIPT = ROOT / "docs/evidence/location-metadata-development-2026-11-15.json"
TARGETS = {"development": "https://vnpkyvtbupnquvirzlzp.supabase.co",
           "production": "https://zjnuqqtbapbpudsjbpif.supabase.co"}
ALLOWED = {"latitude", "longitude", "opening_hours", "estimated_cost_min",
           "estimated_cost_max", "description"}


class RefreshBlocked(ValueError):
    pass


def load_plan():
    plan = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if plan.get("schema_version") != 1 or len(plan.get("entries", [])) != 7:
        raise RefreshBlocked("Unexpected plan shape.")
    for environment in TARGETS:
        baseline = {r["id"]: r for r in plan["baseline"][environment]}
        if len(baseline) != 10 or len({e["id"] for e in plan["entries"]}) != 7:
            raise RefreshBlocked("Ambiguous identities.")
        for entry in plan["entries"]:
            patch = entry["proposal"]
            old = baseline[entry["id"]]
            if (entry["name"] != old["name"] or not patch or set(patch) - ALLOWED
                    or set(patch) != set(entry["expected"][environment])
                    or not entry.get("sources") or not entry.get("qualification")):
                raise RefreshBlocked("Invalid proposal or provenance.")
            for key, value in patch.items():
                if entry["expected"][environment][key] != old.get(key):
                    raise RefreshBlocked("Expected values differ from baseline.")
                if key != "description" and old.get(key) not in (None, {}):
                    raise RefreshBlocked("Only missing metadata may be filled.")
                if key == "opening_hours":
                    _hours(value)
                elif key.startswith("estimated_cost_"):
                    _money(value)
            if ("latitude" in patch) != ("longitude" in patch):
                raise RefreshBlocked("Coordinate pair incomplete.")
            if ("estimated_cost_min" in patch) != ("estimated_cost_max" in patch):
                raise RefreshBlocked("Cost pair incomplete.")
            if patch.get("estimated_cost_min", 0) > patch.get("estimated_cost_max", 0):
                raise RefreshBlocked("Costs out of order.")
            Location.model_validate(old | patch)
    return plan


def snapshot(client, entries):
    response = client.get("/rest/v1/locations", params={
        "id": "in.(" + ",".join(e["id"] for e in entries) + ")", "select": "*",
    })
    response.raise_for_status()
    rows = response.json()
    if not isinstance(rows, list) or len(rows) != len(entries):
        raise RefreshBlocked("Incomplete target inventory.")
    indexed = {r["id"]: r for r in rows}
    if len(indexed) != len(entries) or any(indexed[e["id"]]["name"] != e["name"] for e in entries):
        raise RefreshBlocked("Target identity mismatch.")
    return indexed


def matching(row, fields):
    return all(row.get(k) == v for k, v in fields.items())


def apply_plan(client, plan, environment):
    entries = plan["entries"]
    before = snapshot(client, entries)
    pending = []
    for entry in entries:
        row = before[entry["id"]]
        if matching(row, entry["proposal"]):
            continue
        if not matching(row, entry["expected"][environment]):
            raise RefreshBlocked("A target was edited; reconcile before writing.")
        pending.append(entry)
    changed = 0
    for entry in pending:
        params = {"id": "eq." + entry["id"], "name": "eq." + entry["name"]}
        for key, value in entry["expected"][environment].items():
            if value is None:
                params[key] = "is.null"
            elif isinstance(value, dict):
                params[key] = "eq." + json.dumps(value, separators=(",", ":"))
            else:
                params[key] = "eq." + str(value)
        response = client.patch("/rest/v1/locations", params=params,
                                headers={"Prefer": "return=representation"}, json=entry["proposal"])
        response.raise_for_status()
        rows = response.json()
        if (not isinstance(rows, list) or len(rows) != 1 or rows[0].get("id") != entry["id"]
                or not matching(rows[0], entry["proposal"])):
            raise RefreshBlocked("Concurrent edit or unexpected write result; inspect state.")
        changed += 1
    after = snapshot(client, entries)
    for entry in entries:
        row = after[entry["id"]]
        if not matching(row, entry["proposal"]):
            raise RefreshBlocked("Readback differs from proposal.")
        if any(row.get(k) != v for k, v in before[entry["id"]].items() if k not in entry["proposal"]):
            raise RefreshBlocked("Unmanaged field changed; inspect before continuing.")
    return {"changed": changed, "unchanged": len(entries) - changed,
            "unmanaged_fields_preserved": True}


def sql_plan(plan, environment):
    lines = [f"-- Target ONLY {environment}: {TARGETS[environment]}",
             "-- Review qualified estimates and select the correct Supabase project before executing.",
             "BEGIN;"]
    for i, entry in enumerate(plan["entries"]):
        identity = f"id = '{entry['id']}'::uuid AND name = {_sql_literal(entry['name'], 'name')}"
        def predicate(fields):
            return " AND ".join(f"{k} IS NOT DISTINCT FROM {_sql_literal(v, k)}" for k, v in fields.items())
        proposed, old = entry["proposal"], entry["expected"][environment]
        settings = ", ".join(f"{k} = {_sql_literal(v, k)}" for k, v in proposed.items())
        lines += [f"DO $refresh_{i}$", "BEGIN",
                  f"  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE {identity} AND {predicate(proposed)}) THEN",
                  f"    UPDATE public.locations SET {settings} WHERE {identity} AND {predicate(old)};",
                  "    IF NOT FOUND THEN RAISE EXCEPTION 'Metadata target missing or edited'; END IF;",
                  "  END IF;", f"END; $refresh_{i}$;"]
    return "\n".join(lines + ["COMMIT;", ""])


def require_development():
    receipt = json.loads(RECEIPT.read_text(encoding="utf-8"))
    if (receipt.get("manifest_sha256") != hashlib.sha256(MANIFEST.read_bytes()).hexdigest()
            or receipt.get("rerun", {}).get("changed") != 0
            or receipt.get("first_run", {}).get("unmanaged_fields_preserved") is not True):
        raise RefreshBlocked("Matching development verification is required.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--environment", required=True, choices=TARGETS)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--execute", action="store_true")
    mode.add_argument("--emit-sql", action="store_true")
    args = parser.parse_args(argv)
    try:
        plan = load_plan()
        if args.environment == "production" and (args.execute or args.emit_sql):
            require_development()
        if args.emit_sql:
            print(sql_plan(plan, args.environment), end="")
        elif not args.execute:
            print(json.dumps({"environment": args.environment, "proposed_rows": len(plan["entries"]),
                              "deferred": plan["deferred"], "writes": 0}, indent=2))
        else:
            from dotenv import load_dotenv
            load_dotenv(ROOT / ".env", override=False)
            if args.environment == "development":
                if os.environ.get("SUPABASE_URL", "").rstrip("/") != TARGETS["development"]:
                    raise RefreshBlocked("Configured target is not development.")
                key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
            else:
                key = os.environ.get("LOCATION_METADATA_PRODUCTION_KEY")
            if not key:
                raise RefreshBlocked("Required target credential is absent; .env was not changed.")
            with httpx.Client(base_url=TARGETS[args.environment], headers=admin_headers(key),
                              timeout=20, follow_redirects=False, trust_env=False) as client:
                result = apply_plan(client, plan, args.environment)
                rerun = apply_plan(client, plan, args.environment)
            receipt = {"environment": args.environment, "first_run": result, "rerun": rerun,
                       "manifest_sha256": hashlib.sha256(MANIFEST.read_bytes()).hexdigest()}
            if args.environment == "development":
                RECEIPT.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
            print(json.dumps(receipt))
        return 0
    except (ValueError, KeyError, TypeError, OSError, httpx.HTTPError):
        print("Metadata refresh blocked. Check the target credential, baseline and source decisions. "
              "Inspect live state before retrying; earlier row updates may have succeeded.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
