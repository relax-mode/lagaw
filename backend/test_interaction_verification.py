"""Guardrails for live #52 verification: target refusal and partial-setup cleanup."""

import httpx
import pytest

import verify_interactions as verifier
from app.database import LocationDatabase
from verify_trip_items import VerificationFailed


@pytest.mark.parametrize("url", [
    "https://zjnuqqtbapbpudsjbpif.supabase.co/rest/v1/",
    "https://unknown.supabase.co/rest/v1/", "http://127.0.0.1:53000/",
])
def test_live_main_refuses_other_projects_before_http(monkeypatch, capsys, url):
    requests = []
    with httpx.Client(base_url=url, transport=httpx.MockTransport(requests.append)) as rest:
        def connection():
            yield LocationDatabase(rest)
        monkeypatch.setattr(verifier, "get_database", connection)
        assert verifier.main() == 1
    assert requests == []
    assert "production refused" in capsys.readouterr().out


@pytest.mark.parametrize("cleanup_failure", [False, True])
def test_partial_fixture_setup_attempts_all_exact_cleanup(cleanup_failure):
    deleted = []
    def handle(request):
        if request.method == "POST":
            return httpx.Response(500, json={"message": "private-provider-error"})
        if request.method == "DELETE":
            deleted.append(request)
            return httpx.Response(500 if cleanup_failure and len(deleted) == 1 else 204)
        return httpx.Response(200, json=[])
    with (
        httpx.Client(base_url="https://offline.invalid/", transport=httpx.MockTransport(handle)) as rest,
        pytest.raises(VerificationFailed) as failure,
    ):
        verifier.verify(rest)
    assert "private-provider-error" not in str(failure.value)
    assert len(deleted) == 4
    assert [request.url.path for request in deleted] == [
        "/user_location_interactions", "/user_location_interactions", "/users", "/locations",
    ]
    assert all(len(request.url.params) == 1 for request in deleted)
    assert all(next(iter(request.url.params.values())).startswith("in.(") for request in deleted)
