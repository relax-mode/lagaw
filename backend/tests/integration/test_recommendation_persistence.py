"""#53 real owner/catalog/history/preservation checks on disposable CI services."""

import pytest

from verify_trip_recommendations import verify

pytestmark = pytest.mark.db


def test_saved_trip_recommendations_persistence_and_owner_isolation(rest):
    verify(rest)
