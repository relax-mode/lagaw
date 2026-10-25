"""Read-only deployed staging checks. Never print credentials or response bodies."""

import json
import os
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen
from uuid import UUID

ORIGIN = "https://staging.lagaw.pages.dev"
HOSTS = {
    "lagaw-api-staging-i5kvldluga-as.a.run.app",
    "lagaw-api-staging-663710289405.asia-southeast1.run.app",
}


def verify(base_url, token, owner):
    parsed = urlsplit(base_url)
    if (parsed.scheme != "https" or parsed.netloc not in HOSTS
            or parsed.path not in ("", "/") or parsed.query or parsed.fragment):
        raise ValueError("Refusing a URL outside the staging API allowlist.")
    if len(token) < 32 or not token.isascii() or any(c.isspace() for c in token):
        raise ValueError("A valid staging demo token is required.")
    if UUID(owner).int == 0:
        raise ValueError("A staging demo user UUID is required.")

    def read(path, expected, authenticated=False):
        headers = {"Origin": ORIGIN, "Accept": "application/json"}
        if authenticated:
            headers["Authorization"] = "Bearer " + token
        request = Request(base_url.rstrip("/") + path, headers=headers)
        try:
            response = urlopen(request, timeout=30)
        except HTTPError as error:
            response = error
        with response:
            if response.status != expected:
                raise ValueError(f"Staging {path}: expected HTTP {expected}, got {response.status}.")
            if response.headers.get("Access-Control-Allow-Origin") != ORIGIN:
                raise ValueError(f"Staging {path}: missing staging CORS permission.")
            return json.load(response)

    locations = read("/locations?limit=1", 200)
    if (not isinstance(locations, dict) or not isinstance(locations.get("items"), list)
            or not locations["items"]):
        raise ValueError("Staging returned no locations.")
    read("/api/v1/trips?limit=1", 401)
    trips = read("/api/v1/trips?limit=1", 200, authenticated=True)
    if (not isinstance(trips, dict) or not isinstance(trips.get("items"), list)
            or any(not isinstance(item, dict) or item.get("user_id") != owner
                   for item in trips["items"])):
        raise ValueError("Staging Trip response or demo ownership is invalid.")
    print("Staging locations, Trip authentication/ownership, and CORS checks passed.")


if __name__ == "__main__":
    try:
        verify(
            os.environ.get("STAGING_API_URL", ""),
            os.environ.get("STAGING_TRIP_DEMO_TOKEN", ""),
            os.environ.get("STAGING_TRIP_DEMO_USER_ID", ""),
        )
    except (ValueError, KeyError, TypeError, URLError, TimeoutError):
        sys.exit("Staging smoke check failed; check the API URL, demo configuration, responses, and CORS.")
