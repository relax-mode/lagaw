"""Deterministic development data. Never reads environment or writes to a database."""

import json
from pathlib import Path
from uuid import NAMESPACE_URL, uuid5

from .contracts import (
    Interaction,
    LocationAttributes,
    Preferences,
    RecommendationRequest,
)

FIXTURE_DIR = Path(__file__).resolve().parents[2] / "fixtures" / "recommendations"


def fixture_id(label: str) -> str:
    return str(uuid5(NAMESPACE_URL, f"lagaw:recommendation:v1:{label}"))


def build_fixtures(source: list[dict]) -> dict[str, object]:
    """Pure builder: fixed IDs, dates and ordering; no random seed or wall clock."""
    locations = []
    for row in source:
        attributes = {
            key: row[key]
            for key in (
                "name",
                "category",
                "vibe_tags",
                "estimated_cost_min",
                "estimated_cost_max",
                "typical_visit_duration",
                "suitable_group_types",
                "is_active",
            )
        }
        attributes["id"] = fixture_id("location:" + row["name"])
        attributes["coordinates"] = (
            {"latitude": row["latitude"], "longitude": row["longitude"]}
            if row["latitude"] is not None and row["longitude"] is not None
            else None
        )
        locations.append(
            LocationAttributes.model_validate(attributes).model_dump(mode="json")
        )
    # Fabricated variants are separate IDs, never overrides of researched catalog facts.
    variants = [
        (
            "Budget cafe test variant",
            "cafe",
            ["cafe", "relaxing"],
            "50",
            "100",
            "indoor",
            True,
        ),
        (
            "Premium dining test variant",
            "restaurant",
            ["food"],
            "800",
            "1200",
            "indoor",
            True,
        ),
        (
            "Free park test variant",
            "park",
            ["nature", "photography"],
            "0",
            "0",
            "outdoor",
            True,
        ),
        ("Inactive cafe test variant", "cafe", ["cafe"], "50", "100", "indoor", False),
    ]
    for name, category, tags, low, high, setting, active in variants:
        locations.append(
            LocationAttributes(
                id=fixture_id("location:" + name),
                name=name,
                category=category,
                vibe_tags=tags,
                estimated_cost_min=low,
                estimated_cost_max=high,
                suitable_group_types=["solo", "couple", "family", "friends", "group"],
                typical_visit_duration=30,
                is_active=active,
                setting=setting,
                step_free_access=True,
                coordinates={"latitude": 10.676, "longitude": 122.95213},
            ).model_dump(mode="json")
        )
    personas = [
        ("budget_cafe", ["cafe", "relaxing"], "100", "solo"),
        ("heritage", ["heritage", "photography"], "500", "couple"),
        ("family_nature", ["nature"], "300", "family"),
        ("premium_food", ["food"], "1500", "friends"),
        ("cold_start", ["photography"], "500", "solo"),
        ("cold_start_no_tags", [], "0", "group"),
    ]
    travelers = [
        Preferences(
            user_id=fixture_id("user:" + name),
            preferred_tags=tags,
            budget_min="0",
            budget_max=budget,
            group_type=group,
        ).model_dump(mode="json")
        for name, tags, budget, group in personas
    ]
    interactions = []
    for index, traveler in enumerate(travelers[:4]):
        for offset, (kind, value, rating) in enumerate(
            [
                ("right_swipe", "1", None),
                ("save", "1", None),
                ("rating", "1", "4"),
                ("left_swipe", "-1", None),
            ]
        ):
            location = locations[(index + offset) % len(source)]
            interactions.append(
                Interaction(
                    id=fixture_id(f"event:{index}:{offset}"),
                    user_id=traveler["user_id"],
                    location_id=location["id"],
                    interaction_type=kind,
                    interaction_value=value,
                    rating_value=rating,
                    created_at=f"2026-10-25T00:{index:02}:{offset:02}Z",
                    provenance="synthetic",
                ).model_dump(mode="json")
            )
    cases = []

    def case(name, traveler_index, updates, eligible_names, behavior):
        preferences = travelers[traveler_index] | updates
        request = RecommendationRequest(
            preferences=preferences,
            locations=locations,
            interactions=[
                e for e in interactions if e["user_id"] == preferences["user_id"]
            ],
            limit=5,
        )
        cases.append(
            {
                "id": name,
                "input": request.model_dump(mode="json"),
                "expected": {
                    "eligible_examples": [
                        fixture_id("location:" + n) for n in eligible_names
                    ],
                    "behavior": behavior,
                    "assertions": [
                        "unique_active_catalog_ids",
                        "score_between_zero_and_one",
                        "descending_score",
                        "exclude_left_swipes",
                        "respect_constraints",
                    ],
                },
            }
        )

    case(
        "budget_cafe",
        0,
        {},
        [variants[0][0]],
        "Prefer cafe/relaxing matches; reject premium dining above the per-person cap.",
    )
    case(
        "heritage",
        1,
        {},
        ["The Negros Museum"],
        "Prefer heritage/photography matches; unknown costs cannot satisfy a hard budget cap.",
    )
    case(
        "family_nature",
        2,
        {},
        [variants[2][0]],
        "Prefer nature with confirmed family suitability and known affordable cost.",
    )
    case(
        "premium_food",
        3,
        {},
        [variants[1][0]],
        "Premium food is affordable; budget is a ceiling, not an instruction to spend it all.",
    )
    case(
        "cold_start",
        4,
        {},
        ["The Negros Museum", variants[2][0]],
        "Use explicit preferences and catalog attributes with no interaction history.",
    )
    case(
        "cold_start_no_tags",
        5,
        {},
        [variants[2][0]],
        "No tags/history must not crash; only confirmed free compatible places fit zero budget.",
    )
    case(
        "accessibility_indoor",
        4,
        {"requires_step_free_access": True, "setting": "indoor"},
        [variants[0][0]],
        "Reject unknown access/setting and outdoor candidates.",
    )
    case(
        "distance_and_duration",
        4,
        {
            "origin": {"latitude": 10.676, "longitude": 122.95213},
            "max_distance_km": 1,
            "max_visit_duration_minutes": 30,
        },
        [variants[2][0]],
        "Reject unknown coordinates/duration and values outside either bound.",
    )
    case(
        "empty_result",
        4,
        {"budget_max": "0", "setting": "indoor"},
        [],
        "Return an empty items list when no candidate satisfies all hard constraints.",
    )
    case(
        "explicit_exclusion",
        0,
        {"excluded_location_ids": [locations[10]["id"]]},
        [],
        "Never return explicit exclusions, left swipes, inactive or unknown locations.",
    )
    return {
        "locations.json": locations,
        "travelers.json": travelers,
        "interactions.json": interactions,
        "evaluation_cases.json": cases,
        "manifest.json": {
            "schema_version": "1",
            "provenance": "synthetic_development_fixture",
            "source": "supabase/data/locations.json",
            "source_location_count": len(source),
            "synthetic_location_ids": [row["id"] for row in locations[len(source) :]],
            "traveler_labels": {
                name: row["user_id"] for (name, *_), row in zip(personas, travelers)
            },
            "warning": "No real users or interactions. Synthetic IDs are not database IDs.",
        },
    }


def load_request(case_id: str = "cold_start") -> RecommendationRequest:
    cases = json.loads(
        (FIXTURE_DIR / "evaluation_cases.json").read_text(encoding="utf-8")
    )
    return RecommendationRequest.model_validate(
        next(c["input"] for c in cases if c["id"] == case_id)
    )


if __name__ == "__main__":
    source_path = (
        Path(__file__).resolve().parents[3] / "supabase" / "data" / "locations.json"
    )
    FIXTURE_DIR.mkdir(parents=True, exist_ok=True)
    for filename, data in build_fixtures(
        json.loads(source_path.read_text(encoding="utf-8"))
    ).items():
        (FIXTURE_DIR / filename).write_text(
            json.dumps(data, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
