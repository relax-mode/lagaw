"""Run the complete #52 API/FK/cleanup verifier in the isolated CI services."""

import pytest

from verify_interactions import verify

pytestmark = pytest.mark.db


def test_interaction_persistence_relationships_and_owner_isolation(rest):
    # The shared fixture refuses all hosted targets before connecting. The same
    # verifier can be explicitly run against development Supabase outside pytest.
    verify(rest)
