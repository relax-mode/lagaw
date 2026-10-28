"""Post-deploy checks for staging or production. Never print credentials or response bodies.

Each environment has fixed API/Auth allowlists and a dedicated confirmed-email
test account. Sessions are acquired per run, never embedded in a Flutter build.

The script signs in, reads the API, and submits one blank extraction prompt that
is rejected (422) before calling the AI provider. Authentication can provision the
dedicated account's profile; the check never writes trips or interaction events.
"""

import json
import os
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
from uuid import UUID

ENVIRONMENTS = {
    "staging": ("https://staging.lagaw.pages.dev", {
        "lagaw-api-staging-i5kvldluga-as.a.run.app",
        "lagaw-api-staging-663710289405.asia-southeast1.run.app",
    }),
    "production": ("https://lagaw.pages.dev", {
        "lagaw-api-i5kvldluga-as.a.run.app",
        "lagaw-api-663710289405.asia-southeast1.run.app",
    }),
}
ORIGIN = ENVIRONMENTS["staging"][0]
AUTH_URLS = {
    "staging": "https://vnpkyvtbupnquvirzlzp.supabase.co",
    "production": "https://zjnuqqtbapbpudsjbpif.supabase.co",
}


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def urlopen(request, timeout=30):
    """Never forward a password or bearer token through a provider redirect."""
    return build_opener(NoRedirect).open(request, timeout=timeout)


def validate_api_url(base_url, environment):
    _origin, hosts = ENVIRONMENTS[environment]
    parsed = urlsplit(base_url)
    if (parsed.scheme != "https" or parsed.netloc not in hosts
            or parsed.path not in ("", "/") or parsed.query or parsed.fragment):
        raise ValueError(f"Refusing a URL outside the {environment} API allowlist.")


def sign_in(base_url, environment):
    """Use environment-scoped, synthetic account credentials without logging them."""
    validate_api_url(base_url, environment)
    email = os.environ.get("SMOKE_AUTH_EMAIL", "")
    password = os.environ.get("SMOKE_AUTH_PASSWORD", "")
    key = os.environ.get("SMOKE_SUPABASE_KEY", "")
    if not email or not password or not key:
        raise ValueError("Dedicated smoke Auth account configuration is missing.")
    request = Request(AUTH_URLS[environment] + "/auth/v1/token?grant_type=password",
                      data=json.dumps({"email": email, "password": password}).encode(),
                      headers={"apikey": key, "Content-Type": "application/json"})
    with urlopen(request, timeout=30) as response:
        if response.status != 200:
            raise ValueError("Smoke account sign-in failed.")
        result = json.load(response)
    if not isinstance(result, dict) or not isinstance(result.get("access_token"), str):
        raise TypeError("Smoke account did not return an access token.")
    return result["access_token"]


def verify(base_url, token, owner, environment="staging"):
    validate_api_url(base_url, environment)
    origin, _hosts = ENVIRONMENTS[environment]
    if len(token) < 32 or not token.isascii() or any(c.isspace() for c in token):
        raise ValueError(f"A valid {environment} access token is required.")
    if UUID(owner).int == 0:
        raise ValueError(f"A {environment} profile UUID is required.")

    def read(path, expected, authenticated=False, body=None):
        headers = {"Origin": origin, "Accept": "application/json"}
        if authenticated:
            headers["Authorization"] = "Bearer " + token
        data = None
        if body is not None:
            headers["Content-Type"] = "application/json"
            data = json.dumps(body).encode()
        request = Request(base_url.rstrip("/") + path, data=data, headers=headers)
        try:
            response = urlopen(request, timeout=30)
        except HTTPError as error:
            response = error
        with response:
            if response.status != expected:
                raise ValueError(f"{environment} {path}: expected HTTP {expected}, got {response.status}.")
            if response.headers.get("Access-Control-Allow-Origin") != origin:
                raise ValueError(f"{environment} {path}: missing CORS permission for its web origin.")
            return json.load(response)

    locations = read("/locations?limit=1", 200)
    if (not isinstance(locations, dict) or not isinstance(locations.get("items"), list)
            or not locations["items"]):
        raise ValueError(f"{environment} returned no locations.")
    read("/api/v1/trips?limit=1", 401)
    trips = read("/api/v1/trips?limit=1", 200, authenticated=True)
    if (not isinstance(trips, dict) or not isinstance(trips.get("items"), list)
            or any(not isinstance(item, dict) or item.get("user_id") != owner
                   for item in trips["items"])):
        raise ValueError(f"{environment} Trip response or profile ownership is invalid.")
    # A blank prompt fails request validation before the provider is called.
    read("/api/v1/preferences/extract", 422, authenticated=True, body={"prompt": ""})
    print(f"{environment}: locations, Trip authentication/ownership, extraction route, and CORS checks passed.")


if __name__ == "__main__":
    # Usage: python scripts/smoke_deployed.py staging|production
    # Env: SMOKE_API_URL, SMOKE_PROFILE_ID, SMOKE_AUTH_EMAIL,
    # SMOKE_AUTH_PASSWORD, SMOKE_SUPABASE_KEY. All scoped to one environment.
    environment = sys.argv[1] if len(sys.argv) == 2 else ""
    if environment not in ENVIRONMENTS:
        sys.exit("Usage: smoke_deployed.py staging|production")
    try:
        base_url = os.environ.get("SMOKE_API_URL", "")
        owner = os.environ.get("SMOKE_PROFILE_ID", "")
        if UUID(owner).int == 0:
            raise ValueError("A smoke profile UUID is required.")
        verify(base_url, sign_in(base_url, environment), owner, environment)
    except (ValueError, KeyError, TypeError, URLError, TimeoutError):
        sys.exit(f"{environment} smoke check failed; check the API URL, Auth account configuration, responses, and CORS.")
