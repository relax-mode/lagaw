"""Trip CRUD HTTP checks; no hosted databases or real secrets are used."""

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
            "SUPABASE_URL": "http://127.0.0.1:54321",
            "SUPABASE_SERVICE_ROLE_KEY": "sb_secret_offline_only",
            "TRIP_AUTH_MODE": "demo",
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

    def test_patch_changes_only_supplied_fields_and_scopes_write(self):
        updated = {**ROW, "title": "Updated afternoon"}
        self.reply.side_effect = [
            httpx.Response(200, json=[ROW]), httpx.Response(200, json=[updated]),
        ]
        response = self.client.patch(f"{BASE}/{TRIP_ID}", json={"title": " Updated afternoon "})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), updated)
        read, write = self.requests
        self.assertEqual(read.method, "GET")
        self.assertEqual(write.method, "PATCH")
        for request in (read, write):
            self.assertEqual(request.url.path, "/rest/v1/trips")
            self.assertEqual(request.url.params["user_id"], f"eq.{OWNER}")
            self.assertEqual(request.url.params["id"], f"eq.{TRIP_ID}")
        self.assertEqual(json.loads(write.content), {"title": "Updated afternoon"})
        self.assertEqual(write.headers["Prefer"], "return=representation")
        self.assertEqual(write.headers["Content-Profile"], "public")
        self.assertNotIn(TOKEN, str(write.headers))

    def test_patch_supports_all_editable_fields(self):
        changes = {
            "title": "Two days in Bacolod", "start_date": "2026-11-02",
            "end_date": "2026-11-03", "budget_min": "0", "budget_max": "900.25",
            "transportation_mode": "taxi", "group_type": "friends",
            "preferred_tags": ["food", "heritage"],
        }
        self.reply.side_effect = [
            httpx.Response(200, json=[ROW]),
            httpx.Response(200, json=[{**ROW, **changes}]),
        ]
        response = self.client.patch(f"{BASE}/{TRIP_ID}", json=changes)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {**ROW, **changes})
        self.assertEqual(json.loads(self.requests[-1].content), changes)

    def test_patch_can_clear_optional_labels_and_tags(self):
        changes = {"transportation_mode": None, "group_type": None, "preferred_tags": []}
        self.reply.side_effect = [
            httpx.Response(200, json=[ROW]),
            httpx.Response(200, json=[{**ROW, **changes}]),
        ]
        response = self.client.patch(f"{BASE}/{TRIP_ID}", json=changes)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {**ROW, **changes})
        self.assertEqual(json.loads(self.requests[-1].content), changes)

    def test_patch_validates_ranges_against_unchanged_saved_values(self):
        for changes in (
            {"start_date": "2026-11-02"}, {"end_date": "2026-10-31"},
            {"budget_min": "500.51"}, {"budget_max": "99.99"},
            {"start_date": "2026-11-03", "end_date": "2026-11-02"},
            {"budget_min": "600", "budget_max": "500"},
        ):
            with self.subTest(changes=changes):
                self.requests.clear()
                response = self.client.patch(f"{BASE}/{TRIP_ID}", json=changes)
                self.assertEqual(response.status_code, 422)
                self.assertEqual([request.method for request in self.requests], ["GET"])
                self.assertTrue(all(
                    "input" not in error and "ctx" not in error
                    for error in response.json()["detail"]
                ))

    def test_patch_rejects_empty_invalid_null_and_server_owned_fields(self):
        changes = [
            {}, {"title": " "}, {"title": 123}, {"title": "x" * 201},
            {"start_date": "2026-02-30"}, {"end_date": 1793491200},
            {"start_date": "2026-11-01T00:00:00"},
            {"budget_min": -1}, {"budget_max": "NaN"}, {"budget_min": True},
            {"budget_max": "Infinity"}, {"budget_max": "500.501"},
            {"budget_max": "10000000000"},
            {"transportation_mode": " "}, {"group_type": "x" * 51},
            {"preferred_tags": "cafe"}, {"preferred_tags": [""]},
            {"preferred_tags": ["food"] * 31},
            {"id": TRIP_ID}, {"user_id": OTHER}, {"status": "archived"},
            {"estimated_total_cost": "100"},
            *({field: None} for field in (
                "title", "start_date", "end_date", "budget_min", "budget_max", "preferred_tags",
            )),
        ]
        for change in changes:
            with self.subTest(change=change):
                response = self.client.patch(f"{BASE}/{TRIP_ID}", json=change)
                self.assertEqual(response.status_code, 422)
        for content in ("[]", "null", "broken json", '{"budget_min": NaN}'):
            with self.subTest(content=content):
                response = self.client.patch(
                    f"{BASE}/{TRIP_ID}", content=content,
                    headers={"Content-Type": "application/json"},
                )
                self.assertEqual(response.status_code, 422)
        self.assertEqual(self.requests, [])

    def test_mutations_hide_missing_and_other_owner_trips(self):
        self.reply.return_value = httpx.Response(200, json=[])
        for owner in (OWNER, OTHER):
            with self.subTest(owner=owner), patch.dict(os.environ, {"TRIP_DEMO_USER_ID": owner}):
                for method in ("PATCH", "DELETE"):
                    self.requests.clear()
                    response = self.client.request(
                        method, f"{BASE}/{TRIP_ID}",
                        **({"json": {"title": "Update"}} if method == "PATCH" else {}),
                    )
                    self.assertEqual(response.status_code, 404)
                    self.assertEqual(response.json(), {"detail": "Trip not found."})
                    self.assertEqual(len(self.requests), 1)
                    self.assertEqual(self.requests[0].url.params["user_id"], f"eq.{owner}")

    def test_patch_handles_trip_deleted_between_read_and_write(self):
        self.reply.side_effect = [
            httpx.Response(200, json=[ROW]), httpx.Response(200, json=[]),
        ]
        response = self.client.patch(f"{BASE}/{TRIP_ID}", json={"title": "Update"})
        self.assertEqual(response.status_code, 404)

    def test_database_constraint_conflict_is_safe(self):
        self.reply.side_effect = [
            httpx.Response(200, json=[ROW]),
            httpx.Response(400, json={"code": "23514", "details": "private provider details"}),
        ]
        response = self.client.patch(f"{BASE}/{TRIP_ID}", json={"budget_min": "200"})
        self.assertEqual(response.status_code, 409)
        self.assertNotIn("private provider details", response.text)

    def test_delete_is_owner_scoped_and_returns_no_body(self):
        self.reply.return_value = httpx.Response(200, json=[{"id": TRIP_ID, "user_id": OWNER}])
        response = self.client.delete(f"{BASE}/{TRIP_ID}")
        self.assertEqual(response.status_code, 204)
        self.assertEqual(response.content, b"")
        request, = self.requests
        self.assertEqual(request.method, "DELETE")
        self.assertEqual(request.url.path, "/rest/v1/trips")
        self.assertEqual(request.url.params["id"], f"eq.{TRIP_ID}")
        self.assertEqual(request.url.params["user_id"], f"eq.{OWNER}")
        self.assertEqual(request.url.params["select"], "id,user_id")
        self.assertEqual(request.headers["Prefer"], "return=representation")
        self.assertEqual(request.headers["Content-Profile"], "public")

    def test_mutations_require_authentication_and_demo_configuration(self):
        for method in ("PATCH", "DELETE"):
            kwargs = {"json": {"title": "Update"}} if method == "PATCH" else {}
            for header in ("", "Bearer wrong", "Basic wrong"):
                with self.subTest(method=method, header=header):
                    response = self.client.request(
                        method, f"{BASE}/{TRIP_ID}", headers={"Authorization": header}, **kwargs,
                    )
                    self.assertEqual(response.status_code, 401)
                    self.assertEqual(response.headers["WWW-Authenticate"], "Bearer")
            with patch.dict(os.environ, {"TRIP_DEMO_TOKEN": ""}):
                response = self.client.request(method, f"{BASE}/{TRIP_ID}", **kwargs)
                self.assertEqual(response.status_code, 503)
            response = self.client.request(method, f"{BASE}/not-a-uuid", **kwargs)
            self.assertEqual(response.status_code, 422)
        self.assertEqual(self.requests, [])

    def test_mutation_provider_and_network_errors_are_safe(self):
        for method in ("PATCH", "DELETE"):
            kwargs = {"json": {"title": "Update"}} if method == "PATCH" else {}
            failures = [httpx.Response(status, text="private provider details")
                        for status in (400, 401, 403, 409, 429, 500, 503)]
            failures.extend([
                httpx.ConnectError("private provider details"),
                httpx.ReadTimeout("private provider details"),
            ])
            for failure in failures:
                with self.subTest(method=method, failure=type(failure)):
                    self.reply.side_effect = (
                        [httpx.Response(200, json=[ROW]), failure] if method == "PATCH"
                        else [failure]
                    )
                    self.assert_safe_unavailable(self.client.request(
                        method, f"{BASE}/{TRIP_ID}", **kwargs,
                    ))

    def test_mutation_malformed_or_cross_owner_responses_are_safe(self):
        for method in ("PATCH", "DELETE"):
            kwargs = {"json": {"title": "Update"}} if method == "PATCH" else {}
            invalid = [
                {"error": "private provider details"}, [{"id": TRIP_ID}],
                [{**ROW, "user_id": OTHER}], [ROW, ROW],
                [{**ROW, "id": OTHER}],
            ]
            for body in invalid:
                with self.subTest(method=method, body=body):
                    failure = httpx.Response(200, json=body)
                    self.reply.side_effect = (
                        [httpx.Response(200, json=[ROW]), failure] if method == "PATCH"
                        else [failure]
                    )
                    self.assert_safe_unavailable(self.client.request(
                        method, f"{BASE}/{TRIP_ID}", **kwargs,
                    ))

    def test_crud_sequence_preserves_fields_rejects_invalid_edits_and_removes_trip(self):
        # Stateful transport checks API behavior, not real PostgreSQL persistence/cascades.
        saved = []

        def database(request):
            if request.method == "POST":
                saved.append({**ROW, **json.loads(request.content)})
                return httpx.Response(201, json=saved)
            if request.method == "PATCH":
                saved[0].update(json.loads(request.content))
                return httpx.Response(200, json=saved)
            if request.method == "DELETE":
                deleted = [{"id": row["id"], "user_id": row["user_id"]} for row in saved]
                saved.clear()
                return httpx.Response(200, json=deleted)
            return httpx.Response(200, json=saved)

        self.reply.side_effect = database
        self.assertEqual(self.client.post(BASE, json=PAYLOAD).status_code, 201)
        response = self.client.patch(f"{BASE}/{TRIP_ID}", json={"title": "Updated"})
        self.assertEqual(response.status_code, 200)
        expected = {**ROW, "title": "Updated"}
        self.assertEqual(response.json(), expected)
        invalid = self.client.patch(f"{BASE}/{TRIP_ID}", json={"budget_min": "999"})
        self.assertEqual(invalid.status_code, 422)
        self.assertEqual(self.client.get(f"{BASE}/{TRIP_ID}").json(), expected)
        self.assertEqual(self.client.get(BASE).json()["items"], [expected])
        self.assertEqual(self.client.delete(f"{BASE}/{TRIP_ID}").status_code, 204)
        self.assertEqual(self.client.get(BASE).json()["items"], [])
        self.assertEqual(self.client.get(f"{BASE}/{TRIP_ID}").status_code, 404)
        self.assertEqual(self.client.delete(f"{BASE}/{TRIP_ID}").status_code, 404)


if __name__ == "__main__":
    unittest.main()
