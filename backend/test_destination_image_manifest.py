"""#107: the destination image manifest only approves licensed, attributed images."""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = json.loads(
    (ROOT / "docs/destination-image-manifest.json").read_text("utf-8")
)
SEED_SQL = (
    ROOT / "supabase/migrations/20261014154651_seed_sample_locations.sql"
).read_text("utf-8")

ACCEPTED = re.compile(r"^(CC0|Public domain|CC BY(-SA)? \d\.\d)$")
REQUIRED = (
    "source_page_url",
    "file_url",
    "photographer",
    "license",
    "license_url",
    "attribution_text",
    "restrictions",
    "accessed_on",
)


def test_every_seeded_location_is_listed_once():
    seeded = set(re.findall(r"'([0-9a-f-]{36})'::uuid", SEED_SQL))
    listed = [entry["location_id"] for entry in MANIFEST["locations"]]
    assert len(listed) == len(set(listed))
    assert set(listed) == seeded


def test_approved_images_have_complete_attribution():
    for entry in MANIFEST["locations"]:
        if entry["status"] != "approved":
            continue
        image = entry["image"]
        missing = [key for key in REQUIRED if not image.get(key)]
        assert not missing, f"{entry['name']}: missing {missing}"
        assert ACCEPTED.match(image["license"]), entry["name"]
        assert "NC" not in image["license"] and "ND" not in image["license"]
        assert image["photographer"] in image["attribution_text"]
        assert image["license"] in image["attribution_text"]
        assert image["source_page_url"].startswith("https://commons.wikimedia.org/")
        assert image["file_url"].startswith("https://upload.wikimedia.org/")
        if image["license"] != "Public domain":
            assert image["license_url"].startswith("https://creativecommons.org/")
        assert image["share_alike"] == image["license"].startswith("CC BY-SA")


def test_excluded_locations_explain_why_and_have_no_image():
    for entry in MANIFEST["locations"]:
        assert entry["status"] in {"approved", "excluded"}
        if entry["status"] == "excluded":
            assert entry["image"] is None
            assert entry["note"].strip(), entry["name"]


def test_rejected_candidates_give_reasons():
    for entry in MANIFEST["locations"]:
        for candidate in entry["rejected_candidates"]:
            assert candidate["title"].startswith("File:")
            assert candidate["reason"].strip()
