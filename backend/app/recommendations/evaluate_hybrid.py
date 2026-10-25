"""Held-out top-N comparison; no held-out event reaches training or inference history."""

import argparse
import json
from math import log2
from pathlib import Path

from .collaborative import MODEL_VERSION, TrainingData, train
from .content_based import recommend as content_recommend
from .contracts import Interaction, RecommendationRequest
from .hybrid import HybridRecommender
from .hybrid_fixtures import DATASET_PATH, SEED


def evaluate(dataset: dict) -> dict:
    training = TrainingData.model_validate(dataset["training"])
    held_out = [Interaction.model_validate(row) for row in dataset["held_out"]]
    if (
        training.provenance != "synthetic"
        or dataset["manifest"]["provenance"] != "synthetic"
        or any(event.provenance != "synthetic" for event in held_out)
    ):
        raise ValueError("this evaluation accepts synthetic data only")
    train_ids = {event.id for event in training.interactions}
    train_pairs = {
        (event.user_id, event.location_id) for event in training.interactions
    }
    test_pairs = {(event.user_id, event.location_id) for event in held_out}
    if train_ids & {event.id for event in held_out} or train_pairs & test_pairs:
        raise ValueError("held-out leakage")
    if len(test_pairs) != len(held_out):
        raise ValueError("expected exactly one distinct positive per evaluation user")
    targets = {event.user_id: event.location_id for event in held_out}
    if len(targets) != len(held_out) or any(
        event.rating_value != 5 for event in held_out
    ):
        raise ValueError("expected one held-out positive rating per user")
    model = train(training)
    if model is None:
        raise ValueError("evaluation unexpectedly fell back during training")
    engine = HybridRecommender(model)
    rows = []
    for profile in dataset["profiles"]:
        history = [
            event
            for event in training.interactions
            if str(event.user_id) == profile["user_id"]
        ]
        # Evaluate discovery: exclude all training-seen pairs from both ranking methods.
        preferences = profile | {
            "excluded_location_ids": sorted(
                {str(event.location_id) for event in history}
            )
        }
        request = RecommendationRequest(
            preferences=preferences,
            locations=dataset["locations"],
            interactions=history,
            limit=3,
        )
        target = targets[request.preferences.user_id]
        baseline, hybrid = content_recommend(request), engine.recommend(request)
        row = {"user_id": profile["user_id"], "held_out_location_id": str(target)}
        for name, response in (("content", baseline), ("hybrid", hybrid)):
            ids = [item.location_id for item in response.items]
            rank = ids.index(target) + 1 if target in ids else None
            row[name] = {
                "recall_at_3": int(rank is not None),
                "ndcg_at_3": 1 / log2(rank + 1) if rank is not None else 0,
                "hit_at_1": int(rank == 1),
                "items": [item.model_dump(mode="json") for item in response.items],
            }
        rows.append(row)
    if not rows:
        raise ValueError("no evaluation users")
    summary = {
        name: {
            metric: round(sum(row[name][metric] for row in rows) / len(rows), 6)
            for metric in ("recall_at_3", "ndcg_at_3", "hit_at_1")
        }
        for name in ("content", "hybrid")
    }
    return {
        "model_version": MODEL_VERSION,
        "seed": SEED,
        "provenance": "synthetic",
        "training_event_count": len(training.interactions),
        "held_out_event_count": len(held_out),
        "training_digest": model.training_digest,
        "rank": model.rank,
        "evaluation_users": len(rows),
        "summary": summary,
        "users": rows,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", type=Path, default=DATASET_PATH)
    parser.add_argument("--output", type=Path)
    parser.add_argument(
        "--artifact",
        type=Path,
        help="Optional synthetic artifact output for offline use",
    )
    args = parser.parse_args()
    dataset = json.loads(args.dataset.read_text(encoding="utf-8"))
    report = evaluate(dataset)
    if args.artifact:
        model = train(TrainingData.model_validate(dataset["training"]))
        args.artifact.parent.mkdir(parents=True, exist_ok=True)
        model.save(args.artifact)
    serialized = json.dumps(report, indent=2) + "\n"
    if args.output:
        args.output.write_text(serialized, encoding="utf-8")
    else:
        print(serialized, end="")
