"""Explicit real PostgREST/PostgreSQL checks for #26, development or disposable CI only."""

import argparse
import os
import secrets
import time
from contextlib import contextmanager
from unittest.mock import patch
from urllib.parse import urlsplit
from uuid import UUID, uuid4

import httpx
from fastapi.testclient import TestClient

from app.database import get_database
from app.trip_database import TripDatabase

DEV_HOST = "vnpkyvtbupnquvirzlzp.supabase.co"
CI_URL = "http://127.0.0.1:53000/"


class VerificationFailed(Exception):
    """Only safe, fixed diagnostic messages may reach the terminal."""


def require(condition, message):
    if not condition:
        raise VerificationFailed(message)


def validate_target(url: str, *, ci: bool = False):
    parsed = urlsplit(url)
    if ci:
        require(url == CI_URL, "CI requires the disposable loopback PostgREST service.")
    else:
        require(
            parsed.scheme == "https" and parsed.netloc == DEV_HOST
            and parsed.path == "/rest/v1/" and not parsed.query and not parsed.fragment,
            "This verification requires the known development Supabase project; production refused.",
        )


def rows(client, table, **params):
    response = client.get(table, params={"select": "*", **params})
    require(response.status_code == 200, "Database fixture read failed.")
    result = response.json()
    require(isinstance(result, list), "Database returned an invalid fixture result.")
    return result


def insert(client, table, payload):
    response = client.post(
        table, json=payload, headers={"Prefer": "return=representation", "Content-Profile": "public"},
    )
    require(response.status_code == 201, "Database fixture creation failed.")
    result = response.json()
    require(isinstance(result, list) and len(result) == 1, "Database fixture result was invalid.")
    return result[0]


def delete_exact(client, table, record_id):
    # Parse before constructing any cleanup filter. Never truncate or reset a table.
    record_id = UUID(str(record_id))
    response = client.delete(table, params={"id": f"eq.{record_id}"})
    require(response.status_code in (200, 204), "Exact fixture cleanup failed.")


@contextmanager
def api_client(database, owner, token):
    # Exercise the real bearer dependency; only the database provider is replaced.
    # No application import is permitted to load/change local configuration here.
    with patch.dict(os.environ, {
        "TRIP_DEMO_USER_ID": str(owner), "TRIP_DEMO_TOKEN": token,
        "CORS_ALLOWED_ORIGINS": "",
    }), patch("dotenv.load_dotenv"):
        from app.main import create_app
        from app.trips import get_trip_database

        with patch("app.main.load_dotenv"):
            application = create_app()

        def store():
            yield TripDatabase(database)

        application.dependency_overrides[get_trip_database] = store
        with TestClient(application, headers={"Authorization": f"Bearer {token}"}) as api:
            yield api


def verify(database):
    # IDs are registered before the first request so partial setup can be cleaned.
    owner, other = uuid4(), uuid4()
    trip, sibling_trip, other_trip = uuid4(), uuid4(), uuid4()
    location, second_location, inactive_location = uuid4(), uuid4(), uuid4()
    other_item, sibling_item = uuid4(), uuid4()
    invalid_fk_items = [uuid4(), uuid4()]
    users = (owner, other)
    trips = (trip, sibling_trip, other_trip)
    locations = (location, second_location, inactive_location)
    direct_items = (other_item, sibling_item, *invalid_fk_items)
    token = secrets.token_urlsafe(32)
    print(f'Fixture owners (synthetic): {owner}, {other}')
    try:
        for user in users:
            insert(database, "users", {
                "id": str(user), "name": "Issue 26 isolated fixture",
                "email": f"issue26-{user}@example.invalid",
            })
        for destination in locations:
            insert(database, "locations", {
                "id": str(destination), "name": f"Issue 26 fixture {destination}",
                "category": "heritage", "is_active": destination != inactive_location,
            })
        for saved_trip, user in ((trip, owner), (sibling_trip, owner), (other_trip, other)):
            insert(database, "trips", {
                "id": str(saved_trip), "user_id": str(user), "title": "Issue 26 isolated trip",
                "start_date": "2026-11-01", "end_date": "2026-11-02",
                "budget_min": "0.00", "budget_max": "500.00",
            })
        for item, parent in ((other_item, other_trip), (sibling_item, sibling_trip)):
            insert(database, "itinerary_items", {
                "id": str(item), "trip_id": str(parent), "location_id": str(location),
                "day_number": 1, "visit_order": 1,
            })

        url = f"/api/v1/trips/{trip}/items"
        body = {"location_id": str(location), "day_number": 1, "visit_order": 1}
        with api_client(database, owner, token) as api:
            response = api.get(url)
            require(response.status_code == 200 and response.json()["items"] == [],
                    "An empty owned trip did not return an empty page.")
            saved = []
            for destination, day, position in (
                (location, 2, 1), (second_location, 1, 2), (location, 1, 1),
            ):
                response = api.post(url, json={
                    "location_id": str(destination), "day_number": day, "visit_order": position,
                })
                require(response.status_code == 201, "Valid API association was rejected.")
                item = response.json()
                require(item["trip_id"] == str(trip)
                        and item["location_id"] == str(destination)
                        and item["location"]["id"] == str(destination),
                        "Saved item did not include its associated location.")
                saved.append(item)

            ordered = [saved[2], saved[1], saved[0]]
            response = api.get(url)
            require(response.status_code == 200 and response.json()["items"] == ordered,
                    "Database-backed items were not returned in day/visit order.")
            response = api.get(url + "?limit=1&offset=1")
            require(response.status_code == 200 and response.json()["items"] == [saved[1]],
                    "Itinerary pagination failed.")
            require(len(rows(database, "itinerary_items", trip_id=f"eq.{trip}")) == 3,
                    "API additions did not persist in PostgreSQL.")
            print("PASS: Multiple associations, nested locations, ordering and PostgreSQL persistence.")

            for repeated in (body, {**body, "location_id": str(second_location)}):
                require(api.post(url, json=repeated).status_code == 409,
                        "An occupied position did not return 409.")
            require(len(rows(database, "itinerary_items", trip_id=f"eq.{trip}")) == 3,
                    "A rejected repeat changed the saved items.")
            print("PASS: Repeated additions conflict atomically; revisits at other positions are allowed.")

            for payload, expected in (
                ({**body, "location_id": str(uuid4())}, 404),
                ({**body, "location_id": str(inactive_location)}, 404),
                ({**body, "location_id": "bad"}, 422),
                ({**body, "day_number": 0}, 422),
                ({**body, "day_number": 3}, 422),
                ({**body, "visit_order": -1}, 422),
                ({**body, "trip_id": str(other_trip)}, 422),
            ):
                require(api.post(url, json=payload).status_code == expected,
                        "Invalid association returned an unexpected status.")
            for parent in (other_trip, uuid4()):
                parent_url = f"/api/v1/trips/{parent}/items"
                for method, suffix, kwargs in (
                    ("GET", "", {}), ("POST", "", {"json": body}),
                    ("DELETE", f"/{other_item}", {}),
                ):
                    require(api.request(method, parent_url + suffix, **kwargs).status_code == 404,
                            "Missing or other-owner trip was accessible.")
            for protected_item in (other_item, sibling_item, uuid4()):
                require(api.delete(url + f"/{protected_item}").status_code == 404,
                        "Removal accepted an item outside the requested trip.")
            for method, suffix, kwargs in (
                ("GET", "", {}), ("POST", "", {"json": body}),
                ("DELETE", f"/{saved[2]['id']}", {}),
            ):
                require(api.request(method, url + suffix, headers={"Authorization": ""}, **kwargs)
                        .status_code == 401, "An unauthenticated item request was accepted.")
            require(len(rows(database, "itinerary_items", trip_id=f"eq.{trip}")) == 3,
                    "Rejected associations or access attempts changed the saved items.")
            require(len(rows(database, "itinerary_items", id=f"eq.{other_item}")) == 1,
                    "Owner isolation failed to preserve the other owner's item.")
            require(len(rows(database, "itinerary_items", id=f"eq.{sibling_item}")) == 1,
                    "A cross-trip removal changed a sibling trip.")
            print("PASS: Invalid associations, owner isolation, authentication and cross-trip removal.")

            # Verify the actual database FKs, independent of API prevalidation.
            for identifier, parent, destination in (
                (invalid_fk_items[0], uuid4(), location),
                (invalid_fk_items[1], trip, uuid4()),
            ):
                response = database.post("itinerary_items", json={
                    "id": str(identifier), "trip_id": str(parent),
                    "location_id": str(destination), "day_number": 1, "visit_order": 50,
                })
                require(response.status_code == 409 and response.json().get("code") == "23503",
                        "PostgreSQL did not enforce an association foreign key.")
            print("PASS: PostgreSQL rejects invalid trip and location foreign keys.")

            removed = saved[2]["id"]
            response = api.delete(url + f"/{removed}")
            require(response.status_code == 204 and response.content == b"",
                    "Item removal did not return an empty 204.")
            require(api.delete(url + f"/{removed}").status_code == 404,
                    "Repeated removal did not return 404.")
            require(not rows(database, "itinerary_items", id=f"eq.{removed}"),
                    "Item removal did not persist in PostgreSQL.")
            require(len(rows(database, "locations", id=f"eq.{location}")) == 1,
                    "Removing an item deleted its location.")
            require(api.get(url).json()["items"] == ordered[1:],
                    "Removal affected the wrong itinerary items.")

        # New app/client instance re-reads committed state; this is not a hosted redeploy.
        with api_client(database, owner, token) as fresh:
            response = fresh.get(url)
            require(response.status_code == 200 and response.json()["items"] == ordered[1:],
                    "Saved associations did not survive a new application/client.")
            require(fresh.post(url, json=body).status_code == 201,
                    "A freed position could not be reused.")
        print("PASS: Removal preserves locations; committed changes survive a new application/client.")
    finally:
        # HTTP writes commit separately, so transaction rollback alone is insufficient.
        # Clean every registered fixture even when an earlier cleanup request fails.
        cleanup_failed = False
        for table, identifiers in (
            ("itinerary_items", direct_items), ("trips", trips),
            ("users", users), ("locations", locations),
        ):
            for identifier in identifiers:
                try:
                    delete_exact(database, table, identifier)
                except Exception:  # noqa: BLE001 - Attempt every exact fixture cleanup.
                    cleanup_failed = True
        if cleanup_failed:
            raise VerificationFailed("Fixture cleanup failed; investigate this run before retrying.")
        for table, identifiers in (
            ("users", users), ("trips", trips), ("locations", locations),
            ("itinerary_items", direct_items),
        ):
            for identifier in identifiers:
                require(not rows(database, table, id=f"eq.{identifier}"),
                        "An isolated fixture survived cleanup.")
        for identifier in trips:
            require(not rows(database, "itinerary_items", trip_id=f"eq.{identifier}"),
                    "A test trip's itinerary items survived cleanup.")
        print("PASS: Exact synthetic fixtures cleaned and absence verified.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ci", action="store_true", help="Use disposable loopback PostgREST only.")
    args = parser.parse_args(argv)
    try:
        if args.ci:
            validate_target(CI_URL, ci=True)
            with httpx.Client(
                base_url=CI_URL, timeout=10, follow_redirects=False,
                headers={"Accept-Profile": "public", "Content-Profile": "public"},
            ) as database:
                for attempt in range(30):
                    try:
                        ready = database.get("locations", params={"select": "id", "limit": 0})
                        if ready.status_code == 200:
                            break
                    except httpx.HTTPError:
                        pass
                    time.sleep(1)
                else:
                    raise VerificationFailed("Disposable PostgREST did not become ready.")
                verify(database)
        else:
            # Existing backend settings select the project. Validate before the first request.
            with contextmanager(get_database)() as configured:
                validate_target(str(configured.client.base_url))
                verify(configured.client)
        return 0
    except VerificationFailed as error:
        print(f"FAIL: {error}")
    except Exception as error:  # noqa: BLE001 - Never expose credential-bearing exceptions.
        print(f"FAIL: Association verification failed ({type(error).__name__}); details omitted.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
