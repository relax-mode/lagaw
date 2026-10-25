"""Run fixture evaluation and a small local timing benchmark; no provider calls."""

import argparse
import json
import platform
from pathlib import Path
from statistics import median
from time import perf_counter

from .content_based import MODEL_VERSION, recommend
from .contracts import RecommendationRequest
from .fixtures import FIXTURE_DIR


def evaluate() -> dict:
    """Return deterministic behavior evidence, separate from variable timing results."""
    cases = json.loads(
        (FIXTURE_DIR / "evaluation_cases.json").read_text(encoding="utf-8")
    )
    results = []
    for case in cases:
        request = RecommendationRequest.model_validate(case["input"])
        response = recommend(request)
        names = {location.id: location.name for location in request.locations}
        expected = set(case["expected"]["eligible_examples"])
        actual = {str(item.location_id) for item in response.items}
        results.append(
            {
                "case": case["id"],
                "candidate_count": len(request.locations),
                "interaction_count": len(request.interactions),
                "result_count": len(response.items),
                "eligible_examples_returned": expected <= actual,
                "empty_result_correct": case["id"] != "empty_result"
                or not response.items,
                "reproducible": response == recommend(request),
                "ranking": [
                    {"name": names[item.location_id], **item.model_dump(mode="json")}
                    for item in response.items
                ],
            }
        )
    return {
        "model_version": MODEL_VERSION,
        "data": "synthetic development fixtures",
        "case_count": len(results),
        "cases": results,
    }


def benchmark(repeats: int = 100) -> dict:
    if repeats < 1:
        raise ValueError("repeats must be positive")
    cases = json.loads(
        (FIXTURE_DIR / "evaluation_cases.json").read_text(encoding="utf-8")
    )
    requests = [RecommendationRequest.model_validate(case["input"]) for case in cases]
    for request in requests:
        recommend(request)
    samples = []
    for _ in range(repeats):
        for request in requests:
            start = perf_counter()
            recommend(request)
            samples.append((perf_counter() - start) * 1000)
    ordered = sorted(samples)
    return {
        "python": platform.python_version(),
        "platform": platform.system(),
        "calls": len(samples),
        "candidates_per_call": len(requests[0].locations),
        "median_ms": round(median(samples), 4),
        "p95_ms": round(ordered[(95 * len(ordered) + 99) // 100 - 1], 4),
        "scope": "local warm calls including validation; excludes fixture loading and network",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--benchmark", action="store_true")
    parser.add_argument(
        "--output", type=Path, help="Write JSON evidence instead of printing it"
    )
    args = parser.parse_args()
    report = evaluate()
    if args.benchmark:
        report["benchmark"] = benchmark()
    serialized = json.dumps(report, indent=2) + "\n"
    if args.output:
        args.output.write_text(serialized, encoding="utf-8")
    else:
        print(serialized, end="")
