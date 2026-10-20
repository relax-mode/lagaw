"""Verify trip relationships on development or disposable CI; roll back fixtures."""

import argparse
from datetime import date
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import func, select
from sqlalchemy.engine import Engine
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.db_session import get_engine
from app.models import ItineraryItem, Location, Trip, User

DEV_PROJECT_ID = "vnpkyvtbupnquvirzlzp"
LOCATION_IDS = (
    UUID("1a3bca09-5532-5de6-8587-2440c4e5830d"),
    UUID("61bf94ab-6ec0-5ec3-8451-b575ee06169e"),
)


class VerificationFailed(Exception):
    """A verification failure with a message safe to show in terminal output."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise VerificationFailed(message)


def validate_target(engine: Engine, *, ci: bool = False) -> None:
    host = engine.url.host or ""
    if ci:
        require(
            host in ("localhost", "127.0.0.1", "::1")
            and engine.url.database == "lagaw_test",
            "CI verification requires the disposable lagaw_test database on loopback.",
        )
        return
    require(
        (
            engine.url.username == f"postgres.{DEV_PROJECT_ID}"
            and host.endswith(".pooler.supabase.com")
        )
        or host == f"db.{DEV_PROJECT_ID}.supabase.co",
        "This verification must target the test/development project.",
    )


def verify(session: Session) -> tuple[UUID, UUID]:
    locations = {
        location.id: location
        for location in session.scalars(
            select(Location).where(Location.id.in_(LOCATION_IDS))
        )
    }
    require(
        len(locations) == len(LOCATION_IDS),
        "San Sebastian Cathedral and The Negros Museum must already be seeded.",
    )

    user = User(
        name="Relationship Verification",
        email=f"relationships-{uuid4()}@example.invalid",
    )
    trip = Trip(
        user=user,
        title="Bacolod Relationship Verification",
        start_date=date(2026, 10, 20),
        end_date=date(2026, 10, 20),
        budget_min=Decimal(0),
        budget_max=Decimal(500),
    )
    trip.itinerary_items = [
        ItineraryItem(
            location=locations[location_id],
            day_number=1,
            visit_order=position,
        )
        for position, location_id in enumerate(LOCATION_IDS, start=1)
    ]
    session.add(trip)
    session.flush()

    user_id = user.id
    trip_id = trip.id
    item_id = trip.itinerary_items[0].id

    # Expire the identity map so these relationships are fetched from PostgreSQL.
    session.expire_all()
    loaded_user = session.get(User, user_id)
    require(loaded_user is not None, "Test user was not found.")
    require(len(loaded_user.trips) == 1, "User-to-trip relationship failed.")

    loaded_trip = loaded_user.trips[0]
    require(loaded_trip.id == trip_id, "The wrong trip was loaded.")
    require(loaded_trip.user.id == user_id, "Trip-to-user relationship failed.")
    require(
        len(loaded_trip.itinerary_items) == len(LOCATION_IDS),
        "Trip-to-itinerary relationship failed.",
    )
    require(
        [item.location.id for item in loaded_trip.itinerary_items]
        == list(LOCATION_IDS),
        "Itinerary-to-location relationship failed.",
    )
    require(
        all(item.trip.id == trip_id for item in loaded_trip.itinerary_items),
        "Itinerary-to-trip relationship failed.",
    )
    print("PASS: Related user, trip, itinerary, and locations loaded.")

    invalid_links = (
        (Trip.__table__, "user_id", trip_id),
        (ItineraryItem.__table__, "trip_id", item_id),
        (ItineraryItem.__table__, "location_id", item_id),
    )
    for table, column, record_id in invalid_links:
        for invalid_value, expected_state in ((uuid4(), "23503"), (None, "23502")):
            try:
                # Each rejected update is isolated from the outer transaction.
                with session.begin_nested():
                    session.execute(
                        table.update()
                        .where(table.c.id == record_id)
                        .values({column: invalid_value})
                    )
            except IntegrityError as error:
                require(
                    getattr(error.orig, "sqlstate", None) == expected_state,
                    f"Unexpected constraint failure for {table.name}.{column}.",
                )
            else:
                raise VerificationFailed(
                    f"Invalid reference accepted for {table.name}.{column}."
                )
    print("PASS: Invalid and missing foreign keys rejected.")

    # Unload the collection so PostgreSQL performs the ON DELETE CASCADE.
    session.expire(loaded_trip, ["itinerary_items"])
    session.delete(loaded_trip)
    session.flush()

    remaining_items = session.scalar(
        select(func.count())
        .select_from(ItineraryItem)
        .where(ItineraryItem.trip_id == trip_id)
    )
    require(remaining_items == 0, "Trip deletion left itinerary items behind.")
    print("PASS: Trip deletion removed its itinerary items.")

    remaining_locations = session.scalar(
        select(func.count())
        .select_from(Location)
        .where(Location.id.in_(LOCATION_IDS))
    )
    remaining_user = session.scalar(
        select(func.count()).select_from(User).where(User.id == user_id)
    )
    require(remaining_locations == len(LOCATION_IDS), "Trip deletion affected destinations.")
    require(remaining_user == 1, "Trip deletion affected its user.")
    print("PASS: User and destinations preserved.")
    return user_id, trip_id


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--ci", action="store_true", help="Use a disposable loopback lagaw_test database."
    )
    args = parser.parse_args(argv)
    engine = None
    try:
        engine = get_engine()
        validate_target(engine, ci=args.ci)

        with Session(engine) as session:
            try:
                user_id, trip_id = verify(session)
            finally:
                session.rollback()

        # Check rollback using a new session instead of the ORM identity map.
        with Session(engine) as session:
            require(session.get(User, user_id) is None, "Test user survived rollback.")
            require(session.get(Trip, trip_id) is None, "Test trip survived rollback.")
            remaining_items = session.scalar(
                select(func.count())
                .select_from(ItineraryItem)
                .where(ItineraryItem.trip_id == trip_id)
            )
            require(remaining_items == 0, "Test itinerary items survived rollback.")
        print("PASS: Temporary verification records rolled back.")
        return 0

    except VerificationFailed as error:
        print(f"FAIL: {error}")
        return 1
    except Exception as error:  # noqa: BLE001 - Hide credential-bearing driver tracebacks.
        print(f"FAIL: Database verification failed ({type(error).__name__}).")
        print("Connection details were omitted to protect credentials.")
        return 1
    finally:
        if engine is not None:
            engine.dispose()


if __name__ == "__main__":
    raise SystemExit(main())
