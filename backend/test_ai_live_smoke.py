"""The scheduled live AI check must stay on staging and reject bad provider results."""

import importlib.util
import io
import json
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError

spec = importlib.util.spec_from_file_location(
    "ai_live_smoke", Path(__file__).resolve().parents[1] / "scripts" / "ai_live_smoke.py",
)
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
