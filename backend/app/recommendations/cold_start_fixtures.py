"""Versioned realistic scenarios with explicitly fictional controlled destinations."""

import json

from .contracts import LocationAttributes, Preferences
from .fixtures import FIXTURE_DIR, fixture_id

REVISION = "cold-start-v1"
DATASET_PATH = FIXTURE_DIR / "cold_start_cases.json"


def build_fixtures() -> dict:
    locations = []
    for name, tags, cost, group, duration, setting, access, active in (
        ("Fictional free park", ["nature", "photography"], "0", "all", 45, "outdoor", True, True),
        ("Fictional budget cafe", ["cafe", "relaxing"], "100", "all", 40, "indoor", True, True),
        ("Fictional heritage gallery", ["heritage", "photography"], "80", "all", 60, "indoor", False, True),
        ("Fictional food stop", ["food"], "150", "all", 60, "indoor", True, True),
        ("Fictional premium dining", ["food", "relaxing"], "900", "all", 90, "indoor", True, True),
        ("Fictional unknown-cost cafe", ["cafe"], None, "all", 30, None, None, True),
        ("Fictional inactive cafe", ["cafe"], "0", "all", 20, "indoor", True, False),
        ("Fictional friends cafe", ["cafe", "relaxing"], "50", "friends", 30, "indoor", True, True),
    ):
        locations.append(LocationAttributes(
            id=fixture_id("cold-start:" + name), name=name,
            category="cafe" if "cafe" in tags else "attraction",
            vibe_tags=tags, estimated_cost_min=cost, estimated_cost_max=cost,
            suitable_group_types=(["solo", "couple", "family", "friends", "group"]
                                  if group == "all" else [group]),
            typical_visit_duration=duration, setting=setting, step_free_access=access,
            coordinates={"latitude": 10.676, "longitude": 122.95213}, is_active=active,
        ).model_dump(mode="json"))
    cases = []

    def case(label, description, tags, cap, group, top, updates=None, source_top="The Negros Museum"):
        preferences = Preferences(
            user_id=fixture_id("cold-start:user:" + label), preferred_tags=tags,
            budget_min="0", budget_max=cap, group_type=group, **(updates or {}),
        )
        cases.append({
            "id": label, "description": description,
            "interface_scope": "engine_constraint_diagnostic" if updates else "onboarding_compatible",
            "preferences": preferences.model_dump(mode="json"), "limit": 3,
            "expected_top": {"controlled": top, "source_catalog": source_top},
        })

    case("budget_cafe_solo", "Student exploring cafes alone; no prior swipes.",
         ["cafe", "relaxing"], "200", "solo", "Fictional budget cafe")
    case("heritage_couple", "Couple seeking history and photography.",
         ["heritage", "photography"], "200", "couple", "Fictional heritage gallery")
    case("family_nature", "Family seeking affordable nature stops.",
         ["nature"], "200", "family", "Fictional free park")
    case("friends_cafe", "Friends seeking a cafe, with group eligibility respected.",
         ["cafe", "relaxing"], "200", "friends", "Fictional friends cafe")
    case("food_budget", "Food interests with a modest visit ceiling.",
         ["food"], "200", "solo", "Fictional food stop")
    case("food_high_budget", "Same food interests with a higher ceiling; cheaper matches can win.",
         ["food"], "1200", "solo", "Fictional food stop")
    case("food_relaxing_high_budget", "Food and relaxing matter jointly to a higher-budget traveler.",
         ["food", "relaxing"], "1200", "solo", "Fictional premium dining")
    case("free_photography", "Photographer requesting confirmed free visits only.",
         ["photography"], "0", "solo", "Fictional free park", source_top=None)
    case("no_tags", "Onboarding interests skipped; rank by budget headroom.",
         [], "200", "solo", "Fictional free park")
    case("very_low_budget_cafe", "Cafe interest but only PHP 50 per person per visit.",
         ["cafe"], "50", "solo", "Fictional free park", source_top=None)
    case("step_free_family", "Family explicitly requires verified step-free access.",
         ["nature"], "200", "family", "Fictional free park",
         {"requires_step_free_access": True}, source_top=None)
    case("indoor_relaxing", "Traveler wants an indoor cafe.",
         ["cafe", "relaxing"], "200", "solo", "Fictional budget cafe",
         {"setting": "indoor"}, source_top=None)
    case("short_visit", "Only 30 minutes available at each stop.",
         ["cafe"], "200", "solo", None,
         {"max_visit_duration_minutes": 30}, source_top=None)
    case("free_indoor", "Confirmed free indoor visits requested.",
         ["heritage"], "0", "solo", None,
         {"setting": "indoor"}, source_top=None)
    case("nearby_photography", "Photography within one straight-line kilometre of a stated origin.",
         ["photography"], "200", "solo", "Fictional free park",
         {"origin": {"latitude": 10.676, "longitude": 122.95213}, "max_distance_km": 1})
    case("empty_catalog", "Catalog unavailable as an empty valid snapshot.",
         ["cafe"], "200", "solo", None, source_top=None)
    return {
        "revision": REVISION,
        "scenario_provenance": "Authored hypothetical travelers, not collected user labels",
        "controlled_provenance": "All controlled locations, costs, access and coordinates are fictional",
        "controlled_locations": locations, "cases": cases,
    }


if __name__ == "__main__":
    DATASET_PATH.write_text(json.dumps(build_fixtures(), indent=2) + "\n", encoding="utf-8")
