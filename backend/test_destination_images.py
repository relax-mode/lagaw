"""#108 offline tests for the development-only Storage administration tool."""
import importlib.util
from pathlib import Path
from uuid import UUID

import httpx
import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "destination_images.py"
spec = importlib.util.spec_from_file_location("destination_images", SCRIPT)
images = importlib.util.module_from_spec(spec)
spec.loader.exec_module(images)

LOCATION = UUID("14000000-0000-4000-8000-000000000001")
PNG = b"\x89PNG\r\n\x1a\n" + b"fixture-image"
KEY = "sb_secret_" + "fixture"


def test_image_type_size_and_content_address(tmp_path):
    path = tmp_path / "photo.png"
    path.write_bytes(PNG)
    data, mime, obj = images.image_info(path, LOCATION)
    assert data == PNG and mime == "image/png"
    assert obj.startswith(f"locations/{LOCATION}/") and obj.endswith(".png")
    assert images.image_info(path, LOCATION)[2] == obj
    path.write_bytes(b"invalid")
    with pytest.raises(images.StorageError):
        images.image_info(path, LOCATION)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + b"x" * images.MAX_BYTES)
    with pytest.raises(images.StorageError):
        images.image_info(path, LOCATION)
    bad = tmp_path / "photo.exe"
    bad.write_bytes(PNG)
    with pytest.raises(images.StorageError):
        images.image_info(bad, LOCATION)


def test_target_is_development_only_without_leaking_key(monkeypatch):
    monkeypatch.setattr(images, "load_dotenv", lambda *a, **kw: None)
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", KEY)
    monkeypatch.setenv("SUPABASE_URL", "https://zjnuqqtbapbpudsjbpif.supabase.co")
    with pytest.raises(images.StorageError) as failure:
        images.development_credentials()
    assert KEY not in str(failure.value)
    monkeypatch.setenv("SUPABASE_URL", images.DEVELOPMENT)
    assert images.development_credentials() == (images.DEVELOPMENT, KEY)
    assert images.admin_headers(KEY) == {"apikey": KEY}


def test_no_execute_is_offline_dry_run(tmp_path, monkeypatch, capsys):
    path = tmp_path / "approved.png"
    path.write_bytes(PNG)
    monkeypatch.setattr(images, "development_credentials", lambda: pytest.fail(
        "dry run must not read credentials"
    ))
    assert images.main(["--file", str(path), "--location-id", str(LOCATION)]) == 0
    assert "DRY RUN" in capsys.readouterr().out


def test_approved_upload_creates_bucket_checks_public_hash_and_links(tmp_path, monkeypatch):
    path = tmp_path / "approved.png"
    path.write_bytes(PNG)
    monkeypatch.setattr(images, "development_credentials", lambda: (images.DEVELOPMENT, KEY))
    calls = []
    bucket_exists = False

    def handler(request):
        nonlocal bucket_exists
        calls.append((request.method, request.url.path, "apikey" in request.headers))
        p = request.url.path
        if p == f"/storage/v1/bucket/{images.BUCKET}":
            if not bucket_exists:
                return httpx.Response(404, json={})
            return httpx.Response(200, json={
                "id": images.BUCKET, "public": True,
                "file_size_limit": images.MAX_BYTES,
                "allowed_mime_types": images.ALLOWED_MIME_TYPES,
            })
        if p == "/storage/v1/bucket" and request.method == "POST":
            assert request.headers["apikey"] == KEY
            bucket_exists = True
            return httpx.Response(200, json={})
        if p.startswith(f"/storage/v1/object/{images.BUCKET}/") and request.method == "POST":
            assert request.content == PNG and request.headers["apikey"] == KEY
            assert request.headers["content-type"] == "image/png"
            return httpx.Response(200, json={"Key": "stored"})
        if p.startswith("/storage/v1/object/public/"):
            assert "apikey" not in request.headers
            return httpx.Response(200, content=PNG)
        if p == "/rest/v1/locations" and request.method == "PATCH":
            assert request.headers["apikey"] == KEY
            assert request.url.params["image_url"] == "is.null"
            return httpx.Response(200, json=[
                {"id": str(LOCATION), "image_url": request.content.decode().split('"')[3]}
            ])
        raise AssertionError(f"Unexpected request {request.method} {p}")

    # The API returns the exact URL from the JSON body in a response.
    def safe_handler(req):
        if req.method == "PATCH":
            import json
            value = json.loads(req.content)["image_url"]
            calls.append((req.method, req.url.path, "apikey" in req.headers))
            assert req.url.params["image_url"] == "is.null"
            return httpx.Response(200, json=[{"id": str(LOCATION), "image_url": value}])
        return handler(req)

    original = httpx.Client
    monkeypatch.setattr(images.httpx, "Client", lambda **kwargs: original(
        transport=httpx.MockTransport(safe_handler), **kwargs
    ))
    assert images.main([
        "--execute", "--approved-usage", "--file", str(path),
        "--location-id", str(LOCATION), "--link-location",
    ]) == 0
    assert any(method == "PATCH" for method, *_ in calls)
    assert any(path.startswith("/storage/v1/object/public/") and not privileged
               for method, path, privileged in calls)


def test_no_approved_usage_or_conflicting_bucket_fails_closed(tmp_path, monkeypatch):
    path = tmp_path / "approved.png"
    path.write_bytes(PNG)
    assert images.main([
        "--execute", "--file", str(path), "--location-id", str(LOCATION)
    ]) == 1
    monkeypatch.setattr(images, "development_credentials", lambda: (images.DEVELOPMENT, KEY))
    original = httpx.Client

    def handler(req):
        if req.url.path.endswith("/storage/v1/bucket/destination-images"):
            return httpx.Response(200, json={
                "id": images.BUCKET, "public": False,
                "file_size_limit": images.MAX_BYTES,
                "allowed_mime_types": images.ALLOWED_MIME_TYPES,
            })
        raise AssertionError("Conflicting bucket may not be modified.")

    monkeypatch.setattr(images.httpx, "Client", lambda **kw: original(
        transport=httpx.MockTransport(handler), **kw
    ))
    assert images.main(["--execute"]) == 1


def test_public_hash_mismatch_never_updates_location(tmp_path, monkeypatch):
    path = tmp_path / "approved.png"
    path.write_bytes(PNG)
    monkeypatch.setattr(images, "development_credentials", lambda: (images.DEVELOPMENT, KEY))
    original = httpx.Client
    calls = []

    def handler(req):
        calls.append(req.method)
        if req.method == "GET" and "/bucket/" in req.url.path:
            return httpx.Response(200, json={
                "id": images.BUCKET, "public": True, "file_size_limit": images.MAX_BYTES,
                "allowed_mime_types": images.ALLOWED_MIME_TYPES,
            })
        if req.method == "POST":
            return httpx.Response(201, json={})
        if req.method == "GET" and "/object/public/" in req.url.path:
            return httpx.Response(200, content=b"tampered")
        raise AssertionError("Must not link unverifiable object.")

    monkeypatch.setattr(images.httpx, "Client", lambda **kw: original(
        transport=httpx.MockTransport(handler), **kw
    ))
    assert images.main([
        "--execute", "--approved-usage", "--file", str(path),
        "--location-id", str(LOCATION), "--link-location",
    ]) == 1
    assert "PATCH" not in calls




def test_existing_image_reference_is_not_overwritten():
    original = "https://legacy.example/curated.webp"

    def handler(request):
        assert request.url.params["id"] == f"eq.{LOCATION}"
        if request.method == "PATCH":
            assert request.url.params["image_url"] == "is.null"
            return httpx.Response(200, json=[])
        assert request.method == "GET"
        return httpx.Response(200, json=[{"image_url": original}])

    with httpx.Client(
        base_url=images.DEVELOPMENT,
        transport=httpx.MockTransport(handler),
    ) as client, pytest.raises(images.StorageError):
        images.link_if_empty(client, LOCATION, "https://new.example/asset.png")


def test_policy_migration_is_storage_optional_and_restricts_all_client_mutations():
    sql = (Path(__file__).resolve().parents[1] / "supabase" / "migrations" /
           "20261103100000_destination_image_storage_policies.sql").read_text()
    assert "to_regclass('storage.objects')" in sql
    for operation in ("insert", "update", "delete"):
        assert f"as restrictive for {operation}" in sql
    assert "to anon, authenticated" in sql
    assert "bucket_id <> 'destination-images'" in sql
