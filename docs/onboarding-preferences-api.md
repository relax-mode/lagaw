# S4-02: Authenticated onboarding preferences (issue #102)

**Status (2026-10-31):** Implemented in the `feat/s4-02-onboarding-preferences` feature branch. Focused offline test rerun: **39 passed in 1.73 s**; Ruff: **All checks passed**; `git diff --check`: no whitespace errors (only Windows line-ending warnings). The prior full non-DB Windows run reported **788 passed, 7 failed, 106 deselected**; five failures were caused by a subsequently corrected test assertion and the remaining two were unrelated pre-existing #94 POSIX file-mode assertions on Windows. Full regression after the correction, CI, deployed verification and review **pending**. No production deployment, migration or environment edits.

## Why this route exists

This is **profile onboarding persistence**, not the already implemented paid AI text extraction API `POST /api/v1/preferences/extract`. The extraction route returns an unconfirmed transient draft and never persists. S4-02 stores user-confirmed onboarding values.

It uses the existing `public.users` columns (`preferred_tags`, `default_budget_min`, `default_budget_max`, `traveler_type`). No schema migration or new secret is required. Profile ownership comes from `app.trips.get_trip_user` and the Supabase-verified Auth subject -> `public.users.auth_user_id` mapping; **Auth UUID and application profile UUID are different identifiers**. The client's JSON never accepts `user_id`, `id`, `auth_user_id`, email, name, or any other profile fields.

## HTTP contract for #101, #103 and #104

| Method | Endpoint | Result |
| --- | --- | --- |
| GET | `/api/v1/me/preferences` | 200, current saved preferences; newly linked profile has `[]` tags and null optional fields |
| PUT | `/api/v1/me/preferences` | 200, replaces and returns the four preference fields in one owner-scoped database PATCH |

Both require `Authorization: Bearer <Supabase access token>` for a confirmed, non-anonymous user. This uses the existing `SupabaseAccessToken` OpenAPI security scheme. No user/profile ID appears in the URL.

**PUT full-replacement body** (all four keys are required):

```json
{
  "preferred_tags": ["cafe", "heritage"],
  "budget_min": "0.00",
  "budget_max": "500.00",
  "travel_style": "slow"
}
```

**Response:** the same four fields in the same shape; exact PHP decimals serialize as JSON strings, not floating-point amounts. For a new account the GET response is:

```json
{
  "preferred_tags": [],
  "budget_min": null,
  "budget_max": null,
  "travel_style": null
}
```

The supported travel-style values **reuse the existing extraction pace vocabulary**: `slow`, `moderate`, `fast`; `null` indicates unset, not an invented fourth pace. These are *proposed onboarding labels* pending UI owner (#101/#104) agreement; they are stored in the existing `traveler_type` column rather than inventing a new pace column. An existing noncanonical `traveler_type` row is not silently rewritten or guessed; retrieval fails closed and requires a reviewed compatibility decision. Do not mistake the style for trip `group_type`, which is a different concept.

**Tag vocabulary:** `cafe`, `photography`, `relaxing`, `heritage`, `food`, `nature`, directly reused from `app.preference_vocabulary.TravelTag`. Maximum 30 items, no duplicates, unknown tags/case variants rejected. `[]` is an intentional clear.

**Budgets:** PHP, nonnegative Decimal(12,2), at most two fraction digits. Both `budget_min` and `budget_max` must be present with values or both explicitly `null`; `budget_min <= budget_max`. `0` is valid, `NaN`, `Infinity`, negatives, malformed/overprecision amounts and one-sided ranges are rejected. No low/medium/high-to-PHP conversion is invented. The saved default budget is a **profile default range**, *not* a generated itinerary budget or per-venue recommendation budget.

**Save semantics:** PUT is a complete replacement, not PATCH, and requires all four keys. Use GET before showing the edit screen and submit all four confirmed fields; missing fields get HTTP 422 instead of silently clearing values. A single database PATCH changes only the four preference columns. It preserves name, email, auth link, trips and interaction history. Repeating the same PUT is idempotent. Unsupported fields are rejected rather than ignored.

## Errors and security

| Status | Meaning |
| --- | --- |
| 401 | Missing, invalid, or expired token; `WWW-Authenticate: Bearer` |
| 403 | Email not confirmed |
| 404 | Verified profile was removed concurrently |
| 409 | Existing identity/profile linking requires review |
| 422 | Invalid/unknown/missing fields; sanitized per-field error locations, no submitted values |
| 503 | Auth, profile or database unavailable; no provider body, tokens or secret values in output |

FastAPI receives the verified **profile UUID** on the server; all Supabase `users` GET/PATCH requests filter `id=eq.<verified_profile_id>`, and returned rows are validated for that same ID. Unexpected multiple/cross-owner or malformed rows fail closed. No client-selected ID ever reaches database filters.

Backend uses the existing service-role Data API only. Flutter never receives the database service key; it sends the user's Supabase access token to FastAPI.

## Local verification and delivery

From the repository root with your existing `.venv` active:

```powershell
python -m pytest -q backend/test_onboarding.py
cd backend
python -m ruff check .
python -m pytest -q -m "not db"
cd ..
git diff --check
```

The local Windows non-DB suite previously had two unrelated POSIX `0o600` mode assertions failing in `test_seed_and_train.py`. Record any recurrence instead of weakening those assertions. CI/Linux results will be authoritative for that existing issue.

The offline `backend/test_onboarding.py` exercises the actual API with two authenticated-owner identities supplied by a controlled fake authentication boundary and a `httpx.MockTransport` database; it does not contact Supabase, modify cloud data, read .env, or call DeepSeek. The dedicated auth suite (`backend/test_auth.py`) separately verifies the real signed-token/Auth endpoint boundary; offline stubs do **not** prove a live Supabase deployment.

After teammate-approved contract alignment, merge authorization and staging deployment, manually verify two **controlled** confirmed Supabase accounts can save/read separate preferences, both from refreshed client sessions; verify rejected cross-owner and malformed values, no changes to unrelated fields, and zero AI calls. Preserve existing user data. Coordinate with #101/#103/#104 before calling integration complete.

**No merge to `main`, production write or deployment has been authorized by the S4-02 code work.**
