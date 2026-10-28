"""Week 3 offline evaluation and regression entry point. Never contacts a provider."""

import argparse
import hashlib
import json
import os
import platform
import subprocess
import sys
from importlib.metadata import version
from pathlib import Path
from unittest.mock import Mock, patch

import httpx
from fastapi.testclient import TestClient
from pydantic import ValidationError

with patch.dict(os.environ, {}, clear=True), patch("dotenv.load_dotenv"):
    from app.main import create_app

from app.preference_extraction import ExtractionResponse
from app.recommendations.evaluate_content import evaluate as evaluate_content
from app.recommendations.evaluate_hybrid import evaluate as evaluate_hybrid
from app.trip_schemas import TripResponse
from app.trips import get_trip_database

ROOT = Path(__file__).resolve().parent
FIXTURES = ROOT / "fixtures"
MANIFEST = FIXTURES / "extraction/manifest.json"
BASELINE = ROOT.parent / "docs/evidence/week3-evaluation.json"
HTTP_CLIENT = httpx.Client
OWNER = "23000000-0000-4000-8000-000000000001"
TOKEN = "offline-week3-demo-token-12345678901234567890"
PRIVATE = "do-not-echo-provider-detail"
TEST_FILES = [
    "test_deepseek.py",
    "test_preference_extraction.py",
    "test_recommendation_contracts.py",
    "test_content_based.py",
    "test_hybrid_recommendations.py",
    "test_week3_evaluation.py",
]


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def digest(value):
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, ensure_ascii=True).encode()
    ).hexdigest()


def extraction_cases():
    successes = [
        row
        | {
            "stub": {"kind": "output", "content": row["provider"]},
            "status": 200,
            "provider_calls": 1,
        }
        for row in read_json(FIXTURES / "extraction/cases.json")
    ]
    return successes + read_json(FIXTURES / "extraction/regressions-v1.json")


def run_extraction_case(case):
    """Exercise real FastAPI/helper through an in-memory provider transport."""
    stub = case["stub"]
    environment = {
        "TRIP_AUTH_MODE": "demo",
        "SUPABASE_URL": "http://127.0.0.1:54321",
        "TRIP_DEMO_USER_ID": OWNER,
        "TRIP_DEMO_TOKEN": TOKEN,
        "DEEPSEEK_API_KEY": "dummy-week3-key-only",
        "DEEPSEEK_MODEL": "deepseek-flash",
        "DEEPSEEK_TIMEOUT_MS": "30000",
    }
    if stub["kind"] == "missing_key":
        environment.pop("DEEPSEEK_API_KEY")
    if stub["kind"] == "invalid_configuration":
        environment["DEEPSEEK_TIMEOUT_MS"] = "invalid"
    captured = []

    def handle(request):
        if (
            request.url != "https://api.deepseek.com/chat/completions"
            or request.method != "POST"
        ):
            raise AssertionError("Unexpected outbound request blocked")
        body = json.loads(request.content)
        captured.append({"payload": body, "timeout": request.extensions.get("timeout")})
        if stub["kind"] == "timeout":
            raise httpx.ReadTimeout(PRIVATE)
        if stub["kind"] == "network":
            raise httpx.ConnectError(PRIVATE)
        if stub["kind"] == "http_error":
            return httpx.Response(stub["status"], text=PRIVATE)
        if stub["kind"] == "malformed":
            content, finish = "{" + PRIVATE, "stop"
        elif stub["kind"] == "truncated":
            content, finish = '{"tags": [', "length"
        else:
            content, finish = json.dumps(stub.get("content", {})), "stop"
        return httpx.Response(
            200,
            json={
                "choices": [{"finish_reason": finish, "message": {"content": content}}]
            },
        )

    def factory(**kwargs):
        return HTTP_CLIENT(transport=httpx.MockTransport(handle), **kwargs)

    with (
        patch.dict(os.environ, environment, clear=True),
        patch("app.main.load_dotenv"),
        patch("app.deepseek.load_dotenv"),
        patch(
            "httpx.HTTPTransport.handle_request",
            side_effect=AssertionError("Real HTTP blocked"),
        ),
    ):
        app = create_app()
        saved = TripResponse(
            id="23000000-0000-4000-8000-000000000003",
            user_id=OWNER,
            title="Existing evaluation trip",
            start_date="2026-11-01",
            end_date="2026-11-01",
            budget_min="0",
            budget_max="500",
            preferred_tags=["heritage"],
            status="draft",
            estimated_total_cost=None,
        )
        store = Mock()
        store.retrieve_trip.return_value = saved
        app.dependency_overrides[get_trip_database] = lambda: store
        with (
            TestClient(app, headers={"Authorization": f"Bearer {TOKEN}"}) as client,
            patch("app.deepseek.httpx.Client", side_effect=factory),
        ):
            before = client.get(f"/api/v1/trips/{saved.id}").json()
            response = client.post(
                "/api/v1/preferences/extract",
                json={
                    "prompt": case["prompt"],
                    "explicit_preferences": case.get("explicit_preferences", {}),
                },
            )
            after = client.get(f"/api/v1/trips/{saved.id}").json()
    checks = {
        "http_status": response.status_code == case["status"],
        "provider_call_count": len(captured) == case["provider_calls"],
        "saved_trip_unchanged": before == after,
        "no_trip_writes": not store.create_trip.called
        and not store.update_trip.called
        and not store.delete_trip.called,
        "sanitized_response": not any(
            value in response.text for value in (PRIVATE, TOKEN, "dummy-week3-key-only")
        ),
    }
    if case["status"] == 200:
        try:
            parsed = ExtractionResponse.model_validate(response.json())
            actual = parsed.preferences.model_dump(mode="json")
            checks["schema_valid"] = True
            checks["confirmation_required"] = parsed.requires_confirmation is True
            checks["trip_budget_scope"] = actual["budget_scope"] == "trip_total"
            expected_missing = (["budget"] if actual["budget_min"] is None else []) + (
                ["group_type"] if actual["group_type"] is None else []
            )
            checks["missing_fields"] = parsed.missing_fields == expected_missing
            for key, value in case["expected"].items():
                checks["field:" + key] = actual.get(key) == value
        except (ValidationError, ValueError):
            checks["schema_valid"] = False
    else:
        error = response.json().get("detail", {})
        checks["error_code"] = (
            isinstance(error, dict) and error.get("code") == case["code"]
        )
        checks["manual_fallback"] = (
            isinstance(error, dict) and error.get("manual_fallback") is True
        )
    return {
        "id": case["id"],
        "expected_status": case["status"],
        "actual_status": response.status_code,
        "passed": all(checks.values()),
        "checks": checks,
        "failures": [key for key, passed in checks.items() if not passed],
    }, captured


def run_evaluation():
    manifest = read_json(MANIFEST)
    cases = extraction_cases()
    rows, first_request = [], None
    for case in cases:
        row, captured = run_extraction_case(case)
        rows.append(row)
        if first_request is None and captured:
            first_request = captured[0]
    payload = first_request["payload"]
    prompt = payload["messages"][0]["content"]
    config = {key: value for key, value in payload.items() if key != "messages"}
    config["timeout_seconds"] = first_request["timeout"]
    fixture_paths = [
        "extraction/manifest.json",
        "extraction/cases.json",
        "extraction/regressions-v1.json",
        "recommendations/evaluation_cases.json",
        "hybrid/dataset.json",
    ]
    hashes = {name: digest(read_json(FIXTURES / name)) for name in fixture_paths}
    content = evaluate_content()
    hybrid = evaluate_hybrid(read_json(FIXTURES / "hybrid/dataset.json"))
    content_checks = [
        {
            "id": case["case"],
            "passed": case["eligible_examples_returned"]
            and case["empty_result_correct"]
            and case["reproducible"],
            "result_count": case["result_count"],
            "top_location_id": case["ranking"][0]["location_id"]
            if case["ranking"]
            else None,
        }
        for case in content["cases"]
    ]
    failures = [
        {"id": row["id"], "checks": row["failures"]}
        for row in rows
        if not row["passed"]
    ]
    failures.extend(
        {"id": row["id"], "checks": ["recommendation_acceptance"]}
        for row in content_checks
        if not row["passed"]
    )
    field_checks = [
        passed
        for row in rows
        for key, passed in row["checks"].items()
        if key.startswith("field:")
    ]
    return {
        "fixture_revision": manifest["fixture_revision"],
        "implementation_base": manifest["implementation_base"],
        "mode": manifest["evaluation_mode"],
        "live_provider_evaluation": "not_performed",
        "identifiers": {
            "prompt_sha256": hashlib.sha256(prompt.encode()).hexdigest(),
            "configuration_sha256": digest(config),
            "requested_model": payload["model"],
            "provider_model_revision": "unknown_not_contacted",
            "configuration": config,
            "fixture_sha256": hashes,
        },
        "environment": {
            "python": platform.python_version(),
            "platform": platform.system(),
            "packages": {
                name: version(name)
                for name in ("fastapi", "pydantic", "httpx", "httpx2", "numpy")
            },
        },
        "extraction": {
            "case_count": len(rows),
            "accepted_cases": sum(case["status"] == 200 for case in cases),
            "rejected_cases": sum(case["status"] != 200 for case in cases),
            "passed": sum(row["passed"] for row in rows),
            "field_checks_passed": sum(field_checks),
            "field_checks_total": len(field_checks),
            "cases": rows,
        },
        "content": {
            "model_version": content["model_version"],
            "case_count": len(content_checks),
            "cases": content_checks,
        },
        "hybrid": {
            key: hybrid[key]
            for key in (
                "model_version",
                "seed",
                "training_digest",
                "training_event_count",
                "held_out_event_count",
                "evaluation_users",
                "summary",
            )
        },
        "failures": failures,
        "limitations": [
            "Mocked extraction is not live model accuracy or prompt-injection robustness.",
            "Synthetic recommendation clusters are intentionally recoverable; no real-user quality claim.",
            "Model alias does not identify an actually evaluated provider model revision.",
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output", type=Path, default=ROOT / "test-results/week3-evaluation.json"
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Also run the existing mocked/model regression suite",
    )
    args = parser.parse_args()
    report = run_evaluation()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(
        f"Extraction: {report['extraction']['passed']}/{report['extraction']['case_count']}; "
        f"content: {report['content']['case_count']} cases; failures: {len(report['failures'])}"
    )
    status = int(bool(report["failures"]))
    if args.check:
        status = max(
            status,
            subprocess.run(
                [sys.executable, "-m", "pytest", *TEST_FILES, "-q"],
                cwd=ROOT,
                check=False,
            ).returncode,
        )
    return status


if __name__ == "__main__":
    raise SystemExit(main())
