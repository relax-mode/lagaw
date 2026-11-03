# S4-06 — Destination catalogue enrichment, provenance and release gates

**Issue:** [#106](https://github.com/relax-mode/lagaw/issues/106)
**Evidence checked:** 2026-10-31 (Asia/Manila)
**State:** Implementation prepared for review; **zero source-approved updates, zero database writes, and no verified three-stop production itinerary**. Andrew ran the offline planner and focused tests on October 31: **26 passed in 0.05 s**. The initial Ruff check reported **FURB157 and SIM102** in the planner; both were corrected, and the final Ruff rerun reported **All checks passed**. GitHub CI and reviewed deployment remain pending.

## Why #106 is not yet a data deployment

The approved [#105 source audit](destination-sources-s4-05.md) measured both staging and production on 2026-10-31. Both public APIs listed **10 active locations**, with **6 coordinate pairs, 2 hour schedules, 1 known upper/lower cost pair, and 1 syntactically complete itinerary candidate**. The only complete candidate, the Negros Museum, has two conflicting published operating schedules and pricing classes. These are read-only measurements; no production users, inactive rows or database writes were examined.

The [itinerary generation contract](itinerary-generation-api.md) requires a usable opening interval on the planned weekday, a coordinate pair, a positive visit duration and a known **upper** venue cost, plus a budget/travel-feasible sequence. The current committed seed cannot honestly demonstrate three distinct, fully supported stops. **Unknown cost is not free**; `{}` hours are not all-day availability. A successful CI build is not proof of a real visitor itinerary.

## New reviewable source evidence

`supabase/data/destination-enrichment-s4-06.json` contains field-level observations, dated public source links, qualifying caveats, immutable IDs, proposed changes where applicable and an explicit default-deny approval record.

| Real seed destination | Operator/source findings checked on October 31 | Missing evidence and approval decision |
| --- | --- | --- |
| **The Negros Museum** | Managing foundation advertises Monday–Saturday **08:30–16:30**; regular **PHP 150**, student/PWD/senior **PHP 120**. Older museum-branded site advertises **09:00–18:00**; adult **PHP 100**, student/child **PHP 70**, senior **PHP 80**. Stable museum mapping coordinates and editorial 60-minute estimate already exist | Conflicting published schedules and price classes; no direct current operator confirmation of which values apply on a chosen visit date. **Blocked**. The proposed values in the JSON are *not approved or applied* |
| **Negros Forest Park** | [Talarak Foundation's venue page](https://www.talarak.org/negros-forest-park) confirms public visitor access at South Capitol Road. A historical third-party guide quotes **08:00–17:00 Tue–Sun** and PHP 50–100 by class; an independently editable Waze listing says **09:00–17:00 Tue–Sun** | Current operator hours, fees, eligibility and **entrance/drop-off coordinate** have not been confirmed. **Blocked** |
| **Capitol Park and Lagoon** | Published third-party listings disagree: **05:00–22:00**, **08:00–17:00**, and **24/7**. Some assert free entry. A mapped park-feature center is already in the seed | No current responsible provincial authority confirmation of visitor access hours, free entry, gate/drop-off or special event restrictions. **Blocked** |
| **San Sebastian Cathedral** | A 2024 third-party travel/audio guide quotes 06:00–20:00 and free entry, while a local guide advises checking worship services | Requires current cathedral authority confirmation of public sightseeing versus worship hours, entrance, admission and photography/access rules. **Blocked** |

For exact links, source publishers and observation dates, see the manifest; the original seed identity, coordinates, tags and editorial durations remain unchanged.

**Source links checked October 31, 2026:**
- Museum (managing foundation): https://www.ncfiph.org/the-negros-museum/museum-tours/
- Museum (older branded page): https://negrosmuseum.wixsite.com/negrosmuseum/museum-hours
- Negros Forest Park (operator): https://www.talarak.org/negros-forest-park
- Forest Park historical guide: https://outoftownblog.com/negros-forest-park-wildlife-sanctuary-in-bacolod-city/
- Forest Park mapping hours: https://www.waze.com/live-map/directions/ph/western-visayas/bacolod/negros-forest-park?to=place.ChIJHc9QrprRrjMRg6Cl6HZ4VUM
- Capitol Park recent travel guide: https://thepinaysolobackpacker.com/bacolod-things-to-do/
- Capitol Park mapping hours: https://www.waze.com/en-GB/live-map/directions/ph/western-visayas/bacolod/capitol-park-and-lagoon?to=place.ChIJU_vwLKnRrjMRbrWcHvpUYKU
- Capitol Park travel listing: https://www.traveloka.com/en-ph/explore/destination/bacolod-things-to-do/63719
- Cathedral guide last reviewed 2024: https://audiala.com/en/philippines/bacolod/san-sebastian-cathedral
- Cathedral local guide: https://bacolod.com/places/san-sebastian-cathedral

**Freshness:** These are **retrieval/check dates**, not a claim that the publisher updated the content on October 31. The legacy museum page is undated; some third-party sources are historical. Publicly readable facts do not grant automatic image reuse rights. No new image or venue was imported.

## Safe enrichment mechanism

New `scripts/plan_destination_enrichment.py` is **offline and dry-run-only**. It reads the committed `supabase/data/locations.json` and evidence manifest, validates stable IDs, sources, dates, exact prior values, approved field names, weekday interval formatting, coordinate pairs and nonnegative centavo-bounded costs. It cannot authenticate to Supabase or execute SQL.

Run from the repository root with Python 3.12:

```powershell
python scripts/plan_destination_enrichment.py
python -m pytest -q backend/test_destination_enrichment.py
cd backend
python -m ruff check . ../scripts/plan_destination_enrichment.py
cd ..
```

The summary must currently report **0 approved updates**, four blocked source candidates, and **0 production writes**. The optional `--emit-sql` flag **must fail closed** today because there are no approved candidates. It only prints SQL to stdout; it never connects to a server, runs `psql` or changes a file/database.

After an operator supplies dated, attributable confirmation and the project owner approves a specific target:
1. Review the venue and applicability for actual travel dates, required admission by visitor eligibility, optional purchases, exact entrance pin, visitor hours and publication/reuse terms. Record a direct operator confirmation reference (never private contact details or secret values in Git) and a named reviewer/date; explicitly mark a verified-free admission claim before introducing **0** costs.
2. Re-inspect the current **target environment** rows with an authorized **read-only** account and reconcile any value that differs from the committed expected baseline. Do not assume staging equals production.
3. Mark approved candidates and confirm proposed values in the manifest. The offline planner can then **print** a PostgreSQL transaction for review via `python scripts/plan_destination_enrichment.py --emit-sql`. It uses stable seed UUIDs and names, compares every touched column to its expected prior value, and refuses stale/missing rows. A successful rerun becomes a no-op. Other administrator-managed columns are untouched.
4. Review the exact SQL separately and obtain **explicit approval** before executing any migration or production write. The generated SQL is **not automatically imported** as a Supabase migration. First verify against disposable/staging data with the appropriate access and repeat twice; verify administrator edits survive and rollback on conflicts. Record actual before/after counts and reviewer sign-off.
5. Only after authorized deployment, create an owned test trip and call the existing authenticated `POST /api/v1/trips/{trip_id}/generate-itinerary` with `planned_visits: 3`, valid group/tags/budget, a clearly specified date and pace, and approved origin/transportation settings. Confirm that exactly three *real* distinct persisted locations have in-window arrival/departure, incoming travel times and non-guessed total PHP costs, and that repeated reads return the same itinerary.

## Specific production-acceptance blocker

A *potential geographically nearby set*, **The Negros Museum → Negros Forest Park → Capitol Park and Lagoon**, uses three real seed venues. This is **a verification target only**, not an itinerary recommendation or claim that they are open, fee-confirmed or mutually routeable. In the committed production catalogue:
- Museum opening hours/fees contradict one another in operator-associated pages.
- Forest Park has no verified current admission bounds or visiting window (third-party hour listings disagree).
- Capitol Park has no verified current admission/free-entry policy or visitor window (published listings disagree).
- A map-feature coordinate is not a verified entrance, and driving/walking distance estimates in #54 are heuristic rather than real road/traffic evidence.

Thus **no feasible three-stop production itinerary has been demonstrated**, and this document records the precise unmet criteria as required by issue #106. Do not fake a successful three-stop demonstration, insert synthetic locations, run arbitrary SQL, turn null into zero or close the issue based only on passing unit tests.

## Tests, review and handoff

`backend/test_destination_enrichment.py` includes offline checks for:
- Stable source IDs, source dates, source inventory and default-deny approvals.
- Refusal to generate any SQL when no candidate is approved.
- Repeated application idempotence and preservation of other fields.
- Abort on stale administrator edits; guarded SQL uses equality/null-safe preconditions.
- Invalid/unapproved candidates, zero-fee policy, malformed hours, missing coordinate pairs, duplicate/unknown venues, and source-manifest immutability.

**Evidence status:** Andrew ran the dry run and verified **10 seed records, 4 source-blocked candidates, zero approved updates, zero writes and no verified three-stop itinerary**. `python -m pytest -q backend/test_destination_enrichment.py` returned **26 passed in 0.05 s**. Initial `python -m ruff check . ../scripts/plan_destination_enrichment.py` reported two style findings (FURB157 and SIM102), which have been corrected; the final Ruff rerun reported **All checks passed**. GitHub CI remains **pending**. Previous #105 production coverage is valid as a dated October 31 observation, not a fresh deployment-specific #106 write test. The broader Windows backend suite previously had unrelated #94 POSIX file-mode assertions failing on Windows; do not relax them. Coordinate review with #105 researchers and the DevOps owner; route all changes through a reviewed PR and a separately authorized release.
