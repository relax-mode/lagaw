"""Build the Flutter image-credits asset from the #107 image manifest.

The app shows a destination photo only when the uploaded file's SHA-256
(part of its Storage object path, see destination_images.py) is approved
for that same location, and it shows the credit recorded here. [S4-09]

    python scripts/build_image_credits.py          # rewrite the asset
    python scripts/build_image_credits.py --check  # fail if it is stale
"""

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "docs/destination-image-manifest.json"
ASSET = ROOT / "frontend/assets/image_credits.json"


def build(manifest: dict) -> dict:
    images = []
    for location in manifest["locations"]:
        if location["status"] != "approved":
            continue
        entries = [location["image"], *location.get("additional_images", [])]
        for order, image in enumerate(entries):
            images.append(
                {
                    "location_id": location["location_id"],
                    "sha256": image["upload_sha256"],
                    "primary": order == 0,
                    "attribution": image["attribution_text"],
                    "photographer": image["photographer"],
                    "license": image["license"],
                    "license_url": image["license_url"],
                    "source_url": image["source_page_url"],
                    "modified": image["upload_modification"],
                }
            )
    return {
        "schema_version": "1",
        "generated_from": "docs/destination-image-manifest.json",
        "images": images,
    }


def render(manifest: dict) -> str:
    return json.dumps(build(manifest), indent=2, ensure_ascii=False) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    expected = render(json.loads(MANIFEST.read_text("utf-8")))
    if args.check:
        current = ASSET.read_text("utf-8") if ASSET.exists() else ""
        if current != expected:
            print(f"{ASSET.relative_to(ROOT)} is stale; run {Path(__file__).name}")
            return 1
        print("image credits are up to date")
        return 0
    ASSET.parent.mkdir(parents=True, exist_ok=True)
    ASSET.write_text(expected, "utf-8")
    print(f"wrote {ASSET.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
