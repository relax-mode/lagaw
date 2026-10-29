"""The scheduled live AI check must stay on staging and reject bad provider results."""

import importlib.util
import io
import json
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

spec = importlib.util.spec_from_file_location("ai_live_smoke", SCRIPTS / "ai_live_smoke.py")
live = importlib.util.module_from_spec(spec)
spec.loader.exec_module(live)

API = "https://lagaw-api-staging-i5kvldluga-as.a.run.app"
TOKEN = "dummy-staging-token-for-offline-checks-only"
DRAFT = {
    "schema_version": "1",
    "requires_confirmation": True,
    "missing_fields": ["budget"],
    "preferences": {
        "preferred_tags": ["cafe", "photography"], "budget_level": "low", "budget_min": None,
        "budget_max": None, "budget_scope": "trip_total", "group_type": None,
        "duration": "afternoon", "pace": "relaxed",
    },
}


def response(status, data):
    result = io.BytesIO(json.dumps(data).encode())
    result.status = status
    return result


class AiLiveSmokeTests(unittest.TestCase):
    def test_check_signs_in_as_the_staging_smoke_account(self):
        with patch.object(live, "sign_in", return_value=TOKEN) as signed, \
                patch.object(live, "verify", return_value=3) as verified:
            self.assertEqual(live.run(API), 3)
        signed.assert_called_once_with(API, "staging")
        verified.assert_called_once_with(API, TOKEN)

    def test_missing_smoke_account_fails_before_extraction(self):
        with patch.dict(os.environ, {}, clear=True), \
                patch.object(live, "verify") as verified, self.assertRaises(ValueError):
            live.run(API)
        verified.assert_not_called()

    def test_refuses_production_before_network(self):
        with patch.object(live, "urlopen") as opened, self.assertRaises(ValueError):
            live.verify("https://lagaw-api-663710289405.asia-southeast1.run.app", TOKEN)
        opened.assert_not_called()

    def test_accepts_schema_valid_draft(self):
        with patch.object(live, "urlopen", return_value=response(200, DRAFT)) as opened:
            self.assertEqual(live.verify(API, TOKEN), 2)
        request = opened.call_args.args[0]
        self.assertEqual(request.get_method(), "POST")
        self.assertTrue(request.full_url.endswith("/api/v1/preferences/extract"))

    def test_unauthenticated_request_fails_the_check(self):
        failure = HTTPError(API, 401, "unauthorized", {}, io.BytesIO(json.dumps(
            {"detail": "A valid Supabase access token is required."}).encode()))
        with patch.object(live, "urlopen", side_effect=failure), \
                self.assertRaisesRegex(ValueError, "401 \\(unknown\\)"):
            live.verify(API, TOKEN)

    def test_safe_provider_failure_fails_the_check(self):
        failure = HTTPError(API, 503, "unavailable", {}, io.BytesIO(json.dumps(
            {"detail": {"code": "extraction_unavailable", "manual_fallback": True}}).encode()))
        with patch.object(live, "urlopen", side_effect=failure), \
                self.assertRaisesRegex(ValueError, "503 \\(extraction_unavailable\\)"):
            live.verify(API, TOKEN)

    def test_unexpected_shape_fails_the_check(self):
        draft = json.loads(json.dumps(DRAFT))
        draft["preferences"]["preferred_tags"] = []
        with patch.object(live, "urlopen", return_value=response(200, draft)), self.assertRaises(ValueError):
            live.verify(API, TOKEN)


if __name__ == "__main__":
    unittest.main()
