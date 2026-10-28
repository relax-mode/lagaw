"""The hosted-development verifier also runs on disposable CI services."""

import pytest

from verify_itinerary_generation import verify

pytestmark = pytest.mark.db


def test_generation_persistence_replacement_owner_isolation_and_manual_edits(rest):
    verify(rest)
