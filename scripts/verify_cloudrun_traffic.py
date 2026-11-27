"""Verify Cloud Run serves 100% of traffic from the latest ready revision.

Reads the projected JSON output of `gcloud run services describe` from stdin:
  --format='json(metadata.name,status.latestReadyRevisionName,status.traffic,spec.template.spec.containers[0].image)'

Fails closed (exit 1) when traffic is pinned to a named revision, split across
revisions, missing, or serving an unexpected container image. Never prints raw
service JSON, environment variables, or credentials.
"""

import argparse
import json
import sys
from typing import Any

KNOWN_SERVICES = ("lagaw-api-staging", "lagaw-api")


def _check_revision_matches_service(revision: str, service: str) -> None:
    other_services = [
        other
        for other in KNOWN_SERVICES
        if other != service and other.startswith(service + "-")
    ]
    if not revision.startswith(service + "-") or any(
        revision.startswith(other + "-") for other in other_services
    ):
        raise ValueError(
            f"Latest ready revision {revision!r} does not belong to {service}."
        )


def verify(
    payload: Any,
    *,
    service: str,
    expected_image: str = "",
) -> str:
    """Validate projected Cloud Run service JSON and return a sanitized summary."""
    if not isinstance(payload, dict):
        raise ValueError("Cloud Run service description must be a JSON object.")

    metadata = payload.get("metadata")
    if isinstance(metadata, dict):
        reported_name = metadata.get("name")
        if reported_name and reported_name != service:
            raise ValueError(
                f"Expected service {service!r}, got {reported_name!r}."
            )

    status = payload.get("status")
    if not isinstance(status, dict):
        raise ValueError(f"{service}: missing status object in Cloud Run output.")

    latest = status.get("latestReadyRevisionName")
    if not isinstance(latest, str) or not latest.strip():
        raise ValueError(f"{service}: status.latestReadyRevisionName is missing.")
    latest = latest.strip()
    _check_revision_matches_service(latest, service)

    traffic = status.get("traffic")
    if not isinstance(traffic, list) or not traffic:
        raise ValueError(f"{service}: status.traffic is missing or empty.")

    total_percent = 0
    latest_percent = 0
    for entry in traffic:
        if not isinstance(entry, dict):
            raise ValueError(f"{service}: invalid traffic entry in Cloud Run output.")
        percent = entry.get("percent", 0)
        if isinstance(percent, bool) or not isinstance(percent, int) or not 0 <= percent <= 100:
            raise ValueError(f"{service}: invalid traffic percentage in Cloud Run output.")
        total_percent += percent
        if percent == 0:
            continue

        revision = entry.get("revisionName")
        if revision != latest:
            raise ValueError(
                f"{service}: {percent}% of traffic is routed to {revision!r} "
                f"instead of latest ready revision {latest!r}."
            )
        if entry.get("latestRevision") is not True:
            raise ValueError(
                f"{service}: traffic is pinned to named revision {revision!r} "
                "(latestRevision is not true)."
            )
        latest_percent += percent

    if total_percent != 100 or latest_percent != 100:
        raise ValueError(
            f"{service}: expected 100% traffic on latest ready revision {latest!r}, "
            f"got {latest_percent}% (total {total_percent}%)."
        )

    expected_image = expected_image.strip()
    if expected_image:
        spec = payload.get("spec")
        template = spec.get("template") if isinstance(spec, dict) else None
        pod_spec = template.get("spec") if isinstance(template, dict) else None
        containers = pod_spec.get("containers") if isinstance(pod_spec, dict) else None
        actual_image = (
            containers[0].get("image")
            if isinstance(containers, list)
            and containers
            and isinstance(containers[0], dict)
            else None
        )
        if actual_image != expected_image:
            raise ValueError(
                f"{service}: template image {actual_image!r} does not match "
                f"deployed image {expected_image!r}."
            )

    return f"{service}: 100% traffic routed to latest ready revision {latest}."


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Verify 100% of Cloud Run traffic serves the latest ready revision."
    )
    parser.add_argument("--service", required=True, help="Expected Cloud Run service name.")
    parser.add_argument(
        "--expected-image",
        default="",
        help="Optional expected spec.template.spec.containers[0].image tag.",
    )
    args = parser.parse_args(argv)

    try:
        raw = sys.stdin.read()
        payload = json.loads(raw)
        summary = verify(
            payload,
            service=args.service,
            expected_image=args.expected_image,
        )
    except ValueError as error:
        print(f"::error::{error}")
        return 1

    print(summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
