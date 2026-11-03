"""S4-06: review-only, offline destination enrichment planner.

Reads the committed seed and a dated evidence manifest. There is NO database,
HTTP, environment/secret, or deployment access in this script. Approved updates
can be printed as guarded PostgreSQL statements; executing them is a separate,
explicitly authorized operation.
"""

import argparse
import json
import re
from copy import deepcopy
from datetime import date
from decimal import Decimal, InvalidOperation
from pathlib import Path
from urllib.parse import urlsplit
from uuid import UUID

ROOT = Path(__file__).resolve().parents[1]
SEED = ROOT / "supabase/data/locations.json"
MANIFEST = ROOT / "supabase/data/destination-enrichment-s4-06.json"
EDITABLE = frozenset({
    "opening_hours", "estimated_cost_min", "estimated_cost_max",
    "latitude", "longitude", "typical_visit_duration",
})
WEEKDAYS = frozenset({
    "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
})
TIME = re.compile(r"^(?:[01][0-9]|2[0-3]):[0-5][0-9]$")
ISO_DATE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$")


class EnrichmentError(ValueError):
    """Fail closed for unreviewed evidence or stale original values."""


def _date(value):
    if not isinstance(value, str) or not ISO_DATE.fullmatch(value):
        raise EnrichmentError("Evidence dates must be YYYY-MM-DD.")
    try:
        date.fromisoformat(value)
    except ValueError as exc:
        raise EnrichmentError("Evidence date is invalid.") from exc


def _money(value):
    if value is None:
        return
    if isinstance(value, bool) or not isinstance(value, (int, float, str)):
        raise EnrichmentError("Cost must be a decimal PHP amount or null.")
    try:
        decimal = Decimal(str(value))
    except InvalidOperation as exc:
        raise EnrichmentError("Cost is not a decimal.") from exc
    if not decimal.is_finite() or decimal < 0 or decimal.as_tuple().exponent < -2:
        raise EnrichmentError("Cost is negative, non-finite or overprecise.")
    if decimal >= Decimal(10000000000):
        raise EnrichmentError("Cost exceeds numeric(12,2).")


def _hours(value):
    if not isinstance(value, dict) or not value or not set(value).issubset(WEEKDAYS):
        raise EnrichmentError("Visiting hours require named weekdays.")
    for windows in value.values():
        if not isinstance(windows, list) or not windows:
            raise EnrichmentError("Each supplied weekday needs visiting windows.")
        previous = None
        for window in windows:
            if (not isinstance(window, dict) or set(window) != {"open", "close"}
                    or not all(isinstance(t, str) and TIME.fullmatch(t)
                               for t in window.values())
                    or window["open"] >= window["close"]
                    or (previous is not None and window["open"] < previous)):
                raise EnrichmentError("Visiting windows must be ordered, nonoverlapping HH:MM.")
            previous = window["close"]


def _validate_field(key, value):
    if key == "opening_hours":
        _hours(value)
    elif key in {"estimated_cost_min", "estimated_cost_max"}:
        _money(value)
    elif key in {"latitude", "longitude"}:
        bound = 90 if key == "latitude" else 180
        if value is None or type(value) not in {float, int} or not -bound <= value <= bound:
            raise EnrichmentError("Invalid geographic coordinate.")
    elif key == "typical_visit_duration" and (
        type(value) is not int or value <= 0 or value > 1440
    ):
        raise EnrichmentError("Visit duration must be positive and plausible.")


def _validate_pair(values, left, right):
    if (left in values) != (right in values):
        raise EnrichmentError(f"{left} and {right} must be updated together.")
    if left in values and (values[left] is None) != (values[right] is None):
        raise EnrichmentError(f"Only complete {left}/{right} pairs are allowed.")
    if (left == "estimated_cost_min" and left in values
            and values[left] is not None
            and Decimal(str(values[left])) > Decimal(str(values[right]))):
        raise EnrichmentError("Minimum cannot exceed maximum.")


def _source_supported(candidate):
    sources = candidate.get("sources")
    if not isinstance(sources, list) or not sources:
        raise EnrichmentError("Each candidate needs a source trail.")
    for source in sources:
        if not isinstance(source, dict) or not all(
            isinstance(source.get(field), str) and source[field].strip()
            for field in ("publisher", "url", "claim", "confidence")
        ):
            raise EnrichmentError("Missing evidence provenance.")
        _date(source.get("checked_on"))
        url = urlsplit(source["url"])
        if (url.scheme != "https" or not url.netloc or url.username
                or url.password or any(c.isspace() for c in source["url"])):
            raise EnrichmentError("Evidence sources must use plain public HTTPS URLs.")


def validate_manifest(manifest, seed):
    """Return validated candidates in manifest order, never modifying inputs."""
    if manifest.get("schema_version") != 1 or manifest.get("timezone") != "Asia/Manila":
        raise EnrichmentError("Unsupported manifest version or timezone.")
    _date(manifest.get("checked_on"))
    rows = {row["name"]: row for row in seed}
    if len(rows) != len(seed) or not all("name" in row for row in seed):
        raise EnrichmentError("Ambiguous original catalogue.")
    seen = set()
    candidates = manifest.get("candidates")
    if not isinstance(candidates, list):
        raise EnrichmentError("Manifest candidates must be a list.")
    for item in candidates:
        if not isinstance(item, dict):
            raise EnrichmentError("Invalid candidate.")
        name = item.get("name")
        identity = item.get("id")
        if not isinstance(name, str) or not isinstance(identity, str):
            raise EnrichmentError("Candidate identity missing.")
        try:
            UUID(identity)
        except ValueError as exc:
            raise EnrichmentError("Invalid location ID.") from exc
        if (name not in rows or identity in seen
                or identity != SEED_IDS.get(name)):
            raise EnrichmentError("Candidate is unknown or duplicated.")
        seen.add(identity)
        _date(item.get("checked_on"))
        _source_supported(item)
        proposed, expected = item.get("proposal"), item.get("expected")
        if not isinstance(proposed, dict) or not isinstance(expected, dict):
            raise EnrichmentError("Candidate needs expected and proposed field maps.")
        if set(proposed) != set(expected) or not set(proposed).issubset(EDITABLE):
            raise EnrichmentError("Proposed fields must exactly match permitted old-value checks.")
        for k, v in proposed.items():
            _validate_field(k, v)
            if expected[k] != rows[name].get(k):
                raise EnrichmentError("Expected values differ from committed source baseline.")
        for values in (proposed, expected):
            _validate_pair(values, "estimated_cost_min", "estimated_cost_max")
            _validate_pair(values, "latitude", "longitude")
        approval = item.get("approval", {})
        if not isinstance(approval, dict) or type(approval.get("approved")) is not bool:
            raise EnrichmentError("Each candidate needs an explicit approval decision.")
        if approval["approved"]:
            if item.get("status") != "approved" or not proposed:
                raise EnrichmentError("Approved changes need a nonempty reviewed proposal.")
            if not all(isinstance(approval.get(field), str) and approval[field].strip()
                       for field in ("reviewed_by", "operator_confirmation_ref")):
                raise EnrichmentError("Approval needs a reviewer and operator confirmation.")
            _date(approval.get("reviewed_on"))
            if item["checked_on"] > approval["reviewed_on"]:
                raise EnrichmentError("Approval cannot precede source inspection.")
            if (any(proposed.get(key) == 0 for key in
                    ("estimated_cost_min", "estimated_cost_max") if key in proposed)
                    and approval.get("explicit_free_admission_verified") is not True):
                raise EnrichmentError("Zero cost needs affirmative free-entry confirmation.")
        elif item.get("status") == "approved":
            raise EnrichmentError("Approval status and decision disagree.")
    return candidates


# Fixed identities from the reviewed, deterministic S1-02 seed migration.
SEED_IDS = {
    "The Negros Museum": "61bf94ab-6ec0-5ec3-8451-b575ee06169e",
    "Negros Forest Park": "b3783066-7484-5917-a09b-404974974880",
    "Capitol Park and Lagoon": "af80a358-d1ad-529f-84b3-ff1e591e041f",
    "San Sebastian Cathedral": "1a3bca09-5532-5de6-8587-2440c4e5830d",
}


def apply_if_unchanged(row, item):
    """Model the SQL compare-and-swap: unchanged, applied or stale/conflict."""
    old, new = item["expected"], item["proposal"]
    updated = deepcopy(row)
    if all(updated.get(key) == value for key, value in new.items()):
        return updated, False
    if any(updated.get(key) != value for key, value in old.items()):
        raise EnrichmentError("Source row changed since review; manual reconciliation needed.")
    updated.update(deepcopy(new))
    return updated, True


def _sql_literal(value, kind):
    if kind == "opening_hours":
        return "'" + json.dumps(value, sort_keys=True, separators=(",", ":")).replace("'", "''") + "'::jsonb"
    if value is None:
        return "NULL"
    if kind in {"estimated_cost_min", "estimated_cost_max", "latitude", "longitude", "typical_visit_duration"}:
        return str(value)
    return "'" + value.replace("'", "''") + "'"


def sql_plan(manifest, seed):
    """Print-only SQL; guards every field and stable ID, never touches live DB."""
    candidates = validate_manifest(manifest, seed)
    approved = [c for c in candidates if c["approval"]["approved"]]
    if not approved:
        raise EnrichmentError("No operator-confirmed and reviewed updates; no SQL generated.")
    statements = [
        "-- S4-06 REVIEW ONLY; DO NOT EXECUTE WITHOUT EXPLICIT DEPLOYMENT APPROVAL.",
        "-- Update fails closed on stale field values. Re-running an applied update is a no-op.",
        "BEGIN;",
    ]
    for i, item in enumerate(approved):
        old, new = item["expected"], item["proposal"]
        label = f"$s406_{i}$"
        predicate = (f"id = '{item['id']}'::uuid AND "
                     f"name = {_sql_literal(item['name'], 'name')}")
        before = " AND ".join(
            f"{key} IS NOT DISTINCT FROM {_sql_literal(old[key], key)}"
            for key in sorted(old)
        )
        after = " AND ".join(
            f"{key} IS NOT DISTINCT FROM {_sql_literal(new[key], key)}"
            for key in sorted(new)
        )
        settings = ", ".join(
            f"{key} = {_sql_literal(new[key], key)}" for key in sorted(new)
        )
        statements.extend([
            f"-- Verified candidate: {item['name']} ({item['id']})",
            f"DO {label}",
            "BEGIN",
            f"  IF NOT EXISTS (SELECT 1 FROM public.locations WHERE {predicate} AND {after}) THEN",
            f"    UPDATE public.locations SET {settings} WHERE {predicate} AND {before};",
            "    IF NOT FOUND THEN",
            "      RAISE EXCEPTION 'S4-06 location is missing or changed since approval';",
            "    END IF;",
            "  END IF;",
            "END;",
            f"{label};",
        ])
    statements.append("COMMIT;")
    return chr(10).join(statements) + chr(10)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--emit-sql", action="store_true",
                        help="PRINT reviewed, guarded SQL only; never connect or apply")
    args = parser.parse_args()
    seed = json.loads(SEED.read_text(encoding="utf-8"))
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    try:
        candidates = validate_manifest(manifest, seed)
        if args.emit_sql:
            print(sql_plan(manifest, seed), end="")
        else:
            print(json.dumps({
                "checked_on": manifest["checked_on"],
                "catalogue_rows_in_seed": len(seed),
                "candidates": len(candidates),
                "approved_updates": sum(c["approval"]["approved"] for c in candidates),
                "blocked_candidates": [
                    {"name": c["name"], "status": c["status"]} for c in candidates
                    if not c["approval"]["approved"]
                ],
                "production_writes": 0,
                "three_stop_itinerary_proved": False,
            }, indent=2))
    except EnrichmentError as exc:
        parser.exit(2, f"Enrichment blocked: {exc}" + chr(10))


if __name__ == "__main__":
    main()
