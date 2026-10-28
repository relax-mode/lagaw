"""Deterministic ranked first-fit scheduling; no routing provider or model calls."""

import math
import re
from datetime import date, time, timedelta
from decimal import ROUND_CEILING, Decimal
from itertools import pairwise

from app.itinerary_schemas import GenerationOptions, PlannedVisit
from app.trip_recommendation_schemas import TripRecommendationResult
from app.trip_schemas import TripResponse

WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
WINDOWS = {"morning": (9 * 60, 12 * 60), "afternoon": (13 * 60, 18 * 60),
           "evening": (18 * 60, 22 * 60), "full_day": (9 * 60, 18 * 60),
           "unspecified": (9 * 60, 18 * 60)}
# Road-distance multiplier, speed in km/h, PHP/km/person. Planning estimates only.
TRANSPORT = {"walking": (1.3, 4, Decimal(0)),
             "jeepney": (1.3, 15, Decimal(5)),
             "taxi": (1.3, 20, Decimal(20)),
             "motorcycle": (1.3, 20, Decimal(4)),
             "private_car": (1.3, 20, Decimal(8)),
             "public_transport": (1.3, 15, Decimal(5)),
             "private_vehicle": (1.3, 20, Decimal(8))}
PACE = {"slow": (Decimal("1.5"), 30), "moderate": (Decimal(1), 15),
        "fast": (Decimal(1), 0), "unspecified": (Decimal(1), 15)}


class PlanningConflict(Exception):
    def __init__(self, reason, scheduled=0, skipped=None):
        self.reason = reason
        self.scheduled = scheduled
        self.skipped = skipped or {}


class UnsupportedPlanningTrip(Exception):
    pass


def minute(value: str) -> int:
    if not re.fullmatch(r"(?:[01]\d|2[0-3]):[0-5]\d", value):
        raise ValueError
    return int(value[:2]) * 60 + int(value[3:])


def opening_intervals(hours: dict, day: date) -> list[tuple[int, int]]:
    """Fail closed for unknown/unsupported hours; never infer 24-hour opening."""
    if not hours or set(hours) - set(WEEKDAYS):
        raise ValueError
    parsed = {}
    for weekday, periods in hours.items():
        if not isinstance(periods, list):
            raise TypeError
        intervals = []
        for period in periods:
            if not isinstance(period, dict) or set(period) != {"open", "close"}:
                raise ValueError
            start, end = minute(period["open"]), minute(period["close"])
            # Overnight/24h/holiday formats need explicit catalog normalization.
            if end <= start:
                raise ValueError
            intervals.append((start, end))
        intervals.sort()
        if any(right[0] < left[1] for left, right in pairwise(intervals)):
            raise ValueError
        parsed[weekday] = intervals
    return parsed.get(WEEKDAYS[day.weekday()], [])


def travel(origin, location, mode, party_size):
    if location.latitude is None or location.longitude is None:
        raise ValueError
    if origin is None:
        # With no explicit origin, each day starts at its first destination.
        return 0, Decimal("0.00")
    lat1, lon1 = map(math.radians, origin)
    lat2, lon2 = map(math.radians, (location.latitude, location.longitude))
    hav = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    distance = 6371.0088 * 2 * math.asin(math.sqrt(min(1, max(0, hav))))
    multiplier, speed, rate = TRANSPORT[mode]
    km = Decimal(str(distance * multiplier))
    minutes = math.ceil(float(km) / speed * 60) + (5 if distance > 0 else 0)
    fare = (km * rate * party_size).quantize(Decimal("0.01"), rounding=ROUND_CEILING)
    return minutes, fare


def plan_itinerary(trip: TripResponse, options: GenerationOptions, ranked: TripRecommendationResult):
    days = (trip.end_date - trip.start_date).days + 1
    if days > 31 or trip.transportation_mode not in TRANSPORT:
        raise UnsupportedPlanningTrip
    if not ranked.items:
        raise PlanningConflict("no_suitable_recommendations")
    start, end = WINDOWS[options.duration]
    factor, buffer = PACE[options.pace]
    initial = options.recommendations.origin
    initial = (initial.latitude, initial.longitude) if initial else None
    state = [{"cursor": start, "origin": initial, "count": 0} for _ in range(days)]
    visits, total, skipped = [], Decimal("0.00"), {}
    target = options.recommendations.planned_visits
    for item in ranked.items:
        location = item.location
        reason = "insufficient_time_or_closed"
        if location.typical_visit_duration is None or location.estimated_cost_max is None:
            skipped[str(location.id)] = "missing_duration_or_cost"
            continue
        visit_minutes = math.ceil(Decimal(location.typical_visit_duration) * factor)
        maximum_duration = options.recommendations.max_visit_duration_minutes
        if maximum_duration is not None and visit_minutes > maximum_duration:
            skipped[str(location.id)] = "pace_exceeds_visit_duration_limit"
            continue
        try:
            intervals = [opening_intervals(location.opening_hours, trip.start_date + timedelta(days=i))
                         for i in range(days)]
        except (TypeError, ValueError):
            skipped[str(location.id)] = "unknown_or_unsupported_opening_hours"
            continue
        for day, slot in enumerate(state):
            try:
                travel_minutes, fare = travel(slot["origin"], location, trip.transportation_mode,
                                              options.recommendations.party_size)
            except ValueError:
                reason = "missing_coordinates"
                break
            cost = (Decimal(str(location.estimated_cost_max)) * options.recommendations.party_size + fare).quantize(Decimal("0.01"))
            if total + cost > trip.budget_max:
                reason = "insufficient_budget"
                continue
            for opened, closed in intervals[day]:
                arrival = max(slot["cursor"] + travel_minutes, opened)
                departure = arrival + visit_minutes
                if departure > min(closed, end):
                    continue
                visits.append(PlannedVisit(
                    location_id=location.id, day_number=day + 1, visit_order=slot["count"] + 1,
                    arrival_time=time(arrival // 60, arrival % 60),
                    departure_time=time(departure // 60, departure % 60),
                    estimated_travel_time=travel_minutes, estimated_cost=cost,
                    recommendation_score=item.recommendation_score,
                    recommendation_reason=item.recommendation_reason,
                ))
                slot.update(cursor=departure + buffer, origin=(location.latitude, location.longitude), count=slot["count"] + 1)
                total += cost
                break
            else:
                continue
            break
        else:
            skipped[str(location.id)] = reason
            continue
        if len(visits) == target:
            break
        if not any(visit.location_id == location.id for visit in visits):
            skipped[str(location.id)] = reason
    if len(visits) != target:
        raise PlanningConflict("requested_visits_do_not_fit", len(visits), skipped)
    return sorted(visits, key=lambda visit: (visit.day_number, visit.visit_order)), total
