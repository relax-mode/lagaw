"""The email config checker must stay local-first, redact everything, and guard apply.

All HTTP goes through a fake opener; no test reaches the network or sends mail.
Dummy values below are deliberately not key-shaped.
"""

import importlib.util
import io
import json
import unittest
from pathlib import Path
from urllib.error import HTTPError, URLError

spec = importlib.util.spec_from_file_location(
    "check_email_config", Path(__file__).resolve().parents[1] / "scripts" / "check_email_config.py",
)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)

DUMMY_KEY = "re_dummy_test_key_only"
DUMMY_PAT = "sbp_dummy_test_token_only"
DUMMY_SERVICE = "dummy-service-role-value-never-print"
DUMMY_ADMIN = "auth@verified-domain.org"
STAGING_REF = "abcdefghijklmnopqrst"
PRODUCTION_REF = "tsrqponmlkjihgfedcba"
SECRETS = (DUMMY_KEY, DUMMY_PAT, DUMMY_SERVICE)

GOOD_ENV = {
    "RESEND_API_KEY": DUMMY_KEY,
    "SMTP_ADMIN_EMAIL": DUMMY_ADMIN,
    "SUPABASE_PERSONAL_ACCESS_TOKEN": DUMMY_PAT,
    "STAGING_SUPABASE_PROJECT_REF": STAGING_REF,
    "PRODUCTION_SUPABASE_PROJECT_REF": PRODUCTION_REF,
}
MATCHING_CONFIG = {
    "smtp_host": "smtp.resend.com",
    "smtp_port": "465",
    "smtp_user": "resend",
    "smtp_pass": DUMMY_KEY,
    "smtp_admin_email": DUMMY_ADMIN,
    "smtp_sender_name": "Lagaw",
    "rate_limit_email_sent": 30,
    "mailer_autoconfirm": False,
}


class FakeResponse:
    def __init__(self, status=200, body=b""):
        self.status = status
        self._body = body

    def read(self):
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


def ok_json(data):
    return FakeResponse(200, json.dumps(data).encode())


class FakeOpener:
    """Returns queued responses in order and records every request it receives."""

    def __init__(self, *responses):
        self.responses = list(responses)
        self.requests = []

    def __call__(self, request, timeout=30):
        self.requests.append(request)
        if not self.responses:
            raise AssertionError("unexpected network request")
        item = self.responses.pop(0)
        if isinstance(item, BaseException):
            raise item
        return item


def http_error(code, body):
    return HTTPError("https://api.supabase.com/v1/projects/x/config/auth", code, "err",
                     {}, io.BytesIO(body))


class CheckEmailConfigTests(unittest.TestCase):
    def run_cli(self, argv, env=None, opener=None):
        out, err = io.StringIO(), io.StringIO()
        opener = FakeOpener() if opener is None else opener
        code = checker.main(argv, env=GOOD_ENV if env is None else env, opener=opener, out=out, err=err)
        return code, out.getvalue(), err.getvalue(), opener

    def assertNoSecrets(self, *texts):
        for text in texts:
            for secret in SECRETS:
                self.assertNotIn(secret, text)

    def preflight_env(self, environment="staging", **changes):
        env = dict(GOOD_ENV)
        for key, value in changes.items():
            if value is None:
                env.pop(key, None)
            else:
                env[key] = value
        return checker.preflight(environment, env)

    def statuses(self, results):
        return {name: status for status, name, _message in results}

    # --- preflight: presence and shape -------------------------------------------------

    def test_good_env_passes_preflight(self):
        results = self.preflight_env()
        self.assertFalse(checker.has_failure(results))
        self.assertFalse(any(status == checker.WARN for status, _n, _m in results))

    def test_missing_resend_key_fails(self):
        self.assertEqual(self.statuses(self.preflight_env(RESEND_API_KEY=None))["RESEND_API_KEY"], "FAIL")

    def test_missing_admin_email_fails(self):
        self.assertEqual(self.statuses(self.preflight_env(SMTP_ADMIN_EMAIL=None))["SMTP_ADMIN_EMAIL"], "FAIL")

    def test_missing_pat_fails(self):
        self.assertEqual(self.statuses(self.preflight_env(SUPABASE_PERSONAL_ACCESS_TOKEN=None))[
            "SUPABASE_PERSONAL_ACCESS_TOKEN"], "FAIL")

    def test_resend_key_wrong_prefix_fails(self):
        results = self.preflight_env(RESEND_API_KEY="sk_dummy_test_key_only")
        self.assertEqual(self.statuses(results)["RESEND_API_KEY shape"], "FAIL")

    def test_resend_key_too_short_fails(self):
        self.assertEqual(self.statuses(self.preflight_env(RESEND_API_KEY="re_short"))["RESEND_API_KEY shape"], "FAIL")

    def test_resend_key_placeholder_fails(self):
        results = self.preflight_env(RESEND_API_KEY="re_xxxxxx_placeholder")
        self.assertEqual(self.statuses(results)["RESEND_API_KEY shape"], "FAIL")

    def test_resend_key_with_space_fails(self):
        results = self.preflight_env(RESEND_API_KEY="re_dummy test key only")
        self.assertEqual(self.statuses(results)["RESEND_API_KEY shape"], "FAIL")

    def test_pat_wrong_prefix_fails(self):
        results = self.preflight_env(SUPABASE_PERSONAL_ACCESS_TOKEN="token_dummy")
        self.assertEqual(self.statuses(results)["SUPABASE_PERSONAL_ACCESS_TOKEN shape"], "FAIL")

    def test_admin_email_bad_syntax_fails(self):
        results = self.preflight_env(SMTP_ADMIN_EMAIL="not-an-address")
        self.assertEqual(self.statuses(results)["SMTP_ADMIN_EMAIL format"], "FAIL")

    def test_admin_email_invalid_tld_fails(self):
        results = self.preflight_env(SMTP_ADMIN_EMAIL="auth@domain.invalid")
        self.assertEqual(self.statuses(results)["SMTP_ADMIN_EMAIL domain"], "FAIL")

    def test_admin_email_example_domain_fails(self):
        results = self.preflight_env(SMTP_ADMIN_EMAIL="auth@example.com")
        self.assertEqual(self.statuses(results)["SMTP_ADMIN_EMAIL domain"], "FAIL")

    def test_admin_email_resend_dev_warns_with_required_text(self):
        results = self.preflight_env(SMTP_ADMIN_EMAIL="onboarding@resend.dev")
        self.assertIn(("WARN", "SMTP_ADMIN_EMAIL domain", checker.TEST_ONLY_WARNING), results)

    def test_admin_email_gmail_warns_test_only(self):
        results = self.preflight_env(SMTP_ADMIN_EMAIL="someone@gmail.com")
        self.assertEqual(self.statuses(results)["SMTP_ADMIN_EMAIL domain"], "WARN")
        self.assertIn("test-only sender: delivers only to the Resend account owner",
                      [message for _s, _n, message in results])

    def test_warning_only_result_does_not_fail(self):
        results = self.preflight_env(SMTP_ADMIN_EMAIL="onboarding@resend.dev")
        self.assertFalse(checker.has_failure(results))

    def test_sender_name_with_newline_fails(self):
        results = self.preflight_env(SMTP_SENDER_NAME="Lagaw\nBcc: x")
        self.assertEqual(self.statuses(results)["SMTP_SENDER_NAME"], "FAIL")

    def test_sender_name_too_long_fails(self):
        results = self.preflight_env(SMTP_SENDER_NAME="x" * 65)
        self.assertEqual(self.statuses(results)["SMTP_SENDER_NAME"], "FAIL")

    def test_sender_name_unset_passes_with_default(self):
        results = self.preflight_env(SMTP_SENDER_NAME=None)
        self.assertEqual(self.statuses(results)["SMTP_SENDER_NAME"], "PASS")

    # --- preflight: project refs -------------------------------------------------------

    def test_missing_staging_ref_fails(self):
        results = self.preflight_env("staging", STAGING_SUPABASE_PROJECT_REF=None)
        self.assertEqual(self.statuses(results)["project ref"], "FAIL")

    def test_project_ref_argument_satisfies_missing_env(self):
        env = dict(GOOD_ENV)
        env.pop("STAGING_SUPABASE_PROJECT_REF")
        results = checker.preflight("staging", env, project_ref=STAGING_REF)
        self.assertEqual(self.statuses(results)["project ref"], "PASS")

    def test_malformed_ref_fails(self):
        results = self.preflight_env("staging", STAGING_SUPABASE_PROJECT_REF="ABC-123")
        self.assertEqual(self.statuses(results)["project ref"], "FAIL")

    def test_identical_staging_and_production_refs_fail(self):
        results = self.preflight_env("staging", PRODUCTION_SUPABASE_PROJECT_REF=STAGING_REF)
        self.assertEqual(self.statuses(results)["project refs"], "FAIL")

    def test_production_environment_uses_production_ref(self):
        results = self.preflight_env("production", STAGING_SUPABASE_PROJECT_REF=None)
        self.assertEqual(self.statuses(results)["project ref"], "PASS")

    # --- preflight output and CLI exit codes -------------------------------------------

    def test_preflight_cli_exits_zero_on_pass_and_one_on_fail(self):
        code, out, _err, opener = self.run_cli(["preflight", "--env", "staging"])
        self.assertEqual(code, 0)
        self.assertEqual(opener.requests, [])
        code, out, _err, _ = self.run_cli(["preflight", "--env", "staging"], env={})
        self.assertEqual(code, 1)
        self.assertIn("FAIL RESEND_API_KEY: missing", out)

    def test_preflight_output_never_contains_secret_values(self):
        _code, out, err, _ = self.run_cli(["preflight", "--env", "staging"])
        self.assertNoSecrets(out, err)
        _code, out, err, _ = self.run_cli(["preflight", "--env", "staging"],
                                          env=dict(GOOD_ENV, SMTP_ADMIN_EMAIL="x@resend.dev"))
        self.assertNoSecrets(out, err)

    # --- inspect -----------------------------------------------------------------------

    def test_inspect_prints_only_whitelisted_projection(self):
        leaky = dict(MATCHING_CONFIG, service_role_key=DUMMY_SERVICE, unknown_setting="x")
        opener = FakeOpener(ok_json(leaky))
        code, out, err, _ = self.run_cli(["inspect", "--env", "staging"], opener=opener)
        self.assertEqual(code, 0)
        self.assertNotIn("service_role_key", out)
        self.assertNotIn("unknown_setting", out)
        self.assertIn("smtp_host: smtp.resend.com", out)
        self.assertIn("smtp_pass_set: True", out)
        self.assertIn("smtp_user_set: True", out)
        self.assertNoSecrets(out, err)

    def test_inspect_never_prints_smtp_pass_value_even_when_returned(self):
        opener = FakeOpener(ok_json(dict(MATCHING_CONFIG, smtp_pass=DUMMY_KEY)))
        _code, out, err, _ = self.run_cli(["inspect", "--env", "staging"], opener=opener)
        self.assertNoSecrets(out, err)
        self.assertNotIn("smtp_pass:", out)

    def test_inspect_sends_token_in_header_only(self):
        opener = FakeOpener(ok_json(MATCHING_CONFIG))
        self.run_cli(["inspect", "--env", "staging"], opener=opener)
        request = opener.requests[0]
        self.assertEqual(request.get_method(), "GET")
        self.assertEqual(request.get_header("Authorization"), "Bearer " + DUMMY_PAT)
        self.assertNotIn(DUMMY_PAT, request.full_url)
        self.assertTrue(request.full_url.endswith(f"/v1/projects/{STAGING_REF}/config/auth"))

    def test_http_error_prints_status_only(self):
        body = json.dumps({"message": "bad " + DUMMY_SERVICE + DUMMY_PAT}).encode()
        opener = FakeOpener(http_error(401, body))
        code, out, err, _ = self.run_cli(["inspect", "--env", "staging"], opener=opener)
        self.assertEqual(code, 1)
        self.assertIn("HTTP 401", err)
        self.assertNoSecrets(out, err)

    def test_network_error_prints_exception_class_only(self):
        opener = FakeOpener(URLError("dummy leak " + DUMMY_PAT))
        code, out, err, _ = self.run_cli(["inspect", "--env", "staging"], opener=opener)
        self.assertEqual(code, 1)
        self.assertIn("URLError", err)
        self.assertNoSecrets(out, err)

    def test_non_json_success_body_is_not_echoed(self):
        opener = FakeOpener(FakeResponse(200, ("<html>" + DUMMY_SERVICE).encode()))
        code, out, err, _ = self.run_cli(["inspect", "--env", "staging"], opener=opener)
        self.assertEqual(code, 1)
        self.assertIn("not valid JSON", err)
        self.assertNoSecrets(out, err)

    def test_inspect_refuses_missing_pat_without_network(self):
        env = dict(GOOD_ENV)
        env.pop("SUPABASE_PERSONAL_ACCESS_TOKEN")
        code, _out, _err, opener = self.run_cli(["inspect", "--env", "staging"], env=env)
        self.assertEqual(code, 1)
        self.assertEqual(opener.requests, [])

    # --- plan --------------------------------------------------------------------------

    def test_desired_body_matches_documented_values(self):
        body = checker.desired_body(GOOD_ENV)
        self.assertEqual(body["smtp_host"], "smtp.resend.com")
        self.assertEqual(body["smtp_port"], "465")
        self.assertEqual(body["smtp_user"], "resend")
        self.assertEqual(body["smtp_pass"], DUMMY_KEY)
        self.assertEqual(body["smtp_sender_name"], "Lagaw")
        self.assertEqual(body["rate_limit_email_sent"], 30)
        self.assertNotIn("mailer_autoconfirm", body)

    def test_plan_reports_already_configured_idempotently(self):
        opener = FakeOpener(ok_json(MATCHING_CONFIG), ok_json(MATCHING_CONFIG))
        code, out, err, _ = self.run_cli(["plan", "--env", "staging"], opener=opener)
        self.assertEqual(code, 0)
        self.assertIn("already configured", out)
        self.assertNotIn("differs:", out)
        self.assertNoSecrets(out, err)

    def test_plan_lists_differing_fields_and_redacts_password(self):
        stale = dict(MATCHING_CONFIG, smtp_host="smtp.example.net", rate_limit_email_sent=2,
                     smtp_pass_set=False)
        stale.pop("smtp_pass")
        opener = FakeOpener(ok_json(stale))
        code, out, err, _ = self.run_cli(["plan", "--env", "staging"], opener=opener)
        self.assertEqual(code, 0)
        self.assertIn("differs: smtp_host, rate_limit_email_sent, smtp_pass", out)
        self.assertIn("smtp_pass: <redacted>", out)
        self.assertNoSecrets(out, err)

    def test_plan_treats_missing_smtp_user_as_differing(self):
        config = dict(MATCHING_CONFIG)
        config.pop("smtp_user")
        _code, out, _err, _ = self.run_cli(["plan", "--env", "staging"], opener=FakeOpener(ok_json(config)))
        self.assertIn("smtp_user", out.split("differs: ")[1].splitlines()[0])

    def test_plan_makes_only_a_get_request(self):
        opener = FakeOpener(ok_json(MATCHING_CONFIG))
        self.run_cli(["plan", "--env", "staging"], opener=opener)
        self.assertEqual([request.get_method() for request in opener.requests], ["GET"])

    def test_plan_stops_on_preflight_failure_without_network(self):
        env = dict(GOOD_ENV, RESEND_API_KEY="bad")
        code, _out, _err, opener = self.run_cli(["plan", "--env", "staging"], env=env)
        self.assertEqual(code, 1)
        self.assertEqual(opener.requests, [])

    # --- apply guards ------------------------------------------------------------------

    def test_apply_without_execute_refuses_without_network(self):
        code, out, _err, opener = self.run_cli(["apply", "--env", "staging", "--confirm", "staging"])
        self.assertEqual(code, 2)
        self.assertIn("refusing", out)
        self.assertEqual(opener.requests, [])

    def test_apply_requires_confirm_to_match_env(self):
        code, _out, _err, opener = self.run_cli(["apply", "--env", "staging", "--execute", "--confirm", "production"])
        self.assertEqual(code, 2)
        self.assertEqual(opener.requests, [])

    def test_production_apply_requires_authorization_text(self):
        code, out, _err, opener = self.run_cli(
            ["apply", "--env", "production", "--execute", "--confirm", "production"])
        self.assertEqual(code, 2)
        self.assertIn("--production-authorized-by", out)
        self.assertEqual(opener.requests, [])

    def test_production_apply_rejects_blank_authorization(self):
        code, _out, _err, opener = self.run_cli(
            ["apply", "--env", "production", "--execute", "--confirm", "production",
             "--production-authorized-by", "   "])
        self.assertEqual(code, 2)
        self.assertEqual(opener.requests, [])

    def test_apply_refuses_test_only_sender_without_flag(self):
        env = dict(GOOD_ENV, SMTP_ADMIN_EMAIL="onboarding@resend.dev")
        code, out, _err, opener = self.run_cli(
            ["apply", "--env", "staging", "--execute", "--confirm", "staging"], env=env)
        self.assertEqual(code, 2)
        self.assertIn("test-only sender", out)
        self.assertEqual(opener.requests, [])

    def test_apply_refuses_when_preflight_fails(self):
        env = dict(GOOD_ENV)
        env.pop("RESEND_API_KEY")
        code, _out, _err, opener = self.run_cli(
            ["apply", "--env", "staging", "--execute", "--confirm", "staging"], env=env)
        self.assertEqual(code, 1)
        self.assertEqual(opener.requests, [])

    def test_apply_is_noop_when_already_configured(self):
        opener = FakeOpener(ok_json(MATCHING_CONFIG))
        code, out, _err, _ = self.run_cli(
            ["apply", "--env", "staging", "--execute", "--confirm", "staging"], opener=opener)
        self.assertEqual(code, 0)
        self.assertIn("already configured; no PATCH sent", out)
        self.assertEqual([request.get_method() for request in opener.requests], ["GET"])

    def test_apply_patches_then_verifies(self):
        stale = dict(MATCHING_CONFIG, rate_limit_email_sent=2)
        stale.pop("smtp_pass")
        stale["smtp_pass_set"] = False
        opener = FakeOpener(
            ok_json(stale),                       # inspect before
            FakeResponse(200, b""),               # PATCH accepted, body not read
            ok_json(MATCHING_CONFIG),             # verification read
        )
        code, out, err, _ = self.run_cli(
            ["apply", "--env", "staging", "--execute", "--confirm", "staging"], opener=opener)
        self.assertEqual(code, 0)
        self.assertIn("verified", out)
        methods = [request.get_method() for request in opener.requests]
        self.assertEqual(methods, ["GET", "PATCH", "GET"])
        self.assertNoSecrets(out, err)

    def test_apply_patch_body_is_exact_and_never_touches_autoconfirm(self):
        opener = FakeOpener(ok_json({}), FakeResponse(200, b""), ok_json(MATCHING_CONFIG))
        self.run_cli(["apply", "--env", "staging", "--execute", "--confirm", "staging"], opener=opener)
        patch_request = opener.requests[1]
        body = json.loads(patch_request.data.decode())
        self.assertEqual(set(body), {"smtp_host", "smtp_port", "smtp_user", "smtp_pass",
                                     "smtp_admin_email", "smtp_sender_name", "rate_limit_email_sent"})
        self.assertEqual(body["smtp_port"], "465")
        self.assertNotIn("mailer_autoconfirm", body)

    def test_apply_verification_mismatch_fails(self):
        opener = FakeOpener(ok_json({}), FakeResponse(200, b""), ok_json(dict(MATCHING_CONFIG, rate_limit_email_sent=2)))
        code, out, err, _ = self.run_cli(
            ["apply", "--env", "staging", "--execute", "--confirm", "staging"], opener=opener)
        self.assertEqual(code, 1)
        self.assertIn("still differs: rate_limit_email_sent", out)
        self.assertNoSecrets(out, err)

    def test_apply_patch_error_prints_status_only(self):
        opener = FakeOpener(ok_json({}), http_error(403, b'{"detail":"' + DUMMY_SERVICE.encode() + b'"}'))
        code, out, err, _ = self.run_cli(
            ["apply", "--env", "staging", "--execute", "--confirm", "staging"], opener=opener)
        self.assertEqual(code, 1)
        self.assertIn("HTTP 403", err)
        self.assertNoSecrets(out, err)

    def test_production_apply_with_authorization_runs_and_targets_production_ref(self):
        opener = FakeOpener(ok_json({}), FakeResponse(200, b""), ok_json(MATCHING_CONFIG))
        code, _out, _err, _ = self.run_cli(
            ["apply", "--env", "production", "--execute", "--confirm", "production",
             "--production-authorized-by", "release owner"], opener=opener)
        self.assertEqual(code, 0)
        self.assertIn(f"/v1/projects/{PRODUCTION_REF}/config/auth", opener.requests[0].full_url)

    def test_test_only_sender_allowed_with_explicit_flag(self):
        env = dict(GOOD_ENV, SMTP_ADMIN_EMAIL="onboarding@resend.dev")
        resend_admin = dict(MATCHING_CONFIG, smtp_admin_email="onboarding@resend.dev")
        opener = FakeOpener(ok_json(MATCHING_CONFIG), FakeResponse(200, b""), ok_json(resend_admin))
        code, _out, _err, _ = self.run_cli(
            ["apply", "--env", "staging", "--execute", "--confirm", "staging", "--allow-test-sender"],
            env=env, opener=opener)
        self.assertEqual(code, 0)

    # --- projection unit ---------------------------------------------------------------

    def test_projection_ignores_unknown_and_secret_keys(self):
        projected = checker.project(dict(MATCHING_CONFIG, smtp_pass=DUMMY_SERVICE, anything=DUMMY_PAT))
        self.assertEqual(set(projected), set(checker.PROJECTION_KEYS) | {"smtp_user_set", "smtp_pass_set"})
        self.assertNotIn(DUMMY_SERVICE, json.dumps(projected))
        self.assertNotIn(DUMMY_PAT, json.dumps(projected))

    def test_projection_replaces_non_scalar_values(self):
        projected = checker.project(dict(MATCHING_CONFIG, smtp_host={"nested": DUMMY_KEY}))
        self.assertEqual(projected["smtp_host"], "<non-scalar>")
        self.assertNotIn(DUMMY_KEY, json.dumps(projected))


if __name__ == "__main__":
    unittest.main()
