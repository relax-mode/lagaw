# S4-05 — Bacolod destination sources, quality and acquisition plan

**Issue:** [#105](https://github.com/relax-mode/lagaw/issues/105)

**Prepared:** 2026-10-31 (Asia/Manila)

**Scope:** Research, field coverage, verification criteria and acquisition recommendations. No catalogue migration or data writes; image-licensing work belongs to #107.

## 1. Evidence boundaries

The committed [source dataset](../supabase/data/locations.json) and [original venue provenance](location-data-sources.md) contain ten researched records. Original sources were inspected on **2026-10-14**. The seed migration [20261014154651](../supabase/migrations/20261014154651_seed_sample_locations.sql) uses stable location identifiers and does not overwrite later manual edits. **Committed seed completeness does not establish live development or production completeness.**

The seed was re-inspected against `main` commit `96594c38cd1efeb744a45f48431611ef96a5f712` on October 31, 2026. The team sprint log reported ten active records in both hosted projects on October 29, but that **historical assertion is not a new live measurement**.

The public `GET /locations` API returns **active** locations only. A current active-record audit can be executed without any credential or database write using:

```powershell
python scripts/destination_coverage_audit.py --environment development
python scripts/destination_coverage_audit.py --environment production
```

The script is fixed to the publicly documented staging and production Cloud Run domains, uses GET only, disables redirects, paginates, prints aggregates rather than individual records, and never reads `.env`. Staging uses development Supabase; production uses a separate Supabase project. If either endpoint is unavailable, record its failure rather than supplying invented counts. Inactive rows require a specifically authorized, separately documented read-only database count; do not infer inactive totals from the public API.

### Live coverage evidence — verified on October 31

Andrew ran the script in the existing repository virtual environment on **2026-10-31** and supplied the outputs; this document records **developer-executed** checks, not direct database queries by the research author. Both HTTPS calls succeeded. Full aggregate output, timestamps, and test results are recorded in [destination source coverage evidence](evidence/destination-coverage-s4-05-2026-10-31.json).

| Environment | Observation date/time (UTC) | Active count | Coordinate pairs | Nonempty hours | Both cost bounds | Complete fields | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Development-backed staging | 2026-10-31 09:22:02 | 10 | 6 | 2 | 1 | 1 | Read-only `GET /locations`; user-run script |
| Production | 2026-10-31 09:22:04 | 10 | 6 | 2 | 1 | 1 | Read-only `GET /locations`; user-run script |
| Committed source seed (not hosted database) | 2026-10-31 | 10 | 6 | 2 | 1 | 1 | `supabase/data/locations.json` |

Both hosted environments also returned ten named/addressed records, ten categories, ten nonempty tag sets, and ten positive visit durations. **These metrics count publicly readable active destinations only**; they do not establish unlisted/inactive rows, ownership, source accuracy, licensing, venue opening status or a functioning three-stop itinerary.

## 2. Field completeness of the committed seed

Denominator **10 records**, including active seed candidates. "Field complete" is a syntactic presence check, not confirmation of factual accuracy, rights, freshness or a feasible itinerary.

| Requirement | Populated | Unknown / absent | Coverage | Qualification |
| --- | ---: | ---: | ---: | --- |
| Name and address | 10 | 0 | 100% | Venue identity supported by 2026-10-14 notes, with entry-specific caveats |
| Category | 10 | 0 | 100% | Editorial normalization, not operator-certified |
| Nonempty `vibe_tags` | 10 | 0 | 100% | Editorial labels, not operator-certified |
| Valid latitude and longitude pair | 6 | 4 | 60% | Map features may be *centers*, not actual visitor entrances |
| Nonempty `opening_hours` | 2 | 8 | 20% | Museum and Arima only; museum's published sources conflict |
| Both bounded visitor costs | 1 | 9 | 10% | Museum only; price classes differ by eligibility and conflict |
| Positive typical visit duration | 10 | 0 | 100% | All ten are **editorial planning estimates**, not measured operator times |
| Coordinates, hours, cost range and duration together | 1 | 9 | 10% | Does not prove the destination is truly itinerary-ready |

**Unknown != free.** Empty hours `{}` mean no corroborated visiting hours, *not* always open or closed. `null` costs mean unknown, *not* zero. `is_active: true` is a database listing flag, *not* a promise of current visitor availability.

The four seed records missing coordinate pairs are **Orange Project, Cafetolyo Coffee Shop, Arima Restaurant, and Calea Pastries & Coffee**. Every record except the Negros Museum lacks a complete bounded cost estimate.

## 3. Location-by-location gap register

The status below reflects the **October 14 source notes**, not a fresh on-site audit. Dates of later checks appear in the source table.

| Destination | Coordinate pair | Visitor hours | Both cost bounds | Duration basis | Immediate confirmation priority |
| --- | --- | --- | --- | --- | --- |
| San Sebastian Cathedral | Existing OSM feature | Unknown | Unknown | Editorial 25 min | Visitor access versus worship hours, admission and exterior access |
| The Negros Museum | Existing OSM feature | **Conflicting current published pages** | **Conflicting published fee classes** | Editorial 60 min | Confirm which operator schedule and fee is presently effective |
| Negros Forest Park | Historic mapped feature | Unknown | Unknown | Editorial 60 min | Operator admission, visitor sessions and entrance pin |
| Orange Project | Unknown | Unknown | Unknown | Editorial 45 min | Gallery's direct operating schedule, access terms and pin |
| Capitol Park and Lagoon | Existing OSM feature | Unknown | Unknown | Editorial 35 min | Public access hours, any events/closures and fee policy |
| Negros Occidental Provincial Capitol | Existing OSM feature | Unknown for *visitors* | Unknown | Editorial 20 min | Exterior versus building access and entry restrictions |
| Cafetolyo Coffee Shop | Unknown | Unknown | Unknown | Editorial 35 min | Café hours, menu prices and exact entrance |
| Arima Restaurant | Unknown | Daily hours in existing notes | Unknown | Editorial 75 min | Menu cost range, holiday hours and independent pin |
| Panaad Park and Sports Complex | Existing OSM feature | Unknown | Unknown | Editorial 60 min | Event versus ordinary visitor hours, fee and exact access |
| Calea Pastries & Coffee | Unknown | Unknown | Unknown | Editorial 40 min | Venue hours, menu prices and exact branch/entrance |

## 4. Sources, trust, freshness, access and rights

**The checked date means we examined a source, not that its publisher guaranteed real-time correctness.** A page footer date is not a publication/update timestamp.

| Source | Supported data and authority | Date/freshness | Access/rights and limitations | Proposed action |
| --- | --- | --- | --- | --- |
| [Negros Cultural Foundation museum tours](https://www.ncfiph.org/the-negros-museum/museum-tours/) | Foundation/operator page: Mon–Sat **08:30–16:30**; regular **PHP 150**, student/PWD/senior **PHP 120**; museum's Gatuslao address | Checked **2026-10-31**; page-update date not established | Primary operator; visiting hours and fee applicability still require confirmation for exact visit date. Public reading does not grant bulk reuse rights | **High priority:** reconcile conflict before #106 writes |
| [Older museum-branded page](https://negrosmuseum.wixsite.com/negrosmuseum/museum-hours) | Mon–Sat **09:00–18:00**; adult **PHP 100**, senior **PHP 80**, student/child **PHP 70**; figures used in seed | Checked **2026-10-31**, publication date undetermined | Conflicts with foundation page; cannot assert older schedule is current | Keep provenance and seek operator confirmation |
| [Park Inn by Radisson Arima dining](https://www.radissonhotels.com/en-us/hotels/park-inn-bacolod/restaurants-and-bars) | Venue operator; existing seed notes show 06:00–22:00 daily | Recorded in 2026-10-14 notes; **not independently rechecked in this audit** | No reviewed price list or exact restaurant-entrance coordinate; hours can vary | Recheck directly and ask about actual meal-price bounds |
| [Talarak Foundation Negros Forest Park](https://www.talarak.org/negros-forest-park) | Park identity, operations and South Capitol Road | Recorded in 2026-10-14 notes; current hours/fees not verified | Do not infer no admission or assume older mapped pin is gate | Contact operator for admission, visiting hours and entrance |
| [Orange Project official website](https://orangeproject.ph/) | Gallery identity, Mandalagan address, exhibition context | Recorded in October 14 notes; update dates vary by exhibition | A venue exhibition listing does not establish everyday opening hours, fees or geocoding rights | Ask operator directly |
| [Negros Occidental government website](https://www.negros-occ.gov.ph/) | Capitol, park and Cafetolyo existence, older reopening/event context | Some linked articles date to 2020–2026; **not a current visitor timetable** | Office-hours and COVID-era schedules cannot stand in for visiting times | Confirm relevant facility directly, retain dated article |
| [Bacolod City Tourism accredited directory](https://tourism.bacolodcity.gov.ph/accredited-directory.php) and [contact](https://tourism.bacolodcity.gov.ph/contact.php) | Municipal venue leads and operator contacts | Checked **2026-10-31**; public directory then displayed **two** establishments | Two entries do not comprise a complete Bacolod attractions directory; not an opening-hours dataset | Use for introductions and corroboration, not wholesale seed import |
| [OpenStreetMap](https://www.openstreetmap.org/copyright) and Mapcarta entries in [original notes](location-data-sources.md) | Exact-feature map points and categories for six records | Feature-specific edit dates not rechecked; existing notes from October 14 | OSM data is ODbL; attribution/share-alike applicability must be considered. Mapcarta access terms separate. Map feature center may not be a visitor entrance | Verify exact feature IDs, entrances, freshness and reuse terms |
| Other venue sites / community directories | Discovery, triangulation | Varies; often undated | User-submitted listings may be stale; browsing permissions do not imply bulk redistribution rights | Discovery only until confirmed by operator |
| Dated direct operator contact | Hours, ticket classes, accessible times, entrance and local visit estimates | Current when properly recorded | Request permission to republish facts as needed; avoid private personal contact details in repository | Preferred missing-field source |

**Important research conflict:** two museum-associated websites currently publish **different** hours and entrance prices. The foundation is a stronger current candidate, but neither page alone proves which schedule is in effect on an itinerary's actual date. #106 must document that uncertainty and verify operational applicability before a production change.

## 5. Proposed field-verification and acceptance criteria for #106

Record for each proposed update: **stable destination identity; field; old value; proposed value; publishing organization; source URL or private operator reference; observation date; actual publication/update date if known; field basis (operator, mapping, editorial estimate); rights/reuse review; verifier; confidence; unresolved conflict; exact update method**. Where the database lacks provenance columns, use a version-controlled reviewable record rather than introducing a #105 migration.

- **Operating hours:** operator-published visitor hours for the named venue, applicable weekdays and timezone Asia/Manila. Document Sunday/holiday unknowns, reservations and date-specific exceptions. Do not confuse office, mass or hotel-wide hours with venue access.
- **Costs:** distinguish *required admission* from *optional café/restaurant purchase*. Record PHP amounts, date, visitor eligibility, party/per-person scope, and included services. Only use `0` if admission is affirmatively verified free. Preserve `null` when unknown.
- **Coordinates:** pair from the exact physical venue; mark mapped feature center versus visitor entrance/drop-off. Verify routing appropriateness and geographic match before scheduling.
- **Categories and tags:** retain canonical vocabulary and label editorial classification separately from provider claims. No manufactured attributes.
- **Typical visit duration:** positive editorial planning assumption unless an operator's tour duration is explicitly published; neither is guaranteed travel or queue time.
- **Rights:** record source and attribution requirements, particularly OSM/ODbL; do not bulk copy restricted commercial map/catalogue content.
- **Rollout:** review exact-ID, idempotent and dry-run update plan; test against development Supabase before separately authorizing production writes; do not replace newer manual corrections.

## 6. Acquisition plan and maintenance cadence

1. **Measure current hosted coverage first.** Save timestamped aggregate counts for both environments; request authorized read-only database inventory if inactive-row coverage matters. No sensitive data or service keys.
2. **Resolve museum conflict directly.** Record who confirmed current museum hours and each admission class; retain both published pages and observation timestamps.
3. **Prioritize two additional nearby real destinations** that can be verified for the same day: admission/spend estimate, safe opening window, visit time and routing entrance. Three real stops are required for #106's production acceptance; one complete seed record is insufficient.
4. **Contact remaining operators in batches** for hours, fees, exact access pins and exceptions, preserving source/date and publication permissions. Do not replace unknown data with guesses.
5. **Proposed operations cadence, not a publisher requirement:** recheck hours and costs monthly during final-demo preparation and immediately on changes; check addresses/pins quarterly or on routing failures; editorial tags after venue changes. Never treat an old checked date as proof of current operation.
6. **Issue handoff to #106:** only approved/source-qualified records are eligible for repeatable updates; demonstrate three actual production stops with times, travel, route order and costs or document precisely why this cannot be completed.

## 7. Honest outcome and remaining blockers

- **Verified from committed files:** ten locations, six coordinate pairs, two nonempty hour objects, one bounded cost range, ten editorial durations.
- **Verified from currently accessible public sources on October 31:** the two museum pages disagree about visitor hours and admission; the tourism accredited directory shows only two entries.
- **Verified by Andrew using live public APIs on October 31:** development-backed staging and production each expose 10 active destinations, six coordinate pairs, two nonempty hours, one cost range and one field-complete record (09:22:02 / 09:22:04 UTC). These are **public API observations**, not comprehensive direct database audits.
- **Verified by Andrew locally, latest checks:** `python -m pytest -q backend/test_destination_coverage_audit.py` → **9 passed in 0.06 s** after fixes; `python -m ruff check . ../scripts/destination_coverage_audit.py` → **All checks passed**. The broader Windows suite reported **762 passed, 2 failed, 106 deselected** in 16.99 seconds; both failing tests belong to pre-existing #94 model-seeding work and compare file permissions to POSIX `0o600`, whereas Windows returned `0o666`. The #94 implementation and tests were left unchanged. Repository CI is still pending.
- **Not yet verified:** inactive location counts, direct operator current hours/fees, a real three-stop production itinerary, or a reviewed/merged PR. Inactive counts would need separately approved read-only database access if required.
- **Before issue closure:** review PR, record CI results, obtain teammate approval, merge via the approved process and confirm the deployed documentation/evidence as appropriate. Avoid marking issue complete merely because the research and public API checks passed.

This research is **not** a claim that any migration, production write, image-rights decision or three-stop production itinerary has occurred.
