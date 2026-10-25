"""Signed low-rank matrix factorization with NumPy SVD; no API or provider imports."""

import hashlib
import json
from collections import defaultdict
from pathlib import Path
from typing import Literal, Self
from uuid import UUID

import numpy as np
from pydantic import Field, FiniteFloat, model_validator

from .contracts import Contract, Interaction

MODEL_VERSION = "signed-svd-v1"
MIN_USER_HISTORY = 3
MIN_ITEM_USERS = 2
MIN_USERS = 3
MIN_ITEMS = 3
MIN_PAIRS = 8
MAX_MATRIX_CELLS = 1_000_000


class TrainingData(Contract):
    """Cross-user training input, deliberately separate from per-user inference."""

    provenance: Literal["synthetic", "real"]
    location_ids: list[UUID]
    interactions: list[Interaction]

    @model_validator(mode="after")
    def validate_source(self) -> Self:
        ids = set(self.location_ids)
        if len(ids) != len(self.location_ids):
            raise ValueError("duplicate catalog IDs")
        if any(
            event.provenance != self.provenance or event.location_id not in ids
            for event in self.interactions
        ):
            raise ValueError("event provenance or catalog reference mismatch")
        return self


def aggregate_events(events: list[Interaction]) -> dict[tuple[UUID, UUID], float]:
    """Latest swipe, save, and rating per pair. Exact duplicate IDs are idempotent."""
    unique = {}
    for event in events:
        event = Interaction.model_validate_json(event.model_dump_json())
        if event.id in unique and event != unique[event.id]:
            raise ValueError("conflicting duplicate event ID")
        unique[event.id] = event
    latest = {}
    for event in sorted(unique.values(), key=lambda e: (e.created_at, str(e.id))):
        channel = (
            "swipe"
            if event.interaction_type.endswith("swipe")
            else event.interaction_type
        )
        latest[event.user_id, event.location_id, channel] = event
    signals = defaultdict(float)
    for (user_id, location_id, _), event in latest.items():
        value = {"left_swipe": -1.0, "right_swipe": 1.0, "save": 2.0}.get(
            event.interaction_type
        )
        if value is None:
            value = float(event.rating_value - 3)  # ratings 1..5 map to -2..2
        signals[user_id, location_id] += value
    return {
        pair: max(-1.0, min(1.0, value / 5))
        for pair, value in sorted(
            signals.items(), key=lambda row: tuple(map(str, row[0]))
        )
        if value != 0
    }


class CollaborativeModel(Contract):
    """Validated, non-executable JSON artifact with UUID mappings and support counts."""

    model_version: Literal["signed-svd-v1"] = MODEL_VERSION
    provenance: Literal["synthetic", "real"]
    training_digest: str = Field(pattern=r"^[a-f0-9]{64}$")
    training_event_ids: list[UUID]
    user_ids: list[UUID]
    item_ids: list[UUID]
    user_factors: list[list[FiniteFloat]]
    item_factors: list[list[FiniteFloat]]
    user_counts: list[int]
    item_counts: list[int]
    rank: int = Field(ge=1, le=3)
    numpy_version: str

    @model_validator(mode="after")
    def validate_dimensions(self) -> Self:
        if len(self.training_event_ids) != len(set(self.training_event_ids)):
            raise ValueError("duplicate training event IDs")
        for ids, factors, counts in (
            (self.user_ids, self.user_factors, self.user_counts),
            (self.item_ids, self.item_factors, self.item_counts),
        ):
            if (
                len(ids) != len(set(ids))
                or not ids
                or len(ids) != len(factors)
                or len(ids) != len(counts)
            ):
                raise ValueError("invalid artifact mappings")
            if any(len(row) != self.rank for row in factors) or any(
                count < 1 for count in counts
            ):
                raise ValueError("invalid artifact factors or counts")
        if len(self.user_ids) < MIN_USERS or len(self.item_ids) < MIN_ITEMS:
            raise ValueError("artifact below minimum matrix size")
        if (
            sum(self.user_counts) != sum(self.item_counts)
            or sum(self.user_counts) < MIN_PAIRS
            or max(self.user_counts) > len(self.item_ids)
            or max(self.item_counts) > len(self.user_ids)
        ):
            raise ValueError("invalid artifact support")
        return self

    def score(self, user_id: UUID, location_id: UUID) -> tuple[float | None, str]:
        if user_id not in self.user_ids:
            return None, "unseen_user"
        user = self.user_ids.index(user_id)
        if self.user_counts[user] < MIN_USER_HISTORY:
            return None, "insufficient_history"
        if location_id not in self.item_ids:
            return None, "unseen_location"
        item = self.item_ids.index(location_id)
        if self.item_counts[item] < MIN_ITEM_USERS:
            return None, "sparse_location"
        raw = float(np.dot(self.user_factors[user], self.item_factors[item]))
        if not np.isfinite(raw):
            return None, "invalid_model_score"
        return float((np.clip(raw, -1, 1) + 1) / 2), "hybrid"

    def save(self, path: Path) -> None:
        path.write_text(self.model_dump_json(indent=2) + "\n", encoding="utf-8")

    @classmethod
    def load(cls, path: Path, *, provenance: Literal["synthetic", "real"]) -> Self:
        model = cls.model_validate_json(path.read_text(encoding="utf-8"))
        if model.provenance != provenance:
            raise ValueError("model provenance mismatch")
        return model


def train(data: TrainingData) -> CollaborativeModel | None:
    """Fit rank <=3 on signed affinities, missing pairs zero. Sparse input returns None."""
    data = TrainingData.model_validate_json(data.model_dump_json())
    signals = aggregate_events(data.interactions)
    users = sorted({user for user, _ in signals}, key=str)
    items = sorted({item for _, item in signals}, key=str)
    if len(users) < MIN_USERS or len(items) < MIN_ITEMS or len(signals) < MIN_PAIRS:
        return None
    if len(users) * len(items) > MAX_MATRIX_CELLS:
        raise ValueError("dense baseline matrix exceeds supported size")
    user_index = {key: index for index, key in enumerate(users)}
    item_index = {key: index for index, key in enumerate(items)}
    matrix = np.zeros((len(users), len(items)), dtype=np.float64)
    for (user, item), value in signals.items():
        matrix[user_index[user], item_index[item]] = value
    if np.ptp(matrix) == 0:
        return None
    try:
        left, singular, right = np.linalg.svd(matrix, full_matrices=False)
    except np.linalg.LinAlgError:
        return None
    rank = min(3, min(matrix.shape) - 1)
    # Canonicalize sign for stable artifact factors as well as reconstructed scores.
    for index in range(rank):
        pivot = np.argmax(np.abs(right[index]))
        if right[index, pivot] < 0:
            right[index] *= -1
            left[:, index] *= -1
    unique = {
        str(event.id): event.model_dump(mode="json") for event in data.interactions
    }
    digest = hashlib.sha256(json.dumps(unique, sort_keys=True).encode()).hexdigest()
    return CollaborativeModel(
        provenance=data.provenance,
        training_digest=digest,
        training_event_ids=sorted({event.id for event in data.interactions}, key=str),
        user_ids=users,
        item_ids=items,
        rank=rank,
        numpy_version=np.__version__,
        user_factors=(left[:, :rank] * singular[:rank]).tolist(),
        item_factors=right[:rank].T.tolist(),
        user_counts=np.count_nonzero(matrix, axis=1).tolist(),
        item_counts=np.count_nonzero(matrix, axis=0).tolist(),
    )
