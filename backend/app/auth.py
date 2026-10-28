"""Supabase-verified identities and explicit, non-production demo access."""

import os
import secrets
from contextlib import contextmanager
from urllib.parse import urlsplit
from uuid import UUID

import httpx
import jwt
from fastapi import HTTPException

from app.database import DatabaseUnavailable, get_database

DEVELOPMENT_URL = "https://vnpkyvtbupnquvirzlzp.supabase.co"


def unauthorized() -> HTTPException:
    return HTTPException(401, "A valid Supabase access token is required.",
                         headers={"WWW-Authenticate": "Bearer"})


def auth_configuration() -> tuple[str, str]:
    """Reuse existing backend settings; no signing secret or dotenv edit is needed."""
    url = os.environ.get("SUPABASE_URL", "").strip().rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    try:
        parsed = urlsplit(url)
        local = parsed.scheme == "http" and parsed.hostname in ("localhost", "127.0.0.1")
        if (not key or not parsed.hostname or (parsed.scheme != "https" and not local)
                or parsed.username or parsed.password or parsed.path
                or parsed.query or parsed.fragment):
            raise ValueError
        _ = parsed.port
    except ValueError:
        raise HTTPException(503, "Authentication is temporarily unavailable.") from None
    return url, key


def verify_identity(token: str) -> tuple[UUID, str]:
    """The Auth /user endpoint verifies signatures (including legacy HS256).

    PyJWT additionally pins the issuer, audience, role, subject and lifetime.
    Decoded claims alone NEVER authorize: a successful remote verification and
    matching, confirmed Auth user are mandatory before any profile/owner lookup.
    """
    url, key = auth_configuration()
    try:
        if len(token) > 16384 or jwt.get_unverified_header(token).get("alg") not in (
            "HS256", "ES256", "RS256",
        ):
            raise ValueError
        claims = jwt.decode(token, options={
            "verify_signature": False, "verify_exp": True, "verify_nbf": True,
            "verify_iat": True, "verify_iss": True, "verify_aud": True,
            "require": ["sub", "iss", "aud", "exp", "iat", "role"],
        }, issuer=f"{url}/auth/v1", audience="authenticated")
        subject = UUID(claims["sub"])
        if subject.int == 0 or claims["role"] != "authenticated":
            raise ValueError
        # No request-selected URL, redirects, sessions or token caching.
        with httpx.Client(timeout=10.0, follow_redirects=False) as client:
            response = client.get(f"{url}/auth/v1/user", headers={
                "apikey": key, "Authorization": f"Bearer {token}", "Accept": "application/json",
            })
        if response.status_code in (400, 401, 403, 404, 422):
            raise unauthorized()
        if response.status_code != 200:
            raise HTTPException(503, "Authentication is temporarily unavailable.")
        user = response.json()
        if not isinstance(user, dict) or user.get("id") != str(subject):
            raise ValueError
        if (user.get("aud") != "authenticated" or user.get("role") != "authenticated"
                or user.get("is_anonymous") is not False):
            raise ValueError
        email = user.get("email")
        if not isinstance(email, str) or not email.strip() or "@" not in email:
            raise ValueError
        if not user.get("email_confirmed_at"):
            raise HTTPException(403, detail={"code": "email_confirmation_required",
                                            "message": "Confirm your email before continuing."})
        # Recheck expiry after the network request as well.
        jwt.decode(token, options={"verify_signature": False, "verify_exp": True,
                                   "require": ["exp"]})
        return subject, email
    except (jwt.PyJWTError, ValueError, TypeError, KeyError, OverflowError):
        raise unauthorized() from None
    except (httpx.HTTPError, httpx.InvalidURL):
        raise HTTPException(503, "Authentication is temporarily unavailable.") from None


def profile_owner(subject: UUID, email: str) -> UUID:
    """Only an explicit auth_user_id link grants ownership, never an email/ID match."""
    try:
        with contextmanager(get_database)() as database:
            client = database.client
            params = {"select": "id,auth_user_id", "auth_user_id": f"eq.{subject}", "limit": 2}

            def linked_owner():
                response = client.get("users", params=params)
                response.raise_for_status()
                rows = response.json()
                if not isinstance(rows, list) or len(rows) > 1:
                    raise ValueError
                if not rows:
                    return None
                row = rows[0]
                if not isinstance(row, dict) or row.get("auth_user_id") != str(subject):
                    raise ValueError
                owner = UUID(row["id"])
                if owner.int == 0:
                    raise ValueError
                return owner

            owner = linked_owner()
            if owner is not None:
                return owner
            # Concurrent first requests resolve to the same unique link. DO NOTHING
            # preserves existing names/preferences; never merge on email or profile ID.
            response = client.post("users", params={"on_conflict": "auth_user_id"},
                                   headers={"Prefer": "resolution=ignore-duplicates,return=minimal",
                                            "Content-Profile": "public"},
                                   json={"auth_user_id": str(subject), "email": email,
                                         "name": "Traveler"})
            if response.status_code == 409:
                raise HTTPException(409, detail={
                    "code": "profile_link_required",
                    "message": "An existing profile needs review before this account can continue.",
                })
            response.raise_for_status()
            owner = linked_owner()
            if owner is None:
                raise ValueError
            return owner
    except (DatabaseUnavailable, httpx.HTTPError, ValueError, TypeError, KeyError):
        raise HTTPException(503, "User profiles are temporarily unavailable.") from None


def demo_owner(token: str) -> UUID:
    """Explicit opt-in is allowed only for the known dev project or loopback."""
    url = os.environ.get("SUPABASE_URL", "").strip().rstrip("/")
    try:
        parsed = urlsplit(url)
        local = (parsed.scheme == "http" and parsed.hostname in ("localhost", "127.0.0.1")
                 and not parsed.username and not parsed.password and not parsed.path
                 and not parsed.query and not parsed.fragment)
        if url != DEVELOPMENT_URL and not local:
            raise ValueError
        configured = os.environ.get("TRIP_DEMO_TOKEN", "")
        owner = UUID(os.environ.get("TRIP_DEMO_USER_ID", ""))
        if (len(configured) < 32 or not configured.isascii() or owner.int == 0
                or any(c.isspace() for c in configured)):
            raise ValueError
    except ValueError:
        raise HTTPException(503, "Trip demo context is not configured.") from None
    if not secrets.compare_digest(token.encode("utf-8"), configured.encode("ascii")):
        raise unauthorized()
    return owner


def authenticate(token: str) -> UUID:
    mode = os.environ.get("TRIP_AUTH_MODE", "supabase")
    if mode == "demo":
        return demo_owner(token)
    if mode != "supabase":
        raise HTTPException(503, "Authentication is temporarily unavailable.")
    subject, email = verify_identity(token)
    return profile_owner(subject, email)
