"""Exercise HTTP responses and Supabase requests without credentials or network."""

import copy
import json
import os
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import httpx
from fastapi.testclient import TestClient

# app.main constructs its module-level app during import. Scope the dotenv guard
# to import time so the test module doesn't leave global state patched.
with patch.dict(os.environ, {}, clear=True), patch("dotenv.load_dotenv"):
    from app.main import app

HTTP_CLIENT = httpx.Client
ROOT = Path(__file__).resolve().parents[1]


class LocationsTests(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {
            "SUPABASE_URL": "https://test-only.supabase.co",
            "SUPABASE_SERVICE_ROLE_KEY": "sb_secret_test_only",
        }, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)
        dotenv = patch("app.database.load_dotenv")
        dotenv.start()
        self.addCleanup(dotenv.stop)
        # This JSON is an offline test fixture, never an application fallback.
        with (ROOT / "supabase/data/locations.json").open(encoding="utf-8") as source:
            self.row = json.load(source)[0]
        self.row["id"] = "1a3bca09-5532-5de6-8587-2440c4e5830d"
        self.requests = []
        self.reply = Mock(return_value=httpx.Response(200, json=[self.row]))
        self.client = TestClient(app)
        self.addCleanup(self.client.close)

        def handle(request):
            self.requests.append(request)
            return self.reply(request)

        def factory(**kwargs):
            return HTTP_CLIENT(transport=httpx.MockTransport(handle), **kwargs)

        self.factory = patch("app.database.httpx.Client", side_effect=factory)
        self.factory.start()
        self.addCleanup(self.factory.stop)

    def test_database_rows_and_unknown_values_are_returned(self):
        response = self.client.get("/locations")
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(body["limit"], 10)
        self.assertEqual(body["offset"], 0)
        self.assertEqual(body["items"][0]["name"], self.row["name"])
        self.assertIsNone(body["items"][0]["estimated_cost_min"])
        self.assertIsNone(body["items"][0]["image_url"])
        self.assertEqual(body["items"][0]["opening_hours"], {})
        request = self.requests[0]
        self.assertEqual(request.method, "GET")
        self.assertEqual(request.url.path, "/rest/v1/locations")
        self.assertEqual(request.url.params["is_active"], "eq.true")
        self.assertEqual(request.url.params["order"], "name.asc,id.asc")
        self.assertEqual(request.headers["apikey"], "sb_secret_test_only")
        self.assertNotIn("authorization", request.headers)
        self.assertNotIn("sb_secret_test_only", response.text)

    def test_pagination_reaches_database(self):
        response = self.client.get("/locations?limit=2&offset=5")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["limit"], 2)
        self.assertEqual(response.json()["offset"], 5)
        self.assertEqual(self.requests[0].url.params["limit"], "2")
        self.assertEqual(self.requests[0].url.params["offset"], "5")

    def test_empty_page_is_success(self):
        self.reply.return_value = httpx.Response(200, json=[])
        response = self.client.get("/locations?offset=100")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"items": [], "limit": 10, "offset": 100})

    def test_invalid_pagination_does_not_query_database(self):
        for query in ("limit=0", "limit=101", "limit=coffee", "offset=-1"):
            with self.subTest(query=query):
                response = self.client.get(f"/locations?{query}")
                self.assertEqual(response.status_code, 422)
        self.assertEqual(self.requests, [])

    def test_provider_errors_do_not_leak(self):
        for status in (401, 403, 429, 500):
            with self.subTest(status=status):
                self.reply.return_value = httpx.Response(status, json={
                    "detail": "private provider details sb_secret_test_only",
                })
                response = self.client.get("/locations")
                self.assert_safe_failure(response)

    def test_network_failures_do_not_leak(self):
        for error in (httpx.ReadTimeout, httpx.ConnectError):
            with self.subTest(error=error):
                def fail(request, error_type=error):
                    raise error_type("private provider details sb_secret_test_only", request=request)
                self.reply.side_effect = fail
                self.assert_safe_failure(self.client.get("/locations"))

    def test_malformed_database_output_is_rejected(self):
        for body in ({"error": "private provider details"}, [{"name": "Missing fields"}]):
            with self.subTest(body=body):
                self.reply.return_value = httpx.Response(200, json=body)
                self.assert_safe_failure(self.client.get("/locations"))
        self.reply.return_value = httpx.Response(200, text="not json")
        self.assert_safe_failure(self.client.get("/locations"))

    def test_inactive_or_nonfinite_data_is_rejected(self):
        for field, value in (("is_active", False), ("latitude", "NaN")):
            with self.subTest(field=field):
                row = copy.deepcopy(self.row)
                row[field] = value
                self.reply.return_value = httpx.Response(200, json=[row])
                self.assert_safe_failure(self.client.get("/locations"))

    def test_missing_configuration_is_safe(self):
        for field in ("SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"):
            with self.subTest(field=field), patch.dict(os.environ, {field: ""}):
                self.assert_safe_failure(self.client.get("/locations"))
        self.assertEqual(self.requests, [])

    def test_unsafe_database_urls_are_rejected_before_client_creation(self):
        for url in (
            "http://example.supabase.co", "https://user:secret@example.supabase.co",
            "https://example.supabase.co/rest/v1", "https://example.supabase.co?x=1",
        ):
            with self.subTest(url=url), patch.dict(os.environ, {"SUPABASE_URL": url}), \
                    patch("app.database.httpx.Client") as client_factory:
                self.assert_safe_failure(self.client.get("/locations"))
                client_factory.assert_not_called()
        self.assertEqual(self.requests, [])

    def test_legacy_server_key_is_supported(self):
        os.environ["SUPABASE_SERVICE_ROLE_KEY"] = "test-only-legacy-key"
        response = self.client.get("/locations")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.requests[0].headers["authorization"], "Bearer test-only-legacy-key")

    def test_endpoint_is_read_only(self):
        self.assertEqual(self.client.post("/locations", json=self.row).status_code, 405)
        self.assertEqual(self.requests, [])

    def assert_safe_failure(self, response):
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json(), {
            "detail": "Locations are temporarily unavailable. Please try again later.",
        })


if __name__ == "__main__":
    unittest.main()
