"""The #54 verifier must refuse production and always attempt exact cleanup."""

from unittest.mock import Mock, patch

import httpx
import pytest

from verify_itinerary_generation import main, verify
from verify_trip_items import VerificationFailed


def test_production_is_refused_before_any_http():
    client = Mock(base_url="https://zjnuqqtbapbpudsjbpif.supabase.co/rest/v1/")

    def configured():
        yield Mock(client=client)

    with patch("verify_itinerary_generation.get_database", configured), \
            patch("verify_itinerary_generation.verify") as run, patch("builtins.print"):
        assert main() == 1
    run.assert_not_called()
    client.get.assert_not_called()
    client.post.assert_not_called()
    client.delete.assert_not_called()


def test_partial_setup_failure_attempts_every_exact_cleanup_stage():
    client = Mock()
    client.post.return_value = httpx.Response(200, content=b"null")
    client.delete.return_value.status_code = 204
    with (
        patch("verify_itinerary_generation.insert", side_effect=VerificationFailed("Setup failed")),
        patch("verify_itinerary_generation.rows", return_value=[]),
        patch("builtins.print"), pytest.raises(VerificationFailed, match="Setup failed"),
    ):
        verify(client)
    assert [call.args[0] for call in client.delete.call_args_list] == [
        "itinerary_items", "trips", "users", "locations",
    ]
    assert all(next(iter(call.kwargs["params"].values())).startswith("in.(")
               for call in client.delete.call_args_list)


def test_cleanup_failure_does_not_skip_other_registered_stages():
    client = Mock()
    client.post.return_value = httpx.Response(200, content=b"null")
    client.delete.side_effect = [RuntimeError("Private diagnostics"), Mock(status_code=204),
                                 Mock(status_code=204), Mock(status_code=204)]
    with (
        patch("verify_itinerary_generation.insert", side_effect=VerificationFailed("Setup failed")),
        patch("verify_itinerary_generation.rows", return_value=[]),
        patch("builtins.print"), pytest.raises(VerificationFailed, match="Fixture cleanup failed"),
    ):
        verify(client)
    assert client.delete.call_count == 4
