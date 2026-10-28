"""Permit only the disposable services used by the Database CI job."""

import httpx
from sqlalchemy.engine import make_url
from sqlalchemy.exc import ArgumentError

LOCAL_ORIGIN = "http://127.0.0.1:53000/"


def require_disposable_services(database_url: str, postgrest_url: str) -> None:
    """Validate before requests; errors deliberately omit supplied settings."""
    try:
        database = make_url(database_url)
        rest = httpx.URL(postgrest_url)
        valid = (
            database.drivername == "postgresql+psycopg"
            and database.host in ("localhost", "127.0.0.1")
            and database.port == 5432
            and database.database == "lagaw_test"
            and database.username == "postgres"
            and dict(database.query) == {"sslmode": "disable"}
            and rest == httpx.URL(LOCAL_ORIGIN)
            and not rest.userinfo and not rest.query and not rest.fragment
        )
        if valid:
            return
    except (ArgumentError, httpx.InvalidURL, ValueError, TypeError):
        pass
    raise ValueError(
        "Trip database tests require disposable loopback PostgreSQL lagaw_test "
        "on port 5432 and PostgREST on 127.0.0.1:53000. Hosted targets are refused."
    ) from None
