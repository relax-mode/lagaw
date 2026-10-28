"""SQLAlchemy mappings for the existing PostgreSQL tables."""

from __future__ import annotations

from datetime import date, datetime, time
from decimal import Decimal
from uuid import UUID

from sqlalchemy import (
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    MetaData,
    Numeric,
    Text,
    Time,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import ARRAY, JSONB
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


class Base(DeclarativeBase):
    metadata = MetaData(schema="public")


class User(Base):
    __tablename__ = "users"

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        primary_key=True,
        server_default=text("gen_random_uuid()"),
    )
    name: Mapped[str] = mapped_column(Text)
    # Explicit identity link. Legacy/demo profiles stay unlinked until reviewed.
    auth_user_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), unique=True)
    email: Mapped[str] = mapped_column(Text, unique=True)
    traveler_type: Mapped[str | None] = mapped_column(Text)
    preferred_tags: Mapped[list[str]] = mapped_column(
        ARRAY(Text), server_default=text("'{}'::text[]")
    )
    default_budget_min: Mapped[Decimal | None] = mapped_column(Numeric(12, 2))
    default_budget_max: Mapped[Decimal | None] = mapped_column(Numeric(12, 2))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=text("now()")
    )

    trips: Mapped[list[Trip]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )


class Location(Base):
    __tablename__ = "locations"

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        primary_key=True,
        server_default=text("gen_random_uuid()"),
    )
    name: Mapped[str] = mapped_column(Text)
    description: Mapped[str | None] = mapped_column(Text)
    category: Mapped[str] = mapped_column(Text)
    vibe_tags: Mapped[list[str]] = mapped_column(
        ARRAY(Text), server_default=text("'{}'::text[]")
    )
    address: Mapped[str | None] = mapped_column(Text)
    latitude: Mapped[Decimal | None] = mapped_column(Numeric(9, 6))
    longitude: Mapped[Decimal | None] = mapped_column(Numeric(9, 6))
    opening_hours: Mapped[dict] = mapped_column(
        JSONB, server_default=text("'{}'::jsonb")
    )
    estimated_cost_min: Mapped[Decimal | None] = mapped_column(Numeric(12, 2))
    estimated_cost_max: Mapped[Decimal | None] = mapped_column(Numeric(12, 2))
    typical_visit_duration: Mapped[int | None] = mapped_column(Integer)
    suitable_group_types: Mapped[list[str]] = mapped_column(
        ARRAY(Text), server_default=text("'{}'::text[]")
    )
    image_url: Mapped[str | None] = mapped_column(Text)
    is_active: Mapped[bool] = mapped_column(server_default=text("true"))

    itinerary_items: Mapped[list[ItineraryItem]] = relationship(
        back_populates="location",
        passive_deletes="all",
    )


class Trip(Base):
    __tablename__ = "trips"
    __table_args__ = (
        Index("trips_user_id_idx", "user_id"),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        primary_key=True,
        server_default=text("gen_random_uuid()"),
    )
    user_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("public.users.id", ondelete="CASCADE"),
    )
    title: Mapped[str] = mapped_column(Text)
    start_date: Mapped[date] = mapped_column(Date)
    end_date: Mapped[date] = mapped_column(Date)
    budget_min: Mapped[Decimal] = mapped_column(Numeric(12, 2))
    budget_max: Mapped[Decimal] = mapped_column(Numeric(12, 2))
    transportation_mode: Mapped[str | None] = mapped_column(Text)
    group_type: Mapped[str | None] = mapped_column(Text)
    preferred_tags: Mapped[list[str]] = mapped_column(
        ARRAY(Text), server_default=text("'{}'::text[]")
    )
    status: Mapped[str] = mapped_column(Text, server_default=text("'draft'"))
    estimated_total_cost: Mapped[Decimal | None] = mapped_column(Numeric(12, 2))

    user: Mapped[User] = relationship(back_populates="trips")
    itinerary_items: Mapped[list[ItineraryItem]] = relationship(
        back_populates="trip",
        cascade="all, delete-orphan",
        passive_deletes=True,
        order_by=lambda: (
            ItineraryItem.day_number,
            ItineraryItem.visit_order,
        ),
    )


class ItineraryItem(Base):
    __tablename__ = "itinerary_items"
    __table_args__ = (
        UniqueConstraint(
            "trip_id",
            "day_number",
            "visit_order",
            name="itinerary_position_unique",
        ),
        Index("itinerary_items_location_id_idx", "location_id"),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        primary_key=True,
        server_default=text("gen_random_uuid()"),
    )
    trip_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("public.trips.id", ondelete="CASCADE"),
    )
    location_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("public.locations.id", ondelete="RESTRICT"),
    )
    day_number: Mapped[int] = mapped_column(Integer)
    visit_order: Mapped[int] = mapped_column(Integer)
    arrival_time: Mapped[time | None] = mapped_column(Time)
    departure_time: Mapped[time | None] = mapped_column(Time)
    estimated_travel_time: Mapped[int | None] = mapped_column(Integer)
    estimated_cost: Mapped[Decimal | None] = mapped_column(Numeric(12, 2))
    recommendation_score: Mapped[Decimal | None] = mapped_column(Numeric)
    recommendation_reason: Mapped[str | None] = mapped_column(Text)

    trip: Mapped[Trip] = relationship(back_populates="itinerary_items")
    location: Mapped[Location] = relationship(back_populates="itinerary_items")
