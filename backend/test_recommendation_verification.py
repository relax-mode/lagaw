"""Guard and partial-setup cleanup checks for the development-only verifier."""

from contextlib import contextmanager
from types import SimpleNamespace
from unittest.mock import Mock

import pytest

import verify_trip_recommendations as verifier
from verify_trip_items import VerificationFailed


@pytest.mark.parametrize("url", [
    "https://zjnuqqtbapbpudsjbpif.supabase.co/rest/v1/",
    "https://unknown.supabase.co/rest/v1/", "http://127.0.0.1:53000/",
])
def test_main_refuses_non_development_before_requests(monkeypatch, url):
    client = Mock(base_url=url)

    @contextmanager
    def configured():
        yield SimpleNamespace(client=client)

    monkeypatch.setattr(verifier, "get_database", configured.__wrapped__)
    assert verifier.main() == 1
    client.get.assert_not_called()
    client.post.assert_not_called()
    client.delete.assert_not_called()


def test_partial_fixture_setup_still_cleans_every_registered_table(monkeypatch):
    client = Mock()
    client.delete.return_value.status_code = 204
    monkeypatch.setattr(verifier, "insert", Mock(side_effect=VerificationFailed("Fixture insert failed.")))
    monkeypatch.setattr(verifier, "rows", lambda *args, **kwargs: [])
    with pytest.raises(VerificationFailed, match="Fixture insert failed"):
        verifier.verify(client)
    assert [call.args[0] for call in client.delete.call_args_list] == [
        "user_location_interactions", "itinerary_items", "trips", "users", "locations",
    ]


def test_cleanup_continues_after_first_delete_failure(monkeypatch):
    client = Mock()
    client.delete.side_effect = [RuntimeError("private"), *[SimpleNamespace(status_code=204) for _ in range(4)]]
    monkeypatch.setattr(verifier, "insert", Mock(side_effect=VerificationFailed("Fixture insert failed.")))
    monkeypatch.setattr(verifier, "rows", lambda *args, **kwargs: [])
    with pytest.raises(VerificationFailed, match="Fixture cleanup failed"):
        verifier.verify(client)
    assert client.delete.call_count == 5
