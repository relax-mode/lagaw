"""Conservative offline triage of untrusted candidate CSV; never produces imports."""

import argparse
import collections
import csv
import hashlib
import json
import math
from pathlib import Path

UNKNOWN = {"", "unknown", "null", "none"}
REQUIRED = {"source_id", "name", "category", "latitude", "longitude", "locality",
            "operating_status", "verification_status", "last_verified_at"}


def present(value):
    return value is not None and value.strip().casefold() not in UNKNOWN


def coordinates(row):
    try:
        lat, lon = float(row["latitude"]), float(row["longitude"])
        return math.isfinite(lat) and math.isfinite(lon) and -90 <= lat <= 90 and -180 <= lon <= 180
    except (ValueError, TypeError, KeyError):
        return False


def audit(path):
    raw = Path(path).read_bytes()
    with Path(path).open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle, strict=True)
        if not reader.fieldnames or not REQUIRED.issubset(reader.fieldnames):
            raise ValueError("CSV is missing required columns")
        if len(set(reader.fieldnames)) != len(reader.fieldnames):
            raise ValueError("CSV contains duplicate columns")
        rows = list(reader)
    if any(None in row or any(value is None for value in row.values()) for row in rows):
        raise ValueError("CSV row has a different field count than its header")
    ids = collections.Counter(row["source_id"].strip() for row in rows if present(row["source_id"]))
    names = collections.Counter(row["name"].strip().casefold() for row in rows if present(row["name"]))
    exact = collections.Counter((row["name"].strip().casefold(), row["latitude"], row["longitude"])
                                for row in rows if present(row["name"]))
    classifications = []
    for index, row in enumerate(rows, 2):
        flags = []
        if not present(row["source_id"]) or ids[row["source_id"].strip()] > 1:
            flags.append("missing_or_duplicate_source_id")
        if not present(row["name"]):
            flags.append("missing_name")
        if not coordinates(row):
            flags.append("invalid_coordinates")
        if row["locality"].strip().casefold() not in {"bacolod", "bacolod city"}:
            flags.append("locality_requires_review")
        if names[row["name"].strip().casefold()] > 1:
            flags.append("repeated_name_not_a_confirmed_duplicate")
        if exact[(row["name"].strip().casefold(), row["latitude"], row["longitude"])] > 1:
            flags.append("same_name_and_coordinates_review")
        if "adult_entertainment" in row["category"].casefold():
            flags.append("category_requires_suitability_review")
        # Discovery data is not evidence of current operation, rights or approval.
        classifications.append({"row": index, "source_id": row["source_id"], "class": "C",
                                "reason": "Unverified discovery record; independent identity, current operation, visitor hours, cost, entrance and approval required",
                                "flags": flags})
    return {"sha256": hashlib.sha256(raw).hexdigest(), "total": len(rows),
            "classes": {"A": 0, "B": 0, "C": len(rows), "D": 0},
            "present_fields": {key: sum(present(row.get(key)) for row in rows)
                               for key in reader.fieldnames},
            "status_counts": dict(collections.Counter(row["verification_status"] for row in rows)),
            "localities": dict(collections.Counter(row["locality"] for row in rows)),
            "duplicate_source_ids": sum(count - 1 for count in ids.values() if count > 1),
            "repeated_name_groups": sum(count > 1 for count in names.values()),
            "same_name_coordinate_groups": sum(count > 1 for count in exact.values()),
            "invalid_coordinate_count": sum(not coordinates(row) for row in rows),
            "records": classifications}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv_file")
    parser.add_argument("--records", action="store_true", help="include row-level triage")
    args = parser.parse_args()
    result = audit(args.csv_file)
    if not args.records:
        del result["records"]
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
