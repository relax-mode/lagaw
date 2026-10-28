"""#54 real API checks; production is refused before any request."""

import os
import secrets
from contextlib import contextmanager
from unittest.mock import Mock, patch
from uuid import uuid4

from fastapi.testclient import TestClient

from app.database import LocationDatabase, get_database
from app.trip_recommendations import get_recommendation_engine
from verify_trip_items import VerificationFailed, insert, require, rows, validate_target


@contextmanager
def api_client(database, owner, engine):
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

        application.dependency_overrides[get_recommendation_engine] = lambda: engine
        with (
            patch("app.trip_recommendations.get_database", connection),
            patch("app.trips.get_database", connection),
            TestClient(application, headers={"Authorization": f"Bearer {token}"}) as api,
        ):
            yield api, application


def verify(database):
    owner, other, first, second, trip, foreign = (uuid4() for _ in range(6))
    owner_filter, trip_filter, location_filter = f"in.({owner},{other})", f"in.({trip},{foreign})", f"in.({first},{second})"
    print(f"#54 fixture owners: {owner}, {other}")
    print(f"#54 fixture trips: {trip}, {foreign}; locations: {first}, {second}")
    engine = Mock()
    engine.recommend.return_value = {"items": [
        {"location_id": str(identifier), "recommendation_score": score,
         "recommendation_reason": "Issue 54 deterministic verified fixture"}
        for identifier, score in ((first, 0.9), (second, 0.8))
    ]}
    options = {"recommendations": {"party_size": 2, "planned_visits": 2, "limit": 10},
               "duration": "morning", "pace": "moderate"}
    url, items_url = f"/api/v1/trips/{trip}/generate-itinerary", f"/api/v1/trips/{trip}/items"
    try:
        # Probe migration before writing any fixture. A random missing trip returns null.
        probe = database.post("rpc/itinerary_state", json={"p_owner": str(owner), "p_trip": str(trip)})
        require(probe.status_code == 200 and probe.json() is None,
                "Issue 54 migration is unavailable; apply it to the verified development target first.")
        for user in (owner, other):
            insert(database, "users", {"id": str(user), "name": "Issue 54 synthetic fixture",
                                       "email": f"issue54-{user}@example.invalid"})
        for identifier, day in ((first, "monday"), (second, "tuesday")):
            insert(database, "locations", {
                "id": str(identifier), "name": f"Issue 54 synthetic venue {identifier}",
                "category": "cafe", "vibe_tags": ["cafe"], "latitude": 10.67, "longitude": 122.95,
                "opening_hours": {day: [{"open": "09:00", "close": "10:00"}]},
                "estimated_cost_min": 10, "estimated_cost_max": 20, "typical_visit_duration": 60,
                "suitable_group_types": ["friends"], "is_active": True,
            })
        for identifier, user in ((trip, owner), (foreign, other)):
            insert(database, "trips", {
                "id": str(identifier), "user_id": str(user), "title": "Issue 54 synthetic trip",
                "start_date": "2026-11-02", "end_date": "2026-11-03", "budget_min": 0,
                "budget_max": 1000, "transportation_mode": "walking", "group_type": "friends",
                "preferred_tags": ["cafe"],
            })
        with api_client(database, owner, engine) as (api, _application):
            require(api.post(url, json=options, headers={"Authorization": ""}).status_code == 401,
                    "Generation bearer guard failed.")
            for inaccessible in (foreign, uuid4()):
                require(api.post(f"/api/v1/trips/{inaccessible}/generate-itinerary", json=options).status_code == 404,
                        "Generation owner isolation failed.")
            response = api.post(url, json=options)
            require(response.status_code == 200, "Real generation/persistence failed.")
            saved = response.json()
            require([(i["day_number"], i["visit_order"]) for i in saved["items"]] == [(1, 1), (2, 1)]
                    and str(saved["estimated_total_cost"]) == "80.00", "Schedule or party total is incorrect.")
            require([i["recommendation_score"] for i in saved["items"]] == [0.9, 0.8]
                    and all(i["arrival_time"] == "09:00:00" and i["departure_time"] == "10:00:00"
                            and i["recommendation_reason"] for i in saved["items"]),
                    "Persisted schedule or scores/reasons are incorrect.")
            reloaded = api.get(items_url).json()["items"]
            mismatches = sorted({key for old, new in zip(saved["items"], reloaded, strict=True)
                                 for key in old if old[key] != new.get(key)})
            require(not mismatches, "Association reload differs in fields: " + ", ".join(mismatches))
            print("PASS: Real ordered multi-day generation, party total, times, score/reason and association reload.")

            before_trip = rows(database, "trips", id=f"eq.{trip}")
            before_items = rows(database, "itinerary_items", trip_id=f"eq.{trip}", order="day_number,visit_order")

            def unchanged():
                require(rows(database, "trips", id=f"eq.{trip}") == before_trip
                        and rows(database, "itinerary_items", trip_id=f"eq.{trip}", order="day_number,visit_order") == before_items,
                        "Failed/repeated generation changed the saved itinerary or trip.")

            repeated = api.post(url, json=options)
            require(repeated.status_code == 409 and repeated.json()["detail"]["code"] == "replacement_confirmation_required",
                    "Repeated generation lacked explicit confirmation.")
            unchanged()
            confirmed = {**options, "replace_existing": True, "expected_revision": saved["revision"]}
            require(api.post(url, json={**confirmed, "expected_revision": "0" * 32}).status_code == 409,
                    "Stale confirmation was accepted.")
            unchanged()
            require(api.post(url, json={**confirmed, "duration": "afternoon"}).status_code == 409,
                    "Closed destinations were scheduled.")
            unchanged()
            engine.recommend.return_value = {"items": []}
            require(api.post(url, json=confirmed).status_code == 409, "No-suitable-results should preserve saved data.")
            unchanged()
            engine.recommend.return_value = {"items": [{"location_id": str(first),
                "recommendation_score": float("nan"), "recommendation_reason": "Malformed fixture"}]}
            require(api.post(url, json=confirmed).status_code == 503, "Malformed model result was accepted.")
            unchanged()
            engine.recommend.return_value = {"items": [
                {"location_id": str(identifier), "recommendation_score": score,
                 "recommendation_reason": "Issue 54 deterministic verified fixture"}
                for identifier, score in ((first, 0.9), (second, 0.8))
            ]}
            replacement = api.post(url, json=confirmed)
            require(replacement.status_code == 200 and replacement.json()["revision"] != saved["revision"],
                    "Confirmed replacement failed.")
            require(api.post(url, json=confirmed).status_code == 409, "Replayed confirmation replaced a newer plan.")
            print("PASS: Confirmation, stale/replayed revisions, closed/empty/malformed failures and exact preservation.")

            persisted = api.get(items_url).json()["items"]
            with api_client(database, owner, engine) as (fresh, _):
                require(fresh.get(items_url).json()["items"] == persisted,
                        "New application/client did not reload committed metadata.")
            require(api.delete(f"{items_url}/{persisted[0]['id']}").status_code == 204, "Manual removal failed.")
            require(rows(database, "trips", id=f"eq.{trip}")[0]["estimated_total_cost"] is None,
                    "Manual removal left a misleading complete-plan total.")
            added = api.post(items_url, json={"location_id": str(first), "day_number": 1, "visit_order": 1})
            require(added.status_code == 201 and added.json()["arrival_time"] is None,
                    "Manual add compatibility failed.")
            require(len(api.get(items_url).json()["items"]) == 2
                    and len(rows(database, "locations", id=location_filter)) == 2,
                    "Manual edits removed unrelated items or locations.")
            print("PASS: Fresh application persistence, manual removal/addition, estimate invalidation and preserved locations.")
    finally:
        failed = False
        for table, params in (
            ("itinerary_items", {"trip_id": trip_filter}), ("trips", {"id": trip_filter}),
            ("users", {"id": owner_filter}), ("locations", {"id": location_filter}),
        ):
            try:
                result = database.delete(table, params=params)
                require(result.status_code in (200, 204), "Exact #54 cleanup failed.")
                require(not rows(database, table, **params), "#54 fixtures remain after cleanup.")
            except Exception:  # noqa: BLE001 - Attempt every cleanup without exposing private details.
                failed = True
        require(not failed, "Fixture cleanup failed; investigate the printed exact IDs.")
        print("PASS: Exact #54 fixture cleanup and independent absence checks.")


def main():
    try:
        with contextmanager(get_database)() as configured:
            validate_target(str(configured.client.base_url))
            verify(configured.client)
        return 0
    except VerificationFailed as error:
        print(f"FAIL: {error}")
    except Exception as error:  # noqa: BLE001 - Never print credentials or provider diagnostics.
        print(f"FAIL: Itinerary verification failed ({type(error).__name__}); details omitted.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
