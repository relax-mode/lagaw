"""Offline content-first scenarios, catalog coverage and no-model hybrid parity."""

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path

from .cold_start_fixtures import DATASET_PATH, REVISION
from .content_based import MODEL_VERSION, recommend
from .contracts import RecommendationRequest, satisfies_constraints, validate_response
from .fixtures import build_fixtures
from .hybrid import HybridRecommender

ROOT = Path(__file__).resolve().parents[3]
SOURCE_PATH = ROOT / "supabase" / "data" / "locations.json"


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def digest(value) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def catalog_coverage(source: list[dict]) -> dict:
    active = [row for row in source if row["is_active"]]
    return {
        "locations": len(source), "active": len(active),
        "known_upper_cost": sum(row["estimated_cost_max"] is not None for row in active),
        "coordinate_pairs": sum(row["latitude"] is not None and row["longitude"] is not None
                                for row in active),
        "nonempty_hours": sum(bool(row["opening_hours"]) for row in active),
        "tagged": sum(bool(row["vibe_tags"]) for row in active),
        "positive_visit_duration": sum(row["typical_visit_duration"] is not None
                                       and row["typical_visit_duration"] > 0 for row in active),
    }


def evaluate(dataset=None, source=None) -> dict:
    dataset = read_json(DATASET_PATH) if dataset is None else dataset
    source = read_json(SOURCE_PATH) if source is None else source
    if dataset["revision"] != REVISION or not dataset["cases"]:
        raise ValueError("Unsupported or empty cold-start suite")
    labels = [case["id"] for case in dataset["cases"]]
    if len(labels) != len(set(labels)):
        raise ValueError("Duplicate scenario IDs")
    # Reuse the existing fixture conversion; take only source-derived rows, never
    # the fabricated variants that builder appends. Unknown facts remain unknown.
    source_locations = build_fixtures(source)["locations.json"][:len(source)] if source else []
    results = []
    for name, locations in (("source_catalog", source_locations),
                            ("controlled", dataset["controlled_locations"])):
        rows = []
        for case in dataset["cases"]:
            request = RecommendationRequest(
                preferences=case["preferences"], interactions=[], limit=case["limit"],
                locations=[] if case["id"] == "empty_catalog" else locations,
            )
            response = recommend(request)
            validate_response(request, response)
            reverse = request.model_copy(deep=True)
            reverse.locations.reverse()
            names = {row.id: row.name for row in request.locations}
            returned = [item.location_id for item in response.items]
            tags = set(request.preferences.preferred_tags)
            matching = {row.id for row in request.locations if tags & set(row.vibe_tags)}
            eligible = {row.id for row in request.locations
                        if satisfies_constraints(request.preferences, row)}
            top = names[returned[0]] if returned else None
            checks = {
                "expected_top": top == case["expected_top"][name],
                "deterministic": response == recommend(request) == recommend(reverse),
                "no_model_hybrid_parity": response == HybridRecommender().recommend(request),
                "eligible_only": set(returned) <= eligible,
                "unique_and_bounded": len(returned) == len(set(returned)) <= request.limit,
            }
            rows.append({
                "case": case["id"], "description": case["description"],
                "interface_scope": case["interface_scope"],
                "interaction_count": 0, "candidate_count": len(request.locations),
                "eligible_count": len(eligible), "result_count": len(returned),
                "matching_tag_candidates": len(matching),
                "eligible_matching_tag_candidates": len(matching & eligible),
                "returned_tag_matches": len(set(returned) & matching),
                "tag_match_fraction": (round(len(set(returned) & matching) / len(returned), 6)
                                       if tags and returned else None),
                "top_has_requested_tag": returned[0] in matching if tags and returned else None,
                "ineligible_counts": {
                    "inactive": sum(not row.is_active for row in request.locations),
                    "unknown_upper_cost": sum(row.estimated_cost_max is None for row in request.locations),
                    "above_budget": sum(row.estimated_cost_max is not None
                                        and row.estimated_cost_max > request.preferences.budget_max
                                        for row in request.locations),
                    "group_mismatch": sum(request.preferences.group_type not in row.suitable_group_types
                                          for row in request.locations),
                },
                "checks": checks, "passed": all(checks.values()),
                "ranking": [{"name": names[item.location_id], **item.model_dump(mode="json")}
                            for item in response.items],
            })
        nonempty_with_tags = [row for row in rows if row["top_has_requested_tag"] is not None]
        results.append({
            "catalog": name, "cases": rows,
            "summary": {
                "cases": len(rows), "passed": sum(row["passed"] for row in rows),
                "empty_cases": sum(not row["result_count"] for row in rows),
                "fill_fraction": round(sum(row["result_count"] for row in rows)
                                       / sum(case["limit"] for case in dataset["cases"]), 6),
                "tagged_nonempty_cases": len(nonempty_with_tags),
                "top_with_tag_match": sum(row["top_has_requested_tag"] for row in nonempty_with_tags),
                "top_name_counts": dict(sorted(Counter(row["ranking"][0]["name"]
                                                       for row in rows if row["ranking"]).items())),
            },
        })
    return {
        "revision": REVISION, "model_version": MODEL_VERSION,
        "source": "supabase/data/locations.json (committed source, not live prices)",
        "source_sha256": digest(source), "fixture_sha256": digest(dataset),
        "budget_scope": "PHP per person per venue visit; transport/lodging excluded",
        "source_catalog_coverage": catalog_coverage(source), "catalogs": results,
        "passed": all(row["passed"] for group in results for row in group["cases"]),
        "limitations": [
            "Scenario expectations are authored behavior checks, not organic relevance labels.",
            "Tag overlap is a diagnostic proxy, not precision, recall or satisfaction.",
            "Exclusion counts overlap and omit optional-constraint breakdowns.",
            "No model artifact, training, retraining, provider or live API is used.",
            "No-model hybrid parity verifies fallback only, not collaborative benefit.",
            "Source fixture IDs are synthetic; fictional controls never replace source facts.",
            "Existing #94 seeded serving evidence does not establish organic recommendation quality.",
        ],
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    report = evaluate()
    serialized = json.dumps(report, indent=2) + "\n"
    if args.output:
        args.output.write_text(serialized, encoding="utf-8")
    else:
        print(serialized, end="")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
