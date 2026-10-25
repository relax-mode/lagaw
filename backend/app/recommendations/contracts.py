"""Version 1 boundary shared by the backend and future recommendation engines."""

from decimal import Decimal
from math import asin, cos, radians, sin, sqrt
from typing import Annotated, Literal, Protocol, Self
from uuid import UUID

from pydantic import (
    AwareDatetime,
    BaseModel,
    ConfigDict,
    Field,
    StringConstraints,
    model_validator,
)

Money = Annotated[Decimal, Field(ge=0, max_digits=12, decimal_places=2)]
Label = Annotated[str, StringConstraints(pattern=r"^[a-z][a-z0-9_]*$", max_length=50)]
Group = Literal["solo", "couple", "family", "friends", "group"]
Tags = Annotated[list[Label], Field(max_length=30)]


class Contract(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)


class Coordinates(Contract):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class Preferences(Contract):
    user_id: UUID
    preferred_tags: Tags
    budget_min: Money
    budget_max: Money
    group_type: Group
    preferred_categories: Tags = Field(default_factory=list)
    setting: Literal["indoor", "outdoor"] | None = None
    requires_step_free_access: bool = False
    max_visit_duration_minutes: int | None = Field(default=None, gt=0)
    origin: Coordinates | None = None
    max_distance_km: float | None = Field(default=None, gt=0)
    excluded_location_ids: list[UUID] = Field(default_factory=list)

    @model_validator(mode="after")
    def check_constraints(self) -> Self:
        if self.budget_min > self.budget_max:
            raise ValueError("budget_min must not exceed budget_max")
        if self.max_distance_km is not None and self.origin is None:
            raise ValueError("max_distance_km requires origin")
        return self


class LocationAttributes(Contract):
    id: UUID
    name: str = Field(min_length=1)
    category: Label
    vibe_tags: Tags
    estimated_cost_min: Money | None
    estimated_cost_max: Money | None
    suitable_group_types: list[Group]
    typical_visit_duration: int | None = Field(gt=0)
    is_active: bool
    coordinates: Coordinates | None = None
    setting: Literal["indoor", "outdoor", "mixed"] | None = None
    step_free_access: bool | None = None

    @model_validator(mode="after")
    def check_cost(self) -> Self:
        if (
            self.estimated_cost_min is not None
            and self.estimated_cost_max is not None
            and self.estimated_cost_min > self.estimated_cost_max
        ):
            raise ValueError("estimated_cost_min must not exceed estimated_cost_max")
        return self


class Interaction(Contract):
    id: UUID
    user_id: UUID
    location_id: UUID
    interaction_type: Literal["left_swipe", "right_swipe", "save", "rating"]
    interaction_value: Decimal
    rating_value: Decimal | None = Field(default=None, ge=1, le=5)
    created_at: AwareDatetime
    provenance: Literal["synthetic", "real"]

    @model_validator(mode="after")
    def check_rating(self) -> Self:
        if (self.interaction_type == "rating") != (self.rating_value is not None):
            raise ValueError("rating_value is required only for rating events")
        return self


class RecommendationRequest(Contract):
    schema_version: Literal["1"] = "1"
    preferences: Preferences
    locations: list[LocationAttributes]
    interactions: list[Interaction] = Field(default_factory=list)
    limit: int = Field(default=10, ge=1, le=100)

    @model_validator(mode="after")
    def check_references(self) -> Self:
        ids = [location.id for location in self.locations]
        if len(ids) != len(set(ids)):
            raise ValueError("duplicate location IDs")
        event_ids = [event.id for event in self.interactions]
        if len(event_ids) != len(set(event_ids)):
            raise ValueError("duplicate interaction IDs")
        if any(
            event.user_id != self.preferences.user_id or event.location_id not in ids
            for event in self.interactions
        ):
            raise ValueError(
                "interactions must belong to this user and candidate catalog"
            )
        return self


class Recommendation(Contract):
    location_id: UUID
    recommendation_score: float = Field(ge=0, le=1)
    recommendation_reason: str = Field(min_length=1, max_length=500, pattern=r"\S")


class RecommendationResponse(Contract):
    schema_version: Literal["1"] = "1"
    items: list[Recommendation]


class Recommender(Protocol):
    """Implement in #51; implementations receive data, never API clients or secrets."""

    def recommend(self, request: RecommendationRequest) -> RecommendationResponse: ...


def satisfies_constraints(
    preferences: Preferences, location: LocationAttributes
) -> bool:
    """Boundary eligibility policy, not a ranking algorithm. Unknown hard facts fail closed."""
    if (
        not location.is_active
        or preferences.group_type not in location.suitable_group_types
    ):
        return False
    if location.id in preferences.excluded_location_ids:
        return False
    if (
        location.estimated_cost_max is None
        or location.estimated_cost_max > preferences.budget_max
    ):
        return False
    if preferences.setting is not None and location.setting != preferences.setting:
        return False
    if preferences.requires_step_free_access and location.step_free_access is not True:
        return False
    duration = preferences.max_visit_duration_minutes
    if duration is not None and (
        location.typical_visit_duration is None
        or location.typical_visit_duration > duration
    ):
        return False
    if preferences.max_distance_km is not None:
        if location.coordinates is None or preferences.origin is None:
            return False
        origin, target = preferences.origin, location.coordinates
        lat1, lat2 = radians(origin.latitude), radians(target.latitude)
        delta_lon = radians(target.longitude - origin.longitude)
        a = (
            sin((lat2 - lat1) / 2) ** 2
            + cos(lat1) * cos(lat2) * sin(delta_lon / 2) ** 2
        )
        distance = 6371.0088 * 2 * asin(sqrt(min(1, max(0, a))))
        if distance > preferences.max_distance_km:
            return False
    return True


def validate_response(
    request: RecommendationRequest,
    response: RecommendationResponse,
) -> RecommendationResponse:
    """Fail closed before results reach persistence, itinerary planning or Flutter."""
    response = RecommendationResponse.model_validate(response.model_dump(mode="json"))
    ids = [item.location_id for item in response.items]
    allowed = {
        location.id
        for location in request.locations
        if satisfies_constraints(request.preferences, location)
    }
    excluded = set(request.preferences.excluded_location_ids)
    excluded.update(
        event.location_id
        for event in request.interactions
        if event.interaction_type == "left_swipe"
    )
    if len(ids) != len(set(ids)) or len(ids) > request.limit:
        raise ValueError("duplicate recommendations or limit exceeded")
    if any(
        location_id not in allowed or location_id in excluded for location_id in ids
    ):
        raise ValueError("unknown, inactive or excluded recommendation")
    scores = [item.recommendation_score for item in response.items]
    if scores != sorted(scores, reverse=True):
        raise ValueError("recommendations must be sorted by descending score")
    return response
