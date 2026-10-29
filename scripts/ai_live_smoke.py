"""Scheduled live AI check: one real preference extraction through deployed staging.

Signs in as the environment's dedicated confirmed-email smoke account, then
exercises the deployed backend, its Secret Manager DeepSeek key and the provider
end to end, without any provider key in GitHub. Spends one extraction call per
run. Never prints credentials or response bodies.
"""

import json
import os
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request

from smoke_deployed import sign_in, urlopen

ORIGIN = "https://staging.lagaw.pages.dev"
HOSTS = {
    "lagaw-api-staging-i5kvldluga-as.a.run.app",
    "lagaw-api-staging-663710289405.asia-southeast1.run.app",
}
PROMPT = "A cheap, relaxing afternoon in Bacolod with coffee and photography spots."
PREFERENCE_FIELDS = {
    "preferred_tags", "budget_level", "budget_min", "budget_max",
    "budget_scope", "group_type", "duration", "pace",
}


def verify(base_url, token):
    parsed = urlsplit(base_url)
    if (parsed.scheme != "https" or parsed.netloc not in HOSTS
            or parsed.path not in ("", "/") or parsed.query or parsed.fragment):
        raise ValueError("Refusing a URL outside the staging API allowlist.")
    if len(token) < 32 or not token.isascii() or any(c.isspace() for c in token):
        raise ValueError("A valid staging access token is required.")

    request = Request(
        base_url.rstrip("/") + "/api/v1/preferences/extract",
        data=json.dumps({"prompt": PROMPT}).encode(),
        headers={"Origin": ORIGIN, "Accept": "application/json",
                 "Content-Type": "application/json", "Authorization": "Bearer " + token},
    )
    try:
        response = urlopen(request, timeout=45)
    except HTTPError as error:
        response = error
    with response:
        status = response.status
        try:
            body = json.load(response)
        except ValueError:
            body = None
    if status != 200:
        detail = body.get("detail") if isinstance(body, dict) else None
        code = detail.get("code") if isinstance(detail, dict) else "unknown"
        raise ValueError(f"Live extraction returned HTTP {status} ({code}).")
    preferences = body.get("preferences") if isinstance(body, dict) else None
    if (body.get("schema_version") != "1" or body.get("requires_confirmation") is not True
            or not isinstance(preferences, dict) or set(preferences) != PREFERENCE_FIELDS
            or not isinstance(preferences["preferred_tags"], list) or not preferences["preferred_tags"]):
        raise ValueError("Live extraction returned an unexpected shape.")
    return len(preferences["preferred_tags"])


def run(base_url):
    """Sign in first: staging rejects the retired demo token."""
    return verify(base_url, sign_in(base_url, "staging"))


if __name__ == "__main__":
    # Env: STAGING_API_URL, SMOKE_AUTH_EMAIL, SMOKE_AUTH_PASSWORD,
    # SMOKE_SUPABASE_KEY. The signed-in session is the only credential sent to
    # the API, because staging accepts only Supabase sessions.
    try:
        tags = run(os.environ.get("STAGING_API_URL", ""))
    except (ValueError, KeyError, TypeError, URLError, TimeoutError) as error:
        sys.exit(f"Live AI check failed: {error}")
    print(f"Live extraction passed: schema-valid draft with {tags} preferred tag(s).")
