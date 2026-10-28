"""Backend-owned snapshots, budget allocation and validation around local models."""

from decimal import ROUND_DOWN, Decimal
from uuid import UUID

import httpx
from pydantic import TypeAdapter

from app.database import LOCATION_COLUMNS, DatabaseUnavailable, LocationDatabase
from app.interaction_database import InteractionDatabase
from app.preference_vocabulary import TravelTag
from app.recommendations.contracts import (
    Coordinates,
    LocationAttributes,
    Preferences,
    RecommendationRequest,
    RecommendationResponse,
    Recommender,
    satisfies_constraints,
    validate_response,
)
from app.schemas import Location
from app.trip_database import TripDatabase
from app.trip_recommendation_schemas import (
    RecommendationBudget,
    TripRecommendation,
    TripRecommendationOptions,
    TripRecommendationResult,
)
from app.trip_schemas import TripResponse

PAGE_SIZE = 100
MAX_CANDIDATES = 10_000
APPROVED_TAGS = TypeAdapter(list[TravelTag])
LOCATIONS = TypeAdapter(list[Location])


class InvalidTripPreferences(Exception):
    """The saved manual form needs canonical tags and a supported group."""


class RecommendationUnavailable(Exception):
    """Never expose raw engine output or internal validation diagnostics."""


def location_attributes(location: Location) -> LocationAttributes:
    values = location.model_dump(include=set(LocationAttributes.model_fields))
    if location.latitude is not None and location.longitude is not None:
        values["coordinates"] = Coordinates(
            latitude=location.latitude, longitude=location.longitude,
        )
    # Setting/accessibility are deliberately unknown: the DB has no such columns.
    return LocationAttributes.model_validate(values)


class RecommendationAdapter:
    def __init__(self, client: httpx.Client):
        self.client = client
        self.trips = TripDatabase(client)
        self.locations = LocationDatabase(client)
        self.interactions = InteractionDatabase(client)

    def catalog(self) -> list[Location]:
        locations, seen = [], set()
        while True:
            page = self.locations.list_locations(PAGE_SIZE, len(locations))
            if any(row.id in seen for row in page) or len(locations) + len(page) > MAX_CANDIDATES:
                raise DatabaseUnavailable
            seen.update(row.id for row in page)
            locations.extend(page)
            if len(page) < PAGE_SIZE:
                return locations

    def current_locations(self, ids: set[UUID]) -> list[Location]:
        if not ids:
            return []
        try:
            response = self.client.get("locations", params={
                "select": LOCATION_COLUMNS, "is_active": "eq.true",
                "id": "in.(" + ",".join(str(value) for value in sorted(ids)) + ")",
                "limit": len(ids),
            })
            response.raise_for_status()
            rows = LOCATIONS.validate_json(response.content)
            if len({row.id for row in rows}) != len(rows) or any(
                row.id not in ids or not row.is_active for row in rows
            ):
                raise ValueError
            return rows
        except (httpx.HTTPError, ValueError):
            raise DatabaseUnavailable from None

    @staticmethod
    def preferences(trip: TripResponse, options: TripRecommendationOptions):
        divisor = options.party_size * options.planned_visits
        budget = RecommendationBudget(
            party_size=options.party_size, planned_visits=options.planned_visits,
            budget_min=(trip.budget_min / divisor).quantize(Decimal("0.01"), rounding=ROUND_DOWN),
            budget_max=(trip.budget_max / divisor).quantize(Decimal("0.01"), rounding=ROUND_DOWN),
        )
        try:
            tags = APPROVED_TAGS.validate_python(trip.preferred_tags)
            preferences = Preferences(
                user_id=trip.user_id, preferred_tags=sorted(set(tags)),
                budget_min=budget.budget_min, budget_max=budget.budget_max,
                group_type=trip.group_type,
                **options.model_dump(exclude={"party_size", "planned_visits", "limit"}),
            )
        except ValueError:
            raise InvalidTripPreferences from None
        return preferences, budget

    def recommend(
        self, trip: TripResponse, options: TripRecommendationOptions, engine: Recommender,
    ) -> TripRecommendationResult:
        preferences, budget = self.preferences(trip, options)
        try:
            catalog = self.catalog()
            candidates = [location_attributes(location) for location in catalog]
        except ValueError:
            raise DatabaseUnavailable from None
        if set(options.preferred_categories) - {row.category for row in candidates}:
            raise InvalidTripPreferences
        history = self.interactions.recommendation_input(trip.user_id, {row.id for row in candidates})
        request = RecommendationRequest(
            preferences=preferences, locations=candidates,
            interactions=history.interactions, limit=options.limit,
        )
        try:
            # Engines receive a copy: an invalid/mutating implementation cannot
            # alter the trusted snapshot used for output eligibility checks.
            raw = engine.recommend(request.model_copy(deep=True))
            if isinstance(raw, RecommendationResponse):
                raw = raw.model_dump(mode="python")
            # JSON score strings and booleans are not numeric model scores, even
            # though Pydantic's default float coercion would otherwise admit them.
            if isinstance(raw, dict) and isinstance(raw.get("items"), list) and any(
                isinstance(item, dict) and isinstance(
                    item.get("recommendation_score"), (str, bool),
                ) for item in raw["items"]
            ):
                raise ValueError
            response = RecommendationResponse.model_validate(raw)
            if len(response.items) > request.limit:
                raise ValueError
            response = self.filter_response(request, response)
            validate_response(request, response)
        except Exception:  # noqa: BLE001 - Local model failures have a sanitized boundary.
            raise RecommendationUnavailable from None

        # Recheck fresh rows and history after inference. Drop changed venues so
        # old scores/reasons cannot describe newly edited facts. No writes occur.
        current = {row.id: row for row in self.current_locations({item.location_id for item in response.items})}
        original = {row.id: row for row in catalog}
        current = {key: row for key, row in current.items() if row == original[key]}
        history = self.interactions.recommendation_input(trip.user_id, set(current))
        fresh_request = RecommendationRequest(
            preferences=preferences, locations=[location_attributes(row) for row in current.values()],
            interactions=history.interactions, limit=options.limit,
        )
        response = self.filter_response(fresh_request, response)
        validate_response(fresh_request, response)
        return TripRecommendationResult(
            trip_id=trip.id, budget=budget,
            items=[TripRecommendation(**item.model_dump(), location=current[item.location_id])
                   for item in response.items],
            empty_reason=None if response.items else "no_compatible_locations",
        )

    @staticmethod
    def filter_response(request: RecommendationRequest, response: RecommendationResponse):
        rejected = {event.location_id for event in request.interactions if event.interaction_type == "left_swipe"}
        allowed = {row.id for row in request.locations if satisfies_constraints(request.preferences, row)}
        seen, items = set(), []
        for item in response.items:
            if item.location_id in allowed - rejected and item.location_id not in seen:
                seen.add(item.location_id)
                items.append(item)
        return RecommendationResponse(items=items)
