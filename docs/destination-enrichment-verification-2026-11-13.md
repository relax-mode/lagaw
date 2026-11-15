# #106: current catalogue verification and deployment handoff

Checked November 13, 2026. Owner: Andrew. Scope: S4-06 only.

## Result and evidence

Existing records remain the preferred enrichment target. No three-stop itinerary
can be certified from the evidence currently available. Alternative venues are
research candidates, not approved replacements or deployed additions.

- [Live public-API snapshot](evidence/destination-live-gaps-2026-11-13.json):
  development first at 15:47:29 UTC, then production at 15:47:36 UTC.
- [Candidate review and source rechecks](evidence/destination-candidate-review-2026-11-13.json):
  scraped source IDs, published claims, source roles, freshness limits and caveats.
- [Existing approved enrichment workflow](destination-enrichment-s4-06.md)
  and [unapproved manifest](../supabase/data/destination-enrichment-s4-06.json).

Both environments expose 10 active destinations, six coordinate pairs, two hour
schedules, one bounded cost range and ten positive editorial visit durations.
Only the Negros Museum has all four scheduling fields populated. This is a
presence measurement, not proof of accurate prices/hours or a feasible schedule.
Only public active records were measured; inactive/private database rows were
not inspected. Matching scheduling fields do not prove full database parity.

## Existing records: remaining work

| Destination | Field gaps / factual blockers | Next evidence needed |
| --- | --- | --- |
| The Negros Museum | Saved 09:00-18:00 / PHP 70-100 conflicts with foundation's 08:30-16:30 / PHP 120-150 | Dated confirmation of current visitor schedule, regular adult fee, discount eligibility and entrance |
| Negros Forest Park | Hours and costs absent; operator page does not resolve them | Current visitor hours, admission classes and entrance |
| Capitol Park and Lagoon | Hours and costs absent; prior listings disagree | Responsible authority's public access window, admission/free-entry statement and restrictions |
| San Sebastian Cathedral | Visitor hours and costs absent | Sightseeing access versus worship schedule, admission policy and entrance |
| Negros Occidental Provincial Capitol | Hours and costs absent | Areas tourists can visit, public visiting hours and any fee |
| Panaad Park and Sports Complex | Hours and costs absent | Ordinary visitor access outside festivals/sports bookings, fees and entry point |
| Orange Project | Coordinates, hours and costs absent | Review operator-linked pin; confirm current gallery hours and general admission policy |
| Arima Restaurant | Coordinates and costs absent; daily 06:00-22:00 agrees with operator page | Venue entrance and dated meal/menu evidence defining the costed visit |
| Cafetolyo Coffee Shop | Coordinates, hours and costs absent | Exact branch, entrance, current hours and dated prices for a defined visit |
| Calea Pastries & Coffee | Coordinates, hours and costs absent | Exact branch, entrance, current hours and dated prices for a defined visit |

Existing durations are editorial estimates, not operator measurements. Retain
that qualification. Existing map-feature coordinates still need entrance review.
Unknown cost cannot become zero, and missing hours cannot become all-day access.
An event's free snacks or provincial website office hours do not establish
general park admission or opening hours.

## Alternatives: conditional use only

All five alternatives below match records in Andrew's CSV. The CSV itself remains
an untracked research input; its 4,784 entries are not imported or approved.

| Candidate | Fit and useful evidence | Why it is not ready to import |
| --- | --- | --- |
| Museo De La Salle-Bacolod | Heritage; MFPI directory explicitly lists free entry and weekday split hours; university confirms identity | Confirm non-student campus access, appointment rules, applicable schedule and entrance |
| Jojo Vito Designs Gallery | Local art/MassKara; owner-authored historical free-entry/hour statement | Refresh policy/hours; resolve entrance; exclude paid painting from a free browsing visit |
| Bantug Lake Ranch | Nature; venue publishes admission and weekly hours | Resolve entrance-pin difference, date applicability and source-integrity caveat; define admission-only visit |
| Caribbean Waterpark and Resotel | Family recreation; operator publishes daily hours and weekday/weekend day-pass prices | Deduplicate competing pins; check holiday rates, rental requirements and sufficient swim time |
| Timezone Capitol Central | Indoor recreation; operator hours and card-loading terms | A prepaid load is not admission or guaranteed gameplay duration; cost semantics need review |

For cultural trips, prioritize the museum and Jojo Vito. Bantug is a nature
option. Caribbean is suitable for an intentional swimming trip, not automatically
a short sightseeing stop. Timezone is a lower-priority recreation option.
Do not choose three venues just because their data is easier to obtain.

No route is demonstrated here. Preferences, selected weekday, budget, entry rules,
travel allowances and visit lengths must work together before claiming feasibility.

## Questions Andrew can resolve without further broad research

If there are replies to Andrew's earlier venue emails or dated visit notes, use
those first. No one was contacted during this work. The narrow questions are:

1. Museum: which published schedule and admission table currently applies, on
   what dates, and where should a visitor enter?
2. Forest Park / Lagoon / Orange Project: what are the visitor hours, required
   admission (explicitly free if applicable), exceptions and correct entrance?
3. If using alternatives: can an outside visitor enter Museo De La Salle without
   an appointment, and does Jojo Vito still offer free browsing at the stated hours?

Keep a dated, attributable reference and reviewer decision. Avoid committing
private messages or personal contact details. For restaurants, identify the
specific meal/visit being costed and include mandatory charges; a review-site
average or cheapest menu item is not an upper spending bound.

## Development before production

No hosted writes were attempted because there are no approved updates. No
credentials or `.env` contents were read or changed. The public API checks require
neither. Production GETs above are a baseline audit, not a production write test.

When evidence arrives:

1. Reconcile proposed values with the current **development Supabase project**
   and record stable IDs and exact expected prior values. Existing records keep
   their IDs; avoid duplicates. New venues require a reviewed insert plan: the
   current planner only updates its four allowlisted seed venues, so it cannot
   silently import alternatives or Orange Project.
2. Complete source/reviewer approval, then generate and review guarded SQL.
   Confirm the target project independently; do not switch targets by editing
   `.env`. If execution requires configuration unavailable in the session,
   document exactly what is missing before proceeding.
3. Execute authorized changes in development, rerun for no-op behavior, verify
   administrator fields survive, and test the existing generation endpoint plus
   saved-plan reload. No synthetic venue data enters hosted projects.
4. After review, reconcile the separate production baseline, release the reviewed
   changes, and verify three real persisted stops with visit date, arrival and
   departure times, incoming travel time, defined costs and total budget evidence.

Until then, #106 remains blocked on factual confirmation. Its documented-blocker
acceptance option can be considered by the reviewer; this record does not claim
catalogue enrichment is deployed or authorize automatic issue closure.

## Validation performed

- Focused enrichment and coverage tests: **35 passed in 0.09 seconds**.
- Ruff for the two existing scripts and their focused test files: **passed**.
- Offline planner: 10 seed records, four blocked candidates, zero approved updates,
  zero writes and no proven three-stop itinerary.
- Existing tests cover simulated repeat application, preservation of unrelated
  values and rejection of stale edits. No live database rerun test is claimed.
- Evidence JSON validation and whitespace checks passed. PR CI is reported on
  GitHub separately; local success is not deployed acceptance evidence.

## Publication handoff

Branch: `docs/s4-06-catalogue-verification`. Git push succeeded. The connected
GitHub integration returned HTTP 403, `Resource not accessible by integration`,
for both PR creation and the #106 update comment. No local GitHub CLI is installed.
No PR or comment was created and no PR CI result is claimed.

[Open the PR comparison](https://github.com/relax-mode/lagaw/compare/main...docs/s4-06-catalogue-verification?expand=1).
Suggested title: **docs(data): verify catalogue gaps and record #106 release blockers**.

Copy-ready PR description:

> Refs #106. Records a fresh development-first and production-second public
> catalogue audit: ten active destinations per environment, only one with all
> scheduling fields populated, and unresolved source conflicts. Adds the dated
> snapshot, candidate/source review, exact existing-record gaps and concrete
> verification questions. Corrects the stale PR #130 implementation status.
>
> Validation: 35 focused tests pass; Ruff, JSON parsing and whitespace checks
> pass. The offline planner still reports four blocked candidates, zero approved
> updates and zero writes. No `.env` access, catalogue changes or deployed
> three-stop itinerary. Alternatives remain conditional; development verification
> must precede production changes. Please review the documented blocker; do not
> automatically close #106 or treat this as deployed enrichment.

Copy-ready #106 update comment:

> Branch `docs/s4-06-catalogue-verification` contains the November 13 live audit
> and verification handoff. Development was checked before production using
> credential-free GETs only. Both expose ten active records but only one
> field-complete candidate, with factual conflicts unresolved. 35 focused tests
> and Ruff pass. No `.env` edits or hosted writes. Dated operator replies or visit
> notes are needed before approving catalogue changes; alternatives are not yet
> imported. See `docs/destination-enrichment-verification-2026-11-13.md` and link
> the PR here once opened. #106 remains open pending review/acceptance.
