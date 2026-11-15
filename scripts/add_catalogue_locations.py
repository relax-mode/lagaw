"""Insert the fixed twenty-location expansion; offline unless --execute is used."""

import argparse
import hashlib
import json
import os
import sys
from datetime import UTC, datetime
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))
sys.path.insert(0, str(ROOT / "scripts"))

from app.preference_vocabulary import TravelTag
from app.schemas import Location
from destination_images import admin_headers
from plan_destination_enrichment import _hours

MANIFEST = ROOT / "supabase/data/location-expansion-2026-11-15.json"
RECEIPT = ROOT / "docs/evidence/location-expansion-development-2026-11-15.json"
TARGETS = {"development": "https://vnpkyvtbupnquvirzlzp.supabase.co",
           "production": "https://zjnuqqtbapbpudsjbpif.supabase.co"}
COLUMNS = tuple(Location.model_fields)


class ExpansionBlocked(ValueError):
    pass


def load_plan():
    from typing import get_args

    plan = json.loads(MANIFEST.read_text(encoding="utf-8"))
    records = [entry["record"] for entry in plan["entries"]]
    if (plan.get("schema_version") != 1 or len(records) != 20
            or len({r["id"] for r in records}) != 20
            or len({r["name"].strip().casefold() for r in records}) != 20):
        raise ExpansionBlocked("Unexpected or duplicate target records.")
    allowed_tags = set(get_args(TravelTag))
    for entry in plan["entries"]:
        row = entry["record"]
        Location.model_validate(row)
        _hours(row["opening_hours"])
        if (set(row) != set(COLUMNS) or row["image_url"] is not None
                or row["is_active"] is not True or not entry.get("provenance")
                or not set(row["vibe_tags"]).issubset(allowed_tags)
                or "andrew" in row["description"].casefold()
                or "supplied" in row["description"].casefold()
                or (row["latitude"] is None) != (row["longitude"] is None)
                or (row["estimated_cost_min"] is None) != (row["estimated_cost_max"] is None)):
            raise ExpansionBlocked("Invalid image, attribution, tags or paired fields.")
        if (row["estimated_cost_min"] is not None
                and row["estimated_cost_min"] > row["estimated_cost_max"]):
            raise ExpansionBlocked("Cost range is reversed.")
        if any(round(row[k], 6) != row[k] for k in ("latitude", "longitude") if row[k] is not None):
            raise ExpansionBlocked("Coordinates exceed database precision.")
    for environment in TARGETS:
        baseline = plan["baseline"][environment]
        if len(baseline) != 10 or len({r["id"] for r in baseline}) != 10:
            raise ExpansionBlocked("Unexpected baseline inventory.")
        if ({r["id"] for r in baseline} & {r["id"] for r in records}
                or {r["name"].strip().casefold() for r in baseline}
                & {r["name"].strip().casefold() for r in records}):
            raise ExpansionBlocked("Expansion overlaps baseline destinations.")
    return plan


def snapshot(client):
    response = client.get("/rest/v1/locations", params={
        "select": ",".join(COLUMNS), "order": "id.asc", "limit": 1000,
    })
    response.raise_for_status()
    rows = response.json()
    if not isinstance(rows, list) or len(rows) >= 1000:
        raise ExpansionBlocked("Unexpected or truncated location inventory.")
    for row in rows:
        Location.model_validate(row)
    if len({r["id"] for r in rows}) != len(rows):
        raise ExpansionBlocked("Duplicate location identity.")
    return {r["id"]: r for r in rows}


def pending_records(inventory, plan, environment):
    baseline = {r["id"]: r for r in plan["baseline"][environment]}
    desired = {e["record"]["id"]: e["record"] for e in plan["entries"]}
    if set(inventory) - (set(baseline) | set(desired)):
        raise ExpansionBlocked("Unrecognized inventory; reconcile before inserting.")
    if any(inventory.get(identity) != row for identity, row in baseline.items()):
        raise ExpansionBlocked("Existing destination changed; no inserts attempted.")
    if any(identity in inventory and inventory[identity] != row for identity, row in desired.items()):
        raise ExpansionBlocked("An expansion record was edited; do not overwrite it.")
    return [row for identity, row in desired.items() if identity not in inventory]


def apply_plan(client, plan, environment):
    before = snapshot(client)
    pending = pending_records(before, plan, environment)
    if pending:
        # One plain bulk INSERT, not an upsert: PostgREST executes the batch in
        # one transaction and a conflicting UUID aborts rather than overwrites.
        response = client.post("/rest/v1/locations", json=pending,
                               headers={"Prefer": "return=representation"})
        response.raise_for_status()
        rows = response.json()
        if (not isinstance(rows, list) or len(rows) != len(pending)
                or {r["id"]: r for r in rows} != {r["id"]: r for r in pending}):
            raise ExpansionBlocked("Unexpected insert result; inspect live state before retrying.")
    after = snapshot(client)
    expected = {r["id"]: r for r in plan["baseline"][environment]}
    expected.update({e["record"]["id"]: e["record"] for e in plan["entries"]})
    if after != expected:
        raise ExpansionBlocked("Readback differs; inspect live state before retrying.")
    return {"inserted": len(pending), "already_present": 20 - len(pending),
            "total_locations": len(after), "existing_ten_preserved": True,
            "new_images_null": True}


def require_development():
    receipt = json.loads(RECEIPT.read_text(encoding="utf-8"))
    if (receipt.get("manifest_sha256") != hashlib.sha256(MANIFEST.read_bytes()).hexdigest()
            or receipt.get("first_run", {}).get("existing_ten_preserved") is not True
            or receipt.get("first_run", {}).get("total_locations") != 30
            or receipt.get("rerun", {}).get("inserted") != 0):
        raise ExpansionBlocked("Matching development verification is required.")


def sql_plan(plan, environment):
    def literal(value):
        return "'" + json.dumps(value, ensure_ascii=False, indent=2).replace("'", "''") + "'::jsonb"

    records = [e["record"] for e in plan["entries"]]
    baseline = plan["baseline"][environment]
    all_ids = [r["id"] for r in baseline + records]
    columns = ", ".join(COLUMNS)
    return "\n".join([
        f"-- Target ONLY {environment}: {TARGETS[environment]}",
        "-- Twenty insertions; images null; existing records must match the captured baseline.",
        "-- Safe reruns accept identical records only. Select the correct project in SQL Editor.",
        "BEGIN;", "LOCK TABLE public.locations IN SHARE ROW EXCLUSIVE MODE;",
        "DO $catalogue_expansion$", "DECLARE expected jsonb; desired jsonb;", "BEGIN",
        "  IF EXISTS (SELECT 1 FROM public.locations WHERE NOT (id = ANY (ARRAY["
        + ",".join("'" + identity + "'::uuid" for identity in all_ids)
        + "]))) THEN RAISE EXCEPTION 'Unrecognized location inventory'; END IF;",
        f"  FOR expected IN SELECT value FROM jsonb_array_elements({literal(baseline)}) LOOP",
        "    IF NOT EXISTS (SELECT 1 FROM public.locations AS existing WHERE existing.id = (expected->>'id')::uuid AND to_jsonb(existing) @> expected) THEN",
        "      RAISE EXCEPTION 'Existing destination changed; transaction aborted';",
        "    END IF;", "  END LOOP;",
        f"  FOR desired IN SELECT value FROM jsonb_array_elements({literal(records)}) LOOP",
        "    IF EXISTS (SELECT 1 FROM public.locations WHERE id = (desired->>'id')::uuid) THEN",
        "      IF NOT EXISTS (SELECT 1 FROM public.locations AS existing WHERE existing.id = (desired->>'id')::uuid AND to_jsonb(existing) @> desired) THEN",
        "        RAISE EXCEPTION 'Expansion record changed; transaction aborted';",
        "      END IF;",
        "    ELSIF EXISTS (SELECT 1 FROM public.locations WHERE lower(btrim(name)) = lower(btrim(desired->>'name'))) THEN",
        "      RAISE EXCEPTION 'Destination name collision; transaction aborted';",
        "    ELSE",
        f"      INSERT INTO public.locations ({columns}) SELECT {columns} FROM jsonb_populate_record(NULL::public.locations, desired);",
        "    END IF;", "  END LOOP;", "END;", "$catalogue_expansion$;", "COMMIT;", "",
    ])


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
            return 0
        if not args.execute:
            print(json.dumps({"environment": args.environment, "proposed_rows": 20, "writes": 0}))
            return 0
        from dotenv import load_dotenv
        load_dotenv(ROOT / ".env", override=False)
        if args.environment == "development":
            if os.environ.get("SUPABASE_URL", "").rstrip("/") != TARGETS["development"]:
                raise ExpansionBlocked("Configured target is not development.")
            key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
        else:
            key = os.environ.get("LOCATION_METADATA_PRODUCTION_KEY")
        if not key:
            raise ExpansionBlocked("Target write credential absent; no networking or writes attempted.")
        with httpx.Client(base_url=TARGETS[args.environment], headers=admin_headers(key),
                          timeout=30, follow_redirects=False, trust_env=False) as client:
            result = apply_plan(client, plan, args.environment)
            rerun = apply_plan(client, plan, args.environment)
        receipt = {"environment": args.environment, "observed_at_utc": datetime.now(UTC).isoformat(),
                   "manifest_sha256": hashlib.sha256(MANIFEST.read_bytes()).hexdigest(),
                   "first_run": result, "rerun": rerun}
        path = RECEIPT if args.environment == "development" else RECEIPT.with_name(
            "location-expansion-production-2026-11-15.json")
        path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(receipt))
        return 0
    except (ValueError, KeyError, TypeError, OSError, httpx.HTTPError):
        print("Catalogue expansion blocked. Check target credentials and expected inventory. "
              "Inspect live state before retrying; no existing records are overwritten.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
