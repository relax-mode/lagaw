"""Offline snapshot-and-train command for the collaborative model (#94).

Run by DevOps from a trusted shell, never in CI or request handling. It reads
`user_location_interactions` with the existing server credential (carried by the
environment, never printed) for an explicit allowlist of seeded demo profile IDs
only, trains `signed-svd-v1` and writes a private artifact under the gitignored
`backend/model_artifacts/`. Output is limited to counts, digests and model state.

    SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... python train_collaborative_model.py \\
        --environment staging --profiles-file ~/private/staging-profiles.txt \\
        --output model_artifacts/staging-real-svd.json

The profiles file holds one profile UUID per line (`#` comments allowed) and must
live outside this repository. Organic users are never added without a recorded decision.
"""

import argparse
import contextlib
import hashlib
import os
import sys
from pathlib import Path
from uuid import UUID

from app.database import DatabaseUnavailable, get_database
from app.interaction_database import InteractionDatabase
from app.recommendation_adapter import RecommendationAdapter
from app.recommendations.collaborative import CollaborativeModel, TrainingData, train

ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = Path(__file__).resolve().parent / "model_artifacts"
SUPABASE_REFS = {
    "staging": "vnpkyvtbupnquvirzlzp",  # Development and staging share this project.
    "production": "zjnuqqtbapbpudsjbpif",
}
MAX_PROFILES = 50
SECRET_LIMIT_BYTES = 64 * 1024  # Secret Manager's maximum secret version payload.


class TrainingFailed(ValueError):
    """Only authored, identifier-free messages may be displayed."""


def require(condition, message):
    if not condition:
        raise TrainingFailed(message)


def validate_target(environment: str, base_url: str) -> None:
    expected = f"https://{SUPABASE_REFS[environment]}.supabase.co/rest/v1/"
    require(base_url == expected, f"The configured Supabase project is not the {environment} project; refusing.")


def read_profiles(path: Path) -> list[UUID]:
    require(not path.resolve().is_relative_to(ROOT), "Keep the profile allowlist outside the repository.")
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        raise TrainingFailed("Could not read the profile allowlist.") from None
    try:
        profiles = [UUID(line.split("#")[0].strip()) for line in lines if line.split("#")[0].strip()]
    except ValueError:
        raise TrainingFailed("The profile allowlist must contain one UUID per line.") from None
    require(profiles and len(profiles) == len(set(profiles)), "Provide distinct allowlisted profile UUIDs.")
    require(len(profiles) <= MAX_PROFILES and all(p.int for p in profiles),
            f"Allowlists are limited to {MAX_PROFILES} non-nil profiles.")
    return profiles


def snapshot(client, profiles: list[UUID]) -> tuple[TrainingData, dict[str, int]]:
    """A `real` TrainingData for allowlisted owners over the active catalog only."""
    catalog = {location.id for location in RecommendationAdapter(client).catalog()}
    database = InteractionDatabase(client)
    events = [
        event for profile in profiles
        for event in database.recommendation_input(profile).interactions
    ]
    usable = [event for event in events if event.location_id in catalog]
    stats = {"profiles": len(profiles), "events_read": len(events), "events_used": len(usable)}
    return TrainingData(provenance="real", location_ids=sorted(catalog, key=str), interactions=usable), stats


def write_artifact(model: CollaborativeModel, output: Path) -> tuple[str, int]:
    data = (model.model_dump_json(indent=2) + "\n").encode("utf-8")
    require(len(data) <= SECRET_LIMIT_BYTES,
            f"The artifact is {len(data)} bytes, over the {SECRET_LIMIT_BYTES}-byte delivery limit; use fewer events.")
    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "wb") as handle:
        handle.write(data)
    require(CollaborativeModel.load(output, provenance="real") == model, "The written artifact did not reload.")
    return hashlib.sha256(data).hexdigest(), len(data)


def run(environment: str, profiles_file: Path, output: Path) -> None:
    resolved = output.resolve()
    require(resolved.is_relative_to(ARTIFACTS) and resolved.suffix == ".json",
            "Write the artifact to a .json file under backend/model_artifacts/.")
    profiles = read_profiles(profiles_file)
    with contextlib.contextmanager(get_database)() as configured:
        validate_target(environment, str(configured.client.base_url))
        data, stats = snapshot(configured.client, profiles)
    print(f"Environment: {environment}; allowlisted profiles: {stats['profiles']}")
    print(f"Interaction events read: {stats['events_read']}; in the active catalog: {stats['events_used']}")
    model = train(data)
    if model is None:
        print("Model state: none (the snapshot is below the global training gates); no artifact written.")
        raise TrainingFailed("Seed more overlapping demo interactions, then retry.")
    digest, size = write_artifact(model, resolved)
    print("Model state: trained")
    print(f"Version: {model.model_version}; provenance: {model.provenance}; rank: {model.rank}")
    print(f"Users: {len(model.user_ids)}; items: {len(model.item_ids)}; pairs: {sum(model.user_counts)}")
    print(f"Users with enough history: {sum(c >= 3 for c in model.user_counts)}; "
          f"items with enough users: {sum(c >= 2 for c in model.item_counts)}")
    print(f"Training digest: {model.training_digest}")
    print(f"Artifact SHA-256: {digest}")
    print(f"Artifact size: {size} bytes (limit {SECRET_LIMIT_BYTES})")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--environment", required=True, choices=sorted(SUPABASE_REFS))
    parser.add_argument("--profiles-file", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        run(args.environment, args.profiles_file, args.output)
        return 0
    except TrainingFailed as error:
        print(f"FAIL: {error}")
    except DatabaseUnavailable:
        print("FAIL: The interaction snapshot could not be read; details omitted.")
    except Exception as error:  # noqa: BLE001 - Never print credential-bearing diagnostics.
        print(f"FAIL: Training failed ({type(error).__name__}); details omitted.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
