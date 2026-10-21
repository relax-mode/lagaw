"""Issue #23 HTTP contract checks; no hosted databases or real secrets are used."""

import json
import os
import unittest
from unittest.mock import Mock, patch
from uuid import UUID

import httpx
from fastapi.testclient import TestClient

with patch.dict(os.environ, {}, clear=True), patch("dotenv.load_dotenv"):
    from app.main import create_app

HTTP_CLIENT = httpx.Client
OWNER = "23000000-0000-4000-8000-000000000001"
OTHER = "23000000-0000-4000-8000-000000000002"
TRIP_ID = "23000000-0000-4000-8000-000000000003"
TOKEN = "offline-demo-token-only-12345678901234567890"
BASE = "/api/v1/trips"
PAYLOAD = {
    "title": "Bacolod afternoon",
    "start_date": "2026-11-01",
    "end_date": "2026-11-01",
    "budget_min": "100.00",
    "budget_max": "500.50",
    "transportation_mode": "walking",
    "group_type": "solo",
    "preferred_tags": ["heritage", "cafe"],
}
ROW = {
    **PAYLOAD, "id": TRIP_ID, "user_id": OWNER,
    "status": "draft", "estimated_total_cost": None,
}


class TripApiTests(unittest.TestCase):
    def setUp(self):
        self.environment = patch.dict(os.environ, {
            "SUPABASE_URL": "https://database.invalid",
            "SUPABASE_SERVICE_ROLE_KEY": "sb_secret_offline_only",
            "TRIP_DEMO_USER_ID": OWNER,
            "TRIP_DEMO_TOKEN": TOKEN,
            "CORS_ALLOWED_ORIGINS": "http://localhost:3000",
        }, clear=True)
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.dotenv = patch("dotenv.load_dotenv")
        self.dotenv.start()
        self.addCleanup(self.dotenv.stop)
        self.database_dotenv = patch("app.database.load_dotenv")
        self.database_dotenv.start()
        self.addCleanup(self.database_dotenv.stop)
        with patch("app.main.load_dotenv"):
            self.app = create_app()
        self.client = TestClient(self.app, headers={"Authorization": f"Bearer {TOKEN}"})
        self.addCleanup(self.client.close)
        self.requests = []
        self.reply = Mock(return_value=httpx.Response(200, json=[ROW]))

        def handle(request):
            self.requests.append(request)
            return self.reply(request)

        def factory(**kwargs):
            return HTTP_CLIENT(transport=httpx.MockTransport(handle), **kwargs)

        transport = patch("app.database.httpx.Client", side_effect=factory)
        transport.start()
        self.addCleanup(transport.stop)

    def assert_safe_unavailable(self, response):
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json(), {
            "detail": "Trips are temporarily unavailable. Please try again later.",
        })
        for private in (TOKEN, "sb_secret_offline_only", "private provider details"):
            self.assertNotIn(private, response.text)

    def test_create_sends_owner_and_returns_saved_trip(self):
        self.reply.return_value = httpx.Response(201, json=[ROW])
        response = self.client.post(BASE, json=PAYLOAD)
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json(), ROW)
        request = self.requests[0]
        self.assertEqual(request.method, "POST")
        self.assertEqual(request.url.path, "/rest/v1/trips")
        self.assertEqual(json.loads(request.content), {**PAYLOAD, "user_id": OWNER})
        self.assertEqual(request.headers["Prefer"], "return=representation")
        self.assertEqual(request.headers["Content-Profile"], "public")
        self.assertEqual(request.headers["apikey"], "sb_secret_offline_only")
        self.assertNotIn(TOKEN, str(request.headers))

    def test_optional_fields_and_zero_budgets(self):
        payload = {key: value for key, value in PAYLOAD.items()
                   if key not in ("transportation_mode", "group_type", "preferred_tags")}
        payload.update(budget_min=0, budget_max=0)
        self.reply.return_value = httpx.Response(201, json=[{
            **ROW, "budget_min": 0, "budget_max": 0,
            "transportation_mode": None, "group_type": None, "preferred_tags": [],
        }])
        response = self.client.post(BASE, json=payload)
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json()["preferred_tags"], [])
        self.assertEqual(response.json()["budget_min"], "0")

    def test_list_is_paginated_and_owner_scoped(self):
        response = self.client.get(f"{BASE}?limit=2&offset=4")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"items": [ROW], "limit": 2, "offset": 4})
        params = self.requests[0].url.params
        self.assertEqual(params["user_id"], f"eq.{OWNER}")
        self.assertEqual(params["limit"], "2")
        self.assertEqual(params["offset"], "4")
        self.assertEqual(params["order"], "start_date.asc,id.asc")

    def test_empty_list_is_success(self):
        self.reply.return_value = httpx.Response(200, json=[])
        response = self.client.get(BASE)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"items": [], "limit": 10, "offset": 0})

    def test_retrieve_scopes_both_id_and_owner(self):
        response = self.client.get(f"{BASE}/{TRIP_ID}")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), ROW)
        self.assertEqual(self.requests[0].url.params["id"], f"eq.{TRIP_ID}")
        self.assertEqual(self.requests[0].url.params["user_id"], f"eq.{OWNER}")

    def test_missing_and_other_owner_trips_have_same_404(self):
        self.reply.return_value = httpx.Response(200, json=[])
        missing = self.client.get(f"{BASE}/{TRIP_ID}")
        self.assertEqual(missing.status_code, 404)
        self.assertEqual(missing.json(), {"detail": "Trip not found."})
        os.environ["TRIP_DEMO_USER_ID"] = OTHER
        inaccessible = self.client.get(f"{BASE}/{TRIP_ID}")
        self.assertEqual(inaccessible.status_code, 404)
        self.assertEqual(inaccessible.json(), missing.json())
        self.assertEqual(self.requests[-1].url.params["user_id"], f"eq.{OTHER}")

    def test_validation_rejects_bad_dates_budgets_and_fields(self):
        cases = [
            {"title": "  "}, {"title": 123}, {"title": "x" * 201},
            {"start_date": "2026-02-30"}, {"end_date": "2026-10-01"},
            {"start_date": 1793491200}, {"start_date": "2026-11-01T00:00:00"},
            {"budget_min": -1}, {"budget_max": -1}, {"budget_min": "600"},
            {"budget_min": "NaN"}, {"budget_max": "Infinity"},
            {"budget_max": "10000000000"}, {"budget_max": "500.501"},
            {"budget_min": True}, {"group_type": " "},
            {"preferred_tags": "cafe"}, {"preferred_tags": [""]},
            {"user_id": OTHER}, {"status": "published"},
        ]
        for change in cases:
            with self.subTest(change=change):
                response = self.client.post(BASE, json={**PAYLOAD, **change})
                self.assertEqual(response.status_code, 422)
                self.assertTrue(response.json()["detail"])
                self.assertTrue(all("input" not in item for item in response.json()["detail"]))
        self.assertEqual(self.requests, [])

    def test_missing_fields_invalid_json_and_nonfinite_json(self):
        for content in ("{}", "[]", "null", "broken json", '{"budget_min": NaN}'):
            with self.subTest(content=content):
                response = self.client.post(
                    BASE, content=content, headers={"Content-Type": "application/json"},
                )
                self.assertEqual(response.status_code, 422)
        self.assertEqual(self.requests, [])

    def test_invalid_id_and_pagination_never_query_database(self):
        for suffix in ("/not-a-uuid", "?limit=0", "?limit=101", "?offset=-1", "?offset=no"):
            with self.subTest(suffix=suffix):
                self.assertEqual(self.client.get(BASE + suffix).status_code, 422)
        self.assertEqual(self.requests, [])

    def test_authentication_required_on_every_endpoint(self):
        for header in ("", "Bearer wrong", "Basic wrong"):
            for method, path in (("GET", BASE), ("GET", f"{BASE}/{TRIP_ID}"), ("POST", BASE)):
                with self.subTest(header=header, method=method):
                    response = self.client.request(
                        method, path, headers={"Authorization": header},
                        **({"json": PAYLOAD} if method == "POST" else {}),
                    )
                    self.assertEqual(response.status_code, 401)
                    self.assertEqual(response.headers["WWW-Authenticate"], "Bearer")
        self.assertEqual(self.requests, [])

    def test_demo_context_disabled_or_invalid(self):
        for key, value in (
            ("TRIP_DEMO_TOKEN", ""), ("TRIP_DEMO_TOKEN", "too-short"),
            ("TRIP_DEMO_TOKEN", "x" * 32 + "\n"),
            ("TRIP_DEMO_USER_ID", ""), ("TRIP_DEMO_USER_ID", "not-a-uuid"),
            ("TRIP_DEMO_USER_ID", str(UUID(int=0))),
        ):
            with self.subTest(key=key, value=value), patch.dict(os.environ, {key: value}):
                response = self.client.get(BASE)
                self.assertEqual(response.status_code, 503)
                self.assertEqual(response.json(), {"detail": "Trip demo context is not configured."})
        self.assertEqual(self.requests, [])

    def test_unconfigured_database_is_safe(self):
        os.environ["SUPABASE_SERVICE_ROLE_KEY"] = ""
        self.assert_safe_unavailable(self.client.get(BASE))
        self.assertEqual(self.requests, [])

    def test_provider_errors_on_all_endpoints_are_safe(self):
        for status in (400, 401, 403, 409, 429, 500, 503):
            self.reply.return_value = httpx.Response(status, text="private provider details")
            with self.subTest(status=status):
                self.assert_safe_unavailable(self.client.get(BASE))
                self.assert_safe_unavailable(self.client.get(f"{BASE}/{TRIP_ID}"))
                self.assert_safe_unavailable(self.client.post(BASE, json=PAYLOAD))

    def test_network_errors_are_safe(self):
        for error in (httpx.ConnectError, httpx.ReadTimeout):
            self.reply.side_effect = error("private provider details")
            with self.subTest(error=error):
                self.assert_safe_unavailable(self.client.get(BASE))
                self.assert_safe_unavailable(self.client.post(BASE, json=PAYLOAD))

    def test_malformed_and_cross_owner_output_is_not_exposed(self):
        for body in ({"error": "private provider details"}, [{"id": TRIP_ID}],
                     [{**ROW, "user_id": OTHER}], [ROW, ROW]):
            with self.subTest(body=body):
                self.reply.return_value = httpx.Response(200, json=body)
                self.assert_safe_unavailable(self.client.get(f"{BASE}/{TRIP_ID}"))
        self.reply.return_value = httpx.Response(200, json=[{**ROW, "user_id": OTHER}])
        self.assert_safe_unavailable(self.client.get(BASE))
        self.reply.return_value = httpx.Response(200, text="not json")
        self.assert_safe_unavailable(self.client.get(BASE))

    def test_wrong_trip_id_is_not_exposed(self):
        self.reply.return_value = httpx.Response(200, json=[{**ROW, "id": OTHER}])
        self.assert_safe_unavailable(self.client.get(f"{BASE}/{TRIP_ID}"))

    def test_create_requires_a_saved_representation(self):
        for status, body in ((201, []), (200, [ROW]), (201, [{**ROW, "user_id": OTHER}])):
            with self.subTest(status=status, body=body):
                self.reply.return_value = httpx.Response(status, json=body)
                self.assert_safe_unavailable(self.client.post(BASE, json=PAYLOAD))

    def test_cors_headers_on_trip_errors(self):
        response = self.client.get(
            BASE, headers={"Authorization": "", "Origin": "http://localhost:3000"},
        )
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.headers["access-control-allow-origin"], "http://localhost:3000")


if __name__ == "__main__":
    unittest.main()
