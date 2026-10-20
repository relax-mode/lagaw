"""Create the SQLAlchemy engine when database access is requested."""

import os
from functools import lru_cache
from pathlib import Path

from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.engine import Engine, make_url

ROOT = Path(__file__).resolve().parents[2]


@lru_cache(maxsize=1)
def get_engine() -> Engine:
    load_dotenv(ROOT / ".env", override=False)

    database_url = os.environ.get("DATABASE_URL", "").strip()
    if not database_url:
        raise RuntimeError("DATABASE_URL is missing.")

    url = make_url(database_url)
    if url.drivername != "postgresql+psycopg":
        raise RuntimeError("DATABASE_URL must start with postgresql+psycopg://")

    sslmode = url.query.get("sslmode", "require")
    if sslmode not in ("require", "verify-ca", "verify-full") and url.host not in (
        "localhost", "127.0.0.1", "::1",
    ):
        raise RuntimeError("Hosted PostgreSQL connections require SSL.")

    return create_engine(
        url,
        pool_pre_ping=True,
        hide_parameters=True,
        connect_args={"connect_timeout": 10, "sslmode": sslmode},
    )
