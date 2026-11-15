# Destination description attribution cleanup

Remove personal supplied-by wording from Cafetolyo, Calea, Provincial Capitol, and Panaad public descriptions. Keep schedule, cost, coordinate, image and other metadata unchanged, along with existing source/verification qualifications. Previous audit snapshots remain historical records.

Development changed four descriptions, rerun changed zero, and full public readback matched all ten expected records. No application code, schema or environment files changed.

Production is pending because its write credential is unavailable. Execute [the guarded SQL transaction](location-description-cleanup-production-2026-11-15.sql) in production project `zjnuqqtbapbpudsjbpif`, then verify production readback. Merging does not execute SQL.

[Manifest](../supabase/data/location-description-attribution-cleanup-2026-11-15.json) and [verification evidence](evidence/location-description-attribution-cleanup-2026-11-15.json).
