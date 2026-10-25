"""Deterministic, credential-free content baseline. No training or HTTP dependencies."""

from dataclasses import dataclass

from .contracts import (
    LocationAttributes,
    Preferences,
    Recommendation,
    RecommendationRequest,
    RecommendationResponse,
    satisfies_constraints,
    validate_response,
)

MODEL_VERSION = "content-v1"
TAG_WEIGHT = 0.60
CATEGORY_WEIGHT = 0.25
BUDGET_WEIGHT = 0.15


@dataclass(frozen=True)
class ContentExplanation:
    """Component values are [0,1]; None denotes an unused preference feature."""

    tag_score: float | None
    category_score: float | None
    budget_score: float
    matched_tags: tuple[str, ...]
    category_match: bool
    group_match: bool
    score: float


def score_location(
    preferences: Preferences,
    location: LocationAttributes,
) -> ContentExplanation | None:
    """Explain an eligible location, or return None if a hard constraint fails.

    Interaction exclusions are applied by recommend(), not this per-location helper.
    """
    if not satisfies_constraints(preferences, location):
        return None
    preferred_tags = set(preferences.preferred_tags)
    matched = tuple(sorted(preferred_tags & set(location.vibe_tags)))
    tag_score = len(matched) / len(preferred_tags) if preferred_tags else None
    category_score = (
        float(location.category in preferences.preferred_categories)
        if preferences.preferred_categories
        else None
    )
    # Eligibility guarantees a known upper estimate <= the per-visit budget ceiling.
    cap = preferences.budget_max
    upper_cost = location.estimated_cost_max
    assert upper_cost is not None
    budget_score = float(1 - upper_cost / cap) if cap else 1.0
    components = [(BUDGET_WEIGHT, budget_score)]
    if tag_score is not None:
        components.append((TAG_WEIGHT, tag_score))
    if category_score is not None:
        components.append((CATEGORY_WEIGHT, category_score))
    score = sum(weight * value for weight, value in components) / sum(
        weight for weight, _ in components
    )
    return ContentExplanation(
        tag_score=tag_score,
        category_score=category_score,
        budget_score=budget_score,
        matched_tags=matched,
        category_match=category_score == 1,
        group_match=True,
        score=max(0.0, min(1.0, score)),
    )


def _reason(explanation: ContentExplanation, preferences: Preferences) -> str:
    # Bounded factual templates preserve the agreed string schema (max 500 chars).
    if explanation.tag_score is None:
        tags = "not specified"
    elif explanation.matched_tags:
        tags = ", ".join(explanation.matched_tags[:3])
        if len(explanation.matched_tags) > 3:
            tags += f" (+{len(explanation.matched_tags) - 3} more)"
    else:
        tags = "no matches"
    category = (
        "not specified"
        if explanation.category_score is None
        else "match"
        if explanation.category_match
        else "no match"
    )
    return (
        f"Tags: {tags}; category: {category}; "
        f"budget headroom: {explanation.budget_score:.2f}; "
        f"group: {preferences.group_type}; all requested hard constraints satisfied."
    )


def recommend(request: RecommendationRequest) -> RecommendationResponse:
    """Rank validated candidates with stable UUID tie-breaking and configurable limit."""
    # Revalidate mutable model instances and work on a snapshot without changing callers.
    request = RecommendationRequest.model_validate(request.model_dump(mode="json"))
    rejected = {
        event.location_id
        for event in request.interactions
        if event.interaction_type == "left_swipe"
    }
    scored = []
    for location in request.locations:
        if location.id in rejected:
            continue
        explanation = score_location(request.preferences, location)
        if explanation is not None:
            scored.append((location.id, explanation))
    scored.sort(key=lambda row: (-row[1].score, str(row[0])))
    response = RecommendationResponse(
        items=[
            Recommendation(
                location_id=location_id,
                recommendation_score=explanation.score,
                recommendation_reason=_reason(explanation, request.preferences),
            )
            for location_id, explanation in scored[: request.limit]
        ]
    )
    return validate_response(request, response)


class ContentBasedRecommender:
    """Structural implementation of the existing Recommender protocol."""

    def recommend(self, request: RecommendationRequest) -> RecommendationResponse:
        return recommend(request)
