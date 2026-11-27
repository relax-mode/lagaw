"""Tests for #204 Cloud Run latest-revision traffic verification and CI wiring."""

import importlib.util
import io
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "verify_cloudrun_traffic", ROOT / "scripts" / "verify_cloudrun_traffic.py"
)
traffic = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(traffic)

STAGING_IMAGE = "asia-southeast1-docker.pkg.dev/relax-mode-lagaw/lagaw/service:staging-0000000"
PROD_IMAGE = "asia-southeast1-docker.pkg.dev/relax-mode-lagaw/lagaw/service:0000000"


def _service_payload(
    *,
    service: str = "lagaw-api-staging",
    latest: str = "lagaw-api-staging-00052-abc",
    entries: list | None = None,
    image: str = STAGING_IMAGE,
) -> dict:
    if entries is None:
        entries = [
            {
                "latestRevision": True,
                "percent": 100,
                "revisionName": latest,
            }
        ]
    return {
        "metadata": {"name": service},
        "status": {
            "latestReadyRevisionName": latest,
            "traffic": entries,
        },
        "spec": {
            "template": {
                "spec": {
                    "containers": [{"image": image}],
                }
            }
        },
    }


def test_accepts_100_percent_traffic_on_latest_ready_revision():
    summary = traffic.verify(
        _service_payload(),
        service="lagaw-api-staging",
        expected_image=STAGING_IMAGE,
    )
    assert "lagaw-api-staging" in summary
    assert "lagaw-api-staging-00052-abc" in summary


def test_accepts_zero_percent_tagged_canary_alongside_100_percent_latest():
    payload = _service_payload(
        entries=[
            {
                "latestRevision": True,
                "percent": 100,
                "revisionName": "lagaw-api-staging-00052-abc",
            },
            {
                "percent": 0,
                "revisionName": "lagaw-api-staging-00051-xyz",
                "tag": "aifail",
            },
        ]
    )
    summary = traffic.verify(payload, service="lagaw-api-staging")
    assert "100%" in summary


def test_rejects_pinned_named_revision_even_if_it_matches_latest_name():
    payload = _service_payload(
        entries=[
            {
                "percent": 100,
                "revisionName": "lagaw-api-staging-00052-abc",
            }
        ]
    )
    with pytest.raises(ValueError, match="pinned"):
        traffic.verify(payload, service="lagaw-api-staging")


def test_rejects_inc5_stale_pinned_revision():
    payload = _service_payload(
        latest="lagaw-api-staging-00052-abc",
        entries=[
            {
                "percent": 100,
                "revisionName": "lagaw-api-staging-00035-xp9",
            }
        ],
    )
    with pytest.raises(ValueError, match="lagaw-api-staging-00035-xp9"):
        traffic.verify(payload, service="lagaw-api-staging")


def test_rejects_split_traffic():
    payload = _service_payload(
        entries=[
            {
                "latestRevision": True,
                "percent": 80,
                "revisionName": "lagaw-api-staging-00052-abc",
            },
            {
                "percent": 20,
                "revisionName": "lagaw-api-staging-00051-xyz",
            },
        ]
    )
    with pytest.raises(ValueError, match="20%"):
        traffic.verify(payload, service="lagaw-api-staging")


def test_rejects_sibling_service_revision_prefix():
    payload = _service_payload(
        service="lagaw-api",
        latest="lagaw-api-staging-00052-abc",
        image=PROD_IMAGE,
    )
    with pytest.raises(ValueError, match="does not belong to lagaw-api"):
        traffic.verify(payload, service="lagaw-api", expected_image=PROD_IMAGE)


def test_rejects_mismatched_image():
    payload = _service_payload(image=STAGING_IMAGE)
    with pytest.raises(ValueError, match="does not match"):
        traffic.verify(
            payload,
            service="lagaw-api-staging",
            expected_image=PROD_IMAGE,
        )


@pytest.mark.parametrize(
    "bad_payload",
    [
        [],
        {"status": {}},
        {"status": {"latestReadyRevisionName": "lagaw-api-00041-465", "traffic": []}},
        {
            "status": {
                "latestReadyRevisionName": "lagaw-api-00041-465",
                "traffic": [
                    {
                        "latestRevision": True,
                        "percent": True,
                        "revisionName": "lagaw-api-00041-465",
                    }
                ],
            }
        },
        {
            "metadata": {"name": "lagaw-api-staging"},
            "status": {
                "latestReadyRevisionName": "lagaw-api-00041-465",
                "traffic": [
                    {
                        "latestRevision": True,
                        "percent": 100,
                        "revisionName": "lagaw-api-00041-465",
                    }
                ],
            },
        },
    ],
)
def test_rejects_malformed_service_payloads(bad_payload):
    with pytest.raises(ValueError):
        traffic.verify(bad_payload, service="lagaw-api")


def test_cli_returns_zero_on_valid_input_and_one_on_failure(monkeypatch, capsys):
    monkeypatch.setattr(
        "sys.stdin",
        io.StringIO(json.dumps(_service_payload(service="lagaw-api", latest="lagaw-api-00042-aaa", image=PROD_IMAGE))),
    )
    assert traffic.main(["--service", "lagaw-api", "--expected-image", PROD_IMAGE]) == 0
    assert "100% traffic routed" in capsys.readouterr().out

    monkeypatch.setattr("sys.stdin", io.StringIO("not-json"))
    assert traffic.main(["--service", "lagaw-api"]) == 1
    assert "::error::" in capsys.readouterr().out


def test_ci_workflow_routes_and_verifies_traffic_and_sets_panel_capacity():
    workflow = (ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")

    assert "scripts/verify_cloudrun_traffic.py" in workflow
    assert "backend/*|scripts/smoke_deployed.py|scripts/verify_cloudrun_traffic.py" in workflow

    staging_start = workflow.index("  deploy-staging:")
    prod_start = workflow.index("  deploy-backend:")
    web_start = workflow.index("  deploy-web:")

    staging_job = workflow[staging_start:prod_start]
    prod_job = workflow[prod_start:web_start]

    # Staging: scale-to-zero kept, max-instances aligned to 4, traffic routed and verified before smoke.
    assert "--min-instances=0" in staging_job
    assert "--max-instances=4" in staging_job
    assert "--concurrency=20" in staging_job
    staging_route = staging_job.index("gcloud run services update-traffic lagaw-api-staging")
    staging_verify = staging_job.index("python3 scripts/verify_cloudrun_traffic.py")
    staging_smoke = staging_job.index("python3 scripts/smoke_deployed.py staging")
    assert staging_route < staging_verify < staging_smoke
    assert "--to-latest" in staging_job[staging_route:staging_verify]

    # Production: 1 warm instance, max 4 instances, concurrency 20, traffic routed and verified before smoke.
    assert "--min-instances=1" in prod_job
    assert "--max-instances=4" in prod_job
    assert "--concurrency=20" in prod_job
    prod_route = prod_job.index("gcloud run services update-traffic lagaw-api")
    prod_verify = prod_job.index("python3 scripts/verify_cloudrun_traffic.py")
    prod_smoke = prod_job.index("python3 scripts/smoke_deployed.py production")
    assert prod_route < prod_verify < prod_smoke
    assert "--to-latest" in prod_job[prod_route:prod_verify]
