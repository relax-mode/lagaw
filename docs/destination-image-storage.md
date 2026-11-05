# #108 — Destination images: Storage access and repeatable uploads

Prepared **November 3, 2026**. This is a **development-first proposal**; it
does not claim that the hosted project contains the bucket or policies.

## Existing contract and planned configuration

`public.locations.image_url` already exists, is nullable, and is exposed by
`GET /locations`; no new location field, API route or Flutter change is needed.
Existing external URLs remain valid. Before applying anything, inventory the
development project's buckets, `storage.objects` RLS policies and current
non-null image URLs. The local migrations alone cannot establish current hosted
state.

The dedicated `destination-images` bucket is **public read / backend-only write**.
Bucket restrictions: maximum **5 MiB**, MIME types `image/png`, `image/jpeg`
and `image/webp`. Upload through Storage's API, never by writing Storage object
metadata directly. The additive SQL migration
`supabase/migrations/20261103100000_destination_image_storage_policies.sql`
adds **restrictive** INSERT/UPDATE/DELETE denial for `anon` and
`authenticated` in that bucket; other buckets are unaffected. When disposable
CI PostgreSQL lacks Storage, the migration notices and skips rather than failing
the existing database tests. The migration alone does **not** create the bucket.

Only the trusted server administrator process using
`SUPABASE_SERVICE_ROLE_KEY` may create/upload approved images. The service
credential is never sent to Flutter or printed. A public bucket makes only
retrieval public, not uploading, moving or deleting.

Object paths: `locations/<location_uuid>/<sha256-content-hash>.<ext>`.
The resulting public object URL is stored in the existing `image_url` field
only if it is currently null. Content addressing and the existing-reference
guard make repeat uploads safe and preserve manual corrections.

## Development procedure

1. Confirm the environment is **development** project
   `vnpkyvtbupnquvirzlzp` and inspect existing bucket and policies (read-only).
   **Do not apply this procedure to production**.
2. Apply the additive policy migration through the established development
   migration process and verify its contents and grants. CI's disposable
   PostgreSQL migration test cannot prove hosted Storage authorization.
3. Use the existing private development environment settings without displaying
   their values. From the repository root:

   ```powershell
   python scripts/destination_images.py --file <APPROVED_IMAGE.png> --location-id <EXISTING_LOCATION_UUID>
   # After checking that the image is authorized for use:
   python scripts/destination_images.py --execute --approved-usage --file <APPROVED_IMAGE.png> --location-id <EXISTING_LOCATION_UUID> --link-location
   ```

   The first command is an **offline dry run** (no writes or network). The
   second verifies development URL identity, creates the bucket via the Storage
   API if absent, compares existing bucket settings if present, uploads the
   content-addressed image, verifies that a *public unauthenticated GET* returns
   matching bytes, and conditionally links the URL to the location. If the row
   already has a different URL, it stays unchanged.
4. From an **unprivileged** key/session, attempt to upload or replace a harmless
   temporary object in the development bucket; require denial. Verify ordinary
   public GET works and existing `GET /locations` returns the same URL. Preserve
   sanitized evidence of accepted and rejected requests without credentials or
   image content.
5. From `backend/`, run `python -m pytest -v -m "not db"` and
   `python -m ruff check .`, and run the database CI suite.
6. Only after development verification, request **separate explicit approval**
   for production Storage/policy changes, any production image upload and the
   production-affecting merge. Check the staging/production pipeline.

## Safety and recovery

Supabase Storage's public endpoint is read-only. Storage's own RLS policies
must reject client writes even when bypassing the application. If an upload
succeeds but its location link fails, the content-addressed object may remain
unreferenced: review it before any manual cleanup, and use the Storage API,
never deletion from `storage.objects`. Do not remove access restrictions to
make uploads succeed. No image licensing assessment is included in this issue.

Rollback is to preserve existing `image_url` values and restore reviewed
bucket/policy configuration through approved change control. Do not delete
objects or reset the Storage schema as an emergency shortcut.

## Evidence as of November 3

- Repository code/migration drafted; offline tests are separate from hosted
  development proof.
- **Hosted bucket inventory, authorized/unauthorized upload, public retrieval
  and reference resolution: not yet verified.**
- **Production writes, production verification and merge: not attempted.**

References: [Supabase Storage schema](https://supabase.com/docs/guides/storage/schema/design),
[Storage buckets](https://supabase.com/docs/guides/storage/buckets/fundamentals),
[Storage access control](https://supabase.com/docs/guides/storage/security/access-control).
