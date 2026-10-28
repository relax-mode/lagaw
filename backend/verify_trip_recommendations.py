"""Explicit #53 verification against development Supabase or disposable CI."""

import os
import secrets
from contextlib import contextmanager
from unittest.mock import Mock, patch
from uuid import uuid4

from fastapi.testclient import TestClient

from app.database import LocationDatabase, get_database
from app.recommendations.hybrid import HybridRecommender
from app.trip_recommendations import get_recommendation_engine
from verify_trip_items import VerificationFailed, insert, require, rows, validate_target


@contextmanager
def api_client(database, owner):
    token = secrets.token_urlsafe(32)
    with patch.dict(os.environ, {
        "TRIP_AUTH_MODE": "demo", "SUPABASE_URL": "http://127.0.0.1:54321",
        "TRIP_DEMO_USER_ID": str(owner), "TRIP_DEMO_TOKEN": token, "CORS_ALLOWED_ORIGINS": "",
    }), patch("dotenv.load_dotenv"):
        from app.main import create_app

        with patch("app.main.load_dotenv"):
            application = create_app()

        def connection():
            yield LocationDatabase(database)

        application.dependency_overrides[get_recommendation_engine] = lambda: HybridRecommender()
        with (
            patch("app.trip_recommendations.get_database", connection),
            TestClient(application, headers={"Authorization": f"Bearer {token}"}) as api,
        ):
            yield api, application


def verify(database):
    owner, other, location, inactive, trip, foreign_trip, item, event = (uuid4() for _ in range(8))
    owner_ids, location_ids, trip_ids = f"in.({owner},{other})", f"in.({location},{inactive})", f"in.({trip},{foreign_trip})"
    print(f"Fixture owners: {owner}, {other}")
    print(f"Fixture locations: {location}, {inactive}; trips: {trip}, {foreign_trip}")
    try:
        for user in (owner, other):
            insert(database, "users", {"id": str(user), "name": "Issue 53 isolated fixture",
                                       "email": f"issue53-{user}@example.invalid"})
        for destination in (location, inactive):
            insert(database, "locations", {
                "id": str(destination), "name": f"Issue 53 synthetic venue {destination}",
                "category": "heritage", "vibe_tags": ["heritage"],
                "estimated_cost_min": 0, "estimated_cost_max": 0,
                "suitable_group_types": ["solo"], "typical_visit_duration": 30,
                "latitude": 10.67, "longitude": 122.95, "is_active": destination == location,
            })
        for identifier, user in ((trip, owner), (foreign_trip, other)):
            insert(database, "trips", {
                "id": str(identifier), "user_id": str(user), "title": "Issue 53 manual trip",
                "start_date": "2026-11-01", "end_date": "2026-11-01",
                "budget_min": 0, "budget_max": 0, "group_type": "solo", "preferred_tags": ["heritage"],
            })
        insert(database, "itinerary_items", {"id": str(item), "trip_id": str(trip),
                                             "location_id": str(location), "day_number": 1, "visit_order": 1})
        insert(database, "user_location_interactions", {
            "id": str(event), "user_id": str(other), "location_id": str(location),
            "interaction_type": "left_swipe", "interaction_value": -1,
        })
        before_trip = rows(database, "trips", id=f"eq.{trip}")
        before_items = rows(database, "itinerary_items", trip_id=f"eq.{trip}")
        options = {"party_size": 1, "planned_visits": 1, "limit": 100}
        url = f"/api/v1/trips/{trip}/recommendations"
        with api_client(database, owner) as (api, application):
            with patch("app.preference_extraction.extract_preferences", side_effect=AssertionError("Provider unavailable")) as provider:
                result = api.post(url, json=options)
                require(result.status_code == 200, "Cold-start manual recommendations failed.")
                returned = {row["location_id"] for row in result.json()["items"]}
                require(str(location) in returned and str(inactive) not in returned,
                        "Database candidates or other-owner rejection isolation failed.")
                provider.assert_not_called()
            print("PASS: Real saved manual trip/catalog rank with no model artifact or DeepSeek; other-owner rejection is isolated.")
            for identifier in (foreign_trip, uuid4()):
                response = api.post(f"/api/v1/trips/{identifier}/recommendations", json=options)
                require(response.status_code == 404, "Missing/foreign trip was accessible.")
            require(api.post(url, json=options, headers={"Authorization": ""}).status_code == 401,
                    "Missing bearer credential accessed recommendations.")
            require(api.post(url, json={**options, "limit": 0}).status_code == 422,
                    "Invalid limit was not rejected.")
            restricted = api.post(url, json={**options, "requires_step_free_access": True})
            require(restricted.status_code == 200 and restricted.json()["items"] == []
                    and restricted.json()["empty_reason"] == "no_compatible_locations",
                    "Unavailable accessibility facts did not fail closed.")
            print("PASS: Persistence-backed owner isolation, auth, input validation and valid empty result.")
            # Raw invalid model scores must fail before serialization or persistence.
            engine = Mock()
            engine.recommend.return_value = {"items": [{"location_id": str(location),
                                                        "recommendation_score": float("nan"),
                                                        "recommendation_reason": "Invalid score fixture"}]}
            application.dependency_overrides[get_recommendation_engine] = lambda: engine
            require(api.post(url, json=options).status_code == 503, "Malformed model output was exposed.")
            engine.recommend.side_effect = RuntimeError("Private diagnostics")
            require(api.post(url, json=options).status_code == 503, "Model failure was not handled safely.")
            application.dependency_overrides[get_recommendation_engine] = lambda: HybridRecommender()

            # This owner's real persisted rejection now excludes the venue.
            insert(database, "user_location_interactions", {
                "id": str(uuid4()), "user_id": str(owner), "location_id": str(location),
                "interaction_type": "left_swipe", "interaction_value": -1,
            })
            response = api.post(url, json=options)
            require(response.status_code == 200 and str(location) not in
                    {row["location_id"] for row in response.json()["items"]},
                    "Persisted owner rejection was not applied.")
        require(rows(database, "trips", id=f"eq.{trip}") == before_trip
                and rows(database, "itinerary_items", trip_id=f"eq.{trip}") == before_items,
                "Recommendations or failures changed the trip/itinerary.")
        print("PASS: Persisted rejection filters and malformed/failing model requests preserve trip and itinerary exactly.")
    finally:
        failed = False
        # Registered UUIDs only; attempt every stage even after partial setup.
        for table, params in (
            ("user_location_interactions", {"user_id": owner_ids}),
            ("itinerary_items", {"trip_id": trip_ids}),
            ("trips", {"id": trip_ids}),
            ("users", {"id": owner_ids}),
            ("locations", {"id": location_ids}),
        ):
            try:
                response = database.delete(table, params=params)
                require(response.status_code in (200, 204), "Exact fixture cleanup failed.")
                require(not rows(database, table, **params), "Fixture rows survived cleanup.")
            except Exception:  # noqa: BLE001 - Try all cleanup, keep diagnostics private.
                failed = True
        require(not failed, "Fixture cleanup failed; investigate the printed exact IDs.")
        print("PASS: Exact fixture cleanup and independent absence checks.")


def main():
    try:
        with contextmanager(get_database)() as configured:
            validate_target(str(configured.client.base_url))
            verify(configured.client)
        return 0
    except VerificationFailed as error:
        print(f"FAIL: {error}")
    except Exception as error:  # noqa: BLE001 - Never print credentials/provider diagnostics.
        print(f"FAIL: Recommendation verification failed ({type(error).__name__}); details omitted.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
