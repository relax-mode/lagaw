"""Post-deploy checks for staging or production. Never print credentials or response bodies.

Each environment has a fixed API host allowlist and browser origin, so a demo
token can only be sent to the API of its own environment.

All requests are reads, except one extraction request with a blank prompt that
the API rejects (422) before calling the AI provider, so the check never writes
data or spends provider quota.
"""

import json
import os
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen
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


def verify(base_url, token, owner, environment="staging"):
    origin, hosts = ENVIRONMENTS[environment]
    parsed = urlsplit(base_url)
    if (parsed.scheme != "https" or parsed.netloc not in hosts
            or parsed.path not in ("", "/") or parsed.query or parsed.fragment):
        raise ValueError(f"Refusing a URL outside the {environment} API allowlist.")
    if len(token) < 32 or not token.isascii() or any(c.isspace() for c in token):
        raise ValueError(f"A valid {environment} demo token is required.")
    if UUID(owner).int == 0:
        raise ValueError(f"A {environment} demo user UUID is required.")

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
        raise ValueError(f"{environment} Trip response or demo ownership is invalid.")
    # A blank prompt fails request validation before the provider is called.
    read("/api/v1/preferences/extract", 422, authenticated=True, body={"prompt": ""})
    print(f"{environment}: locations, Trip authentication/ownership, extraction route, and CORS checks passed.")


if __name__ == "__main__":
    # Usage: python scripts/smoke_deployed.py staging|production
    # Env: SMOKE_API_URL, SMOKE_TRIP_DEMO_TOKEN, SMOKE_TRIP_DEMO_USER_ID
    environment = sys.argv[1] if len(sys.argv) == 2 else ""
    if environment not in ENVIRONMENTS:
        sys.exit("Usage: smoke_deployed.py staging|production")
    try:
        verify(
            os.environ.get("SMOKE_API_URL", ""),
            os.environ.get("SMOKE_TRIP_DEMO_TOKEN", ""),
            os.environ.get("SMOKE_TRIP_DEMO_USER_ID", ""),
            environment,
        )
    except (ValueError, KeyError, TypeError, URLError, TimeoutError):
        sys.exit(f"{environment} smoke check failed; check the API URL, demo configuration, responses, and CORS.")
