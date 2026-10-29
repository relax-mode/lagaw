"""Reusable hybrid inference with explicit, observable content-only fallback paths."""

import hashlib
import json
import re
from pathlib import Path
from typing import Literal, NamedTuple

from .collaborative import MODEL_VERSION, CollaborativeModel
from .content_based import recommend as content_recommend
from .content_based import score_location
from .contracts import (
    Recommendation,
    RecommendationRequest,
    RecommendationResponse,
    validate_response,
)

COLLABORATIVE_WEIGHT = 0.40
MAX_ARTIFACT_BYTES = 1_048_576  # Far above the 64 KiB delivery limit; bounds a bad mount.
SHA256 = re.compile(r"^[a-f0-9]{64}$")


class ArtifactReport(NamedTuple):
    """Why an engine is, or is not, collaborative. Carries no identifiers or factors."""

    reason: str
    file_sha256: str | None = None
    model: CollaborativeModel | None = None

    @property
    def loaded(self) -> bool:
        return self.model is not None

    def log_line(self) -> str:
        model = self.model
        fields = {
            "status": "present" if model else "absent",
            "reason": self.reason,
            "version": model.model_version if model else "none",
            "provenance": model.provenance if model else "none",
            "training_digest": model.training_digest if model else "none",
            "users": len(model.user_ids) if model else 0,
            "items": len(model.item_ids) if model else 0,
            "pairs": sum(model.user_counts) if model else 0,
            "file_sha256": self.file_sha256 or "none",
        }
        return "recommendation_model " + " ".join(f"{key}={value}" for key, value in fields.items())


class HybridRecommender:
    def __init__(self, model: CollaborativeModel | None = None):
        # Snapshot and validate artifacts once, without trusting mutable caller data.
        self.model = (
            CollaborativeModel.model_validate_json(model.model_dump_json())
            if model is not None
            else None
        )

    @classmethod
    def from_artifact(
        cls, path: Path, *, provenance: Literal["synthetic", "real"],
        expected_sha256: str | None = None,
    ):
        # Missing, corrupt, wrong-version/provenance or unpinned bytes: content-only.
        return load_artifact(path, provenance=provenance, expected_sha256=expected_sha256)[0]

    def recommend(self, request: RecommendationRequest) -> RecommendationResponse:
        request = RecommendationRequest.model_validate_json(request.model_dump_json())
        if self.model is None:
            return content_recommend(request)
        rejected = {
            event.location_id
            for event in request.interactions
            if event.interaction_type == "left_swipe"
        }
        items = []
        for location in request.locations:
            if location.id in rejected:
                continue
            content = score_location(request.preferences, location)
            if content is None:
                continue
            collaborative, mode = self.model.score(
                request.preferences.user_id, location.id
            )
            if collaborative is None:
                score = content.score
                reason = f"Content fallback ({mode}); content score: {content.score:.4f}; constraints satisfied."
            else:
                score = (
                    COLLABORATIVE_WEIGHT * collaborative
                    + (1 - COLLABORATIVE_WEIGHT) * content.score
                )
                reason = (
                    f"Hybrid: content={content.score:.4f} (60%); "
                    f"collaborative={collaborative:.4f} (40%); constraints satisfied."
                )
            items.append(
                Recommendation(
                    location_id=location.id,
                    recommendation_score=round(score, 12),
                    recommendation_reason=reason,
                )
            )
        items.sort(key=lambda row: (-row.recommendation_score, str(row.location_id)))
        return validate_response(
            request, RecommendationResponse(items=items[: request.limit])
        )


def inspect_artifact(
    path: Path, *, provenance: Literal["synthetic", "real"], expected_sha256: str | None = None,
) -> ArtifactReport:
    """Validate one artifact file; never raises, so a bad file cannot fail startup."""
    try:
        if expected_sha256 is not None:
            expected_sha256 = expected_sha256.strip().lower()
            if not SHA256.fullmatch(expected_sha256):
                return ArtifactReport("invalid_expected_digest")
        try:
            with path.open("rb") as handle:
                raw = handle.read(MAX_ARTIFACT_BYTES + 1)
        except FileNotFoundError:
            return ArtifactReport("missing")
        except OSError:
            return ArtifactReport("unreadable")
        if len(raw) > MAX_ARTIFACT_BYTES:
            return ArtifactReport("too_large")
        digest = hashlib.sha256(raw).hexdigest()
        # Check the pin before parsing: unpinned bytes are never interpreted.
        if expected_sha256 is not None and digest != expected_sha256:
            return ArtifactReport("digest_mismatch", digest)
        try:
            document = json.loads(raw)
        except ValueError:
            return ArtifactReport("corrupt", digest)
        if not isinstance(document, dict) or document.get("model_version") != MODEL_VERSION:
            return ArtifactReport("wrong_version", digest)
        try:
            model = CollaborativeModel.model_validate(document)
        except ValueError:
            return ArtifactReport("invalid_artifact", digest)
        if model.provenance != provenance:
            return ArtifactReport("provenance_mismatch", digest)
        return ArtifactReport("loaded", digest, model)
    except Exception:  # noqa: BLE001 - Any surprise still serves the content baseline.
        return ArtifactReport("unexpected_error")


def load_artifact(
    path: Path, *, provenance: Literal["synthetic", "real"], expected_sha256: str | None = None,
) -> tuple[HybridRecommender, ArtifactReport]:
    report = inspect_artifact(path, provenance=provenance, expected_sha256=expected_sha256)
    return HybridRecommender(report.model), report
