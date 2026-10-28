"""Interactive #79 acceptance against development only; never prints credentials.

Run from the repository root with --api-url http://127.0.0.1:8000 or the staging
Cloud Run URL. Two dedicated, confirmed-email/password test accounts are required.
The app creates/retains their profiles; this verifier removes its exact trip
fixtures and checks existing owner-visible trips are unchanged.
"""

import argparse
import getpass
from copy import deepcopy
from pathlib import Path
from uuid import UUID, uuid4

import httpx
from dotenv import load_dotenv

from app.auth import DEVELOPMENT_URL, auth_configuration

API_URLS = {
    "http://127.0.0.1:8000", "http://localhost:8000",
    "https://lagaw-api-staging-i5kvldluga-as.a.run.app",
    "https://lagaw-api-staging-663710289405.asia-southeast1.run.app",
}


class VerificationFailed(ValueError):
    """Only authored, credential-free messages may be displayed."""


def validate_target(api_url, supabase_url):
    if api_url not in API_URLS or supabase_url != DEVELOPMENT_URL:
        raise VerificationFailed("Verification requires the development project and a local/staging API.")


def require(condition, message):
    if not condition:
        raise VerificationFailed(message)


def history(client, token):
    rows = []
    for offset in range(0, 10001, 100):
        response = client.get("/api/v1/trips", headers={"Authorization": f"Bearer {token}"},
                              params={"limit": 100, "offset": offset})
        require(response.status_code == 200, "Could not read authenticated trips.")
        page = response.json()["items"]
        rows.extend(page)
        if len(page) < 100:
            return rows
    raise VerificationFailed("Too much existing data for a safe verification snapshot.")


def verify(api_url, url, key):
    validate_target(api_url, url)
    sessions = []
    with httpx.Client(timeout=20, follow_redirects=False) as auth:
        for label in ("A", "B"):
            email = getpass.getpass(f"Development test account {label} email (hidden): ")
            password = getpass.getpass(f"Development test account {label} password (hidden): ")
            response = auth.post(f"{url}/auth/v1/token", params={"grant_type": "password"},
                                 headers={"apikey": key}, json={"email": email, "password": password})
            require(response.status_code == 200, "Test account sign-in failed; check confirmation/settings.")
            session = response.json()
            require(session["user"].get("email_confirmed_at"), "Confirm both test account emails first.")
            sessions.append((session["access_token"], UUID(session["user"]["id"])))
    require(sessions[0][1] != sessions[1][1], "Two distinct development accounts are required.")
    tokens = [session[0] for session in sessions]
    fixtures = []
    with httpx.Client(base_url=api_url, timeout=20, follow_redirects=False) as api:
        for authorization in ("", "Bearer invalid-test-token"):
            require(api.get("/api/v1/trips", headers={"Authorization": authorization}).status_code == 401,
                    "Missing/invalid tokens must return 401.")
        print("PASS: Missing and invalid tokens rejected.")
        baseline = [deepcopy(history(api, token)) for token in tokens]
        try:
            for token in tokens:
                response = api.post("/api/v1/trips", headers={"Authorization": f"Bearer {token}"}, json={
                    "title": f"Issue79 verification {uuid4()}", "start_date": "2026-11-01",
                    "end_date": "2026-11-01", "budget_min": "0", "budget_max": "500",
                    "preferred_tags": [],
                })
                require(response.status_code == 201, "Could not create verification trip.")
                trip = response.json()
                fixtures.append((token, str(UUID(trip["id"]))))
                profile_id = str(UUID(trip["user_id"]))
                print(f"INFO: Test account {'AB'[len(fixtures) - 1]} profile UUID: {profile_id}")
                require(trip["user_id"] not in (str(sessions[0][1]), str(sessions[1][1])),
                        "Expected explicit profile mapping, not an Auth UUID owner.")
            for index, (owner_token, trip_id) in enumerate(fixtures):
                other = tokens[1 - index]
                path = f"/api/v1/trips/{trip_id}"
                for method in ("GET", "PATCH", "DELETE"):
                    kwargs = {"json": {"title": "must not be applied"}} if method == "PATCH" else {}
                    result = api.request(method, path, headers={"Authorization": f"Bearer {other}"}, **kwargs)
                    require(result.status_code == 404, "Cross-user trip access was not rejected.")
                require(api.get(path + "/items", headers={"Authorization": f"Bearer {other}"}).status_code == 404,
                        "Cross-user itinerary access was not rejected.")
                require(api.patch(path, headers={"Authorization": f"Bearer {owner_token}"},
                                  json={"title": "Issue79 verified owner update"}).status_code == 200,
                        "The verified owner could not update their trip.")
            print("PASS: Two verified owners can create/update trips; cross-user reads/writes/items return 404.")
        finally:
            errors = []
            for token, trip_id in fixtures:
                try:
                    result = api.delete(f"/api/v1/trips/{trip_id}", headers={"Authorization": f"Bearer {token}"})
                    if result.status_code != 204:
                        errors.append("Exact verification trip cleanup failed.")
                except httpx.HTTPError:
                    errors.append("Exact verification trip cleanup could not complete.")
            for token, original in zip(tokens, baseline, strict=True):
                try:
                    if history(api, token) != original:
                        errors.append("Existing trips changed or a verification fixture remains.")
                except (httpx.HTTPError, ValueError):
                    errors.append("Existing-trip preservation could not be verified.")
            require(not errors, "Verification cleanup/preservation failed.")
        print("PASS: Exact temporary trips removed; both accounts' existing trips preserved.")
        print("PASS: Development Auth verified. Test profiles retained; production was not contacted.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api-url", required=True)
    args = parser.parse_args(argv)
    try:
        load_dotenv(Path(__file__).resolve().parents[1] / ".env", override=False)
        url, key = auth_configuration()
        verify(args.api_url, url, key)
        return 0
    except VerificationFailed as error:
        print(f"FAIL: {error}")
        return 1
    except Exception:  # noqa: BLE001 - Do not expose tokens, account details or provider tracebacks.
        print("FAIL: Development Auth verification failed; credentials and provider details omitted.")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
