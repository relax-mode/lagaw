# Structured preference extraction API

> **Authentication update (#79):** [Verified Supabase ownership and the #80 handoff](authentication.md) supersede the demo authentication setup in this guide. Demo fixtures now require explicit non-production `TRIP_AUTH_MODE=demo`; normal access uses Supabase access tokens. API payloads are unchanged.

`POST /api/v1/preferences/extract` turns a travel request into a validated draft
for user confirmation. It reuses `app.deepseek.extract_preferences`, the existing
strict provider schema, timeout/configuration checks and sanitized failures. It
does not rank destinations, generate an itinerary, or write to any database.
Sprint 1 connectivity (#10) is already complete; this work exposes the helper.

## Contract for Andrew and Roel

This is the implemented contract proposed for backend/Flutter review. Andrew and
Roel have not yet confirmed agreement in this session; teammate review is pending.
The route uses the existing `TripDemoToken` bearer scheme and server-selected
`get_trip_user` context. Clients cannot select a user. This remains a shared demo
access mechanism, not individual end-user authentication.

The request requires a JSON object with `prompt`: a string of 1–2000 characters,
measured before trimming; blank/whitespace-only strings are rejected. Leading and
trailing whitespace is removed before calling the provider. Unknown request keys,
malformed JSON, invalid field types and invalid explicit values receive sanitized
422 errors before any provider call. `explicit_preferences` is optional, defaults
to `{}`, and allows these keys:

| Field | Type and behavior |
| --- | --- |
| `preferred_tags` | Up to 30 canonical tag strings; omitted/null uses extracted tags; `[]` intentionally clears them |
| `budget_level` | `low`, `medium`, `high`, `unspecified`; omitted/null uses extracted level |
| `budget_min`, `budget_max` | PHP Decimal(12,2), nonnegative, ordered; supply both or neither; decimal strings preferred |
| `group_type` | `solo`, `couple`, `family`, `friends`, `group`; otherwise omitted/null |
| `duration` | `morning`, `afternoon`, `evening`, `full_day`, `unspecified`; omitted/null uses extraction |
| `pace` | `slow`, `moderate`, `fast`, `unspecified`; omitted/null uses extraction |

Example request:

```json
{
  "prompt": "A cheap relaxing afternoon with coffee and photography.",
  "explicit_preferences": {
    "budget_min": "0",
    "budget_max": "500",
    "group_type": "solo"
  }
}
```

Example successful response (provider-dependent suggestions, schema fixed):

```json
{
  "schema_version": "1",
  "preferences": {
    "preferred_tags": ["cafe", "photography", "relaxing"],
    "budget_level": "low",
    "budget_min": "0",
    "budget_max": "500",
    "budget_scope": "trip_total",
    "group_type": "solo",
    "duration": "afternoon",
    "pace": "slow"
  },
  "requires_confirmation": true,
  "missing_fields": []
}
```

`preferences`, `requires_confirmation` and `missing_fields` are always returned;
the version is `"1"`. Missing numeric budgets and group type are represented by
null and listed as `"budget"` / `"group_type"` in `missing_fields`. A missing tag
preference is `[]`; missing qualitative preferences are `unspecified`. Missing
fields in the provider JSON itself are rejected; the provider must return the
explicit `unspecified`/empty values defined by its existing strict schema.

## Normalization and S3-01 compatibility

The shared vocabulary in `app.preference_vocabulary` is exactly the approved seed
catalog's six tags: `cafe`, `photography`, `relaxing`, `heritage`, `food`, `nature`.
Provider `tags` become S3-01 `preferred_tags`, deduplicated and sorted. The helper's
strict enum already admits canonical tokens only; unsupported tags, aliases such
as `coffee`, casing variants and unsupported values are rejected, never silently
discarded. DeepSeek may interpret natural-language coffee as the canonical `cafe`
token; the backend still validates that result. A regression check compares the
vocabulary against `supabase/data/locations.json`; deliberate catalog changes must
update the approved vocabulary and tests together. No database is needed to
normalize this version's vocabulary.

Qualitative budgets are **not converted to invented numeric ranges**. There is no
approved low/medium/high-to-PHP table. Numeric budgets come only from explicit
form fields; even “500 pesos” in free text does not establish a numeric budget,
because the existing extraction schema contains no numeric-budget fields. Ask the
user to enter/confirm the amount in the form. `budget_level` is qualitative context,
not a numeric authority. Explicit numeric fields take precedence regardless of the
suggested qualitative level; no silent adjustment is made to reconcile them.

Explicit tags (including empty lists), budget level, duration and pace always win
over extraction. Explicit `unspecified` is retained. Null means no override, not
“clear a previously saved trip.” Zero amounts remain zero. Group type is supplied
only explicitly because the reused provider schema does not extract it. Other
existing form fields are not accepted here and must remain untouched by the client.

S3-01 uses the same canonical tags, money types and group values, but its complete
recommendation `Preferences` model also requires `user_id` and numeric per-person,
per-visit budgets. This response is a **partial draft**, not a recommendation
request. Numeric amounts here are explicitly **total trip PHP**, matching Trip CRUD.
Andrew must allocate them to a per-visit/per-person ceiling before calling the
recommender. Never pass total-trip PHP directly as that ceiling. The API does not
invent allocation, origin, distance, accessibility, dates or category constraints.

Duration and pace retain the canonical enum labels. They are extraction/confirmation
metadata: neither S3-01 nor the current Trip table has duration/pace columns. A
part-of-day label must not be converted to `max_visit_duration_minutes` (a per-place
constraint), and `full_day` is not a precise date or schedule. These labels stay
transient until a separately agreed storage/planning contract supports them.

## Confirmation and manual fallback

Roel's consumer should keep its current form state while extraction is pending.
Show the returned draft for confirmation, keep explicit form values authoritative,
and never auto-submit a Trip mutation merely because extraction returned 200.
If extraction is rejected or unavailable, keep all form fields and saved trip data
unchanged and let the user continue with the manual form. Do not automatically
retry paid calls. Cancellation requires no rollback because this route never writes.

After confirmation, use the existing authenticated `POST /api/v1/trips` or
`PATCH /api/v1/trips/{trip_id}`. Send only user-confirmed supported fields such as
`preferred_tags`, `budget_min`, `budget_max`, `group_type`, plus required title/date
fields for creation. Do not send `budget_level`, `budget_scope`, `duration`, `pace`,
`schema_version` or confirmation metadata into Trip CRUD; unknown fields are
rejected there. PATCH should contain only confirmed changes, preserving other
saved values. No new persistence path or Flutter screen is included in this issue.

## Stable sanitized errors

Extraction/input errors use this envelope, without prompt, provider body, key,
stack trace, or submitted validation values:

```json
{
  "detail": {
    "code": "extraction_timeout",
    "message": "Preference extraction timed out.",
    "manual_fallback": true
  }
}
```

| HTTP | Code | Cause |
| --- | --- | --- |
| 422 | `invalid_request` | Empty, oversized, malformed or invalid request; no provider call |
| 429 | `extraction_rate_limited` | Provider rate limit |
| 502 | `invalid_extraction_output` | Malformed/truncated JSON, unsupported tag/value, missing/extra output fields |
| 502 | `extraction_failed` | Provider rejected the request |
| 503 | `extraction_unavailable` | Missing/invalid provider configuration, authentication/access/balance/model failure, network error or provider outage |
| 504 | `extraction_timeout` | Provider timeout |

Access failures retain the existing Trip context's envelope: 401 has the safe
string detail `A valid trip demo bearer token is required.` and a Bearer challenge;
503 has `Trip demo context is not configured.` when context is disabled/invalid.
Neither reaches the provider. Flutter should support these inherited string
details as well as the extraction-specific object. Provider authentication failures
are 503, not a misleading client 401. No provider details are relayed in headers.

## Offline verification and deployment handoff

From `backend`, with the project virtual environment activated:

```powershell
python -m pytest test_preference_extraction.py test_deepseek.py -v
python -m pytest -q
ruff check .
```

The six [evaluation cases](../backend/fixtures/extraction/cases.json) contain
synthetic prompts, mocked provider JSON, explicit form values and expected output.
They evaluate normalization/confirmation behavior, not live LLM semantic accuracy.
Tests exercise the real helper through `httpx.MockTransport`, block dotenv loading,
use dummy configuration, verify HTTP-level failures and assert that existing saved
trip retrieval stays unchanged. Existing backend CI discovers the tests. No paid
provider access or actual credentials are required. See [verification evidence](evidence/preference-extraction.md).

For Andrew's deployment: the image already copies `app/`, so the new route and
shared vocabulary are packaged without Docker changes. Backend-only DeepSeek
configuration must be injected using existing secret/configuration management;
never put a provider key in Flutter. Keep staging and production credentials
separate according to team policy. No real secret was read or changed here.

After reviewed merge and successful required CI, verify the deployed OpenAPI shows
the versioned route and existing security scheme, then perform one controlled,
authorized extraction through the backend with the configured demo context. Check
the schema, canonical tags, absent invented budgets, confirmation flag, safe invalid
request/auth behavior and unchanged existing trips. Record the revision, time,
safe statuses and issue/PR/CI links in the evidence. Do not paste prompts containing
personal data, bearer tokens or provider output diagnostics into evidence. Actual
deployment and a paid smoke call were not performed in this implementation session.
