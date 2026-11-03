"""Read-only aggregate coverage audit of Lagaw's public active-location endpoints.

Run from repository root:
    python scripts/destination_coverage_audit.py --environment development
    python scripts/destination_coverage_audit.py --environment production

Uses only fixed public HTTPS GET endpoints. Never reads .env, uses credentials,
changes hosted data, or prints individual destination rows.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import UTC, datetime
from decimal import Decimal, InvalidOperation
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import HTTPRedirectHandler, Request, build_opener

ENDPOINTS = {
    "development": "https://lagaw-api-staging-i5kvldluga-as.a.run.app/locations",
    "production": "https://lagaw-api-i5kvldluga-as.a.run.app/locations",
}
PAGE_LIMIT = 100
MAX_PAGES = 100


class NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def finite_decimal(value: object) -> Decimal | None:
    if value is None or isinstance(value, bool):
        return None
    try:
        result = Decimal(str(value))
        return result if result.is_finite() else None
    except (InvalidOperation, ValueError, TypeError):
        return None


def coverage(rows: list[dict]) -> dict:
    counts = {name: 0 for name in (
        "identity_and_address", "category", "vibe_tags", "coordinate_pair",
        "opening_hours", "bounded_cost", "visit_duration", "field_complete_only",
    )}
    for item in rows:
        identity = isinstance(item.get("name"), str) and bool(item["name"].strip())
        identity = identity and isinstance(item.get("address"), str) and bool(item["address"].strip())
        category = isinstance(item.get("category"), str) and bool(item["category"].strip())
        tags = isinstance(item.get("vibe_tags"), list) and bool(item["vibe_tags"])
        lat, lon = finite_decimal(item.get("latitude")), finite_decimal(item.get("longitude"))
        coords = (lat is not None and lon is not None and -90 <= lat <= 90 and -180 <= lon <= 180)
        hours = isinstance(item.get("opening_hours"), dict) and bool(item["opening_hours"])
        lower = finite_decimal(item.get("estimated_cost_min"))
        upper = finite_decimal(item.get("estimated_cost_max"))
        bounded_cost = lower is not None and upper is not None and 0 <= lower <= upper
        duration = finite_decimal(item.get("typical_visit_duration"))
        positive_duration = duration is not None and duration > 0
        conditions = {
            "identity_and_address": identity,
            "category": category,
            "vibe_tags": tags,
            "coordinate_pair": coords,
            "opening_hours": hours,
            "bounded_cost": bounded_cost,
            "visit_duration": positive_duration,
            "field_complete_only": coords and hours and bounded_cost and positive_duration,
        }
        for name, present in conditions.items():
            counts[name] += int(bool(present))
    total = len(rows)
    return {
        "active_location_count": total,
        "field_counts": counts,
        "field_coverage_percent": {
            key: round(value * 100 / total, 1) if total else 0.0
            for key, value in counts.items()
        },
        "caveat": "Field presence does not verify freshness, rights, or itinerary feasibility.",
    }


def fetch_rows(environment: str, opener=None) -> list[dict]:
    """Paginate a fixed public API without any Authorization header or writes."""
    if environment not in ENDPOINTS:
        raise ValueError("Unknown environment")
    opener = opener or build_opener(NoRedirects())
    seen: set[str] = set()
    rows: list[dict] = []
    for page in range(MAX_PAGES):
        url = f"{ENDPOINTS[environment]}?{urlencode({'limit': PAGE_LIMIT, 'offset': page * PAGE_LIMIT})}"
        request = Request(
            url,
            headers={"Accept": "application/json", "User-Agent": "LagawCoverageAudit/1"},
            method="GET",
        )
        with opener.open(request, timeout=15) as response:
            payload = json.load(response)
        if not isinstance(payload, dict) or not isinstance(payload.get("items"), list):
            raise TypeError("Unexpected response shape")
        batch = payload["items"]
        if len(batch) > PAGE_LIMIT:
            raise ValueError("Page exceeds requested limit")
        for item in batch:
            if not isinstance(item, dict) or not isinstance(item.get("id"), str):
                raise TypeError("Invalid destination identity")
            if item["id"] in seen:
                raise ValueError("Duplicate destination across pages")
            seen.add(item["id"])
            rows.append(item)
        if len(batch) < PAGE_LIMIT:
            return rows
    raise ValueError("Maximum pagination reached; no partial report produced")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--environment", choices=sorted(ENDPOINTS), required=True)
    args = parser.parse_args(argv)
    try:
        rows = fetch_rows(args.environment)
    except (HTTPError, URLError, TimeoutError, OSError, TypeError, ValueError, json.JSONDecodeError) as error:
        print(f"Coverage not measured: {type(error).__name__}. No state changed.", file=sys.stderr)
        return 1
    print(json.dumps({
        "environment": args.environment,
        "observed_at_utc": datetime.now(UTC).isoformat(timespec="seconds"),
        "scope": "Public API active destinations only; inactive/private records not measured",
        **coverage(rows),
    }, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
