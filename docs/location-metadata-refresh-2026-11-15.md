# Existing-location metadata refresh — November 15, 2026

Separate task requested by Andrew. Updates existing records only; the cancelled
alternative venues are not added. `.env` is unchanged. This is a qualified
user-supplied data update, not operator verification or a claim that #106's
historical three-stop production blocker is resolved.

## Applied in development

| Existing location | Missing fields filled |
| --- | --- |
| Arima | Supplied coordinate pair rounded to six decimals; PHP 500–1,000 indicative spending |
| Cafetolyo | Coordinate pair; Mon–Sat 06:00–19:00; PHP 70–120 indicative spending |
| Calea | Coordinate pair; Mon–Thu 09:00–21:30, Fri–Sun 09:00–22:00; supplied PHP 95–1,100 menu-price estimate |
| Capitol Park and Lagoon | Daily 05:00–22:00; explicit reported free ordinary entry |
| Negros Forest Park | Tue–Sun 09:00–17:00; historical admission PHP 50–100 by eligibility |
| Orange Project | Coordinate pair; Mon–Sat 13:00–19:00, Sun 13:00–17:00; indicative exhibition admission PHP 0–50 |
| San Sebastian Cathedral | Mon–Sat 06:00–19:00, Sun 05:00–20:30; reported free entry |

Descriptions carry material price/access qualifications so these estimates are
not presented as operator-confirmed guarantees. All other fields, including
current image URLs, IDs, tags, categories, groups and editorial visit estimates,
are preserved. The Negros Museum is untouched.

Andrew explicitly declined further link collection and instructed use of his
supplied values. The [plan and separate environment baselines](../supabase/data/location-metadata-refresh-2026-11-15.json)
record that authorization, sources and uncertainty. Google Maps pins and Cafetolyo
Facebook figures are attributed to Andrew; exact listing/post links were not
provided and no independent inspection is claimed. Calea's schedule is also
user-supplied. A blank weekday is unspecified, not necessarily closed.

## Qualifications and deferred entries

- Arima/Google Maps spending is an estimate, not a guaranteed total or admission.
- Calea's menu range mixes products such as slices and whole cakes. It does not
  establish a per-person meal cost; the displayed estimate is a user-selected
  purchase allowance. The planner uses its upper value as an estimated allowance,
  so recommendations may be conservative. Mandatory extras are not independently
  verified. No exact June menu was inspected.
- Forest Park references are historical (2022); one source lists 08:00 opening
  while Andrew supplies 09:00. The imported 09:00 is the user-selected later time,
  not a claim the conflict has been independently resolved. PHP 50 is discounted,
  not available to all visitors; PHP 100 is the cited adult estimate.
- Orange's cited PHP 50 article concerns March–June 2026 exhibitions; admission
  changes by exhibition. Corner's fetched text confirms Sunday hours, not a full
  current week; other weekdays are Andrew's supplied schedule.
- Cathedral hours/free admission are corroborated by the Pinay Solo Backpacker
  guide. Splendor lists Mass times, not uninterrupted sightseeing access. Respect
  worship and event restrictions; this is not a guaranteed tourist-access window.
- **Provincial Capitol remains unchanged.** A government site's contact/office
  hours do not establish access to tourist areas; the supplied free entry has no
  visitor-specific evidence. The guide also lists different building hours.
- **Panaad remains unchanged.** Andrew labels the Reddit claims unverified and
  distinguishes oval-use fees from general park access. They are retained as
  deferred observations, not converted into park-wide opening hours or admission.

Sources checked where accessible:

- [Pinay Solo Backpacker](https://thepinaysolobackpacker.com/bacolod-things-to-do/)
  explicitly distinguishes park/building hours and reports free entry.
- [Out of Town, May 2022](https://outoftownblog.com/negros-forest-park-wildlife-sanctuary-in-bacolod-city/)
  supplies historical eligibility-based Forest Park fees and an 08:00 opening.
- [Negros Season of Culture](https://www.negrosseasonofculture.com/2022/01/negros-forest-park.html)
  could not be fetched (Google anti-bot redirect); no independent confirmation claimed.
- [Corner](https://www.corner.inc/place/pzjH9f66PJxV),
  [The Benildean, May 2026](https://thebenildean.org/2026/05/land-of-smiles-a-taste-of-bacolod-city),
  [Splendor](https://splendor.church/c/sansebastiancathed08).
- The provincial home page returned HTTP 403 during this review. Prior recorded
  footer office hours are not reclassified as visitor hours.

## Execution and checks

`scripts/refresh_location_metadata.py` is offline by default. It validates the
fixed seven proposals against both snapshots, requires paired coordinates/costs,
and fills only empty/null metadata. The description changes supply qualifications.
Preflight refuses administrator edits before writing. Each REST PATCH also
compares all touched fields to their expected values, preserves unrelated fields
and supports a no-op rerun. REST operations are atomic per record, not across the
whole batch: after an error, inspect state before retrying.

The first live attempt hit a string-filter quoting mismatch and returned no
updated row. The guard stopped execution. Corrected PostgREST equality filters
then updated seven rows successfully. The immediate rerun changed zero. Full
public readback verified all ten records equal their prior values plus only the
intended patches. The original ten identities and image URLs remain intact.

- Focused metadata/enrichment/coverage/planner tests: **77 passed**.
- Focused Ruff: **passed**.
- [Development receipt](evidence/location-metadata-development-2026-11-15.json).
- [Public API readback](evidence/location-metadata-readback-2026-11-15.json).
- Development now has 10 coordinate pairs, 8 schedules and 8 cost ranges.
- Production is unchanged: 6 coordinate pairs, 2 schedules, 1 cost range.
- These counts measure populated fields, not verified real-world feasibility.

## Production handoff: credential blocked

The exact [production transaction](location-metadata-production-2026-11-15.sql)
is prepared, outside automatic migrations. It checks each target ID/name and old
field value; reruns are no-ops and a stale/missing row aborts the entire transaction.
Select production project **zjnuqqtbapbpudsjbpif** in Supabase SQL Editor before
reviewing/executing it. Do not run it in development merely to test production.

Alternatively, an operator may supply `LOCATION_METADATA_PRODUCTION_KEY` in the
current process environment and run:

```powershell
.venv/Scripts/python.exe scripts/refresh_location_metadata.py --environment production --execute
```

Never paste a key into chat or source control. No `.env` edit is necessary. The
fixed production endpoint does not reuse the development credential. A matching
development receipt is required before production execution or SQL generation.
Only credential presence was reported; no secret values were displayed.

Production execution was attempted and blocked **before networking/writes** because
that credential is absent. Production must be read back separately after an
authorized operator executes the transaction; this document does not claim it
has been applied. No synthetic locations, image uploads, schema changes or
changes to the recommender/planner were made.
