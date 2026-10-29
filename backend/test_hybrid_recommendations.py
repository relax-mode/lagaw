"""Offline matrix factorization, held-out evaluation, artifact and fallback checks."""

import copy
import json
from datetime import timedelta
from decimal import Decimal
from pathlib import Path
from uuid import UUID

import numpy as np
import pytest
from pydantic import ValidationError

from app.recommendations.collaborative import (
    CollaborativeModel,
    TrainingData,
    aggregate_events,
    train,
)
from app.recommendations.content_based import recommend as content_recommend
from app.recommendations.content_based import score_location
from app.recommendations.contracts import (
    Interaction,
    LocationAttributes,
    RecommendationRequest,
    validate_response,
)
from app.recommendations.evaluate_hybrid import evaluate
from app.recommendations.fixtures import FIXTURE_DIR, fixture_id, load_request
from app.recommendations.hybrid import HybridRecommender
from app.recommendations.hybrid_fixtures import DATASET_PATH, build_dataset


@pytest.fixture(scope="module")
def dataset():
    return json.loads(DATASET_PATH.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def model(dataset):
    result = train(TrainingData.model_validate(dataset["training"]))
    assert result is not None
    return result


def request_for(dataset, index=0):
    profile = dataset["profiles"][index]
    events = [
        event
        for event in dataset["training"]["interactions"]
        if event["user_id"] == profile["user_id"]
    ]
    return RecommendationRequest(
        preferences=profile,
        locations=dataset["locations"],
        interactions=events,
        limit=3,
    )


def compact(response):
    return [(row.location_id, row.recommendation_score) for row in response.items]


def test_dataset_reproducible_disjoint_and_source_fixtures_reused(dataset):
    assert dataset == build_dataset() == build_dataset()
    train_rows = dataset["training"]["interactions"]
    source = json.loads((FIXTURE_DIR / "interactions.json").read_text(encoding="utf-8"))
    assert train_rows[: len(source)] == source
    assert len(dataset["profiles"]) == len(dataset["held_out"]) == 24
    assert len(train_rows) == 256
    assert all(
        event["provenance"] == "synthetic" for event in train_rows + dataset["held_out"]
    )
    assert {event["id"] for event in train_rows}.isdisjoint(
        event["id"] for event in dataset["held_out"]
    )
    assert {(e["user_id"], e["location_id"]) for e in train_rows}.isdisjoint(
        (e["user_id"], e["location_id"]) for e in dataset["held_out"]
    )


def test_actual_low_rank_factorization_and_blend(dataset, model):
    assert model.rank == 3
    assert (
        np.linalg.matrix_rank(
            np.asarray(model.user_factors) @ np.asarray(model.item_factors).T
        )
        <= 3
    )
    assert set(model.training_event_ids).isdisjoint(
        UUID(row["id"]) for row in dataset["held_out"]
    )
    request = request_for(dataset)
    engine = HybridRecommender(model)
    result = engine.recommend(request)
    assert result == validate_response(request, result)
    for row in result.items:
        location = next(
            location for location in request.locations if location.id == row.location_id
        )
        content = score_location(request.preferences, location).score
        collaborative, mode = model.score(request.preferences.user_id, location.id)
        assert mode == "hybrid"
        assert row.recommendation_score == pytest.approx(
            0.6 * content + 0.4 * collaborative, abs=1e-12
        )
        assert "Hybrid:" in row.recommendation_reason
        assert 0 <= row.recommendation_score <= 1


def test_seed_and_training_input_order_reproducibility(dataset, model):
    again = train(TrainingData.model_validate(dataset["training"]))
    assert again == model
    shuffled = copy.deepcopy(dataset["training"])
    rng = np.random.default_rng(42)
    rng.shuffle(shuffled["interactions"])
    rng.shuffle(shuffled["location_ids"])
    reordered = train(TrainingData.model_validate(shuffled))
    assert reordered == model
    request = request_for(dataset)
    before = request.model_dump_json()
    forward = HybridRecommender(model).recommend(request)
    assert forward == HybridRecommender(model).recommend(request)
    assert request.model_dump_json() == before
    request.locations.reverse()
    assert forward == HybridRecommender(model).recommend(request)


@pytest.mark.parametrize("size", [0, 1, 7])
def test_empty_or_sparse_training_falls_back(dataset, size):
    data = copy.deepcopy(dataset["training"])
    data["interactions"] = data["interactions"][:size]
    model = train(TrainingData.model_validate(data))
    assert model is None
    request = load_request()
    assert HybridRecommender(model).recommend(request) == content_recommend(request)


def test_s3_original_events_can_train_without_extension():
    locations = json.loads((FIXTURE_DIR / "locations.json").read_text(encoding="utf-8"))
    events = json.loads((FIXTURE_DIR / "interactions.json").read_text(encoding="utf-8"))
    model = train(
        TrainingData(
            provenance="synthetic",
            location_ids=[row["id"] for row in locations],
            interactions=events,
        )
    )
    assert model is not None
    response = HybridRecommender(model).recommend(load_request("heritage"))
    assert response == validate_response(load_request("heritage"), response)


def event(kind, rating=None, label="event", seconds=0):
    row = load_request("budget_cafe").interactions[0].model_dump(mode="json")
    row.update(id=fixture_id(label), interaction_type=kind, rating_value=rating)
    result = Interaction.model_validate(row)
    result.created_at += timedelta(seconds=seconds)
    return result


@pytest.mark.parametrize(
    "kind,rating,expected",
    [
        ("left_swipe", None, -0.2),
        ("right_swipe", None, 0.2),
        ("save", None, 0.4),
        ("rating", "1", -0.4),
        ("rating", "3", None),
        ("rating", "5", 0.4),
    ],
)
def test_interaction_weights(kind, rating, expected):
    signals = aggregate_events([event(kind, rating)])
    assert list(signals.values()) == ([] if expected is None else [expected])


def test_repeated_events_do_not_inflate_history_or_weights(dataset, model):
    first = event("right_swipe")
    latest = event("left_swipe", label="later", seconds=1)
    assert aggregate_events([first] * 10) == aggregate_events([first])
    assert list(aggregate_events([first, latest]).values()) == [-0.2]
    save = event("save", label="save")
    rating = event("rating", "5", label="rating")
    assert list(aggregate_events([first, save, rating]).values()) == [1]
    conflicting = first.model_copy(update={"interaction_value": Decimal(99)})
    with pytest.raises(ValueError, match="conflicting duplicate"):
        aggregate_events([first, conflicting])
    duplicate = copy.deepcopy(dataset["training"])
    duplicate["interactions"] += duplicate["interactions"]
    assert train(TrainingData.model_validate(duplicate)) == model


def test_provenance_and_unknown_references_rejected(dataset):
    data = copy.deepcopy(dataset["training"])
    data["interactions"][0]["provenance"] = "real"
    with pytest.raises(ValidationError):
        TrainingData.model_validate(data)
    data = copy.deepcopy(dataset["training"])
    data["interactions"][0]["location_id"] = fixture_id("unknown")
    with pytest.raises(ValidationError):
        TrainingData.model_validate(data)


def test_unseen_users_locations_and_sparse_user_fallback(dataset, model):
    request = request_for(dataset)
    data = request.model_dump(mode="json")
    data["preferences"]["user_id"] = fixture_id("cold-user")
    data["interactions"] = []
    cold = RecommendationRequest.model_validate(data)
    result = HybridRecommender(model).recommend(cold)
    assert compact(result) == pytest.approx(compact(content_recommend(cold)))
    assert all("unseen_user" in item.recommendation_reason for item in result.items)
    clone = LocationAttributes.model_validate(
        request.locations[0].model_dump() | {"id": fixture_id("unseen-item")}
    )
    unseen = RecommendationRequest(preferences=request.preferences, locations=[clone])
    row = HybridRecommender(model).recommend(unseen).items[0]
    assert "unseen_location" in row.recommendation_reason
    assert row.recommendation_score == pytest.approx(
        score_location(unseen.preferences, clone).score
    )
    training = copy.deepcopy(dataset["training"])
    user = str(request.preferences.user_id)
    positive = {
        row["location_id"]
        for row in training["interactions"]
        if row["user_id"] == user and row["interaction_type"] == "save"
    }
    training["interactions"] = [
        row
        for row in training["interactions"]
        if row["user_id"] != user or row["location_id"] in positive
    ]
    sparse_model = train(TrainingData.model_validate(training))
    scores = HybridRecommender(sparse_model).recommend(request)
    assert all(
        "insufficient_history" in row.recommendation_reason for row in scores.items
    )
    assert [row.location_id for row in scores.items] == [
        row.location_id for row in content_recommend(request).items
    ]


def test_sparse_item_support(dataset):
    training = copy.deepcopy(dataset["training"])
    request = request_for(dataset)
    clone_id = fixture_id("singleton-location")
    clone = LocationAttributes.model_validate(
        request.locations[0].model_dump() | {"id": clone_id}
    )
    training["location_ids"].append(clone_id)
    one = copy.deepcopy(training["interactions"][-1])
    one.update(
        id=fixture_id("singleton-event"),
        user_id=str(request.preferences.user_id),
        location_id=clone_id,
        interaction_type="save",
    )
    training["interactions"].append(one)
    model = train(TrainingData.model_validate(training))
    request = RecommendationRequest(preferences=request.preferences, locations=[clone])
    assert (
        "sparse_location"
        in HybridRecommender(model).recommend(request).items[0].recommendation_reason
    )


def test_artifact_roundtrip_and_unavailable_fallback(tmp_path, dataset, model):
    path = tmp_path / "model.json"
    model.save(path)
    assert CollaborativeModel.load(path, provenance="synthetic") == model
    engine = HybridRecommender.from_artifact(path, provenance="synthetic")
    assert engine.recommend(request_for(dataset)) == HybridRecommender(model).recommend(
        request_for(dataset)
    )
    assert HybridRecommender.from_artifact(path, provenance="real").model is None
    assert (
        HybridRecommender.from_artifact(
            tmp_path / "absent.json", provenance="synthetic"
        ).model
        is None
    )
    path.write_text("corrupt", encoding="utf-8")
    assert HybridRecommender.from_artifact(path, provenance="synthetic").recommend(
        load_request()
    ) == content_recommend(load_request())


@pytest.mark.parametrize("change", ["nan", "shape", "version", "counts", "duplicates"])
def test_invalid_artifact_rejected(tmp_path, model, change):
    data = model.model_dump(mode="json")
    if change == "nan":
        data["user_factors"][0][0] = float("nan")
    elif change == "shape":
        data["item_factors"][0] = []
    elif change == "version":
        data["model_version"] = "unknown"
    elif change == "counts":
        data["user_counts"][0] = 0
    else:
        data["user_ids"][1] = data["user_ids"][0]
    path = tmp_path / "bad-model.json"
    path.write_text(json.dumps(data), encoding="utf-8")
    assert HybridRecommender.from_artifact(path, provenance="synthetic").model is None


def test_hard_constraints_limits_and_empty_input(dataset, model):
    request = request_for(dataset)
    engine = HybridRecommender(model)
    initial = engine.recommend(request)
    request.limit = 1
    assert engine.recommend(request).items == initial.items[:1]
    excluded = initial.items[0].location_id
    request.preferences.excluded_location_ids = [excluded]
    assert excluded not in {row.location_id for row in engine.recommend(request).items}
    request.preferences.budget_max = Decimal(0)
    assert engine.recommend(request).items == []
    empty = RecommendationRequest(preferences=request.preferences, locations=[])
    assert engine.recommend(empty).items == []
    request = request_for(dataset)
    for location in request.locations:
        location.is_active = False
    assert engine.recommend(request).items == []


def test_leakage_rejected_and_held_out_not_in_inference(dataset):
    contaminated = copy.deepcopy(dataset)
    contaminated["training"]["interactions"].append(contaminated["held_out"][0])
    with pytest.raises(ValueError, match="leakage"):
        evaluate(contaminated)
    held_ids = {row["id"] for row in dataset["held_out"]}
    for index in range(24):
        assert held_ids.isdisjoint(
            str(event.id) for event in request_for(dataset, index).interactions
        )


def test_evaluation_report_metrics_and_saved_evidence(dataset):
    report = evaluate(dataset)
    again = evaluate(dataset)
    assert report == again
    assert report["training_event_count"] == 256
    assert report["held_out_event_count"] == 24
    saved = json.loads(
        (
            Path(__file__).resolve().parents[1] / "docs/evidence/hybrid-evaluation.json"
        ).read_text(encoding="utf-8")
    )
    assert saved["training_digest"] == report["training_digest"]
    for name in ("content", "hybrid"):
        assert report["summary"][name] == pytest.approx(
            saved["summary"][name], abs=1e-6
        )
        assert all(0 <= metric <= 1 for metric in report["summary"][name].values())
    # Never require a synthetic hybrid gain as a substitute for real-world validation.
    assert len(report["users"]) == 24


def test_svd_failure_and_matrix_size_guard(dataset, monkeypatch):
    data = TrainingData.model_validate(dataset["training"])
    with monkeypatch.context() as scoped:
        scoped.setattr(
            np.linalg,
            "svd",
            lambda *a, **kw: (_ for _ in ()).throw(np.linalg.LinAlgError()),
        )
        assert train(data) is None
    monkeypatch.setattr("app.recommendations.collaborative.MAX_MATRIX_CELLS", 1)
    with pytest.raises(ValueError, match="exceeds"):
        train(data)


@pytest.mark.parametrize(
    "case_id",
    [
        "budget_cafe",
        "heritage",
        "family_nature",
        "premium_food",
        "cold_start",
        "cold_start_no_tags",
        "accessibility_indoor",
        "distance_and_duration",
        "empty_result",
        "explicit_exclusion",
    ],
)
def test_model_unavailable_exactly_reuses_s3_baseline(case_id):
    request = load_request(case_id)
    assert HybridRecommender().recommend(request) == content_recommend(request)


def test_evaluation_refuses_real_labels(dataset):
    changed = copy.deepcopy(dataset)
    changed["held_out"][0]["provenance"] = "real"
    with pytest.raises(ValueError, match="synthetic data only"):
        evaluate(changed)


def test_artifact_digest_pin_accepts_only_the_exact_file(tmp_path, model):
    import hashlib

    path = tmp_path / "pinned.json"
    model.save(path)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    assert HybridRecommender.from_artifact(path, provenance="synthetic", expected_sha256=digest).model == model
    assert HybridRecommender.from_artifact(path, provenance="synthetic", expected_sha256="0" * 64).model is None
    assert HybridRecommender.from_artifact(path, provenance="synthetic", expected_sha256="short").model is None
    path.write_text(path.read_text() + " ", encoding="utf-8")  # Any byte change breaks the pin.
    assert HybridRecommender.from_artifact(path, provenance="synthetic", expected_sha256=digest).model is None
