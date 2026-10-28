"""Deployment checks reject unsafe targets and use dedicated verified sessions."""

import importlib.util
import io
import json
import os
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "smoke_deployed", Path(__file__).resolve().parents[1] / "scripts" / "smoke_deployed.py",
)
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)

API = "https://lagaw-api-staging-i5kvldluga-as.a.run.app"
TOKEN = "dummy-staging-token-for-offline-checks-only"
OWNER = "23000000-0000-4000-8000-000000000001"


def response(status, data):
    result = io.BytesIO(json.dumps(data).encode())
    result.status = status
    result.headers = {"Access-Control-Allow-Origin": smoke.ORIGIN}
    return result


PRODUCTION_API = "https://lagaw-api-663710289405.asia-southeast1.run.app"


class DeployedSmokeTests(unittest.TestCase):
    def test_sign_in_is_bound_to_correct_auth_project(self):
        with patch.dict(os.environ, {"SMOKE_AUTH_EMAIL": "synthetic@example.invalid",
                                    "SMOKE_AUTH_PASSWORD": "synthetic-password-only",
                                    "SMOKE_SUPABASE_KEY": "publishable-synthetic-only"}, clear=True), \
                patch.object(smoke, "urlopen", return_value=response(200, {"access_token": TOKEN})) as opened:
            self.assertEqual(smoke.sign_in(API, "staging"), TOKEN)
        request = opened.call_args.args[0]
        self.assertTrue(request.full_url.startswith(smoke.AUTH_URLS["staging"]))
        self.assertEqual(request.get_method(), "POST")

    def test_sign_in_refuses_environment_mismatch_before_credentials(self):
        with patch.object(smoke, "urlopen") as opened, self.assertRaises(ValueError):
            smoke.sign_in(PRODUCTION_API, "staging")
        opened.assert_not_called()

    def test_missing_smoke_account_never_sends_a_request(self):
        with patch.dict(os.environ, {}, clear=True), \
                patch.object(smoke, "urlopen") as opened, self.assertRaises(ValueError):
            smoke.sign_in(API, "staging")
        opened.assert_not_called()

    def test_refuses_production_before_network(self):
        with patch.object(smoke, "urlopen") as opened, self.assertRaises(ValueError):
            smoke.verify(PRODUCTION_API, TOKEN, OWNER)
        opened.assert_not_called()

    def test_production_check_refuses_staging_before_network(self):
        with patch.object(smoke, "urlopen") as opened, self.assertRaises(ValueError):
            smoke.verify(API, TOKEN, OWNER, "production")
        opened.assert_not_called()

    def test_production_check_requires_the_production_origin(self):
        location = response(200, {"items": [{}]})
        with patch.object(smoke, "urlopen", return_value=location) as opened, self.assertRaises(ValueError):
            smoke.verify(PRODUCTION_API, TOKEN, OWNER, "production")
        self.assertEqual(opened.call_args.args[0].get_header("Origin"), "https://lagaw.pages.dev")

    def test_detects_unconfigured_trip_backend_after_locations_pass(self):
        with patch.object(smoke, "urlopen", side_effect=[
            response(200, {"items": [{}]}),
            response(503, {"detail": "Trip demo context is not configured."}),
        ]), self.assertRaises(ValueError):
            smoke.verify(API, TOKEN, OWNER)

    def test_rejects_mismatched_frontend_token(self):
        with patch.object(smoke, "urlopen", side_effect=[
            response(200, {"items": [{}]}), response(401, {}), response(401, {}),
        ]), self.assertRaises(ValueError):
            smoke.verify(API, TOKEN, OWNER)

    def test_rejects_another_demo_owners_trips(self):
        with patch.object(smoke, "urlopen", side_effect=[
            response(200, {"items": [{}]}), response(401, {}),
            response(200, {"items": [{"user_id": "another-owner"}]}),
        ]), self.assertRaises(ValueError):
            smoke.verify(API, TOKEN, OWNER)

    def test_rejects_missing_browser_permission(self):
        location = response(200, {"items": [{}]})
        location.headers = {}
        with patch.object(smoke, "urlopen", return_value=location), self.assertRaises(ValueError):
            smoke.verify(API, TOKEN, OWNER)

    def test_successful_check_never_writes_or_calls_the_provider(self):
        with patch.object(smoke, "urlopen", side_effect=[
            response(200, {"items": [{}]}), response(401, {}),
            response(200, {"items": [{"user_id": OWNER}]}),
            response(422, {"detail": []}),
        ]) as opened:
            smoke.verify(API, TOKEN, OWNER)
        requests = [call.args[0] for call in opened.call_args_list]
        self.assertTrue(all(request.get_method() == "GET" for request in requests[:3]))
        extraction = requests[3]
        self.assertEqual(extraction.get_method(), "POST")
        self.assertTrue(extraction.full_url.endswith("/api/v1/preferences/extract"))
        self.assertEqual(json.loads(extraction.data), {"prompt": ""})

    def test_rejects_missing_extraction_route(self):
        with patch.object(smoke, "urlopen", side_effect=[
            response(200, {"items": [{}]}), response(401, {}),
            response(200, {"items": [{"user_id": OWNER}]}),
            response(404, {"detail": "Not Found"}),
        ]), self.assertRaises(ValueError):
            smoke.verify(API, TOKEN, OWNER)


if __name__ == "__main__":
    unittest.main()
