"""Guarded catalogue image publication: target isolation and unrelated data preservation."""

import importlib.util
import json
import sys
from pathlib import Path
from uuid import UUID

import httpx
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
spec = importlib.util.spec_from_file_location("upload_catalogue_images", ROOT / "scripts/upload_catalogue_images.py")
uploads = importlib.util.module_from_spec(spec)
spec.loader.exec_module(uploads)
IDENTITY = "14000000-0000-4000-8000-000000000001"
ENTRY = {"location_id": IDENTITY, "name": "Fixture", "primary": True,
         "file": "fixture.jpg", "sha256": "a" * 64}
PREPARED = [(ENTRY, b"fixture", "image/jpeg", f"locations/{UUID(IDENTITY)}/{'a' * 64}.jpg")]


def test_target_guard_rejects_mismatched_identity_and_curated_image():
    row = {"id": IDENTITY, "name": "Fixture", "is_active": True, "image_url": None}
    for change in ({"name": "Other branch"}, {"is_active": False},
                   {"image_url": "https://example.test/curated.jpg"}):
        with pytest.raises(uploads.StorageError):
            uploads.validate_targets({IDENTITY: row | change}, PREPARED, "https://example.test")
    with pytest.raises(uploads.StorageError):
        uploads.validate_targets({}, PREPARED, "https://example.test")


def test_production_stops_before_credentials_when_development_receipt_differs(tmp_path, monkeypatch):
    receipt = tmp_path / "development.json"
    receipt.write_text(json.dumps({"complete": True, "inventory_sha256": "different", "images": []}))
    monkeypatch.setattr(uploads, "receipt_path", lambda env: receipt)
    monkeypatch.setattr(uploads, "production_credentials", lambda: pytest.fail("must not read credentials"))
    with pytest.raises(uploads.StorageError, match="development verification"):
        uploads.run("production", PREPARED, "current")


def test_changed_unrelated_field_prevents_successful_receipt(tmp_path, monkeypatch):
    before = {IDENTITY: {"id": IDENTITY, "name": "Fixture", "is_active": True,
                         "image_url": None, "description": "Original text"}}
    url = "https://example.test"
    expected = uploads.public_url(url, PREPARED[0][3])
    after = {IDENTITY: before[IDENTITY] | {"image_url": expected, "description": "Unexpected edit"}}
    states = iter([before, after])
    receipt = tmp_path / "receipt.json"
    monkeypatch.setattr(uploads, "receipt_path", lambda env: receipt)
    monkeypatch.setattr(uploads, "development_credentials", lambda: (url, "fixture"))
    monkeypatch.setattr(uploads, "snapshot", lambda client: next(states))
    monkeypatch.setattr(uploads, "bucket_configuration", lambda client: None)
    monkeypatch.setattr(uploads, "upload_and_verify", lambda *args: expected)
    monkeypatch.setattr(uploads, "link_if_empty", lambda *args: None)
    with pytest.raises(uploads.StorageError, match="image-only changes"):
        uploads.run("development", PREPARED, "fixture")
    assert json.loads(receipt.read_text())["complete"] is False


def test_duplicate_storage_response_still_requires_correct_public_bytes(monkeypatch):
    import destination_images

    original = httpx.Client
    key = PREPARED[0][3]

    def handler(request):
        if request.method == "POST":
            return httpx.Response(400, json={"error": "Duplicate", "statusCode": "409"})
        assert "apikey" not in request.headers
        return httpx.Response(200, content=b"wrong bytes")

    monkeypatch.setattr(destination_images.httpx, "Client", lambda **kw: original(
        transport=httpx.MockTransport(handler), **kw,
    ))
    with (
        original(base_url="https://example.test", transport=httpx.MockTransport(handler)) as client,
        pytest.raises(uploads.StorageError, match="content verification"),
    ):
        uploads.upload_and_verify(client, "https://example.test", b"fixture", "image/jpeg", key)
