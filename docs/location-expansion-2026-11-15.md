# Twenty-location catalogue expansion

Adds twenty Bacolod catalogue records using the November 15 metadata request.
Development has been updated and verified; production remains pending operator
execution because its write credential is unavailable. This is separate from the
closed #106 evidence decision.

## Records and supplied values

| Destination | Recorded schedule | Indicative PHP range |
| --- | --- | --- |
| Artfull Philippines / Gallery and Cafe | Mon-Fri 08:00-20:00; Sat 08:00-17:00 | 100-950 |
| Lopue's East Bowling Center | Mon-Fri 12:00-22:00; Sat-Sun 10:00-22:00 | 100-160 |
| May's Organic Garden and Restaurant | Daily 08:00-18:00 | 150-350 |
| Quan Native Delicacies - Plaza | Daily 08:00-19:00 | 1-500 |
| The Negros Showroom - South Capitol Road | Daily 09:00-17:00 | 0, browsing only |
| Coffee Culture Roastery - Alijis | Daily 09:00-18:00 | 75-450 |
| Manokan Country - temporary SM site | Daily 09:00-23:00 | 100-250 |
| Pope John Paul II Tower | Daily 08:00-17:00 | 10 student; 20 regular |
| kidzooona - SM City Bacolod | Daily 10:00-22:00 | 230-400 |
| Ayala Malls Capitol Central - general visit | Mon-Fri 11:00-21:00; Sat-Sun 10:00-21:00 | 0, general entrance |
| Timezone - Ayala Malls Capitol Central | Daily 10:00-21:00 | 5-1100 |
| Caribbean Waterpark and Resotel - day use | Daily 08:00-20:00 | 120-250, eligible paid categories |
| Resorts Negrense - day use | Fri-Sun 07:00-22:00 | 50-2800 |
| Merzci - Sum-ag branch | Daily 06:00-20:00 | 15-350 |
| Sharyn's Cansi House - Narra | Daily 08:00-20:00 | 85-580 |
| Aboy's Restaurant - Liroville | Mon-Sat 10:00-22:00 | 50-480 |
| Palawud Resto Grill and Bar - San Juan/Banago | Daily 11:00-23:59, conservative midnight cutoff | 225-2000 |
| Kuppa Coffee and Tea - Tindalo | Daily 07:00-22:00 | 110-500 |
| Fully Booked - SM City Bacolod | Daily 10:00-22:00 | 0, entry only |
| Negros Superlanes - Goldenfield | Tue, Thu-Sun 16:00-23:59, conservative midnight cutoff | Unknown; both fields null |

The supplied Manokan hours have no weekday restriction and are interpreted as
daily. Other omitted weekdays remain unspecified, including Wednesday at Negros
Superlanes. No omitted weekday has been invented as an open interval. The existing
planner cannot represent 24:00 or an overnight 00:00 closing; two midnight closes
are conservatively recorded as 23:59. Original midnight wording is retained in
descriptions and provenance. No planner or frontend code was changed.

The ten supplied Google Maps pairs replace conflicting research pins. The other
ten retain the researched approximate pins; they are not claimed as verified
entrances. All pairs are rounded to the database's six-decimal precision.

## Source and planning qualifications

- The [manifest](../supabase/data/location-expansion-2026-11-15.json) records each
  field's source, original coordinate precision, source labels without direct
  URLs, and outstanding verification. The [CSV](../supabase/data/location-expansion-2026-11-15.csv)
  contains the final records with source columns.
- Explicitly requested ranges are stored as indicative estimates, with short
  qualifications in descriptions and no personal supplied-by wording. Menu
  items, shared dishes, creative purchases, game loads, amenities and rentals
  are not necessarily per-person visit costs or guaranteed maximums. In
  particular, the Resorts Negrense PHP 2800 upper bound may be a rental/package
  cost. The current planner uses cost maxima per person, so this can conservatively
  exclude it from lower-budget itineraries. No pricing-model change is included.
- Lopue's bowling prices remain an unverified Reddit report. No current
  independent venue confirmation is claimed for every record. Aboy's linked
  menu includes shared and weight-priced food and other items outside the
  requested selected-item range.
- Caribbean's retained operator range covers paid categories: below-three-feet
  PHP 120/150 weekdays/weekends; regular PHP 200/250; senior/PWD PHP 200 with ID;
  under one year is listed free. The scalar range does not implement age/height
  pricing rules. Holiday policy and boundary details remain to be confirmed.
- Durations, categories and group suitability are editorial. Tags use the
  existing six canonical travel tags so the current app can consume the data.
- Ordinary catalogue visits only: booked workshops, tours, rooms, cottages,
  private events and other reservation-required experiences are excluded. An
  active record does not guarantee current walk-in availability.
- All twenty new `image_url` fields are null, as requested. The original ten
  records, their IDs and images, and all unrelated data remain unchanged.
- Negros Superlanes has no price evidence. Null is preserved; it is not treated
  as free. Missing cost can exclude it from budget-constrained recommendations.

## Execution and verification

`scripts/add_catalogue_locations.py` is offline by default. It validates the fixed
twenty-record manifest, checks exact baseline/identity values, and uses a single
plain bulk INSERT, never an upsert, PATCH or DELETE. Matching records are accepted
as no-op reruns; edited or unexpected records block before inserting. New UUIDs
are deterministic and identical across environments.

Development inserted twenty rows, bringing its active catalogue from ten to
thirty. Rerun inserted zero. Full public API readback matched all thirty expected
records and preserved the original ten. Production's public API still matches
its original ten-record baseline.

- Focused catalogue, metadata, enrichment, coverage and planner tests: **88 passed**.
- Focused Ruff: **passed**.
- [Development receipt](evidence/location-expansion-development-2026-11-15.json).
- [Public API readback](evidence/location-expansion-readback-2026-11-15.json).
- Development has 30 coordinate pairs, 30 schedules and 29 bounded cost ranges.
- No additional automated database test was run locally because `psql` is absent.
  CI database checks are separate; the manual transaction still needs production
  execution and readback.

## Production handoff

In Supabase SQL Editor, select production project **zjnuqqtbapbpudsjbpif**, then
review and execute [the production transaction](location-expansion-production-2026-11-15.sql).
It locks catalogue writes during the transaction, checks the exact original
baseline and identities, inserts the twenty new records, accepts identical
reruns, and aborts the entire transaction on edited or unexpected records. This
file is outside automatic migrations: merging the PR does not execute it.

Alternatively, an operator can provide `LOCATION_METADATA_PRODUCTION_KEY` in the
current process environment and run:

```powershell
.venv/Scripts/python.exe scripts/add_catalogue_locations.py --environment production --execute
```

The production command requires the matching development receipt and uses only
the fixed production endpoint and its dedicated key. No `.env` edit is needed.
The attempt in this session stopped before networking or writes because that key
is absent. After SQL execution, verify all twenty new production records and
preservation of the original ten through the public API. Production completion is
not claimed in this document.
