"""Offline HTTP contract and failure checks for issue #26."""

import json
import os
import unittest
from unittest.mock import Mock, patch

import httpx
from fastapi.testclient import TestClient

with patch.dict(os.environ, {}, clear=True), patch("dotenv.load_dotenv"):
    from app.main import create_app

HTTP_CLIENT = httpx.Client
OWNER = "26000000-0000-4000-8000-000000000001"
TRIP = "26000000-0000-4000-8000-000000000002"
LOCATION = "26000000-0000-4000-8000-000000000003"
ITEM = "26000000-0000-4000-8000-000000000004"
OTHER = "26000000-0000-4000-8000-000000000005"
TOKEN = "offline-issue26-token-12345678901234567890"
URL = f"/api/v1/trips/{TRIP}/items"
TRIP_ROW = {
    "id": TRIP, "user_id": OWNER, "title": "Offline trip",
    "start_date": "2026-11-01", "end_date": "2026-11-02",
    "budget_min": "0.00", "budget_max": "500.00", "transportation_mode": None,
    "group_type": None, "preferred_tags": [], "status": "draft", "estimated_total_cost": None,
}
LOCATION_ROW = {
    "id": LOCATION, "name": "Offline location", "category": "heritage",
    "description": None, "vibe_tags": [], "address": None,
    "latitude": None, "longitude": None, "opening_hours": {},
    "estimated_cost_min": None, "estimated_cost_max": None,
    "typical_visit_duration": None, "suitable_group_types": [],
    "image_url": None, "is_active": True,
}
BODY = {"location_id": LOCATION, "day_number": 1, "visit_order": 1}
ITEM_ROW = {
    **BODY, "id": ITEM, "trip_id": TRIP, "location": LOCATION_ROW,
    "arrival_time": None, "departure_time": None, "estimated_travel_time": None,
    "estimated_cost": None, "recommendation_score": None, "recommendation_reason": None,
}


class TripItemApiTests(unittest.TestCase):
    def setUp(self):
        environment = patch.dict(os.environ, {
            "SUPABASE_URL": "http://127.0.0.1:54321",
            "SUPABASE_SERVICE_ROLE_KEY": "sb_secret_offline_only",
            "TRIP_AUTH_MODE": "demo",
            "TRIP_DEMO_USER_ID": OWNER, "TRIP_DEMO_TOKEN": TOKEN,
            "CORS_ALLOWED_ORIGINS": "http://localhost:3000",
        }, clear=True)
        environment.start()
        self.addCleanup(environment.stop)
        with patch("app.main.load_dotenv"):
            self.application = create_app()
        dotenv = patch("app.database.load_dotenv")
        dotenv.start()
        self.addCleanup(dotenv.stop)
        self.client = TestClient(
            self.application, headers={"Authorization": f"Bearer {TOKEN}"},
        )
        self.addCleanup(self.client.close)
        self.requests = []
        self.reply = Mock()

        def handle(request):
            self.requests.append(request)
            return self.reply(request)

        def factory(**kwargs):
            return HTTP_CLIENT(transport=httpx.MockTransport(handle), **kwargs)

        transport = patch("app.database.httpx.Client", side_effect=factory)
        transport.start()
        self.addCleanup(transport.stop)

    def responses(self, *bodies, final_status=200):
        self.reply.side_effect = [
            httpx.Response(final_status if index == len(bodies) - 1 else 200, json=body)
            for index, body in enumerate(bodies)
        ]

    def unavailable(self, response):
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json(), {
            "detail": "Trips are temporarily unavailable. Please try again later.",
        })
        for secret in (TOKEN, "sb_secret_offline_only", "private provider details"):
            self.assertNotIn(secret, response.text)

    def test_add_uses_server_trip_and_returns_nested_location(self):
        self.responses([TRIP_ROW], [LOCATION_ROW], [ITEM_ROW], final_status=201)
        response = self.client.post(URL, json=BODY)
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json(), ITEM_ROW)
        owner, location, write = self.requests
        self.assertEqual(owner.url.params["id"], f"eq.{TRIP}")
        self.assertEqual(owner.url.params["user_id"], f"eq.{OWNER}")
        self.assertEqual(location.url.params["id"], f"eq.{LOCATION}")
        self.assertEqual(location.url.params["is_active"], "eq.true")
        self.assertEqual(json.loads(write.content), {**BODY, "trip_id": TRIP})
        self.assertEqual(write.url.path, "/rest/v1/itinerary_items")
        self.assertIn("location:locations(", write.url.params["select"])

    def test_list_is_trip_scoped_ordered_and_paginated(self):
        self.responses([TRIP_ROW], [ITEM_ROW])
        response = self.client.get(URL + "?limit=2&offset=3")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"items": [ITEM_ROW], "limit": 2, "offset": 3})
        params = self.requests[-1].url.params
        self.assertEqual(params["trip_id"], f"eq.{TRIP}")
        self.assertEqual(params["order"], "day_number.asc,visit_order.asc,id.asc")
        self.assertEqual((params["limit"], params["offset"]), ("2", "3"))

    def test_empty_owned_trip_returns_empty_page(self):
        self.responses([TRIP_ROW], [])
        self.assertEqual(self.client.get(URL).json(), {"items": [], "limit": 10, "offset": 0})

    def test_all_methods_require_demo_authorization_before_database(self):
        for method, suffix, kwargs in (
            ("GET", "", {}), ("POST", "", {"json": BODY}), ("DELETE", f"/{ITEM}", {}),
        ):
            for authorization in ("", "Bearer wrong", "Basic wrong"):
                with self.subTest(method=method, authorization=authorization):
                    response = self.client.request(
                        method, URL + suffix, headers={"Authorization": authorization}, **kwargs,
                    )
                    self.assertEqual(response.status_code, 401)
                    self.assertEqual(response.headers["www-authenticate"], "Bearer")
        self.assertEqual(self.requests, [])

    def test_disabled_demo_context_returns_503(self):
        os.environ.pop("TRIP_DEMO_USER_ID")
        self.assertEqual(self.client.get(URL).status_code, 503)
        self.assertEqual(self.requests, [])

    def test_missing_or_other_owner_parent_stops_all_child_access(self):
        for method, suffix, kwargs in (
            ("GET", "", {}), ("POST", "", {"json": BODY}), ("DELETE", f"/{ITEM}", {}),
        ):
            self.requests.clear()
            self.responses([])
            response = self.client.request(method, URL + suffix, **kwargs)
            self.assertEqual(response.status_code, 404)
            self.assertEqual(response.json(), {"detail": "Trip not found."})
            self.assertEqual(len(self.requests), 1)
            self.assertEqual(self.requests[0].url.params["user_id"], f"eq.{OWNER}")

    def test_missing_active_location_does_not_insert(self):
        self.responses([TRIP_ROW], [])
        self.assertEqual(self.client.post(URL, json=BODY).status_code, 404)
        self.assertEqual(len(self.requests), 2)

    def test_out_of_trip_day_does_not_insert(self):
        self.responses([TRIP_ROW])
        response = self.client.post(URL, json={**BODY, "day_number": 3})
        self.assertEqual(response.status_code, 422)
        self.assertEqual(len(self.requests), 1)

    def test_body_rejects_invalid_ids_positions_and_server_owned_fields(self):
        bodies = [{}, {**BODY, "location_id": "bad"}, {**BODY, "trip_id": OTHER},
                  {**BODY, "id": OTHER}, {**BODY, "user_id": OTHER},
                  {**BODY, "recommendation_score": 1}, {**BODY, "arrival_time": "09:00"}]
        for field in ("day_number", "visit_order"):
            bodies.extend({**BODY, field: value} for value in (
                0, -1, None, True, 1.5, "1", 2147483648,
            ))
        for body in bodies:
            with self.subTest(body=body):
                response = self.client.post(URL, json=body)
                self.assertEqual(response.status_code, 422)
                self.assertTrue(all("input" not in error for error in response.json()["detail"]))
        self.assertEqual(self.requests, [])

    def test_malformed_json_and_invalid_path_or_pagination(self):
        self.assertEqual(self.client.post(
            URL, content="broken", headers={"Content-Type": "application/json"},
        ).status_code, 422)
        for suffix in ("?limit=0", "?limit=101", "?offset=-1"):
            self.assertEqual(self.client.get(URL + suffix).status_code, 422)
        self.assertEqual(self.client.get("/api/v1/trips/bad/items").status_code, 422)
        self.assertEqual(self.client.delete(URL + "/bad").status_code, 422)
        self.assertEqual(self.requests, [])

    def test_unique_and_racing_fk_conflicts_are_safe(self):
        for code in ("23505", "23503"):
            self.responses([TRIP_ROW], [LOCATION_ROW], {
                "code": code, "details": "private provider details",
            }, final_status=409)
            response = self.client.post(URL, json=BODY)
            self.assertEqual(response.status_code, 409)
            self.assertNotIn("private provider details", response.text)

    def test_remove_scopes_trip_and_item_and_never_deletes_location(self):
        self.responses([TRIP_ROW], [{"id": ITEM, "trip_id": TRIP}])
        response = self.client.delete(URL + f"/{ITEM}")
        self.assertEqual(response.status_code, 204)
        self.assertEqual(response.content, b"")
        request = self.requests[-1]
        self.assertEqual(request.method, "DELETE")
        self.assertEqual(request.url.path, "/rest/v1/itinerary_items")
        self.assertEqual(request.url.params["id"], f"eq.{ITEM}")
        self.assertEqual(request.url.params["trip_id"], f"eq.{TRIP}")

    def test_missing_or_wrong_trip_item_returns_404(self):
        self.responses([TRIP_ROW], [])
        self.assertEqual(self.client.delete(URL + f"/{ITEM}").status_code, 404)

    def test_invalid_provider_items_are_not_exposed(self):
        bodies = [
            {"error": "private provider details"}, [{"id": ITEM}],
            [{**ITEM_ROW, "trip_id": OTHER}],
            [{**ITEM_ROW, "location_id": OTHER}],
            [{**ITEM_ROW, "location": None}], [ITEM_ROW, ITEM_ROW],
        ]
        for body in bodies:
            self.responses([TRIP_ROW], body)
            self.unavailable(self.client.get(URL))

    def test_invalid_create_representations_fail_safely(self):
        for status, rows in (
            (200, [ITEM_ROW]), (201, []),
            (201, [{**ITEM_ROW, "visit_order": 2}]),
        ):
            self.responses([TRIP_ROW], [LOCATION_ROW], rows, final_status=status)
            self.unavailable(self.client.post(URL, json=BODY))

    def test_inactive_or_mismatched_location_response_is_not_used(self):
        for location in ({**LOCATION_ROW, "is_active": False}, {**LOCATION_ROW, "id": OTHER}):
            self.responses([TRIP_ROW], [location])
            self.unavailable(self.client.post(URL, json=BODY))

    def test_database_failures_at_each_stage_are_safe(self):
        for method, suffix, kwargs, prefix in (
            ("GET", "", {}, [[TRIP_ROW]]),
            ("POST", "", {"json": BODY}, [[TRIP_ROW], [LOCATION_ROW]]),
            ("DELETE", f"/{ITEM}", {}, [[TRIP_ROW]]),
        ):
            for status in (400, 401, 403, 409, 429, 500, 503):
                self.responses(*prefix, {"details": "private provider details"}, final_status=status)
                self.unavailable(self.client.request(method, URL + suffix, **kwargs))
        self.reply.side_effect = httpx.ReadTimeout("private provider details")
        self.unavailable(self.client.get(URL))

    def test_location_lookup_failure_is_safe(self):
        self.responses([TRIP_ROW], {"details": "private provider details"}, final_status=500)
        self.unavailable(self.client.post(URL, json=BODY))

    def test_malformed_json_from_provider_is_safe(self):
        self.reply.side_effect = [
            httpx.Response(200, json=[TRIP_ROW]), httpx.Response(200, text="broken"),
        ]
        self.unavailable(self.client.get(URL))

    def test_delete_rejects_unexpected_returned_rows(self):
        for rows in ([{"id": OTHER, "trip_id": TRIP}], {"id": ITEM}, [ITEM_ROW]):
            self.responses([TRIP_ROW], rows)
            self.unavailable(self.client.delete(URL + f"/{ITEM}"))

    def test_retired_location_can_be_read_in_existing_itinerary(self):
        historical = {**ITEM_ROW, "location": {**LOCATION_ROW, "is_active": False}}
        self.responses([TRIP_ROW], [historical])
        self.assertEqual(self.client.get(URL).json()["items"], [historical])

    def test_handled_error_has_approved_cors_header(self):
        self.responses([])
        response = self.client.get(URL, headers={"Origin": "http://localhost:3000"})
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.headers["access-control-allow-origin"], "http://localhost:3000")
