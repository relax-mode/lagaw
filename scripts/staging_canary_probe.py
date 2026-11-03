"""Read-only release candidate probe for Lagaw staging Cloud Run.

No tokens, credentials, writes, or paid-provider calls. The hostname allowlist
prevents accidentally probing the production API.
"""

from __future__ import annotations

import argparse
import json
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

STAGING_HOSTS = {
    "lagaw-api-staging-i5kvldluga-as.a.run.app",
    "lagaw-api-staging-663710289405.asia-southeast1.run.app",
}
TAG = "s4-qa"
ALLOWED_HOSTS = STAGING_HOSTS | {f"{TAG}---{host}" for host in STAGING_HOSTS}


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def validate_staging_url(value: str) -> str:
    target = urlsplit(value.strip())
    if (
        target.scheme != "https"
        or target.netloc not in ALLOWED_HOSTS
        or target.path not in ("", "/")
        or target.query
        or target.fragment
        or target.username
        or target.password
    ):
        raise ValueError(
            "Use only the Lagaw staging API or its s4-qa tagged Cloud Run URL."
        )
    return f"https://{target.netloc}"


def get_json(url: str) -> dict:
    request = Request(url, headers={"Accept": "application/json"})
    with build_opener(NoRedirect).open(request, timeout=10) as response:
        if response.status != 200:
            raise ValueError(f"Unexpected HTTP {response.status}")
        if "application/json" not in response.headers.get("Content-Type", ""):
            raise ValueError("Expected an application/json response")
        body = json.load(response)
        if not isinstance(body, dict):
            raise TypeError("Expected a JSON object")
        return body


def probe(base_url: str) -> None:
    base = validate_staging_url(base_url)

    for path, expected in (
        ("/health", "ok"),
        ("/ready", "ready"),
    ):
        result = get_json(base + path)
        if result.get("status") != expected:
            raise ValueError(f"{path}: unexpected status")
        print(f"PASS: GET {path} -> 200 ({expected})")

    schema = get_json(base + "/openapi.json")
    paths = schema.get("paths")
    if not isinstance(paths, dict):
        raise TypeError("OpenAPI paths missing")
    required = (
        ("/health", "get"),
        ("/ready", "get"),
        ("/api/v1/preferences/extract", "post"),
    )
    for path, method in required:
        operations = paths.get(path)
        if not isinstance(operations, dict) or method not in operations:
            raise ValueError(f"OpenAPI missing {method.upper()} {path}")
    print("PASS: OpenAPI includes liveness, readiness, and extraction")
    print("PASS: Staging read-only probes complete; no provider requests made")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True, help="Staging or s4-qa tag URL")
    args = parser.parse_args()
    try:
        probe(args.url)
    except (HTTPError, URLError, TimeoutError, TypeError, ValueError, OSError) as exc:
        if isinstance(exc, HTTPError):
            message = f"HTTP {exc.code}"
        elif isinstance(exc, URLError):
            message = "Network request failed"
        else:
            message = str(exc)
        print(f"FAIL: Staging probe: {message}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
