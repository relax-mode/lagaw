# Supplied Capitol and Panaad metadata follow-up

Andrew explicitly requested filling the two remaining destinations with his supplied values on November 15, 2026, despite the previously documented source limitations. This supersedes the prior decision to defer these two records.

| Destination | Opening hours | Estimated cost |
| --- | --- | --- |
| Negros Occidental Provincial Capitol | Tuesday-Friday, 08:00-19:00 | PHP 0-0 (free, as reported by Andrew) |
| Panaad Park and Sports Complex | Daily, 04:00-20:00 | PHP 0-25 |

Capitol hours cite https://www.negros-occ.gov.ph/ and may represent office operations. Panaad hours and fees are user-supplied unverified Reddit reports: PHP 25 regular and PHP 15 student for the oval. Daily hours interpret the supplied schedule without a weekday restriction. Other Capitol days remain unspecified. These qualifications are stored in the destination descriptions; they do not represent independently verified visitor access.

Development applied two records, preserved unmanaged fields, and changed zero on rerun. Full public readback matched all ten expected records. Development now has 10 schedules and 10 cost ranges. Production still has 8 of each and is unchanged in this follow-up because its credential is unavailable. No environment files were changed.

In production project `zjnuqqtbapbpudsjbpif`, execute [the guarded transaction](location-metadata-supplied-production-2026-11-15.sql), then read back the production API. It checks exact identities and previous values, aborts on stale or missing records, and supports no-op reruns. This SQL is outside automatic migrations. Merging does not execute it.

See [manifest](../supabase/data/location-metadata-supplied-followup-2026-11-15.json) and [execution/readback evidence](evidence/location-metadata-supplied-followup-2026-11-15.json).
