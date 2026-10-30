"""Prepare and verify Resend SMTP for Supabase Auth emails (Lagaw #112/#113).

Subcommands report only names, booleans and a whitelisted set of Auth settings.
They never print secret values, the full Management API response, or response
bodies, not even on error.

  preflight --env staging|production   local checks only; no network
  inspect   --env ENV                  GET the Auth config and print the projection
  plan      --env ENV                  compare with the projection; show the PATCH body
  apply     --env ENV --execute --confirm ENV [--production-authorized-by TEXT]
                                       PATCH the Auth config, then verify it

Environment names: RESEND_API_KEY, SMTP_ADMIN_EMAIL, SMTP_SENDER_NAME (optional),
SUPABASE_PERSONAL_ACCESS_TOKEN, STAGING_SUPABASE_PROJECT_REF,
PRODUCTION_SUPABASE_PROJECT_REF (or --project-ref). Read them from the shell;
this script never opens .env.
"""

import argparse
import json
import os
import re
import sys
from urllib.error import HTTPError
from urllib.request import HTTPRedirectHandler, Request, build_opener

API_ROOT = "https://api.supabase.com"
SMTP_HOST = "smtp.resend.com"
SMTP_PORT = "465"  # Supabase types smtp_port as a string; 465 is Resend implicit TLS.
SMTP_USER = "resend"
DEFAULT_SENDER_NAME = "Lagaw"
DEFAULT_RATE_LIMIT = 30
REQUIRED_NAMES = ("RESEND_API_KEY", "SMTP_ADMIN_EMAIL", "SUPABASE_PERSONAL_ACCESS_TOKEN")
REF_ENV_NAMES = {
    "staging": "STAGING_SUPABASE_PROJECT_REF",
    "production": "PRODUCTION_SUPABASE_PROJECT_REF",
}
PROJECTION_KEYS = (
    "smtp_host", "smtp_port", "smtp_admin_email", "smtp_sender_name",
    "rate_limit_email_sent", "mailer_autoconfirm",
)
COMPARED_KEYS = ("smtp_host", "smtp_port", "smtp_admin_email", "smtp_sender_name", "rate_limit_email_sent")
TEST_ONLY_WARNING = "test-only sender: delivers only to the Resend account owner"
TEST_ONLY_DOMAINS = {
    "resend.dev", "gmail.com", "googlemail.com", "outlook.com", "hotmail.com",
    "live.com", "yahoo.com", "icloud.com", "proton.me", "protonmail.com",
}
PLACEHOLDER_DOMAINS = {"example.com", "example.org", "example.net"}
PLACEHOLDER_TLDS = {"invalid", "example", "test", "localhost"}
EMAIL_RE = re.compile(r"^[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+)$")
REF_RE = re.compile(r"^[a-z]{20}$")
RESEND_KEY_RE = re.compile(r"^re_[A-Za-z0-9_]+$")
PAT_RE = re.compile(r"^sbp_[A-Za-z0-9_]+$")
PASS, WARN, FAIL = "PASS", "WARN", "FAIL"


class ApiError(Exception):
    """A safe message only: never a response body or exception text."""


class _NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def default_opener(request, timeout=30):
    """Never forward the bearer token through a redirect."""
    return build_opener(_NoRedirect).open(request, timeout=timeout)


def sender_domain(email):
    match = EMAIL_RE.match(email or "")
    return match.group(1).lower() if match else None


def is_test_only_sender(email):
    domain = sender_domain(email)
    return domain is not None and domain in TEST_ONLY_DOMAINS


def preflight(environment, env, project_ref=None):
    """Return (status, name, message) tuples. Messages never contain values."""
    results = []

    def add(status, name, message):
        results.append((status, name, message))

    for name in REQUIRED_NAMES:
        add(PASS if env.get(name) else FAIL, name, "set" if env.get(name) else "missing")

    key = env.get("RESEND_API_KEY", "")
    if key:
        if not RESEND_KEY_RE.match(key) or not 20 <= len(key) <= 128:
            add(FAIL, "RESEND_API_KEY shape", "expected re_ prefix and 20 to 128 characters")
        elif re.search(r"x{6,}", key, re.IGNORECASE):
            add(FAIL, "RESEND_API_KEY shape", "looks like a placeholder")
        else:
            add(PASS, "RESEND_API_KEY shape", "re_ prefix and plausible length (value not shown)")

    email = env.get("SMTP_ADMIN_EMAIL", "")
    if email:
        domain = sender_domain(email)
        if domain is None:
            add(FAIL, "SMTP_ADMIN_EMAIL format", "not a valid email address")
        elif domain.rsplit(".", 1)[-1] in PLACEHOLDER_TLDS or domain in PLACEHOLDER_DOMAINS:
            add(FAIL, "SMTP_ADMIN_EMAIL domain", "placeholder domain; use a domain you will verify in Resend")
        elif domain in TEST_ONLY_DOMAINS:
            add(WARN, "SMTP_ADMIN_EMAIL domain", TEST_ONLY_WARNING)
        else:
            add(PASS, "SMTP_ADMIN_EMAIL domain", "valid address on a non-test domain (domain must still be verified in Resend)")

    token = env.get("SUPABASE_PERSONAL_ACCESS_TOKEN", "")
    if token:
        if PAT_RE.match(token):
            add(PASS, "SUPABASE_PERSONAL_ACCESS_TOKEN shape", "sbp_ prefix (value not shown)")
        else:
            add(FAIL, "SUPABASE_PERSONAL_ACCESS_TOKEN shape", "expected sbp_ prefix")

    sender = env.get("SMTP_SENDER_NAME", "")
    if sender:
        if any(ord(char) < 32 or ord(char) == 127 for char in sender) or len(sender) > 64:
            add(FAIL, "SMTP_SENDER_NAME", "control characters or longer than 64 characters")
        else:
            add(PASS, "SMTP_SENDER_NAME", "set")
    else:
        add(PASS, "SMTP_SENDER_NAME", f"unset; {DEFAULT_SENDER_NAME} will be used")

    ref_name = REF_ENV_NAMES[environment]
    ref = project_ref or env.get(ref_name, "")
    if not ref:
        add(FAIL, "project ref", f"{ref_name} or --project-ref is required")
    elif not REF_RE.match(ref):
        add(FAIL, "project ref", "expected 20 lowercase letters")
    else:
        add(PASS, "project ref", f"{environment} ref format ok")
        other = REF_ENV_NAMES["production" if environment == "staging" else "staging"]
        if env.get(other) and env.get(other) == ref:
            add(FAIL, "project refs", "staging and production refs must differ")
    return results


def print_results(results, out):
    for status, name, message in results:
        print(f"{status} {name}: {message}", file=out)


def has_failure(results):
    return any(status == FAIL for status, _name, _message in results)


def auth_url(ref):
    return f"{API_ROOT}/v1/projects/{ref}/config/auth"


def call_api(method, ref, token, opener, body=None, expect_json=True):
    """Return parsed JSON (or None). Errors carry only the status code or exception class."""
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode()
    request = Request(auth_url(ref), data=data, headers=headers, method=method)
    try:
        with opener(request, timeout=30) as response:
            status = response.status
            raw = response.read() if expect_json else b""
    except HTTPError as error:
        raise ApiError(f"Supabase Management API returned HTTP {error.code}") from None
    except Exception as error:  # noqa: BLE001 - report the exception class only, never its text.
        raise ApiError(f"request failed ({type(error).__name__})") from None
    if status != 200:
        raise ApiError(f"Supabase Management API returned HTTP {status}")
    if not expect_json:
        return None
    try:
        data = json.loads(raw)
    except ValueError:
        raise ApiError("response was not valid JSON") from None
    if not isinstance(data, dict):
        raise ApiError("unexpected response shape")
    return data


def _scalar(value):
    return value if value is None or isinstance(value, (str, int, float, bool)) else "<non-scalar>"


def project(config):
    """Explicit whitelist: unknown keys, and smtp_user/smtp_pass values, are never copied."""
    picked = {key: _scalar(config.get(key)) for key in PROJECTION_KEYS}
    picked["smtp_user_set"] = bool(config.get("smtp_user"))
    picked["smtp_pass_set"] = bool(config.get("smtp_pass"))
    return picked


def print_projection(current, out):
    for key in PROJECTION_KEYS:
        print(f"{key}: {current[key]}", file=out)
    print(f"smtp_user_set: {current['smtp_user_set']}", file=out)
    print(f"smtp_pass_set: {current['smtp_pass_set']}", file=out)


def desired_body(env, rate_limit=DEFAULT_RATE_LIMIT):
    """The PATCH body. mailer_autoconfirm is deliberately absent."""
    return {
        "smtp_host": SMTP_HOST,
        "smtp_port": SMTP_PORT,
        "smtp_user": SMTP_USER,
        "smtp_pass": env["RESEND_API_KEY"],
        "smtp_admin_email": env["SMTP_ADMIN_EMAIL"],
        "smtp_sender_name": env.get("SMTP_SENDER_NAME") or DEFAULT_SENDER_NAME,
        "rate_limit_email_sent": rate_limit,
    }


def differing_fields(desired, current):
    differing = [key for key in COMPARED_KEYS if str(current.get(key)) != str(desired[key])]
    if not current["smtp_user_set"]:
        differing.append("smtp_user")
    if not current["smtp_pass_set"]:
        differing.append("smtp_pass")
    return differing


def print_plan(desired, differing, out):
    if not differing:
        print("already configured", file=out)
        print("note: smtp_pass cannot be read back; only its presence is compared", file=out)
        return
    print("differs: " + ", ".join(differing), file=out)
    for key, value in desired.items():
        shown = "<redacted>" if key == "smtp_pass" else value
        print(f"  {key}: {shown}", file=out)


def _ref_and_token(args, env, out):
    """Return (ref, token) or None after printing a name-only error."""
    ref = args.project_ref or env.get(REF_ENV_NAMES[args.env], "")
    if not ref or not REF_RE.match(ref):
        print(f"FAIL project ref: {REF_ENV_NAMES[args.env]} or --project-ref must be a valid ref", file=out)
        return None
    token = env.get("SUPABASE_PERSONAL_ACCESS_TOKEN", "")
    if not token or not PAT_RE.match(token):
        print("FAIL SUPABASE_PERSONAL_ACCESS_TOKEN: missing or wrong shape", file=out)
        return None
    return ref, token


def cmd_preflight(args, env, opener, out, err):
    results = preflight(args.env, env, args.project_ref)
    print_results(results, out)
    return 1 if has_failure(results) else 0


def cmd_inspect(args, env, opener, out, err):
    target = _ref_and_token(args, env, out)
    if target is None:
        return 1
    current = project(call_api("GET", *target, opener))
    print_projection(current, out)
    return 0


def cmd_plan(args, env, opener, out, err):
    results = preflight(args.env, env, args.project_ref)
    print_results(results, out)
    if has_failure(results):
        return 1
    target = _ref_and_token(args, env, out)
    if target is None:
        return 1
    desired = desired_body(env, args.rate_limit)
    current = project(call_api("GET", *target, opener))
    print_plan(desired, differing_fields(desired, current), out)
    return 0


def cmd_apply(args, env, opener, out, err):
    if not args.execute:
        print("refusing: pass --execute to send the PATCH", file=out)
        return 2
    if args.confirm != args.env:
        print("refusing: --confirm must repeat the environment name", file=out)
        return 2
    if args.env == "production" and not (args.production_authorized_by or "").strip():
        print("refusing: production needs --production-authorized-by", file=out)
        return 2
    results = preflight(args.env, env, args.project_ref)
    print_results(results, out)
    if has_failure(results):
        return 1
    if is_test_only_sender(env.get("SMTP_ADMIN_EMAIL", "")) and not args.allow_test_sender:
        print("refusing: test-only sender; use --allow-test-sender only for a Resend test send", file=out)
        return 2
    target = _ref_and_token(args, env, out)
    if target is None:
        return 1
    desired = desired_body(env, args.rate_limit)
    current = project(call_api("GET", *target, opener))
    differing = differing_fields(desired, current)
    if not differing:
        print("already configured; no PATCH sent", file=out)
        return 0
    call_api("PATCH", *target, opener, body=desired, expect_json=False)
    print("PATCH accepted; verifying", file=out)
    after = project(call_api("GET", *target, opener))
    remaining = differing_fields(desired, after)
    if remaining:
        print("FAIL verification: still differs: " + ", ".join(remaining), file=out)
        return 1
    print("verified", file=out)
    print_projection(after, out)
    return 0


def positive_int(text):
    value = int(text)
    if value < 1:
        raise argparse.ArgumentTypeError("must be at least 1")
    return value


def build_parser():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for name in ("preflight", "inspect", "plan", "apply"):
        sub = subparsers.add_parser(name)
        sub.add_argument("--env", required=True, choices=sorted(REF_ENV_NAMES))
        sub.add_argument("--project-ref", default="")
        if name in ("plan", "apply"):
            sub.add_argument("--rate-limit", type=positive_int, default=DEFAULT_RATE_LIMIT)
        if name == "apply":
            sub.add_argument("--execute", action="store_true")
            sub.add_argument("--confirm", default="")
            sub.add_argument("--production-authorized-by", default="")
            sub.add_argument("--allow-test-sender", action="store_true")
    return parser


COMMANDS = {
    "preflight": cmd_preflight,
    "inspect": cmd_inspect,
    "plan": cmd_plan,
    "apply": cmd_apply,
}


def main(argv=None, env=None, opener=None, out=None, err=None):
    args = build_parser().parse_args(argv)
    env = os.environ if env is None else env
    opener = default_opener if opener is None else opener
    out = sys.stdout if out is None else out
    err = sys.stderr if err is None else err
    try:
        return COMMANDS[args.command](args, env, opener, out, err)
    except ApiError as error:
        print(f"FAIL {args.command}: {error}", file=err)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
