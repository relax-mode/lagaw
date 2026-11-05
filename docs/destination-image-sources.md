# #107 Destination image sources and licensing

Issue: [relax-mode/lagaw#107](https://github.com/relax-mode/lagaw/issues/107).
Researched **November 6, 2026** by Roel. The machine-readable record is
[`destination-image-manifest.json`](destination-image-manifest.json), which is the
source of truth for #108 (Storage upload) and #109 (Flutter display).
Out of scope: storage policies, uploads and migrations.

## Result

**5 of 10 locations have a usable image. 5 are excluded** because no image with
verifiable rights was found.

| Location | Status | Image | Photographer | License | Notes |
| --- | --- | --- | --- | --- | --- |
| San Sebastian Cathedral | ✅ Approved | [Bacolod Cathedral Facade.jpg](https://commons.wikimedia.org/wiki/File:Bacolod_Cathedral_Facade.jpg) | Rauxilian | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) | Facade of the cathedral; people are small and incidental. |
| The Negros Museum | ✅ Approved | [Negros Museum front (Gatuslao, Bacolod, Negros Occidental; 10-24-2022).jpg](https://commons.wikimedia.org/wiki/File:Negros_Museum_front_(Gatuslao,_Bacolod,_Negros_Occidental;_10-24-2022).jpg) | Patrickroque01 | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) | Front of the museum with its sign; no people. |
| Negros Forest Park | ❌ Excluded | — | — | — | No photograph of this venue found on Wikimedia Commons (searches returned unrelated forests). No permission from the operator on record. |
| Orange Project | ❌ Excluded | — | — | — | No photograph of this venue found on Wikimedia Commons. No permission from the venue on record. |
| Capitol Park and Lagoon | ✅ Approved | [Capitol Lagoon Bacolod City Philippines.jpg](https://commons.wikimedia.org/wiki/File:Capitol_Lagoon_Bacolod_City_Philippines.jpg) | Kguirnela | [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0) | Lagoon with the Capitol behind it; no prominent logos or people. |
| Negros Occidental Provincial Capitol | ✅ Approved | [Negros Occidental Provincial Capitol, Sep 2026.jpg](https://commons.wikimedia.org/wiki/File:Negros_Occidental_Provincial_Capitol,_Sep_2026.jpg) | Ralff Nestor Nacor | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) | Front facade; people only tiny in the distance. |
| Cafetolyo Coffee Shop | ❌ Excluded | — | — | — | Private business; no photograph found on Wikimedia Commons and no permission from the owner on record. |
| Arima Restaurant | ❌ Excluded | — | — | — | Private business; no photograph found on Wikimedia Commons and no permission from the owner on record. |
| Panaad Park and Sports Complex | ✅ Approved | [Panaad Stadium.jpg](https://commons.wikimedia.org/wiki/File:Panaad_Stadium.jpg) | Dominic Alojado | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0) | Panaad Stadium, the complex's main landmark; players are distant and not identifiable. |
| Calea Pastries & Coffee | ❌ Excluded | — | — | — | Private business; no photograph found on Wikimedia Commons and no permission from the owner on record. |

## Licensing rules applied

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
- **Excluded locations keep `image_url = null`.** #109 must show an honest fallback, not a stand-in photo of another place.

## Candidates considered and rejected

- **San Sebastian Cathedral:** `San Sebastian Cathedral Bacolod (Rizal Street, Bacolod, Negros Occidental; 10-31-2022).jpg`: Usable (CC BY-SA 4.0) alternate; not selected.
- **The Negros Museum:** `The Negros Museum, Bacolod City, Sep 2026 (1).jpg`: Usable (CC BY-SA 4.0) alternate; not selected.
- **Capitol Park and Lagoon:** `Negros Occidental Capitol Park lagoon (Bacolod, Negros Occidental; 10-24-2022).jpg`: Excluded: hotel logos (ARB, Seda) dominate the background.
- **Capitol Park and Lagoon:** `Negros Occidental Capitol Park and Lagoon, Sep 2026 (1).jpg`: Excluded: hotel logo (Seda) prominent.
- **Negros Occidental Provincial Capitol:** `Negros Occidental Provincial Capitol 2023-08-05.jpg`: Excluded: two identifiable people seated front and center.
- **Negros Occidental Provincial Capitol:** `Provincial Capitol of Negros Occidental in Bacolod, Philippines.jpg`: Excluded: one identifiable person centered at the entrance.
- **Panaad Park and Sports Complex:** `Panaad Stadium March 2023 renovated.jpg`: Excluded: PD-PhilippinesGov. Government works carry no copyright, but exploiting them for profit needs prior approval (IP Code s.176); whether Lagaw counts as for-profit is uncertain.
- **Panaad Park and Sports Complex:** `2023 Panaad Stadium.jpg`: Excluded: PD-PhilippinesGov, same uncertainty.
- **Negros Forest Park, Orange Project, Cafetolyo, Arima, Calea:** Commons searches returned nothing showing these venues.

## Follow-up

- **Roel will take original photos** of the excluded venues himself, since no online photo with verifiable rights exists for them. Each will be added in a follow-up PR as a photographer-permission entry (credit, date, permission record), with no identifiable people and no third-party logos.
- **Negros Forest Park:** two photos Roel took on 2026-10-11 (a leopard cat and a hornbill) are pending. Both carry a University of St. La Salle watermark from the school publication, so they need an unwatermarked original and confirmation of who holds the rights before use.
- The excluded private venues (Orange Project, Cafetolyo, Arima, Calea) and Negros Forest Park could get photos with **written permission from the owner or operator**. A permission record would have to be added to the manifest before use.
- Licenses can change on Commons. Recheck `source_page_url` before a production upload if it happens long after the access date.

## Automated check

`backend/test_destination_image_manifest.py` (4 tests) runs in the backend CI suite. It checks that:
- every seeded location appears exactly once;
- approved images have all attribution fields and an accepted license (no NC or ND);
- the attribution text names the photographer and license;
- excluded entries give a reason and no image;
- rejected candidates give reasons.
