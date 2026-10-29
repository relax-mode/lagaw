"""Reversible demo seeding for the trained collaborative model (#94).

Creates five clearly named, confirmed Supabase Auth accounts per Supabase project
and writes their swipes/saves through the deployed (or local) API with each
account's own access token, so the real owner-scoped path is used. Interactions
are shaped so one demo user and several places clear every training and
inference gate, while other places stay under-supported on purpose.

Private output goes to --private-dir, which must exist OUTSIDE this repository
(0600 files, never overwritten): credentials, an exact profile/event/trip manifest,
the profile allowlist for train_collaborative_model.py, and cleanup SQL. Only
counts are printed. Credentials come from the shell, never from arguments:
SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (account creation) and SUPABASE_ANON_KEY
(sign-in). Subcommands: seed, cleanup-sql, recommend.
"""

import argparse
import importlib.util
import json
import os
import secrets
import sys
from pathlib import Path
from uuid import UUID

import httpx

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("smoke_deployed", ROOT / "scripts" / "smoke_deployed.py")
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)

REFS = {"staging": "vnpkyvtbupnquvirzlzp", "production": "zjnuqqtbapbpudsjbpif"}
LOCAL_APIS = {"http://127.0.0.1:8000", "http://localhost:8000"}
LETTERS = "ABCDE"
CATALOG_SIZE = 12
GROUP = "friends"
EMAIL = "lagaw-demo-{environment}-{letter}@example.invalid"
# (catalog index, interaction type, rating). A: target with deep history. E: too little
# history (insufficient_history). Items 7-9 have one supporter each (sparse_location);
# items 10-11 are never interacted with (unseen_location). Item 3 is left-swiped.
PLAN = {
    "A": [(0, "right_swipe"), (0, "save"), (1, "right_swipe"), (2, "right_swipe"),
          (3, "left_swipe"), (8, "right_swipe")],
    "B": [(0, "right_swipe"), (1, "save"), (3, "left_swipe"), (4, "right_swipe"), (5, "right_swipe")],
    "C": [(0, "right_swipe"), (2, "right_swipe"), (4, "save"), (5, "right_swipe"), (6, "left_swipe")],
    "D": [(1, "right_swipe"), (2, "right_swipe"), (4, "right_swipe"), (6, "left_swipe"), (7, "right_swipe")],
    "E": [(0, "right_swipe"), (9, "right_swipe")],
}
TRIP_LETTERS = ("A", "E")


class SeedFailed(ValueError):
    """Only authored, credential-free messages may be displayed."""


def require(condition, message):
    if not condition:
        raise SeedFailed(message)


def private_path(directory: Path, environment: str, name: str) -> Path:
    resolved = directory.resolve()
    require(resolved.is_dir() and not resolved.is_relative_to(ROOT),
            "--private-dir must be an existing directory outside the repository.")
    return resolved / f"{environment}-{name}"


def write_private(path: Path, text: str, *, replace: bool = False) -> None:
    flags = os.O_WRONLY | os.O_CREAT | (os.O_TRUNC if replace else os.O_EXCL)
    try:
        descriptor = os.open(path, flags, 0o600)
    except FileExistsError:
        raise SeedFailed("A private seed file already exists; clean up the earlier seed first.") from None
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        handle.write(text)


def supabase_settings(environment: str) -> tuple[str, str, str]:
    url = os.environ.get("SUPABASE_URL", "").strip().rstrip("/")
    service, anon = (os.environ.get(name, "").strip() for name in ("SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_ANON_KEY"))
    require(url == f"https://{REFS[environment]}.supabase.co", f"The configured Supabase project is not {environment}; refusing.")
    return url, service, anon


def validate_api(environment: str, api_url: str) -> None:
    if environment == "staging" and api_url in LOCAL_APIS:
        return  # Local API against the shared development/staging project.
    smoke.validate_api_url(api_url, environment)


def sign_in(url: str, anon: str, email: str, password: str) -> str:
    require(anon, "SUPABASE_ANON_KEY is not set in the environment.")
    response = httpx.post(f"{url}/auth/v1/token", params={"grant_type": "password"}, headers={"apikey": anon},
                          json={"email": email, "password": password}, timeout=20, follow_redirects=False)
    require(response.status_code == 200, "A demo account could not sign in.")
    return response.json()["access_token"]


def create_account(url: str, service: str, email: str, password: str) -> str:
    headers = {"apikey": service}
    if not service.startswith("sb_secret_"):
        headers["Authorization"] = f"Bearer {service}"
    response = httpx.post(f"{url}/auth/v1/admin/users", headers=headers, timeout=20, follow_redirects=False, json={
        "email": email, "password": password, "email_confirm": True,
        "user_metadata": {"purpose": "lagaw-demo-seed"},
    })
    require(response.status_code in (200, 201), "A demo Auth account could not be created (it may already exist).")
    return str(UUID(response.json()["id"]))


def pick_catalog(api: httpx.Client) -> list[str]:
    rows, offset = [], 0
    while True:
        page = api.get("/locations", params={"limit": 100, "offset": offset})
        require(page.status_code == 200, "Could not read the location catalog.")
        items = page.json()["items"]
        rows.extend(items)
        offset += len(items)
        if len(items) < 100:
            break
    eligible = sorted(row["id"] for row in rows
                      if GROUP in row["suitable_group_types"] and row["estimated_cost_max"] is not None)
    require(len(eligible) >= CATALOG_SIZE, "The catalog has too few friends-compatible, priced locations.")
    return eligible[:CATALOG_SIZE]


def seed(environment: str, api_url: str, private_dir: Path) -> None:
    validate_api(environment, api_url)
    url, service, anon = supabase_settings(environment)
    require(service and anon, "SUPABASE_SERVICE_ROLE_KEY and SUPABASE_ANON_KEY must be set.")
    paths = {name: private_path(private_dir, environment, name)
             for name in ("credentials.json", "manifest.json", "profiles.txt", "cleanup.sql")}
    manifest = {"environment": environment, "supabase_ref": REFS[environment], "accounts": {}}
    credentials = {}
    # Claim every private file first, then persist after each write: a mid-run failure
    # still leaves an exact record for cleanup.
    for name in ("credentials.json", "manifest.json"):
        write_private(paths[name], "{}")

    def persist():
        write_private(paths["manifest.json"], json.dumps(manifest, indent=2) + "\n", replace=True)
        write_private(paths["credentials.json"], json.dumps(credentials, indent=2) + "\n", replace=True)

    try:
        with httpx.Client(base_url=api_url, timeout=30, follow_redirects=False) as api:
            catalog = pick_catalog(api)
            manifest["catalog_location_ids"] = catalog
            for letter in LETTERS:
                email, password = EMAIL.format(environment=environment, letter=letter.lower()), secrets.token_urlsafe(24)
                credentials[letter] = {"email": email, "password": password}
                manifest["accounts"][letter] = {"email": email, "events": [], "trip_id": None}
                persist()
                manifest["accounts"][letter]["auth_user_id"] = create_account(url, service, email, password)
                persist()
                headers = {"Authorization": f"Bearer {sign_in(url, anon, email, password)}"}
                for index, kind in PLAN[letter]:
                    response = api.post("/api/v1/interactions", headers=headers,
                                        json={"location_id": catalog[index], "interaction_type": kind})
                    require(response.status_code == 201, "An interaction could not be written through the API.")
                    event = response.json()
                    manifest["accounts"][letter]["profile_id"] = event["user_id"]
                    manifest["accounts"][letter]["events"].append(event["id"])
                    persist()
                if letter in TRIP_LETTERS:
                    response = api.post("/api/v1/trips", headers=headers, json={
                        "title": f"Lagaw demo serving trip {letter}", "start_date": "2026-11-01",
                        "end_date": "2026-11-02", "budget_min": "0", "budget_max": "5000",
                        "group_type": GROUP, "preferred_tags": ["cafe", "relaxing"],
                    })
                    require(response.status_code == 201, "A demo trip could not be created.")
                    manifest["accounts"][letter]["trip_id"] = response.json()["id"]
                    persist()
    finally:
        accounts = manifest["accounts"].values()
        profiles = [a["profile_id"] for a in accounts if a.get("profile_id")]
        if profiles:
            write_private(paths["profiles.txt"], "# Allowlisted demo profile UUIDs (private).\n" + "\n".join(profiles) + "\n")
        write_private(paths["cleanup.sql"], cleanup_sql(manifest, commit=False))
    accounts = list(manifest["accounts"].values())
    print(f"Environment: {environment}; demo accounts created: {len(accounts)}")
    print(f"Interactions written: {sum(len(a['events']) for a in accounts)}; trips created: "
          f"{sum(bool(a['trip_id']) for a in accounts)}; catalog locations used: {len(catalog)}")
    print("Private files written (not printed): credentials, manifest, profile allowlist, cleanup SQL.")


def uuid_list(values) -> str:
    values = sorted(str(UUID(value)) for value in values if value)
    return ", ".join(f"'{value}'" for value in values) or "null"


def cleanup_sql(manifest: dict, *, commit: bool) -> str:
    accounts = list(manifest["accounts"].values())
    events = uuid_list(e for a in accounts for e in a["events"])
    trips = uuid_list(a.get("trip_id") for a in accounts)
    profiles = uuid_list(a.get("profile_id") for a in accounts)
    auths = uuid_list(a.get("auth_user_id") for a in accounts)
    emails = ", ".join("'" + a["email"].replace("'", "''") + "'" for a in accounts) or "null"
    return f"""-- Exact-ID cleanup of the Lagaw demo seed in Supabase project {manifest['supabase_ref']}.
-- Run as the postgres role. It rolls back unless generated with --commit.
-- Profile deletion cascades only to rows owned by these demo profiles.
begin;
select 'events_before' as check, count(*) from public.user_location_interactions where id in ({events});
select 'events_beyond_manifest' as check, count(*) from public.user_location_interactions
    where user_id in ({profiles}) and id not in ({events});
delete from public.user_location_interactions where id in ({events}) and user_id in ({profiles});
delete from public.trips where id in ({trips}) and user_id in ({profiles});
delete from public.users where id in ({profiles}) and auth_user_id in ({auths});
delete from auth.users where id in ({auths}) and email in ({emails});
select 'interactions_left' as check, count(*) from public.user_location_interactions where user_id in ({profiles});
select 'profiles_left' as check, count(*) from public.users where id in ({profiles});
select 'auth_users_left' as check, count(*) from auth.users where id in ({auths});
{'commit' if commit else 'rollback'};
"""


def recommend(environment: str, api_url: str, private_dir: Path, letter: str, output: Path | None) -> None:
    validate_api(environment, api_url)
    url, _service, anon = supabase_settings(environment)
    manifest = json.loads(private_path(private_dir, environment, "manifest.json").read_text())
    credentials = json.loads(private_path(private_dir, environment, "credentials.json").read_text())
    trip = manifest["accounts"][letter]["trip_id"]
    require(trip, "That demo account has no trip.")
    token = sign_in(url, anon, credentials[letter]["email"], credentials[letter]["password"])
    with httpx.Client(base_url=api_url, timeout=60, follow_redirects=False) as api:
        response = api.post(f"/api/v1/trips/{trip}/recommendations", headers={"Authorization": f"Bearer {token}"},
                            json={"party_size": 1, "planned_visits": 1, "limit": 12})
    require(response.status_code == 200, f"Recommendations returned HTTP {response.status_code}.")
    result = response.json()
    result["trip_id"] = "<redacted>"  # Trip IDs are private; catalog location IDs are public.
    reasons = [row["recommendation_reason"].split(";")[0] for row in result["items"]]
    modes = {"hybrid": sum(r.startswith("Hybrid:") for r in reasons)}
    for row in reasons:
        if row.startswith("Content fallback"):
            modes[row.split("(")[1].split(")")[0]] = modes.get(row.split("(")[1].split(")")[0], 0) + 1
    print(f"Account {letter}: HTTP 200; items: {len(result['items'])}; reason modes: {json.dumps(modes, sort_keys=True)}")
    if output is not None:
        resolved = output.resolve()
        require(resolved.suffix == ".json", "Write evidence to a .json file.")
        resolved.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print("Redacted response written.")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("seed", "cleanup-sql", "recommend"):
        command = commands.add_parser(name)
        command.add_argument("--environment", required=True, choices=sorted(REFS))
        command.add_argument("--private-dir", required=True, type=Path)
        if name != "cleanup-sql":
            command.add_argument("--api-url", required=True)
        if name == "cleanup-sql":
            command.add_argument("--commit", action="store_true", help="End with COMMIT instead of ROLLBACK.")
        if name == "recommend":
            command.add_argument("--account", required=True, choices=list(TRIP_LETTERS))
            command.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    try:
        if args.command == "seed":
            seed(args.environment, args.api_url.rstrip("/"), args.private_dir)
        elif args.command == "cleanup-sql":
            manifest = json.loads(private_path(args.private_dir, args.environment, "manifest.json").read_text())
            sys.stdout.write(cleanup_sql(manifest, commit=args.commit))
        else:
            recommend(args.environment, args.api_url.rstrip("/"), args.private_dir, args.account, args.output)
        return 0
    except SeedFailed as error:
        print(f"FAIL: {error}", file=sys.stderr)
    except (httpx.HTTPError, KeyError, ValueError, OSError) as error:
        print(f"FAIL: Seeding step failed ({type(error).__name__}); details omitted.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
