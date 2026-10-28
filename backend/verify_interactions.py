"""Issue #52 real API/database checks, guarded to development Supabase only."""

import os
import secrets
from contextlib import contextmanager
from unittest.mock import patch
from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from app.database import LocationDatabase, get_database
from app.recommendations.contracts import Interaction
from verify_trip_items import (
    VerificationFailed,
    delete_exact,
    insert,
    require,
    rows,
    validate_target,
)

BASE = "/api/v1/interactions"


@contextmanager
def api_client(database, owner, token):
    # Real authorization/routes/persistence; no local configuration is modified.
    with patch.dict(os.environ, {
        "SUPABASE_URL": "http://127.0.0.1:54321",
        "TRIP_AUTH_MODE": "demo",
        "TRIP_DEMO_USER_ID": str(owner), "TRIP_DEMO_TOKEN": token, "CORS_ALLOWED_ORIGINS": "",
    }), patch("dotenv.load_dotenv"):
        from app.main import create_app

        with patch("app.main.load_dotenv"):
            application = create_app()

        def connection():
            yield LocationDatabase(database)

        with (
            patch("app.interactions.get_database", connection),
            TestClient(application, headers={"Authorization": f"Bearer {token}"}) as api,
        ):
            yield api


def verify(database):
    """Use only newly generated fixture IDs; HTTP writes require explicit cleanup."""
    owner, other, missing_owner = uuid4(), uuid4(), uuid4()
    location, inactive, missing_location = uuid4(), uuid4(), uuid4()
    other_event, invalid_user_event, invalid_location_event = uuid4(), uuid4(), uuid4()
    owner_filter = f"in.({owner},{other},{missing_owner})"
    token = secrets.token_urlsafe(32)
    print(f"Fixture owners (synthetic): {owner}, {other}")
    print(f"Fixture locations (synthetic): {location}, {inactive}")
    try:
        for user in (owner, other):
            insert(database, "users", {
                "id": str(user), "name": "Issue 52 isolated fixture",
                "email": f"issue52-{user}@example.invalid",
            })
        for destination in (location, inactive):
            insert(database, "locations", {
                "id": str(destination), "name": f"Issue 52 synthetic location {destination}",
                "category": "heritage", "is_active": destination != inactive,
            })
        insert(database, "user_location_interactions", {
            "id": str(other_event), "user_id": str(other), "location_id": str(location),
            "interaction_type": "save", "interaction_value": 1,
        })
        body = {"location_id": str(location), "interaction_type": "save"}
        saved = []
        with api_client(database, owner, token) as api:
            require(api.get(BASE).json()["items"] == [], "New owner history was not empty.")
            for kind, rating in (("left_swipe", None), ("right_swipe", None), ("save", None),
                                 ("save", None), ("rating", "1"), ("rating", "3.75"), ("rating", "5")):
                payload = {**body, "interaction_type": kind}
                if rating is not None:
                    payload["rating_value"] = rating
                response = api.post(BASE, json=payload)
                require(response.status_code == 201, "Valid interaction did not persist.")
                event = Interaction.model_validate(response.json())
                require(event.user_id == owner and event.location_id == location
                        and event.provenance == "real", "Saved event has invalid ownership or provenance.")
                require(event.interaction_value == (-1 if kind == "left_swipe" else 1),
                        "Saved event has the wrong signal value.")
                saved.append(event)
            require(len({event.id for event in saved}) == 7, "Repeat submissions overwrote events.")
            stored = rows(database, "user_location_interactions", user_id=f"eq.{owner}")
            require({UUID(row["id"]) for row in stored} == {event.id for event in saved},
                    "API events were not independently readable in PostgreSQL.")
            print("PASS: Four event types, rating bounds/decimals and append-only repeats persist.")

            for change, status in (
                ({"location_id": "bad"}, 422), ({"location_id": str(missing_location)}, 404),
                ({"location_id": str(inactive)}, 404), ({"interaction_type": "like"}, 422),
                ({"interaction_type": "rating"}, 422), ({"rating_value": 3}, 422),
                ({"interaction_type": "rating", "rating_value": 0}, 422),
                ({"interaction_type": "rating", "rating_value": 5.01}, 422),
                ({"interaction_type": "rating", "rating_value": True}, 422),
                ({"user_id": str(other)}, 422), ({"interaction_value": 100}, 422),
            ):
                require(api.post(BASE, json={**body, **change}).status_code == status,
                        "An invalid interaction returned an unexpected result.")
            for method, suffix in (("GET", ""), ("POST", ""), ("GET", "/recommendation-input")):
                require(api.request(method, BASE + suffix, json=body,
                                    headers={"Authorization": ""}).status_code == 401,
                        "An unauthorized request accessed interaction data.")
            for identifier in (other_event, uuid4()):
                require(api.get(BASE + f"/{identifier}").status_code == 404,
                        "Another owner's interaction was accessible.")
            history = api.get(BASE, params={"limit": 100, "user_id": str(other)})
            require(history.status_code == 200 and len(history.json()["items"]) == 7
                    and all(event["user_id"] == str(owner) for event in history.json()["items"]),
                    "History owner filtering failed.")
            require(len(api.get(BASE + "?limit=2&offset=1").json()["items"]) == 2,
                    "History pagination failed.")
            require(len(rows(database, "user_location_interactions", user_id=f"eq.{owner}")) == 7,
                    "Rejected events created database rows.")
            handoff = api.get(BASE + "/recommendation-input")
            require(handoff.status_code == 200 and handoff.json()["excluded_location_ids"] == [str(location)]
                    and len(handoff.json()["interactions"]) == 7,
                    "The S3-01 interaction/exclusion handoff was inconsistent.")
            print("PASS: Invalid input creates no rows; auth, owner history and S3-01 exclusions hold.")

        with api_client(database, owner, token) as fresh:
            result = fresh.get(BASE + f"/{saved[0].id}")
            require(result.status_code == 200 and result.json()["id"] == str(saved[0].id),
                    "Persistence did not survive a fresh application/client.")
        with api_client(database, missing_owner, token) as missing:
            result = missing.post(BASE, json=body)
            require(result.status_code == 503 and "23503" not in result.text
                    and "postgres" not in result.text.lower(), "Owner FK failure was not sanitized.")

        for identifier, user, destination in (
            (invalid_user_event, missing_owner, location),
            (invalid_location_event, owner, missing_location),
        ):
            response = database.post("user_location_interactions", json={
                "id": str(identifier), "user_id": str(user), "location_id": str(destination),
                "interaction_type": "save", "interaction_value": 1,
            })
            require(response.status_code == 409 and response.json().get("code") == "23503",
                    "PostgreSQL failed to enforce an interaction foreign key.")
        # Existing catalog references must be preserved rather than cascading away.
        response = database.delete("locations", params={"id": f"eq.{location}"})
        require(response.status_code == 409 and response.json().get("code") == "23503",
                "A referenced location was not protected by its FK.")
        print("PASS: Fresh-client persistence, sanitized failures and both foreign keys verified.")

        delete_exact(database, "user_location_interactions", saved[0].id)
        require(len(rows(database, "users", id=f"eq.{owner}")) == 1
                and len(rows(database, "locations", id=f"eq.{location}")) == 1,
                "Interaction deletion changed its user or location.")
        delete_exact(database, "users", owner)
        require(not rows(database, "user_location_interactions", user_id=f"eq.{owner}"),
                "Deleting a fixture user did not cascade to their interactions.")
        require(len(rows(database, "user_location_interactions", id=f"eq.{other_event}")) == 1
                and len(rows(database, "users", id=f"eq.{other}")) == 1
                and len(rows(database, "locations", id=f"eq.{location}")) == 1,
                "User deletion affected another owner or the location.")
        print("PASS: Interaction changes preserve parent records; user cascade stays owner-scoped.")
    finally:
        failed = False
        # Register filters before writes. Remove only this run's events and fixtures,
        # including hypothetical orphan events if a relationship is broken.
        for table, params in (
            ("user_location_interactions", {"user_id": owner_filter}),
            ("user_location_interactions", {"id": f"in.({other_event},{invalid_user_event},{invalid_location_event})"}),
            ("users", {"id": f"in.({owner},{other})"}),
            ("locations", {"id": f"in.({location},{inactive})"}),
        ):
            try:
                response = database.delete(table, params=params)
                require(response.status_code in (200, 204), "Exact fixture cleanup failed.")
                require(not rows(database, table, **params), "An isolated fixture survived cleanup.")
            except Exception:  # noqa: BLE001 - Attempt every cleanup without exposing secrets.
                failed = True
        require(not failed, "Fixture cleanup failed; investigate the printed fixture IDs before retrying.")
        print("PASS: Exact synthetic fixtures cleaned and absence verified.")


def main():
    try:
        # The application's existing configuration carries secrets without printing
        # them. Refuse production/unknown projects before the first HTTP request.
        with contextmanager(get_database)() as configured:
            validate_target(str(configured.client.base_url))
            verify(configured.client)
        return 0
    except VerificationFailed as error:
        print(f"FAIL: {error}")
    except Exception as error:  # noqa: BLE001 - Never print credential-bearing diagnostics.
        print(f"FAIL: Interaction verification failed ({type(error).__name__}); details omitted.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
