"""Rollback helper: dry-run default, guarded traffic changes, and sanitized output. All commands are mocked."""

import importlib.util
import io
import json
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "rollback_helper", Path(__file__).resolve().parents[1] / "scripts" / "rollback_helper.py",
)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)

PROJECT = "lagaw-test-project"
REGION = "asia-southeast1"
NOW = "2026-10-30T12:00:00Z"
PROD_CURRENT = "lagaw-api-00019-mq8"
PROD_TARGET = "lagaw-api-00017-m5m"
STG_CURRENT = "lagaw-api-staging-00029-hx5"
STG_TARGET = "lagaw-api-staging-00024-96t"
SHA_CURRENT = "a5073051754b5ddad5b34be1d0e437dda1c0f8f0"
SHA_TARGET = "6412bad9a6f24cfdd731dd0ad9222242c4fbfdc6"
DIGEST_CURRENT = "asia-southeast1-docker.pkg.dev/example/lagaw/api@sha256:" + "1" * 64
DIGEST_TARGET = "asia-southeast1-docker.pkg.dev/example/lagaw/api@sha256:" + "2" * 64
ENV_BASE = {"GCP_PROJECT_ID": PROJECT, "GCP_REGION": REGION}
SECRET_SENTINEL = "SENTINEL-SECRET-VALUE-12345"


def revision_json(name, digest, commit, created="2026-10-29T04:00:00Z", owner=None):
    # Auto-generated names look like <service>-<generation>-<suffix>.
    service = owner or name.rsplit("-", 2)[0]
    labels = {"serving.knative.dev/service": service}
    if commit is not None:
        labels["commit-sha"] = commit
    metadata = {"name": name, "creationTimestamp": created, "labels": labels}
    raw = {"metadata": metadata, "status": {"imageDigest": digest} if digest is not None else {}}
    # Environment values a real describe could carry must never reach output.
    raw["spec"] = {"containers": [{"env": [{"name": "DEEPSEEK_API_KEY", "value": SECRET_SENTINEL}]}]}
    return json.dumps(raw)


def traffic_json(*pairs):
    return json.dumps({"metadata": {"name": "svc"},
                       "status": {"traffic": [{"revisionName": n, "percent": p} for n, p in pairs]}})


class FakeRunner:
    """Routes each argv by substring; records every call. Unmatched calls fail with rc 1."""

    def __init__(self, routes=None):
        self.routes = list(routes or [])
        self.calls = []

    def __call__(self, args):
        self.calls.append(list(args))
        joined = " ".join(args)
        for needle, rc, out in self.routes:
            if needle in joined:
                return rc, out
        return 1, ""

    def mutating(self):
        return [call for call in self.calls if "update-traffic" in call]


def production_routes(target_digest=DIGEST_TARGET, target_commit=SHA_TARGET, target_present=True,
                       traffic=None, migrations="", cat_file_rc=0, diff_rc=0):
    routes = [
        ("services describe lagaw-api ", 0, traffic or traffic_json((PROD_CURRENT, 100))),
        ("revisions describe " + PROD_CURRENT, 0, revision_json(PROD_CURRENT, DIGEST_CURRENT, SHA_CURRENT)),
        ("cat-file", cat_file_rc, ""),
        ("diff --name-only", diff_rc, migrations),
    ]
    if target_present:
        routes.insert(1, ("revisions describe " + PROD_TARGET, 0,
                          revision_json(PROD_TARGET, target_digest, target_commit)))
    return routes


def run_main(argv, runner, environ=None):
    out, err = io.StringIO(), io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        code = helper.main(argv, runner=runner, environ=environ if environ is not None else dict(ENV_BASE),
                           clock=lambda: NOW)
    return code, out.getvalue(), err.getvalue()


def guard_env(environment):
    return dict(ENV_BASE, ROLLBACK_AUTHORIZED=environment)


class RollbackHelperTests(unittest.TestCase):
    # Dry-run default and read-only commands.

    def test_execute_without_execute_flag_is_dry_run_and_mutates_nothing(self):
        runner = FakeRunner(production_routes())
        code, out, _err = run_main(["execute", "--env", "production", "--to-revision", PROD_TARGET], runner)
        self.assertEqual(code, 0)
        self.assertEqual(runner.mutating(), [])
        self.assertIn("DRY RUN", out)
        self.assertIn(f"{PROD_TARGET}=100", out)

    def test_restore_without_execute_flag_is_dry_run_and_mutates_nothing(self):
        runner = FakeRunner([("services describe lagaw-api-staging", 0, traffic_json((STG_CURRENT, 100)))])
        code, out, _err = run_main(["restore", "--env", "staging"], runner)
        self.assertEqual(code, 0)
        self.assertEqual(runner.mutating(), [])
        self.assertIn("--to-latest", out)

    def test_plan_is_read_only_and_prints_both_commands(self):
        runner = FakeRunner(production_routes())
        code, out, _err = run_main(["plan", "--env", "production", "--to-revision", PROD_TARGET], runner)
        self.assertEqual(code, 0)
        self.assertEqual(runner.mutating(), [])
        self.assertIn("gcloud run services update-traffic lagaw-api --project lagaw-test-project "
                      f"--region {REGION} --to-revisions {PROD_TARGET}=100", out)
        self.assertIn("--to-latest", out)
        self.assertIn("Timestamp record", out)

    def test_status_projects_fields_and_hides_environment_values(self):
        listing = json.dumps([
            json.loads(revision_json(PROD_CURRENT, DIGEST_CURRENT, SHA_CURRENT, "2026-10-29T04:23:03Z")),
            json.loads(revision_json(PROD_TARGET, DIGEST_TARGET, SHA_TARGET, "2026-10-29T04:18:05Z")),
        ])
        runner = FakeRunner([
            ("services describe lagaw-api ", 0, traffic_json((PROD_CURRENT, 100))),
            ("revisions list", 0, listing),
        ])
        code, out, _err = run_main(["status", "--env", "production", "--limit", "2"], runner)
        self.assertEqual(code, 0)
        self.assertEqual(runner.mutating(), [])
        self.assertIn(f"{PROD_CURRENT}: 100%", out)
        self.assertIn(SHA_TARGET, out)
        self.assertIn(DIGEST_TARGET, out)
        self.assertNotIn(SECRET_SENTINEL, out)
        self.assertNotIn("DEEPSEEK", out)

    def test_status_lists_newest_first_regardless_of_gcloud_order(self):
        listing = json.dumps([
            json.loads(revision_json(PROD_TARGET, DIGEST_TARGET, SHA_TARGET, "2026-10-28T00:00:00Z")),
            json.loads(revision_json(PROD_CURRENT, DIGEST_CURRENT, SHA_CURRENT, "2026-10-29T00:00:00Z")),
        ])
        runner = FakeRunner([("services describe lagaw-api ", 0, traffic_json((PROD_CURRENT, 100))),
                             ("revisions list", 0, listing)])
        _code, out, _err = run_main(["status", "--env", "production"], runner)
        self.assertLess(out.index(PROD_CURRENT + " |"), out.index(PROD_TARGET + " |"))

    # Plan validation.

    def test_plan_refuses_missing_target_revision(self):
        runner = FakeRunner(production_routes(target_present=False))
        code, _out, err = run_main(["plan", "--env", "production", "--to-revision", PROD_TARGET], runner)
        self.assertEqual(code, 2)
        self.assertIn("could not read revision", err)
        self.assertEqual(runner.mutating(), [])

    def test_plan_refuses_revision_owned_by_another_service(self):
        routes = production_routes(target_present=False)
        routes.insert(0, ("revisions describe " + PROD_TARGET, 0,
                          revision_json(PROD_TARGET, DIGEST_TARGET, SHA_TARGET, owner="lagaw-api-staging")))
        runner = FakeRunner(routes)
        code, _out, err = run_main(["plan", "--env", "production", "--to-revision", PROD_TARGET], runner)
        self.assertEqual(code, 2)
        self.assertIn("does not belong to lagaw-api", err)
        self.assertEqual(runner.mutating(), [])

    def test_plan_refuses_target_that_is_already_serving(self):
        runner = FakeRunner(production_routes())
        code, _out, err = run_main(["plan", "--env", "production", "--to-revision", PROD_CURRENT], runner)
        self.assertEqual(code, 2)
        self.assertIn("already the serving revision", err)

    def test_plan_refuses_same_image_config_only_redeploy(self):
        runner = FakeRunner(production_routes(target_digest=DIGEST_CURRENT, target_commit=SHA_CURRENT))
        code, _out, err = run_main(["plan", "--env", "production", "--to-revision", PROD_TARGET], runner)
        self.assertEqual(code, 2)
        self.assertIn("same image digest", err)
        self.assertIn("no-op", err)
        self.assertEqual(runner.mutating(), [])

    def test_same_image_allowed_only_with_explicit_flag(self):
        runner = FakeRunner(production_routes(target_digest=DIGEST_CURRENT, target_commit=SHA_CURRENT))
        code, out, _err = run_main(["plan", "--env", "production", "--to-revision", PROD_TARGET,
                                    "--allow-same-image"], runner)
        self.assertEqual(code, 0)
        self.assertIn("same image digest", out)

    def test_plan_refuses_missing_digest(self):
        runner = FakeRunner(production_routes(target_digest=None))
        code, _out, err = run_main(["plan", "--env", "production", "--to-revision", PROD_TARGET], runner)
        self.assertEqual(code, 2)
        self.assertIn("image digest missing", err)

    def test_plan_refuses_split_traffic(self):
        runner = FakeRunner(production_routes(traffic=traffic_json((PROD_CURRENT, 50), (PROD_TARGET, 50))))
        code, _out, err = run_main(["plan", "--env", "production", "--to-revision", PROD_TARGET], runner)
        self.assertEqual(code, 2)
        self.assertIn("not 100%", err)

    def test_migration_change_produces_warning_with_file_names(self):
        migration = "supabase/migrations/20261028130000_atomic_itinerary_generation.sql\n"
        runner = FakeRunner(production_routes(migrations=migration + "docs/x.md\n"))
        code, out, _err = run_main(["plan", "--env", "production", "--to-revision", PROD_TARGET], runner)
        self.assertEqual(code, 0)
        self.assertIn("WARNING: supabase/migrations changed", out)
        self.assertIn("20261028130000_atomic_itinerary_generation.sql", out)
        self.assertNotIn("docs/x.md", out)
        diff = next(call for call in runner.calls if "diff" in call)
        self.assertEqual(diff[-4:], [SHA_TARGET, SHA_CURRENT, "--", "supabase/migrations"])

    def test_no_migration_warning_when_none_changed(self):
        runner = FakeRunner(production_routes(migrations="docs/only.md\n"))
        _code, out, _err = run_main(["plan", "--env", "production", "--to-revision", PROD_TARGET], runner)
        self.assertNotIn("supabase/migrations changed", out)
        self.assertNotIn("UNKNOWN", out)

    def test_unknown_commit_warns_that_compatibility_is_unknown(self):
        runner = FakeRunner(production_routes(cat_file_rc=128))
        code, out, _err = run_main(["plan", "--env", "production", "--to-revision", PROD_TARGET], runner)
        self.assertEqual(code, 0)
        self.assertIn("not in the local clone", out)
        self.assertIn("UNKNOWN", out)

    def test_missing_commit_label_warns_without_refusing(self):
        runner = FakeRunner(production_routes(target_commit=None))
        code, out, _err = run_main(["plan", "--env", "production", "--to-revision", PROD_TARGET], runner)
        self.assertEqual(code, 0)
        self.assertIn("commit-sha label missing", out)

    def test_same_commit_label_with_different_digest_is_flagged(self):
        runner = FakeRunner(production_routes(target_commit=SHA_CURRENT))
        _code, out, _err = run_main(["plan", "--env", "production", "--to-revision", PROD_TARGET], runner)
        self.assertIn("build provenance is unverified", out)

    # Execute guards.

    def test_execute_refused_without_confirm_and_runs_nothing_mutating(self):
        runner = FakeRunner(production_routes())
        code, _out, err = run_main(["execute", "--env", "production", "--to-revision", PROD_TARGET,
                                    "--execute", "--production-authorized-by", "Kyle"], runner,
                                   environ=guard_env("production"))
        self.assertEqual(code, 2)
        self.assertIn("--confirm must exactly equal", err)
        self.assertEqual(runner.mutating(), [])

    def test_execute_refused_on_confirm_mismatch(self):
        runner = FakeRunner(production_routes())
        code, _out, _err = run_main(["execute", "--env", "production", "--to-revision", PROD_TARGET,
                                     "--execute", "--confirm", f"production:{PROD_CURRENT}",
                                     "--production-authorized-by", "Kyle"], runner,
                                    environ=guard_env("production"))
        self.assertEqual(code, 2)
        self.assertEqual(runner.mutating(), [])

    def test_execute_refused_without_rollback_authorized(self):
        runner = FakeRunner(production_routes())
        code, _out, err = run_main(["execute", "--env", "production", "--to-revision", PROD_TARGET,
                                    "--execute", "--confirm", f"production:{PROD_TARGET}",
                                    "--production-authorized-by", "Kyle"], runner,
                                   environ=dict(ENV_BASE))
        self.assertEqual(code, 2)
        self.assertIn("ROLLBACK_AUTHORIZED=production", err)
        self.assertEqual(runner.mutating(), [])

    def test_execute_refused_when_authorization_names_other_environment(self):
        runner = FakeRunner(production_routes())
        code, _out, _err = run_main(["execute", "--env", "production", "--to-revision", PROD_TARGET,
                                     "--execute", "--confirm", f"production:{PROD_TARGET}",
                                     "--production-authorized-by", "Kyle"], runner,
                                    environ=guard_env("staging"))
        self.assertEqual(code, 2)
        self.assertEqual(runner.mutating(), [])

    def test_production_execute_refused_without_authorized_by(self):
        runner = FakeRunner(production_routes())
        code, _out, err = run_main(["execute", "--env", "production", "--to-revision", PROD_TARGET,
                                    "--execute", "--confirm", f"production:{PROD_TARGET}"], runner,
                                   environ=guard_env("production"))
        self.assertEqual(code, 2)
        self.assertIn("--production-authorized-by", err)
        self.assertEqual(runner.mutating(), [])

    def test_production_execute_refused_for_whitespace_authorized_by(self):
        runner = FakeRunner(production_routes())
        code, _out, _err = run_main(["execute", "--env", "production", "--to-revision", PROD_TARGET,
                                     "--execute", "--confirm", f"production:{PROD_TARGET}",
                                     "--production-authorized-by", "   "], runner,
                                    environ=guard_env("production"))
        self.assertEqual(code, 2)
        self.assertEqual(runner.mutating(), [])

    def test_staging_execute_does_not_need_authorized_by(self):
        routes = [
            ("services describe lagaw-api-staging", 0, traffic_json((STG_CURRENT, 100))),
            ("revisions describe " + STG_CURRENT, 0, revision_json(STG_CURRENT, DIGEST_CURRENT, SHA_CURRENT)),
            ("revisions describe " + STG_TARGET, 0, revision_json(STG_TARGET, DIGEST_TARGET, SHA_TARGET)),
            ("cat-file", 0, ""),
            ("diff --name-only", 0, ""),
            ("update-traffic", 0, ""),
        ]
        runner = FakeRunner(routes)
        code, out, _err = run_main(["execute", "--env", "staging", "--to-revision", STG_TARGET,
                                    "--execute", "--confirm", f"staging:{STG_TARGET}"], runner,
                                   environ=guard_env("staging"))
        self.assertEqual(code, 0)
        self.assertEqual(len(runner.mutating()), 1)
        self.assertIn(f"{STG_TARGET}=100", runner.mutating()[0])
        self.assertIn("traffic_moved", out)

    def test_production_execute_with_all_guards_moves_only_to_named_revision(self):
        runner = FakeRunner(production_routes() + [("update-traffic", 0, "")])
        code, out, _err = run_main(["execute", "--env", "production", "--to-revision", PROD_TARGET,
                                    "--execute", "--confirm", f"production:{PROD_TARGET}",
                                    "--production-authorized-by", "Kyle Yuan"], runner,
                                   environ=guard_env("production"))
        self.assertEqual(code, 0)
        self.assertEqual(runner.mutating(), [[
            "gcloud", "run", "services", "update-traffic", "lagaw-api",
            "--project", PROJECT, "--region", REGION, "--to-revisions", f"{PROD_TARGET}=100",
        ]])
        self.assertIn("authorized by: Kyle Yuan", out)

    def test_failed_traffic_change_returns_nonzero(self):
        runner = FakeRunner(production_routes() + [("update-traffic", 1, "")])
        code, _out, err = run_main(["execute", "--env", "production", "--to-revision", PROD_TARGET,
                                    "--execute", "--confirm", f"production:{PROD_TARGET}",
                                    "--production-authorized-by", "Kyle"], runner,
                                   environ=guard_env("production"))
        self.assertEqual(code, 1)
        self.assertIn("traffic change failed", err)

    # Restore.

    def test_restore_execute_routes_to_latest_with_guards(self):
        runner = FakeRunner([
            ("services describe lagaw-api-staging", 0, traffic_json((STG_TARGET, 100))),
            ("update-traffic", 0, ""),
        ])
        code, out, _err = run_main(["restore", "--env", "staging", "--execute",
                                    "--confirm", "staging:latest"], runner, environ=guard_env("staging"))
        self.assertEqual(code, 0)
        self.assertEqual(runner.mutating(), [[
            "gcloud", "run", "services", "update-traffic", "lagaw-api-staging",
            "--project", PROJECT, "--region", REGION, "--to-latest",
        ]])
        self.assertIn("restore_started", out)

    def test_restore_shows_latest_ready_revision_before_routing_to_it(self):
        describe = json.dumps({"metadata": {"name": "svc"}, "status": {
            "traffic": [{"revisionName": STG_TARGET, "percent": 100}],
            "latestReadyRevisionName": STG_CURRENT}})
        runner = FakeRunner([("services describe lagaw-api-staging", 0, describe)])
        code, out, _err = run_main(["restore", "--env", "staging"], runner)
        self.assertEqual(code, 0)
        self.assertIn(f"latest ready revision (restore target): {STG_CURRENT}", out)
        self.assertEqual(runner.mutating(), [])

    def test_restore_refused_on_named_revision_confirm(self):
        runner = FakeRunner([("services describe lagaw-api-staging", 0, traffic_json((STG_TARGET, 100)))])
        code, _out, _err = run_main(["restore", "--env", "staging", "--execute",
                                     "--confirm", f"staging:{STG_TARGET}"], runner, environ=guard_env("staging"))
        self.assertEqual(code, 2)
        self.assertEqual(runner.mutating(), [])

    def test_production_restore_requires_authorized_by(self):
        runner = FakeRunner([("services describe lagaw-api ", 0, traffic_json((PROD_CURRENT, 100)))])
        code, _out, _err = run_main(["restore", "--env", "production", "--execute",
                                     "--confirm", "production:latest"], runner, environ=guard_env("production"))
        self.assertEqual(code, 2)
        self.assertEqual(runner.mutating(), [])

    # Argument and configuration validation.

    def test_project_and_region_come_from_environment_when_flags_absent(self):
        runner = FakeRunner([("services describe lagaw-api ", 0, traffic_json((PROD_CURRENT, 100))),
                             ("revisions list", 0, "[]")])
        code, _out, _err = run_main(["status", "--env", "production"], runner,
                                    environ={"GCP_PROJECT_ID": PROJECT, "GCP_REGION": REGION})
        self.assertEqual(code, 0)
        self.assertIn(PROJECT, runner.calls[0])
        self.assertIn(REGION, runner.calls[0])

    def test_missing_project_is_refused_before_any_command(self):
        runner = FakeRunner()
        code, _out, err = run_main(["status", "--env", "staging"], runner, environ={"GCP_REGION": REGION})
        self.assertEqual(code, 2)
        self.assertIn("GCP project is missing", err)
        self.assertEqual(runner.calls, [])

    def test_missing_region_is_refused(self):
        runner = FakeRunner()
        code, _out, err = run_main(["status", "--env", "staging"], runner, environ={"GCP_PROJECT_ID": PROJECT})
        self.assertEqual(code, 2)
        self.assertIn("GCP region is missing", err)
        self.assertEqual(runner.calls, [])

    def test_malformed_project_is_refused_without_echoing_it(self):
        runner = FakeRunner()
        bad = "Bad_Project; rm -rf"
        code, _out, err = run_main(["status", "--env", "staging", "--project", bad, "--region", REGION],
                                   runner, environ={})
        self.assertEqual(code, 2)
        self.assertIn("invalid format", err)
        self.assertNotIn("rm -rf", err)
        self.assertEqual(runner.calls, [])

    def test_malformed_region_is_refused(self):
        runner = FakeRunner()
        code, _out, _err = run_main(["status", "--env", "staging", "--project", PROJECT,
                                     "--region", "asia southeast"], runner, environ={})
        self.assertEqual(code, 2)
        self.assertEqual(runner.calls, [])

    def test_revision_name_from_another_service_is_refused(self):
        runner = FakeRunner(production_routes())
        code, _out, err = run_main(["plan", "--env", "production", "--to-revision", STG_TARGET], runner)
        self.assertEqual(code, 2)
        self.assertIn("must be a revision of lagaw-api", err)
        self.assertEqual(runner.calls, [])

    def test_revision_name_with_shell_metacharacters_is_refused(self):
        runner = FakeRunner(production_routes())
        code, _out, _err = run_main(["plan", "--env", "production", "--to-revision", "lagaw-api-1;id"],
                                    runner)
        self.assertEqual(code, 2)
        self.assertEqual(runner.calls, [])

    def test_unknown_environment_is_rejected_by_argparse(self):
        with self.assertRaises(SystemExit):
            run_main(["status", "--env", "dev"], FakeRunner())

    def test_limit_out_of_range_is_rejected(self):
        with self.assertRaises(SystemExit):
            run_main(["status", "--env", "staging", "--limit", "0"], FakeRunner())

    def test_subprocess_runner_uses_list_arguments_without_shell(self):
        with patch.object(helper.subprocess, "run") as run:
            run.return_value.returncode = 0
            run.return_value.stdout = "ok"
            self.assertEqual(helper.run_subprocess(["gcloud", "run", "services", "list"]), (0, "ok"))
        args, kwargs = run.call_args
        self.assertIsInstance(args[0], list)
        self.assertFalse(kwargs.get("shell", False))

    def test_gcloud_failure_message_hides_stderr(self):
        runner = FakeRunner([("services describe", 1, "")])
        code, _out, err = run_main(["status", "--env", "staging"], runner)
        self.assertEqual(code, 2)
        self.assertIn("could not read service", err)
        self.assertNotIn(SECRET_SENTINEL, err)


if __name__ == "__main__":
    unittest.main()
