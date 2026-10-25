"""Canonical extraction vocabulary, matching the approved seeded location tags."""

from typing import Literal

TravelTag = Literal["cafe", "photography", "relaxing", "heritage", "food", "nature"]
BudgetLevel = Literal["low", "medium", "high", "unspecified"]
Duration = Literal["morning", "afternoon", "evening", "full_day", "unspecified"]
Pace = Literal["slow", "moderate", "fast", "unspecified"]
