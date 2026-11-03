# Cold-start recommendations from onboarding preferences

Implemented on `feat/onboarding-recommendations`, November 1, 2026. This is a
read-only backend integration for zero-interaction discovery. It reuses #33's
content engine and #53's catalog/response helpers, alongside #102's saved onboarding
preferences. Collaborative serving/training (#94), general profile CRUD, Flutter
UI (#104), and itinerary generation are separate work.

## Request

`POST /api/v1/me/recommendations` requires the existing `SupabaseAccessToken`
bearer authentication. The backend derives the application profile UUID from the
verified Auth identity; a caller cannot select a user or provide replacement tags.

```json
{
  "group_type": "solo",
  "per_person_visit_budget_max": "300.00",
  "limit": 10
}
```

| Field | Contract |
| --- | --- |
| `group_type` | Required: `solo`, `couple`, `family`, `friends`, or `group` |
| `per_person_visit_budget_max` | Required nonnegative PHP Decimal(12,2), maximum two fractional digits; decimal strings recommended; zero permits confirmed free venues only |
| `limit` | Optional strict integer 1–100, default 10 |

Unknown keys, invalid enums, nonfinite amounts, negative/overprecision budgets,
missing required fields, and boolean/string limits receive sanitized 422 responses.

The backend reads `preferred_tags` from the owner's saved onboarding record.
Onboarding default budgets are not assigned an invented per-visit meaning. This
request explicitly establishes a **per-person, per-visit venue-cost ceiling**;
it is neither total-trip budget nor a transport/lodging allowance. Profile budgets
remain unchanged and are not used by this route. The engine's minimum budget is
zero: no minimum spending is forced. Onboarding `travel_style` is not scored or
converted into a duration; the existing engine does not support pace scoring.

No saved trip, interaction history or model artifact is required. The route always
uses `ContentBasedRecommender` with `interactions=[]`, even if an artifact is
configured for the separate saved-trip API. Existing application startup may
initialize that separate shared engine; this route does not use it or load an
artifact itself. There is no new configuration or secret.

## Response

HTTP 200 contains:

```json
{
  "schema_version": "1",
  "mode": "content_only",
  "budget_scope": "per_person_per_visit",
  "items": [],
  "empty_reason": "no_compatible_locations"
}
```

For nonempty responses, `empty_reason` is null and every item reuses
`TripRecommendation`: `location_id` (UUID), `recommendation_score` (number 0–1),
`recommendation_reason` (bounded string), and `location` (the existing full public
`Location` object, including nullable unknown facts). There is **no** `trip_id` or
saved-trip budget-allocation wrapper. See the generated OpenAPI schema for the
complete nested object, also used by the [saved-trip API](trip-recommendations-api.md).

Only eligible active locations are ranked. Unknown upper costs, over-budget
locations and group mismatches are excluded. The shared content score uses tags,
category and budget headroom; this endpoint supplies no category preference, so
with nonempty tags effective weights are 80% tag match and 20% budget headroom.
Empty tags omit tag scoring and fall back to budget headroom alone. Additional
destination tags do not penalize a match. With no relevance threshold, eligible
nonmatching places can appear below matching ones when the limit permits.

Results sort by descending score, then UUID for equal scores, making stable
snapshots deterministic regardless of catalog order. Scores are compatibility
rankings, not satisfaction probabilities. Empty catalogs and no compatible places
are valid empty responses. Unknown data is not filled with synthetic facts.

The adapter uses bounded catalog pagination and rejects repeated IDs or excessive
catalog size. Engine output is validated against the trusted snapshot. Returned
venues are fetched again after ranking; changed/deactivated venues are dropped,
without refilling the list. Saved preferences are reread: changes require a reload
and retry rather than returning stale preference scores. These reads do not form
a database transaction; edits after the final check remain possible.

## Errors and fallback

| HTTP | Behavior |
| --- | --- |
| 401/403 | Existing missing/invalid/expired token or unconfirmed email handling |
| 404 | Profile no longer exists |
| 409 | Existing identity-linking conflict, or preferences changed while ranking; reload before retrying |
| 422 | Invalid request, sanitized `loc`, `msg`, `type`; no submitted values/context |
| 503 | Profile/catalog unavailable, malformed stored data, invalid model output or ranking failure; safe message only |

An engine exception returns 503 instead of silently switching to arbitrary
recommendations. Cold-start content ranking is already the fallback; empty tags
use its budget-based behavior. This endpoint does not query interactions, so it
does not apply historical left-swipe exclusions. It is intended for onboarding
before interactions; returning users needing history-aware results should use
the existing saved-trip recommendation flow. No request writes profile, trips,
interactions or itinerary items. No DeepSeek/provider call occurs.

## Code and verification evidence

- `backend/app/onboarding_recommendations.py`: request/result schemas, owner-scoped
  route, direct content inference, freshness checks and safe failures.
- `backend/app/main.py`: router registration and sanitized validation handling.
- `backend/test_onboarding_recommendations.py`: real content engine through HTTP,
  with a mocked Data API and synthetic profile/location data.

With the existing project virtual environment activated, from the repository root:

```powershell
python -m pytest -q backend/test_onboarding_recommendations.py
python -m ruff check backend
```

November 1 local evidence: **24 focused tests passed** and backend Ruff passed.
Tests cover two-owner tag personalization, missing onboarding budgets, bounded
pagination, deterministic ties, limits, budget/group/unknown-cost eligibility,
empty catalog, empty-tag fallback, free places, authentication, validation,
profile/database/engine failures, stale venue/profile handling, invalid engine
output, duplicate catalog rows and OpenAPI security/contract registration.
Mocked database traffic is asserted GET-only and restricted to `users`/`locations`;
artifact loading and preference-extraction calls are guarded against accidental use.

The first broader root-level non-DB run (before three additional focused checks)
reported **849 passed, 2 failed, 106 deselected**. Both failures are the pre-existing
#94 POSIX `0o600` assertions on Windows, which reports `0o666`; no #94 code changed.
That root-level invocation also emitted six unregistered `db` marker warnings;
the project's backend test configuration should be used for normal regression runs.

Final regression from `backend`, after all 24 focused checks were added:
**852 passed, 2 failed, 106 deselected in 21.86 seconds**, with no warnings.
The same two existing Windows permission assertions were the only failures.

No live provider/database calls or deployed acceptance check were performed.
Contract alignment is an implementation proposal for #102/#104/#111 consumers;
teammate acknowledgment is not claimed. Reviewed PR, CI, merge and deployed
verification remain pending. Existing catalog completeness limits the number of
eligible real locations regardless of the correctness of this integration.
