"""Deployment checks must reject missing demo configuration and unsafe targets."""

import importlib.util
import io
import json
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "smoke_staging", Path(__file__).resolve().parents[1] / "scripts" / "smoke_staging.py",
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


class StagingSmokeTests(unittest.TestCase):
    def test_refuses_production_before_network(self):
        with patch.object(smoke, "urlopen") as opened, self.assertRaises(ValueError):
            smoke.verify("https://lagaw-api-663710289405.asia-southeast1.run.app", TOKEN, OWNER)
        opened.assert_not_called()

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

    def test_successful_check_is_read_only(self):
        with patch.object(smoke, "urlopen", side_effect=[
            response(200, {"items": [{}]}), response(401, {}),
            response(200, {"items": [{"user_id": OWNER}]}),
        ]) as opened:
            smoke.verify(API, TOKEN, OWNER)
        self.assertTrue(all(call.args[0].get_method() == "GET" for call in opened.call_args_list))


if __name__ == "__main__":
    unittest.main()
