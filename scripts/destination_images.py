"""Repeatable, development-only Supabase destination-image setup and upload.

No live changes by default. Storage bucket operations use the Storage REST API,
not direct writes to managed storage metadata tables. No client upload endpoint.
"""

import argparse
import hashlib
import os
from pathlib import Path
from urllib.parse import urlsplit
from uuid import UUID

import httpx
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
BUCKET = "destination-images"
DEVELOPMENT = "https://vnpkyvtbupnquvirzlzp.supabase.co"
MAX_BYTES = 5 * 1024 * 1024
MIME = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
        ".webp": "image/webp"}
ALLOWED_MIME_TYPES = sorted(set(MIME.values()))


class StorageError(Exception):
    """Safe, credential-free operational failure."""


def image_info(file_path: Path, location: UUID) -> tuple[bytes, str, str]:
    """Reject extensions that disagree with actual file signature or size."""
    try:
        extension = file_path.suffix.lower()
        if extension not in MIME or not 0 < file_path.stat().st_size <= MAX_BYTES:
            raise ValueError
        raw = file_path.read_bytes()
        valid = {
            "image/png": raw.startswith(b"\x89PNG\r\n\x1a\n"),
            "image/jpeg": raw.startswith(b"\xff\xd8\xff"),
            "image/webp": raw.startswith(b"RIFF") and raw[8:12] == b"WEBP",
        }
        content_type = MIME[extension]
        if len(raw) > MAX_BYTES or not valid[content_type]:
            raise ValueError
        digest = hashlib.sha256(raw).hexdigest()
        suffix = ".jpg" if extension == ".jpeg" else extension
        key = f"locations/{location}/{digest}{suffix}"
        return raw, content_type, key
    except (OSError, ValueError):
        raise StorageError("Image must be a readable PNG, JPEG or WebP under 5 MiB.") from None


def development_credentials() -> tuple[str, str]:
    """Read values only inside the program. Never print or format the secret key."""
    load_dotenv(ROOT / ".env", override=False)
    url = os.environ.get("SUPABASE_URL", "").strip().rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    parsed = urlsplit(url)
    loopback = (parsed.scheme == "http" and parsed.hostname in
                ("localhost", "127.0.0.1") and not parsed.path)
    if (url != DEVELOPMENT and not loopback) or not key or parsed.username or parsed.password:
        raise StorageError("Use the explicitly approved development Supabase project.")
    return url, key


def admin_headers(key: str) -> dict[str, str]:
    """New sb_secret keys use apikey alone; legacy service_role JWTs use Bearer too."""
    headers = {"apikey": key}
    if not key.startswith("sb_secret_"):
        headers["Authorization"] = f"Bearer {key}"
    return headers


def bucket_configuration(client: httpx.Client) -> None:
    """Create a single public-read bucket; reject conflicting existing configuration."""
    reply = client.get(f"/storage/v1/bucket/{BUCKET}")
    if reply.status_code == 404:
        created = client.post("/storage/v1/bucket", json={
            "id": BUCKET, "name": BUCKET, "public": True,
            "file_size_limit": MAX_BYTES, "allowed_mime_types": ALLOWED_MIME_TYPES,
        })
        if created.status_code not in (200, 201):
            raise StorageError("Development bucket creation failed.")
        reply = client.get(f"/storage/v1/bucket/{BUCKET}")
    if reply.status_code != 200:
        raise StorageError("Development bucket inventory is unavailable.")
    try:
        data = reply.json()
        valid = (data["id"] == BUCKET and data["public"] is True
                 and data["file_size_limit"] == MAX_BYTES
                 and sorted(data["allowed_mime_types"]) == ALLOWED_MIME_TYPES)
        if not valid:
            raise ValueError
    except (ValueError, TypeError, KeyError):
        raise StorageError("Existing bucket configuration differs; review before changes.") from None


def public_url(url: str, key: str) -> str:
    return f"{url}/storage/v1/object/public/{BUCKET}/{key}"


def upload_and_verify(
    client: httpx.Client, url: str, raw: bytes, content_type: str, key: str
) -> str:
    response = client.post(
        f"/storage/v1/object/{BUCKET}/{key}",
        headers={"Content-Type": content_type, "x-upsert": "false"},
        content=raw,
    )
    if response.status_code not in (200, 201, 409):
        raise StorageError("Authorized image upload was rejected.")
    public = public_url(url, key)
    # Public GET intentionally has NO privileged headers or cookies.
    with httpx.Client(timeout=10.0, follow_redirects=False, trust_env=False) as visitor:
        downloaded = visitor.get(public)
    if downloaded.status_code != 200 or hashlib.sha256(downloaded.content).digest() != hashlib.sha256(raw).digest():
        raise StorageError("Public image retrieval or content verification failed.")
    return public


def link_if_empty(client: httpx.Client, location_id: UUID, image_url: str) -> None:
    """Never overwrite an existing human-curated image reference."""
    reply = client.patch(
        "/rest/v1/locations", params={
            "id": f"eq.{location_id}", "image_url": "is.null",
            "select": "id,image_url",
        },
        headers={"Content-Profile": "public", "Prefer": "return=representation"},
        json={"image_url": image_url},
    )
    if reply.status_code != 200:
        raise StorageError("Destination image reference could not be saved.")
    try:
        rows = reply.json()
        if rows == [{"id": str(location_id), "image_url": image_url}]:
            return
        if rows != []:
            raise ValueError
        existing = client.get("/rest/v1/locations", params={
            "id": f"eq.{location_id}", "select": "image_url", "limit": 1,
        })
        if existing.status_code != 200 or existing.json() != [{"image_url": image_url}]:
            raise ValueError
    except (ValueError, TypeError):
        raise StorageError(
            "Destination missing or has a different existing image reference; left unchanged."
        ) from None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--file", type=Path)
    parser.add_argument("--location-id", type=UUID)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--approved-usage", action="store_true",
                        help="Confirm that this specific image is authorized for project use")
    parser.add_argument("--link-location", action="store_true")
    args = parser.parse_args(argv)
    if (args.file is None) != (args.location_id is None):
        parser.error("--file and --location-id must be supplied together")
    if args.link_location and not args.file:
        parser.error("--link-location requires an image and destination")
    try:
        info = image_info(args.file, args.location_id) if args.file else None
        if not args.execute:
            print("DRY RUN: development storage bucket configuration; no network or writes.")
            if info:
                print(f"DRY RUN: would upload {info[2]} ({len(info[0])} bytes)")
            return 0
        if info and not args.approved_usage:
            raise StorageError("Do not upload before confirming image usage permissions.")
        url, key = development_credentials()
        with httpx.Client(base_url=url, headers=admin_headers(key), timeout=10.0,
                          follow_redirects=False, trust_env=False) as client:
            bucket_configuration(client)
            if info:
                public = upload_and_verify(client, url, info[0], info[1], info[2])
                if args.link_location:
                    link_if_empty(client, args.location_id, public)
                print(f"Verified development public image URL: {public}")
            else:
                print("Development bucket configuration verified.")
        return 0
    except (StorageError, httpx.HTTPError, ValueError):
        print("Destination image storage operation failed; inspect development configuration.")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
