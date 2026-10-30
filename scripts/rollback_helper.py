"""Cloud Run traffic rollback helper for Lagaw. Dry-run unless every guard passes.

Usage (from the repository root):
  python scripts/rollback_helper.py status  --env staging|production [--limit N]
  python scripts/rollback_helper.py plan    --env E --to-revision NAME [--allow-same-image]
  python scripts/rollback_helper.py execute --env E --to-revision NAME [--allow-same-image]
        [--execute --confirm "E:NAME"] [--production-authorized-by TEXT]
  python scripts/rollback_helper.py restore --env E
        [--execute --confirm "E:latest"] [--production-authorized-by TEXT]

status and plan are read-only. execute and restore change traffic only when all of
--execute, an exact --confirm, ROLLBACK_AUTHORIZED=E, and (production) a non-empty
--production-authorized-by are present. Without --execute they print what they would run.
Project and region come from --project/--region or GCP_PROJECT_ID/GCP_REGION.
Only fixed fields from gcloud JSON are printed: no environment variables, secrets,
or raw gcloud output and no gcloud stderr.
"""

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

SERVICES = {"staging": "lagaw-api-staging", "production": "lagaw-api"}
ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = "supabase/migrations"
PROJECT_PATTERN = re.compile(r"[a-z][a-z0-9-]{4,28}[a-z0-9]")
REGION_PATTERN = re.compile(r"[a-z]+-[a-z]+[0-9]+")
REVISION_PATTERN = re.compile(r"[a-z][a-z0-9-]{0,61}[a-z0-9]")
COMMIT_PATTERN = re.compile(r"[0-9a-f]{7,40}")
DIGEST_PATTERN = re.compile(r"\S+@sha256:[0-9a-f]{64}")
SERVICE_FORMAT = "json(metadata.name,status.traffic,status.latestReadyRevisionName)"
REVISION_FORMAT = "json(metadata.name,metadata.creationTimestamp,metadata.labels,status.imageDigest)"
RECORD_EVENTS = ("failure_detected", "rollback_authorized", "traffic_moved",
                 "health_verified", "restore_started", "restored")

Runner = Callable[[Sequence[str]], tuple[int, str]]


class Refusal(Exception):
    """A validation or guard failed. Raised before any mutating command runs."""


@dataclass(frozen=True)
class Config:
    environment: str
    service: str
    project: str
    region: str


@dataclass(frozen=True)
class Revision:
    name: str
    created: str
    commit: str
    digest: str


@dataclass(frozen=True)
class Plan:
    current: Revision
    target: Revision
    warnings: tuple[str, ...]
    command: tuple[str, ...]
    restore_command: tuple[str, ...]


def run_subprocess(args: Sequence[str]) -> tuple[int, str]:
    """The only place that starts a process. List arguments, never a shell."""
    try:
        completed = subprocess.run(list(args), capture_output=True, text=True, check=False, timeout=180)
    except (OSError, subprocess.SubprocessError):
        return 127, ""
    return completed.returncode, completed.stdout


def utc_now() -> str:
    return datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def positive_int(value: str) -> int:
    try:
        number = int(value)
    except ValueError:
        raise argparse.ArgumentTypeError("must be an integer") from None
    if not 1 <= number <= 50:
        raise argparse.ArgumentTypeError("must be between 1 and 50")
    return number


def resolve_config(environment: str, project: str, region: str, environ: Mapping[str, str]) -> Config:
    if environment not in SERVICES:
        raise Refusal("environment must be staging or production.")
    project = project or environ.get("GCP_PROJECT_ID", "")
    region = region or environ.get("GCP_REGION", "")
    if not project:
        raise Refusal("GCP project is missing; pass --project or set GCP_PROJECT_ID.")
    if not region:
        raise Refusal("GCP region is missing; pass --region or set GCP_REGION.")
    # Values are not echoed back, so a malformed value never reaches output.
    if not PROJECT_PATTERN.fullmatch(project):
        raise Refusal("GCP project ID has an invalid format.")
    if not REGION_PATTERN.fullmatch(region):
        raise Refusal("GCP region has an invalid format.")
    return Config(environment, SERVICES[environment], project, region)


def check_revision_name(name: str, service: str) -> None:
    # A prefix match alone is not enough: "lagaw-api-staging-..." also starts with "lagaw-api-".
    # Exclude only more specific sibling services whose names extend this one.
    other_services = [other for other in SERVICES.values()
                      if other != service and other.startswith(service + "-")]
    if (not REVISION_PATTERN.fullmatch(name) or not name.startswith(service + "-")
            or any(name.startswith(other + "-") for other in other_services)):
        raise Refusal(f"revision name must be a revision of {service}.")


def _base(cfg: Config, *parts: str) -> list:
    return ["gcloud", "run", *parts, "--project", cfg.project, "--region", cfg.region]


def read_json(runner: Runner, cmd: Sequence[str], what: str):
    rc, out = runner(cmd)
    if rc != 0:
        raise Refusal(f"could not read {what} (gcloud exit {rc}); check names, project, region and gcloud login.")
    try:
        return json.loads(out)
    except ValueError:
        raise Refusal(f"could not parse {what} output.") from None


def read_service(runner: Runner, cfg: Config) -> tuple[dict, str]:
    """Return (traffic percent by revision, latest ready revision name)."""
    cmd = _base(cfg, "services", "describe", cfg.service) + [f"--format={SERVICE_FORMAT}"]
    data = read_json(runner, cmd, "service")
    status = data.get("status") or {}
    traffic = {}
    for entry in (status.get("traffic") or []):
        name = entry.get("revisionName")
        if name:
            traffic[name] = int(entry.get("percent", 0))
    return traffic, str(status.get("latestReadyRevisionName", ""))


def read_service_traffic(runner: Runner, cfg: Config) -> dict:
    return read_service(runner, cfg)[0]


def summarize_revision(raw: dict) -> Revision:
    """Keep only the fields the runbook needs; labels other than commit-sha are dropped."""
    meta = raw.get("metadata") or {}
    labels = meta.get("labels") or {}
    status = raw.get("status") or {}
    return Revision(
        name=str(meta.get("name", "")),
        created=str(meta.get("creationTimestamp", "")),
        commit=str(labels.get("commit-sha", "")),
        digest=str(status.get("imageDigest", "")),
    )


def describe_revision(runner: Runner, cfg: Config, name: str) -> Revision:
    # gcloud has no --service flag here; revision names are unique per project and region.
    cmd = _base(cfg, "revisions", "describe", name) + [f"--format={REVISION_FORMAT}"]
    raw = read_json(runner, cmd, f"revision {name}")
    owner = ((raw.get("metadata") or {}).get("labels") or {}).get("serving.knative.dev/service")
    if owner != cfg.service:
        raise Refusal(f"revision {name} does not belong to {cfg.service}.")
    return summarize_revision(raw)


def list_revisions(runner: Runner, cfg: Config, limit: int) -> list:
    cmd = _base(cfg, "revisions", "list", "--service", cfg.service, "--limit", str(limit))
    cmd.append(f"--format={REVISION_FORMAT}")
    data = read_json(runner, cmd, "revisions")
    revisions = [summarize_revision(item) for item in data]
    return sorted(revisions, key=lambda rev: rev.created, reverse=True)


def traffic_command(cfg: Config, to_revision: str | None) -> tuple[str, ...]:
    cmd = ["gcloud", "run", "services", "update-traffic", cfg.service,
           "--project", cfg.project, "--region", cfg.region]
    cmd += ["--to-revisions", f"{to_revision}=100"] if to_revision else ["--to-latest"]
    return tuple(cmd)


def migration_warnings(runner: Runner, target: Revision, current: Revision) -> list:
    warnings = []
    if not target.commit or not current.commit:
        return ["commit-sha label missing on target or current revision; migration compatibility is UNKNOWN."]
    if not COMMIT_PATTERN.fullmatch(target.commit) or not COMMIT_PATTERN.fullmatch(current.commit):
        return ["commit-sha label is not a commit hash; migration compatibility is UNKNOWN."]
    for sha in (target.commit, current.commit):
        rc, _out = runner(["git", "-C", str(ROOT), "cat-file", "-e", f"{sha}^{{commit}}"])
        if rc != 0:
            return [(f"commit {sha[:12]} is not in the local clone; fetch it and rerun. "
                     "migration compatibility is UNKNOWN.")]
    rc, out = runner(["git", "-C", str(ROOT), "diff", "--name-only",
                      target.commit, current.commit, "--", MIGRATIONS])
    if rc != 0:
        return ["git diff failed; migration compatibility is UNKNOWN."]
    files = [line.strip() for line in out.splitlines() if line.strip().startswith(MIGRATIONS + "/")]
    if files:
        warnings.append("supabase/migrations changed between target and current: " + ", ".join(files)
                        + ". Migrations are forward-only and rollback does not undo the schema; review each file.")
    return warnings


def build_plan(cfg: Config, runner: Runner, to_revision: str, allow_same_image: bool) -> Plan:
    check_revision_name(to_revision, cfg.service)
    traffic = read_service_traffic(runner, cfg)
    serving = [name for name, percent in traffic.items() if percent > 0]
    if len(serving) != 1 or traffic[serving[0]] != 100:
        raise Refusal("traffic is not 100% on one revision; resolve the split manually before a rollback.")
    current = describe_revision(runner, cfg, serving[0])
    if to_revision == current.name:
        raise Refusal("target is already the serving revision; nothing to roll back.")
    target = describe_revision(runner, cfg, to_revision)
    if not DIGEST_PATTERN.fullmatch(target.digest) or not DIGEST_PATTERN.fullmatch(current.digest):
        raise Refusal("image digest missing or malformed on target or current revision; cannot prove a different image.")
    warnings = []
    if target.digest == current.digest:
        if not allow_same_image:
            raise Refusal("target runs the same image digest as the current revision (config-only redeploy); "
                          "rolling back would be a no-op. Choose an older image or pass --allow-same-image.")
        warnings.append("same image digest: the rollback only restores the target's configuration.")
    elif target.commit and target.commit == current.commit:
        warnings.append("commit-sha labels match but image digests differ; build provenance is unverified.")
    warnings.extend(migration_warnings(runner, target, current))
    return Plan(current, target, tuple(warnings),
                traffic_command(cfg, to_revision), traffic_command(cfg, None))


def check_guards(args, cfg: Config, environ: Mapping[str, str], expected: str) -> None:
    if args.confirm != expected:
        raise Refusal(f"--confirm must exactly equal '{expected}'.")
    if environ.get("ROLLBACK_AUTHORIZED", "") != cfg.environment:
        raise Refusal(f"set ROLLBACK_AUTHORIZED={cfg.environment} to authorize a traffic change on {cfg.environment}.")
    if cfg.environment == "production" and not (args.production_authorized_by or "").strip():
        raise Refusal("production changes also need --production-authorized-by <text naming the approver>.")


def render_record(events: dict) -> str:
    rows = ["| Event | UTC timestamp |", "| --- | --- |"]
    rows += [f"| {name} | {events.get(name, '')} |" for name in RECORD_EVENTS]
    return "\n".join(rows)


def render_status(cfg: Config, traffic: dict, revisions: list, now: str) -> str:
    lines = [f"{cfg.service} ({cfg.environment}) traffic:"]
    lines += [f"  {name}: {percent}%" for name, percent in sorted(traffic.items())] or ["  none reported"]
    lines.append(f"recent revisions, newest first (snapshot {now}):")
    lines.append("  name | created | commit-sha | image digest | traffic")
    for rev in revisions:
        lines.append(f"  {rev.name} | {rev.created} | {rev.commit or 'missing'} | "
                     f"{rev.digest or 'missing'} | {traffic.get(rev.name, 0)}%")
    return "\n".join(lines)


def render_plan(cfg: Config, plan: Plan, now: str) -> str:
    cur, tgt = plan.current, plan.target
    lines = [
        f"PLAN ({cfg.environment}) generated {now}",
        f"project: {cfg.project}  region: {cfg.region}  service: {cfg.service}",
        f"current serving: {cur.name} | created {cur.created} | commit-sha {cur.commit or 'missing'} | digest {cur.digest}",
        f"target:          {tgt.name} | created {tgt.created} | commit-sha {tgt.commit or 'missing'} | digest {tgt.digest}",
        "checks passed: target exists; target is not serving; traffic is on one revision.",
    ]
    lines += [f"WARNING: {text}" for text in plan.warnings]
    lines += ["", "Traffic command (not run by plan or a dry run):", "  " + shlex.join(plan.command),
              "Restore command (not run by plan or a dry run):", "  " + shlex.join(plan.restore_command),
              "", "Timestamp record (UTC; fill in as events happen):",
              render_record({"failure_detected": "", "rollback_authorized": "", "traffic_moved": "",
                             "health_verified": "", "restore_started": "", "restored": ""})]
    return "\n".join(lines)


def cmd_status(args, cfg: Config, runner: Runner, now: str, environ) -> int:
    traffic = read_service_traffic(runner, cfg)
    revisions = list_revisions(runner, cfg, args.limit)
    print(render_status(cfg, traffic, revisions, now))
    return 0


def cmd_plan(args, cfg: Config, runner: Runner, now: str, environ) -> int:
    plan = build_plan(cfg, runner, args.to_revision, args.allow_same_image)
    print(render_plan(cfg, plan, now))
    return 0


def cmd_execute(args, cfg: Config, runner: Runner, now: str, environ) -> int:
    if args.execute:
        check_guards(args, cfg, environ, f"{cfg.environment}:{args.to_revision}")
    plan = build_plan(cfg, runner, args.to_revision, args.allow_same_image)
    print(render_plan(cfg, plan, now))
    if not args.execute:
        print("DRY RUN: no traffic changed. Add --execute, --confirm, ROLLBACK_AUTHORIZED and, for production, "
              "--production-authorized-by to apply.")
        return 0
    rc, _out = runner(plan.command)
    if rc != 0:
        print(f"traffic change failed (gcloud exit {rc}); run status before retrying.", file=sys.stderr)
        return 1
    if cfg.environment == "production":
        print(f"authorized by: {args.production_authorized_by.strip()}")
    print("traffic change issued; verify with status and scripts/smoke_deployed.py before closing.")
    print(render_record({"traffic_moved": now}))
    return 0


def cmd_restore(args, cfg: Config, runner: Runner, now: str, environ) -> int:
    if args.execute:
        check_guards(args, cfg, environ, f"{cfg.environment}:latest")
    traffic, latest_ready = read_service(runner, cfg)
    print(f"{cfg.service} ({cfg.environment}) traffic before restore (snapshot {now}):")
    print("\n".join(f"  {name}: {percent}%" for name, percent in sorted(traffic.items())) or "  none reported")
    # --to-latest sends traffic to the newest ready revision, which after a rollback is often the failed one.
    print(f"latest ready revision (restore target): {latest_ready or 'unknown'}")
    print("Restore only after that revision is the approved fix. Otherwise keep the rollback in place.")
    command = traffic_command(cfg, None)
    print("Restore command: " + shlex.join(command))
    if not args.execute:
        print("DRY RUN: no traffic changed. Add --execute, --confirm, ROLLBACK_AUTHORIZED and, for production, "
              "--production-authorized-by to apply.")
        return 0
    rc, _out = runner(command)
    if rc != 0:
        print(f"restore failed (gcloud exit {rc}); run status before retrying.", file=sys.stderr)
        return 1
    if cfg.environment == "production":
        print(f"authorized by: {args.production_authorized_by.strip()}")
    print(render_record({"restore_started": now}))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Dry-run-by-default Cloud Run traffic rollback helper.")
    sub = parser.add_subparsers(dest="command", required=True)

    def common(p):
        p.add_argument("--env", required=True, choices=sorted(SERVICES))
        p.add_argument("--project", default="", help="defaults to GCP_PROJECT_ID")
        p.add_argument("--region", default="", help="defaults to GCP_REGION")

    def mutation(p):
        p.add_argument("--execute", action="store_true", help="apply the traffic change")
        p.add_argument("--confirm", default="", help="must equal E:NAME (or E:latest for restore)")
        p.add_argument("--production-authorized-by", default="", help="required for production")

    status = sub.add_parser("status", help="read-only traffic and revision snapshot")
    common(status)
    status.add_argument("--limit", type=positive_int, default=6)

    plan = sub.add_parser("plan", help="read-only rollback validation and command preview")
    common(plan)
    plan.add_argument("--to-revision", required=True)
    plan.add_argument("--allow-same-image", action="store_true")

    execute = sub.add_parser("execute", help="guarded traffic change to a named revision")
    common(execute)
    execute.add_argument("--to-revision", required=True)
    execute.add_argument("--allow-same-image", action="store_true")
    mutation(execute)

    restore = sub.add_parser("restore", help="guarded traffic change to --to-latest")
    common(restore)
    mutation(restore)
    return parser


HANDLERS = {"status": cmd_status, "plan": cmd_plan, "execute": cmd_execute, "restore": cmd_restore}


def main(argv: Sequence[str] | None = None, runner: Runner = run_subprocess,
         environ: Mapping[str, str] | None = None, clock: Callable[[], str] = utc_now) -> int:
    args = build_parser().parse_args(argv)
    environ = os.environ if environ is None else environ
    try:
        cfg = resolve_config(args.env, args.project, args.region, environ)
        return HANDLERS[args.command](args, cfg, runner, clock(), environ)
    except Refusal as error:
        print(f"REFUSED: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
