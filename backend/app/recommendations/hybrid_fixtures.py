"""Labeled synthetic extension of S3-01 for cross-user held-out evaluation."""

import json
from datetime import UTC, datetime, timedelta

import numpy as np

from .contracts import Interaction, LocationAttributes, Preferences
from .fixtures import FIXTURE_DIR, fixture_id

SEED = 20261025
DATASET_PATH = FIXTURE_DIR.parent / "hybrid" / "dataset.json"


def build_dataset() -> dict:
    rng = np.random.default_rng(SEED)
    source_locations = json.loads(
        (FIXTURE_DIR / "locations.json").read_text(encoding="utf-8")
    )
    source_events = json.loads(
        (FIXTURE_DIR / "interactions.json").read_text(encoding="utf-8")
    )
    # Copy attributes under separate synthetic IDs; never fabricate facts on source IDs.
    prototypes = [
        source_locations[10],
        source_locations[4],
        source_locations[1],
        source_locations[11],
    ]
    locations, profiles, training, held_out = [], [], list(source_events), []
    clusters = []
    for cluster, prototype in enumerate(prototypes):
        ids = []
        for index in range(3):
            location_id = fixture_id(f"hybrid:location:{cluster}:{index}")
            row = prototype | {
                "id": location_id,
                "name": f"Synthetic cluster {cluster} destination {index}",
                "estimated_cost_min": "50",
                "estimated_cost_max": "100",
                "suitable_group_types": [
                    "solo",
                    "couple",
                    "family",
                    "friends",
                    "group",
                ],
                "is_active": True,
            }
            locations.append(
                LocationAttributes.model_validate(row).model_dump(mode="json")
            )
            ids.append(location_id)
        clusters.append(ids)

    def event(user, location, kind, sequence, *, test=False):
        created = datetime(2026, 10, 25, tzinfo=UTC) + timedelta(
            days=int(test),
            seconds=sequence,
        )
        return Interaction(
            id=fixture_id(f"hybrid:event:{user}:{location}:{kind}:{test}"),
            user_id=user,
            location_id=location,
            interaction_type=kind,
            interaction_value="-1" if kind == "left_swipe" else "1",
            rating_value="5" if kind == "rating" else None,
            created_at=created,
            provenance="synthetic",
        ).model_dump(mode="json")

    for cluster, ids in enumerate(clusters):
        target_order = rng.permutation([0, 1, 2, 0, 1, 2])
        for member, target_index in enumerate(target_order):
            user_id = fixture_id(f"hybrid:user:{cluster}:{member}")
            profiles.append(
                Preferences(
                    user_id=user_id,
                    preferred_tags=[],
                    budget_min="0",
                    budget_max="500",
                    group_type="solo",
                ).model_dump(mode="json")
            )
            target = ids[int(target_index)]
            held_out.append(event(user_id, target, "rating", len(held_out), test=True))
            for location_id in ids:
                if location_id != target:
                    for kind in ("right_swipe", "save"):
                        training.append(
                            event(user_id, location_id, kind, len(training))
                        )
            for other_cluster, other_ids in enumerate(clusters):
                if cluster == other_cluster:
                    continue
                for index in rng.choice(3, 2, replace=False):
                    training.append(
                        event(
                            user_id, other_ids[int(index)], "left_swipe", len(training)
                        )
                    )
    return {
        "manifest": {
            "schema_version": "1",
            "provenance": "synthetic",
            "seed": SEED,
            "source": "S3-01 recommendation locations and 16 synthetic interactions",
            "split": "hold out every event of one positive user/location pair per generated user",
            "warning": "Fabricated costs, personas and interactions; never seed into production.",
        },
        "locations": locations,
        "profiles": profiles,
        "training": {
            "provenance": "synthetic",
            "location_ids": [row["id"] for row in source_locations + locations],
            "interactions": training,
        },
        "held_out": held_out,
    }


if __name__ == "__main__":
    DATASET_PATH.parent.mkdir(parents=True, exist_ok=True)
    DATASET_PATH.write_text(
        json.dumps(build_dataset(), indent=2) + "\n", encoding="utf-8"
    )
