# #107 Destination image sources and licensing

Issue: [relax-mode/lagaw#107](https://github.com/relax-mode/lagaw/issues/107).
Researched **November 6, 2026** by Roel. The machine-readable record is
[`destination-image-manifest.json`](destination-image-manifest.json), which is the
source of truth for #108 (Storage upload) and #109 (Flutter display).
Out of scope: storage policies, uploads and migrations.

## Result

**All 10 locations have a usable image** because no image with
verifiable rights was found.

| Location | Status | Image | Photographer | License | Notes |
| --- | --- | --- | --- | --- | --- |
| San Sebastian Cathedral | ✅ Approved | [Bacolod Cathedral Facade.jpg](https://commons.wikimedia.org/wiki/File:Bacolod_Cathedral_Facade.jpg) | Rauxilian | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) | Facade of the cathedral; people are small and incidental. |
| The Negros Museum | ✅ Approved | [Negros Museum front (Gatuslao, Bacolod, Negros Occidental; 10-24-2022).jpg](https://commons.wikimedia.org/wiki/File:Negros_Museum_front_(Gatuslao,_Bacolod,_Negros_Occidental;_10-24-2022).jpg) | Patrickroque01 | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) | Front of the museum with its sign; no people. |
| Negros Forest Park | ✅ Approved | [Hornbill](destination-images/negros-forest-park/RLSJR-2-hornbill.jpg) (+ [leopard cat](destination-images/negros-forest-park/RLSJR-1-leopard-cat.jpg)) | Roel Jr. S. Lumauag | Photographer permission | Team member's own photos, taken 2026-10-11 inside the park. |
| Orange Project | ✅ Approved | [Exterior](destination-images/orange-project/RLSJR-3-orange-project-exterior.jpg) (full frame; neighbouring shop's name blurred) | Roel Jr. S. Lumauag | Photographer permission | Team member's own photo, taken 2026-11-07; metadata (including GPS) removed. |
| Capitol Park and Lagoon | ✅ Approved | [Capitol Lagoon Bacolod City Philippines.jpg](https://commons.wikimedia.org/wiki/File:Capitol_Lagoon_Bacolod_City_Philippines.jpg) | Kguirnela | [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0) | Lagoon with the Capitol behind it; no prominent logos or people. |
| Negros Occidental Provincial Capitol | ✅ Approved | [Negros Occidental Provincial Capitol, Sep 2026.jpg](https://commons.wikimedia.org/wiki/File:Negros_Occidental_Provincial_Capitol,_Sep_2026.jpg) | Ralff Nestor Nacor | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) | Front facade; people only tiny in the distance. |
| Cafetolyo Coffee Shop | ✅ Approved | [Counter](destination-images/cafetolyo/RLSJR-4-cafetolyo-counter.jpg) (+ [seating](destination-images/cafetolyo/RLSJR-10-cafetolyo-seating.jpg), faces blurred) | Roel Jr. S. Lumauag | Photographer permission | Team member's own photo, taken 2026-11-07; metadata (including GPS) removed. |
| Arima Restaurant | ✅ Approved | [Entrance](destination-images/arima/RLSJR-5-arima-entrance.jpg) (+ [sign](destination-images/arima/RLSJR-6-arima-sign.jpg)) | Roel Jr. S. Lumauag | Photographer permission | Team member's own photo, taken 2026-11-07; metadata (including GPS) removed. |
| Panaad Park and Sports Complex | ✅ Approved | [Panaad Stadium.jpg](https://commons.wikimedia.org/wiki/File:Panaad_Stadium.jpg) | Dominic Alojado | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0) | Panaad Stadium, the complex's main landmark; players are distant and not identifiable. |
| Calea Pastries & Coffee | ✅ Approved | [Entrance](destination-images/calea/RLSJR-9-calea-entrance.jpg) (full frame, diners' faces blurred; + [cakes](destination-images/calea/RLSJR-8-calea-cakes.jpg)) | Roel Jr. S. Lumauag | Photographer permission | Team member's own photo, taken 2026-11-07; metadata (including GPS) removed. |

## Licensing rules applied

- **Photographer permission:** a team member's own original photo. The photographer, date, and a written `permission_record` are required. The file is kept in [`destination-images/`](destination-images/) with its SHA-1, and all embedded metadata (including GPS location) is removed before it is committed. Any visible face of a person who did not consent (including side profiles) is blurred heavily enough to be unrecognizable. Credit: "Photo: <photographer>".
- **Accepted:** CC0, unconditional public domain, CC BY, CC BY-SA, all verified on the file's Wikimedia Commons page through the Commons API (`extmetadata`, license templates and Flickr review status).
- **Excluded:**
  - NC and ND licenses;
  - licenses that could not be verified;
  - Philippine government public-domain works (`PD-PhilippinesGov`), because IP Code §176 requires prior approval for exploitation for profit, and Lagaw's status is uncertain;
  - photos whose subject is an identifiable person;
  - photos dominated by third-party logos;
  - photos that don't clearly show the venue.
- **Sources not used:** Google Maps, Facebook, Instagram, TripAdvisor, blogs, news sites, and stock sites without a verifiable license. A photo being visible online does not license its reuse ([location-data-sources.md](location-data-sources.md)).
- Each candidate was viewed to confirm it shows the right venue and to check for people and logos.

## Requirements for #108 and #109

- **Show the credit with the image**, using the manifest's `attribution_text` (for example "Photo: Rauxilian / CC BY-SA 4.0 via Wikimedia Commons"), with links to `source_page_url` and `license_url`. All approved images require attribution.
- **Share-alike** (`share_alike: true`): if an image is cropped or edited, the edited version must stay under the same license and be marked as changed. Plain resizing for display is fine, with the credit kept.
- Download the original from `file_url`. Its `sha1` is recorded so #108 can confirm the file is the one that was reviewed.
- **Any location without an approved image keeps `image_url = null`** (none today, but places added later start that way). #109 must show an honest fallback, not a stand-in photo of another place.

## Candidates considered and rejected

- **San Sebastian Cathedral:** `San Sebastian Cathedral Bacolod (Rizal Street, Bacolod, Negros Occidental; 10-31-2022).jpg`: Usable (CC BY-SA 4.0) alternate; not selected.
- **The Negros Museum:** `The Negros Museum, Bacolod City, Sep 2026 (1).jpg`: Usable (CC BY-SA 4.0) alternate; not selected.
- **Capitol Park and Lagoon:** `Negros Occidental Capitol Park lagoon (Bacolod, Negros Occidental; 10-24-2022).jpg`: Excluded: hotel logos (ARB, Seda) dominate the background.
- **Capitol Park and Lagoon:** `Negros Occidental Capitol Park and Lagoon, Sep 2026 (1).jpg`: Excluded: hotel logo (Seda) prominent.
- **Negros Occidental Provincial Capitol:** `Negros Occidental Provincial Capitol 2023-08-05.jpg`: Excluded: two identifiable people seated front and center.
- **Negros Occidental Provincial Capitol:** `Provincial Capitol of Negros Occidental in Bacolod, Philippines.jpg`: Excluded: one identifiable person centered at the entrance.
- **Panaad Park and Sports Complex:** `Panaad Stadium March 2023 renovated.jpg`: Excluded: PD-PhilippinesGov. Government works carry no copyright, but exploiting them for profit needs prior approval (IP Code s.176); whether Lagaw counts as for-profit is uncertain.
- **Panaad Park and Sports Complex:** `2023 Panaad Stadium.jpg`: Excluded: PD-PhilippinesGov, same uncertainty.
- **Negros Forest Park, Orange Project, Cafetolyo, Arima, Calea:** Commons searches returned nothing showing these venues. Negros Forest Park is covered by Roel's own photos instead.
- **Orange Project:** photos on immersion-art-leipzig.de come from an exhibition in Leipzig, Germany, not the Bacolod venue. They carry no license, and they show copyrighted artworks. Rejected; Roel's own exterior photo is used instead.

## Follow-up

- **Roel photographed Orange Project, Cafetolyo, Arima and Calea himself on 2026-11-07** (added 2026-11-14). Seven of his photos are used and four were left out: the crowded Calea dining area (too many close, identifiable diners), a Calea storefront where cropping out passers-by left too little of the building, a menu close-up whose prices would go stale, and one dominated by a dress-code sign.
- Blurring instead of cropping: in the Orange Project exterior, the neighbouring shop's name (sign, standing banner and door poster) is blurred; the gallery's own photo wall seen through its open doorway is incidental and kept. Faces are blurred in two: every diner in the Calea entrance photo, and two seated customers in the Cafetolyo seating photo.
- Licenses can change on Commons. Recheck `source_page_url` before a production upload if it happens long after the access date.

## Automated check

`backend/test_destination_image_manifest.py` (4 tests) runs in the backend CI suite. It checks that:
- every seeded location appears exactly once;
- approved images (including `additional_images`) have all attribution fields and an accepted license (no NC or ND); permission entries have a photographer, date, permission record and a repository file whose SHA-1 matches;
- the attribution text names the photographer and license;
- excluded entries give a reason and no image;
- rejected candidates give reasons.
