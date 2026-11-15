# Consistent destination categories

The twenty added destinations used narrow machine identifiers such as
`art_gallery` and `local_food`. The app treated these as new categories and
displayed their identifiers. This follow-up groups them under the existing
categories where appropriate and introduces only three broad categories.

| Display category | Stored ID | Added destinations |
| --- | --- | --- |
| Art | gallery | Artfull |
| Dining | restaurant | Quan Plaza, Manokan, Sharyn's, Aboy's, Palawud |
| Cafés | cafe | Coffee Culture, Kuppa |
| Parks | park | May's Garden |
| Heritage | heritage | Pope John Paul II Tower |
| Activities | recreation | Lopue's Bowling, kidzooona, Timezone, Negros Superlanes |
| Shopping | shopping | Negros Showroom, Ayala Capitol Central, Merzci, Fully Booked |
| Resorts | resort | Caribbean Waterpark, Resorts Negrense |

Museum and Landmark categories remain unchanged. Development now has ten total
categories rather than twenty-three. The original ten destinations keep their
existing categories. Only nineteen records needed a category change; Coffee
Culture already used `cafe`.

## Data verification

The [category manifest](../supabase/data/location-category-normalization-2026-11-15.json)
lists the exact twenty identities and before/after category values for each
environment. The existing guarded refresh helper updated nineteen development
rows and changed zero on rerun. Full readback matched all thirty expected records,
preserving every non-category field and the original ten records.

[Execution and public readback evidence](evidence/location-category-normalization-2026-11-15.json).
Production currently has the thirty expanded records with their previous category
values. Its category update remains pending because the dedicated production
credential is unavailable.

After review, execute [the production category transaction](location-category-normalization-production-2026-11-15.sql)
in Supabase production project `zjnuqqtbapbpudsjbpif`, then verify the production
readback. This changes categories only and aborts on unexpected target changes.
It is outside automatic migrations. The earlier expansion manifest and SQL remain
historical execution evidence; do not use them to overwrite these normalized
categories. Their guards intentionally reject edited existing expansion records.

## App behavior

The app normalizes previous identifiers while parsing location responses, so
old and new responses share the same filter IDs, counts, category carousel and
labels during rollout. Cards and saved itinerary tiles use readable labels, with
a human-readable fallback for future category IDs. Original category naming is
preserved. New category carousel titles scale down within their existing bounds.

A regression case groups Artfull with Orange Project, merges food and recreation
aliases, and checks category counts and labels. Flutter is not installed locally;
Flutter analysis, tests and web build require the PR CI checks. No local rendered
preview or Flutter test result is claimed. The Impeccable mechanical detector
reported no findings on the edited app files. No environment files, destination
names, coordinates, hours, prices, descriptions or images were changed.
