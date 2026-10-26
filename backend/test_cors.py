"""Check browser-facing CORS policy without a live database or real credentials."""

import os
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

# Importing app.main creates its module-level app; scope the dotenv guard to
# import time and keep the rest of the suite's environment untouched.
with patch.dict(os.environ, {}, clear=True), patch("dotenv.load_dotenv"):
    from app.database import DatabaseUnavailable, get_database
    from app.main import create_app

LOCAL_ORIGIN = "http://localhost:3000"
WEB_ORIGIN = "https://lagaw-test.pages.dev"


class CorsTests(unittest.TestCase):
    def setUp(self):
        env = patch.dict(os.environ, {
            "CORS_ALLOWED_ORIGINS": f" {LOCAL_ORIGIN}, , {WEB_ORIGIN} ",
        }, clear=True)
        env.start()
        self.addCleanup(env.stop)
        dotenv = patch("app.main.load_dotenv")
        dotenv.start()
        self.addCleanup(dotenv.stop)
        self.app = create_app()
        self.database_calls = 0

        class EmptyDatabase:
            def list_locations(self, limit, offset):
                return []

        def database():
            self.database_calls += 1
            return EmptyDatabase()

        self.app.dependency_overrides[get_database] = database
        self.client = TestClient(self.app)
        self.addCleanup(self.client.close)

    def preflight(self, origin, method="GET", headers="authorization,content-type"):
        return self.client.options("/locations", headers={
            "Origin": origin,
            "Access-Control-Request-Method": method,
            "Access-Control-Request-Headers": headers,
        })

    def test_approved_local_and_deployed_origins_can_read_locations(self):
        self.assertTrue(False, "deliberate CI gate failure")
        for origin in (LOCAL_ORIGIN, WEB_ORIGIN):
            with self.subTest(origin=origin):
                response = self.client.get("/locations", headers={"Origin": origin})
                self.assertEqual(response.status_code, 200)
                self.assertEqual(response.json(), {"items": [], "limit": 10, "offset": 0})
                self.assertEqual(response.headers["access-control-allow-origin"], origin)
                self.assertIn("Origin", response.headers["vary"])
                self.assertNotIn("access-control-allow-credentials", response.headers)

    def test_preflights_allow_api_methods_without_querying_database(self):
        for method in ("GET", "POST", "PUT", "PATCH", "DELETE"):
            with self.subTest(method=method):
                response = self.preflight(LOCAL_ORIGIN, method)
                self.assertEqual(response.status_code, 200)
                self.assertEqual(response.headers["access-control-allow-origin"], LOCAL_ORIGIN)
                self.assertIn(method, response.headers["access-control-allow-methods"])
        self.assertEqual(self.database_calls, 0)

    def test_unapproved_origins_cannot_get_browser_permission(self):
        for origin in (
            "https://unrelated.pages.dev", "https://lagaw-test.pages.dev.evil.example",
            "http://localhost:3001", "https://localhost:3000", "null",
        ):
            with self.subTest(origin=origin):
                preflight = self.preflight(origin)
                self.assertEqual(preflight.status_code, 400)
                self.assertNotIn("access-control-allow-origin", preflight.headers)
                response = self.client.get("/locations", headers={"Origin": origin})
                self.assertEqual(response.status_code, 200)
                self.assertNotIn("access-control-allow-origin", response.headers)

    def test_unapproved_methods_and_headers_fail_preflight(self):
        self.assertEqual(self.preflight(LOCAL_ORIGIN, method="TRACE").status_code, 400)
        self.assertEqual(self.preflight(LOCAL_ORIGIN, headers="x-unapproved").status_code, 400)
        self.assertEqual(self.database_calls, 0)

    def test_handled_errors_keep_cors_headers(self):
        def unavailable():
            raise DatabaseUnavailable

        self.app.dependency_overrides[get_database] = unavailable
        response = self.client.get("/locations", headers={"Origin": LOCAL_ORIGIN})
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.headers["access-control-allow-origin"], LOCAL_ORIGIN)
        self.assertEqual(response.json(), {
            "detail": "Locations are temporarily unavailable. Please try again later.",
        })

    def test_validation_and_routing_errors_keep_cors_headers(self):
        for method, path, status in (
            ("GET", "/locations?limit=0", 422), ("GET", "/missing", 404),
            ("POST", "/locations", 405),
        ):
            with self.subTest(path=path, method=method):
                response = self.client.request(method, path, headers={"Origin": LOCAL_ORIGIN})
                self.assertEqual(response.status_code, status)
                self.assertEqual(response.headers["access-control-allow-origin"], LOCAL_ORIGIN)

    def test_requests_without_origin_still_work(self):
        response = self.client.get("/locations")
        self.assertEqual(response.status_code, 200)
        self.assertNotIn("access-control-allow-origin", response.headers)

    def test_missing_or_empty_configuration_permits_no_browser_origins(self):
        for value in (None, "", " , "):
            with self.subTest(value=value):
                if value is None:
                    os.environ.pop("CORS_ALLOWED_ORIGINS", None)
                else:
                    os.environ["CORS_ALLOWED_ORIGINS"] = value
                with TestClient(create_app()) as client:
                    response = client.options("/locations", headers={
                        "Origin": LOCAL_ORIGIN, "Access-Control-Request-Method": "GET",
                    })
                self.assertEqual(response.status_code, 400)
                self.assertNotIn("access-control-allow-origin", response.headers)

    def test_invalid_configuration_fails_startup_without_echoing_values(self):
        for value in (
            "*", "https://*.pages.dev", "null", "localhost:3000",
            "https://example.com/", "https://example.com/locations",
            "https://example.com?query=1", "https://example.com#fragment",
            "https://user:private-test-only@example.com", "http://localhost:bad",
        ):
            with self.subTest(value=value):
                os.environ["CORS_ALLOWED_ORIGINS"] = value
                with self.assertRaisesRegex(ValueError, "CORS_ALLOWED_ORIGINS") as caught:
                    create_app()
                self.assertNotIn(value, str(caught.exception))


if __name__ == "__main__":
    unittest.main()
