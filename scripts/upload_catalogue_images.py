"""Upload the reviewed new-location inventory, preserving existing catalogue fields.

Offline by default. --execute --approved-usage authorizes the selected target.
Production requires a matching successful development receipt.
"""

import argparse
import hashlib
import json
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

import httpx
from destination_images import (
    ROOT,
    StorageError,
    admin_headers,
    bucket_configuration,
    development_credentials,
    image_info,
    link_if_empty,
    production_credentials,
    public_url,
    upload_and_verify,
)

INVENTORY = ROOT / "docs/evidence/new-location-image-inventory-2026-11-15.json"
CATALOGUE = ROOT / "supabase/data/location-expansion-2026-11-15.json"


def receipt_path(environment):
    return ROOT / f"docs/evidence/new-location-images-{environment}-2026-11-15.json"


def load_images():
    inventory = json.loads(INVENTORY.read_text("utf-8"))
    catalogue = json.loads(CATALOGUE.read_text("utf-8"))
    records = {e["record"]["id"]: e["record"]["name"] for e in catalogue["entries"]}
    entries = inventory["images"]
    if len(entries) != 32 or {e["location_id"] for e in entries} != set(records):
        raise StorageError("Unexpected image inventory.")
    prepared = []
    for entry in entries:
        path = (ROOT / entry["file"]).resolve()
        if (not path.is_relative_to((ROOT / "docs/destination-images").resolve())
                or entry["name"] != records[entry["location_id"]]):
            raise StorageError("Image path or destination mapping differs.")
        raw, mime, key = image_info(path, UUID(entry["location_id"]))
        if hashlib.sha256(raw).hexdigest() != entry["sha256"]:
            raise StorageError("Inventory image checksum differs.")
        prepared.append((entry, raw, mime, key))
    if len({e["file"] for e in entries}) != len(entries):
        raise StorageError("Duplicate upload files.")
    for identity in records:
        if sum(e["primary"] for e in entries if e["location_id"] == identity) != 1:
            raise StorageError("Each destination requires exactly one main image.")
    return prepared


def snapshot(client):
    response = client.get("/rest/v1/locations", params={
        "select": "*", "order": "id.asc", "limit": 1000,
    })
    if response.status_code != 200:
        raise StorageError("Catalogue inventory failed.")
    rows = response.json()
    if not isinstance(rows, list) or not rows or len(rows) >= 1000:
        raise StorageError("Unexpected catalogue inventory.")
    indexed = {r["id"]: r for r in rows}
    if len(indexed) != len(rows):
        raise StorageError("Duplicate destination IDs.")
    return indexed


def validate_targets(before, prepared, url):
    expected = {}
    for entry, _raw, _mime, key in prepared:
        row = before.get(entry["location_id"])
        if row is None or row["name"] != entry["name"] or row["is_active"] is not True:
            raise StorageError("Destination identity or active state differs.")
        if entry["primary"]:
            desired = public_url(url, key)
            if row["image_url"] not in (None, desired):
                raise StorageError("Existing main image differs; preserved without uploads.")
            expected[entry["location_id"]] = desired
    return expected


def save_receipt(environment, receipt):
    receipt_path(environment).write_text(
        json.dumps(receipt, indent=2, ensure_ascii=False) + "\n", "utf-8",
    )


def run(environment, prepared, digest):
    if environment == "production":
        verified = json.loads(receipt_path("development").read_text("utf-8"))
        if (verified.get("inventory_sha256") != digest or verified.get("complete") is not True
                or len(verified.get("images", [])) != len(prepared)):
            raise StorageError("Matching development verification is required.")
    url, key = (production_credentials() if environment == "production"
                else development_credentials())
    with httpx.Client(base_url=url, headers=admin_headers(key), timeout=30.0,
                      follow_redirects=False, trust_env=False) as client:
        before = snapshot(client)
        expected = validate_targets(before, prepared, url)
        bucket_configuration(client)
        receipt = {
            "environment": environment, "inventory_sha256": digest,
            "started_at": datetime.now(UTC).isoformat(), "complete": False,
            "before": list(before.values()), "images": [],
        }
        save_receipt(environment, receipt)
        for entry, raw, mime, key in prepared:
            public = upload_and_verify(client, url, raw, mime, key)
            if entry["primary"]:
                link_if_empty(client, UUID(entry["location_id"]), public)
            receipt["images"].append({
                "location_id": entry["location_id"], "file": entry["file"],
                "sha256": entry["sha256"], "primary": entry["primary"],
                "url": public, "public_bytes_verified": True,
            })
            save_receipt(environment, receipt)
            print(f"{environment}: verified {len(receipt['images'])}/{len(prepared)} "
                  f"{Path(entry['file']).name}", flush=True)
        after = snapshot(client)
        wanted = {identity: row | ({"image_url": expected[identity]} if identity in expected else {})
                  for identity, row in before.items()}
        if after != wanted:
            raise StorageError("Catalogue readback differs from the intended image-only changes.")
        receipt.update({
            "complete": True, "finished_at": datetime.now(UTC).isoformat(),
            "after": list(after.values()), "all_other_fields_preserved": True,
            "linked_destinations": len(expected),
        })
        save_receipt(environment, receipt)
        print(f"{environment}: all {len(prepared)} images verified; "
              f"{len(expected)} main links verified; other fields preserved.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--environment", choices=("development", "production"),
                        default="development")
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--approved-usage", action="store_true")
    parser.add_argument("--inspect", action="store_true", help="Read-only hosted preflight")
    args = parser.parse_args()
    try:
        prepared = load_images()
        digest = hashlib.sha256(INVENTORY.read_bytes()).hexdigest()
        if args.inspect:
            if args.execute:
                raise StorageError("Choose inspect or execute, not both.")
            url, key = (production_credentials() if args.environment == "production"
                        else development_credentials())
            with httpx.Client(base_url=url, headers=admin_headers(key), timeout=30.0,
                              follow_redirects=False, trust_env=False) as client:
                before = snapshot(client)
                validate_targets(before, prepared, url)
                bucket = client.get("/storage/v1/bucket/destination-images")
                if bucket.status_code != 200:
                    raise StorageError("Existing bucket unavailable for read-only inspection.")
                data = bucket.json()
                print(json.dumps({
                    "environment": args.environment, "locations": len(before),
                    "new_targets": 20, "files": len(prepared),
                    "existing_image_links": sum(bool(r["image_url"]) for r in before.values()),
                    "bucket": {k: data.get(k) for k in
                               ("id", "public", "file_size_limit", "allowed_mime_types")},
                }, indent=2))
            return 0
        if not args.execute:
            print(f"DRY RUN: {args.environment}: {len(prepared)} files, 20 main links; no network.")
            return 0
        if not args.approved_usage:
            raise StorageError("Explicit project use authorization is required.")
        run(args.environment, prepared, digest)
        return 0
    except (StorageError, httpx.HTTPError, OSError, ValueError, KeyError, TypeError) as error:
        # No HTTP response body, request headers, credentials or traceback in output.
        detail = str(error) if isinstance(error, StorageError) else type(error).__name__
        print(f"{args.environment}: upload stopped: {detail}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
