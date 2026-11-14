"""#107: the destination image manifest only approves licensed, attributed images."""

import hashlib
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
COMMONS_REQUIRED = (
    "source_page_url",
    "file_url",
    "photographer",
    "license",
    "license_url",
    "attribution_text",
    "restrictions",
    "accessed_on",
)
PERMISSION_REQUIRED = (
    "file_path",
    "sha1",
    "photographer",
    "date_taken",
    "permission_record",
    "attribution_text",
    "restrictions",
)


def _approved_images():
    for entry in MANIFEST["locations"]:
        if entry["status"] == "approved":
            for image in [entry["image"], *entry.get("additional_images", [])]:
                yield entry["name"], image


def test_every_seeded_location_is_listed_once():
    seeded = set(re.findall(r"'([0-9a-f-]{36})'::uuid", SEED_SQL))
    listed = [entry["location_id"] for entry in MANIFEST["locations"]]
    assert len(listed) == len(set(listed))
    assert set(listed) == seeded


def test_commons_images_have_complete_attribution():
    for name, image in _approved_images():
        if image["source"] != "Wikimedia Commons":
            continue
        missing = [key for key in COMMONS_REQUIRED if not image.get(key)]
        assert not missing, f"{name}: missing {missing}"
        assert ACCEPTED.match(image["license"]), name
        assert "NC" not in image["license"] and "ND" not in image["license"]
        assert image["photographer"] in image["attribution_text"]
        assert image["license"] in image["attribution_text"]
        assert image["source_page_url"].startswith("https://commons.wikimedia.org/")
        assert image["file_url"].startswith("https://upload.wikimedia.org/")
        if image["license"] != "Public domain":
            assert image["license_url"].startswith("https://creativecommons.org/")
        assert image["share_alike"] == image["license"].startswith("CC BY-SA")


def test_permission_images_are_recorded_and_match_their_files():
    for name, image in _approved_images():
        if image["source"] == "Wikimedia Commons":
            continue
        assert image["source"] == "Photographer permission", name
        missing = [key for key in PERMISSION_REQUIRED if not image.get(key)]
        assert not missing, f"{name}: missing {missing}"
        assert image["license"] == "Permission"
        assert image["photographer"] in image["attribution_text"]
        assert image["photographer"] in image["permission_record"]
        path = ROOT / image["file_path"]
        assert path.is_file(), image["file_path"]
        assert hashlib.sha1(path.read_bytes()).hexdigest() == image["sha1"], name


def test_excluded_locations_explain_why_and_have_no_image():
    for entry in MANIFEST["locations"]:
        assert entry["status"] in {"approved", "excluded"}
        if entry["status"] == "excluded":
            assert entry["image"] is None
            assert entry["note"].strip(), entry["name"]


def test_rejected_candidates_give_reasons():
    for entry in MANIFEST["locations"]:
        for candidate in entry["rejected_candidates"]:
            assert candidate["source"] in {
                "Wikimedia Commons",
                "Photographer permission",
            }
            if candidate["source"] == "Wikimedia Commons":
                assert candidate["title"].startswith("File:")
            assert candidate["title"].strip()
            assert candidate["reason"].strip()
