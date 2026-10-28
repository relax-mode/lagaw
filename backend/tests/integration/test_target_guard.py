"""Offline checks that database fixtures cannot select hosted services."""

import pytest
from trip_test_support import LOCAL_ORIGIN, require_disposable_services

DATABASE = "postgresql+psycopg://postgres:test_only@localhost:5432/lagaw_test?sslmode=disable"


@pytest.mark.parametrize("host", ["localhost", "127.0.0.1"])
def test_accepts_disposable_services(host):
    require_disposable_services(DATABASE.replace("localhost", host), LOCAL_ORIGIN)


@pytest.mark.parametrize("database", [
    "", "invalid", DATABASE.replace("lagaw_test", "postgres"),
    DATABASE.replace("5432", "5433"), DATABASE.replace("postgres:test_only", "other:test_only"),
    DATABASE.replace("localhost", "db.vnpkyvtbupnquvirzlzp.supabase.co"),
    DATABASE.replace("localhost", "db.zjnuqqtbapbpudsjbpif.supabase.co"),
    DATABASE.replace("localhost", "another-host.invalid"),
    DATABASE.replace("sslmode=disable", "host=remote.invalid"),
    DATABASE + "&service=hosted",
])
def test_refuses_non_disposable_databases(database):
    with pytest.raises(ValueError, match="Hosted targets are refused") as error:
        require_disposable_services(database, LOCAL_ORIGIN)
    assert "test_only" not in str(error.value)


@pytest.mark.parametrize("rest", [
    "", "https://vnpkyvtbupnquvirzlzp.supabase.co/rest/v1/",
    "https://zjnuqqtbapbpudsjbpif.supabase.co/rest/v1/",
    "http://localhost:53000/", "http://127.0.0.1:53001/",
    "http://127.0.0.1:53000/rest/v1/", "http://127.0.0.1:53000/?x=1",
    "http://127.0.0.1:53000/#fragment", "http://dummy@127.0.0.1:53000/",
    "http://127.0.0.1:53000.evil.invalid/",
])
def test_refuses_other_data_api_targets(rest):
    with pytest.raises(ValueError, match="Hosted targets are refused"):
        require_disposable_services(DATABASE, rest)
