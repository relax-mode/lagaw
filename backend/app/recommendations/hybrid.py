"""Reusable hybrid inference with explicit, observable content-only fallback paths."""

from pathlib import Path
from typing import Literal

from .collaborative import CollaborativeModel
from .content_based import recommend as content_recommend
from .content_based import score_location
from .contracts import (
    Recommendation,
    RecommendationRequest,
    RecommendationResponse,
    validate_response,
)

COLLABORATIVE_WEIGHT = 0.40


class HybridRecommender:
    def __init__(self, model: CollaborativeModel | None = None):
        # Snapshot and validate artifacts once, without trusting mutable caller data.
        self.model = (
            CollaborativeModel.model_validate_json(model.model_dump_json())
            if model is not None
            else None
        )

    @classmethod
    def from_artifact(cls, path: Path, *, provenance: Literal["synthetic", "real"]):
        try:
            return cls(CollaborativeModel.load(path, provenance=provenance))
        except (OSError, ValueError):
            return cls()  # Missing, corrupt, wrong-version/provenance: content-only.

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
