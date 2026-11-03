"""The release validator must stay read-only, fail closed, and never run a shell."""

import importlib.util
import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "release_check", Path(__file__).resolve().parents[1] / "scripts" / "release_check.py",
)
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)

CommandResult = release.CommandResult
SHA = "a" * 40
CI_GREEN = json.dumps({"workflow_runs": [{
    "id": 101, "name": "Lagaw CI", "status": "completed", "conclusion": "success",
    "created_at": "2026-10-30T01:00:00Z",
}]})
DEFAULT_ROUTES = {
    ("git", "rev-parse"): CommandResult(0, SHA + "\n"),
    ("git", "tag"): CommandResult(0, ""),
    ("git", "ls-remote"): CommandResult(0, ""),
    ("git", "merge-base"): CommandResult(0, ""),
    ("git", "status"): CommandResult(0, ""),
    ("gh", "api"): CommandResult(0, CI_GREEN),
}


class FakeRunner:
    """Records every call and answers by command prefix. Unknown commands fail."""

    def __init__(self, overrides=None):
        self.routes = dict(DEFAULT_ROUTES)
        self.routes.update(overrides or {})
        self.calls = []

    def __call__(self, args, cwd):
        self.calls.append(list(args))
        for prefix, result in self.routes.items():
            if tuple(args[:len(prefix)]) == prefix:
                return result
        return CommandResult(1, "")

    def invoked(self, prefix):
        return any(tuple(call[:len(prefix)]) == prefix for call in self.calls)


class ReleaseCheckTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        (self.root / "CHANGELOG.md").write_text(
            "# Changelog\n\n## [Unreleased] - v1.0.0 candidate\n\n### Sprint 1\n", encoding="utf-8")
        (self.root / "docs" / "release-notes").mkdir(parents=True)
        (self.root / "docs" / "release-notes" / "v1.0.0.md").write_text("# v1.0.0\n", encoding="utf-8")
        (self.root / "frontend").mkdir()
        (self.root / "frontend" / "pubspec.yaml").write_text("name: frontend\nversion: 1.0.0+1\n", encoding="utf-8")

    def tearDown(self):
        self._tmp.cleanup()

    def run_checks(self, runner=None, **options):
        runner = runner or FakeRunner()
        return release.run_checks("1.0.0", root=self.root, runner=runner, **options), runner

    def failed(self, checks):
        return [check for check in checks if not check.passed]

    def assert_single_failure(self, checks, name_fragment, detail_fragment=None):
        failures = self.failed(checks)
        self.assertEqual(len(failures), 1, [c.name + ": " + c.detail for c in failures])
        self.assertIn(name_fragment, failures[0].name)
        if detail_fragment:
            self.assertIn(detail_fragment, failures[0].detail)

    # Passing paths
    def test_green_release_passes_every_default_check(self):
        checks, _ = self.run_checks()
        self.assertEqual(len(checks), 8)
        self.assertEqual(self.failed(checks), [])

    def test_remote_and_ci_options_add_their_checks(self):
        checks, runner = self.run_checks(remote=True, ci=True)
        self.assertEqual(len(checks), 10)
        self.assertEqual(self.failed(checks), [])
        self.assertTrue(runner.invoked(("git", "ls-remote")))
        self.assertTrue(runner.invoked(("gh", "api")))

    def test_optional_network_checks_are_off_by_default(self):
        _, runner = self.run_checks()
        self.assertFalse(runner.invoked(("git", "ls-remote")))
        self.assertFalse(runner.invoked(("gh", "api")))

    def test_changelog_accepts_a_dated_version_heading(self):
        (self.root / "CHANGELOG.md").write_text("## [1.0.0] - 2026-10-31\n", encoding="utf-8")
        checks, _ = self.run_checks()
        self.assertEqual(self.failed(checks), [])

    def test_main_exits_zero_and_prints_pass(self):
        output = io.StringIO()
        with redirect_stdout(output):
            code = release.main(["--version", "1.0.0"], runner=FakeRunner(), root=self.root)
        self.assertEqual(code, 0)
        self.assertIn("Result: PASS", output.getvalue())
        self.assertIn("[PASS] version is semantic", output.getvalue())

    # FAIL paths
    def test_non_semver_version_fails_and_stops_early(self):
        checks = release.run_checks("v1.0.0", root=self.root, runner=FakeRunner())
        self.assertEqual(len(checks), 1)
        self.assertFalse(checks[0].passed)
        self.assertIn("without a leading v", checks[0].detail)

    def test_two_part_version_fails(self):
        checks = release.run_checks("1.0", root=self.root, runner=FakeRunner())
        self.assertFalse(checks[0].passed)

    def test_missing_changelog_fails(self):
        (self.root / "CHANGELOG.md").unlink()
        checks, _ = self.run_checks()
        self.assert_single_failure(checks, "CHANGELOG.md", "missing or unreadable")

    def test_changelog_without_matching_heading_fails(self):
        (self.root / "CHANGELOG.md").write_text("## [0.9.0] - 2026-10-01\n", encoding="utf-8")
        checks, _ = self.run_checks()
        self.assert_single_failure(checks, "CHANGELOG.md", "no matching")

    def test_unreleased_heading_without_candidate_version_fails(self):
        (self.root / "CHANGELOG.md").write_text("## [Unreleased]\n", encoding="utf-8")
        checks, _ = self.run_checks()
        self.assert_single_failure(checks, "CHANGELOG.md", "no matching")

    def test_missing_release_notes_fails(self):
        (self.root / "docs" / "release-notes" / "v1.0.0.md").unlink()
        checks, _ = self.run_checks()
        self.assert_single_failure(checks, "release notes", "v1.0.0.md is missing")

    def test_draft_only_release_notes_fail_until_promoted(self):
        notes = self.root / "docs" / "release-notes"
        (notes / "v1.0.0.md").rename(notes / "v1.0.0-draft.md")
        checks, _ = self.run_checks()
        self.assert_single_failure(checks, "release notes", "only the draft exists")

    def test_pubspec_without_build_number_fails(self):
        (self.root / "frontend" / "pubspec.yaml").write_text("version: 1.0.0\n", encoding="utf-8")
        checks, _ = self.run_checks()
        self.assert_single_failure(checks, "pubspec", "no X.Y.Z+N")

    def test_pubspec_version_mismatch_fails(self):
        (self.root / "frontend" / "pubspec.yaml").write_text("version: 0.9.0+4\n", encoding="utf-8")
        checks, _ = self.run_checks()
        self.assert_single_failure(checks, "pubspec", "found 0.9.0+4")

    def test_missing_pubspec_fails(self):
        (self.root / "frontend" / "pubspec.yaml").unlink()
        checks, _ = self.run_checks()
        self.assert_single_failure(checks, "pubspec", "missing or unreadable")

    def test_existing_local_tag_fails(self):
        checks, _ = self.run_checks(runner=FakeRunner({("git", "tag"): CommandResult(0, "v1.0.0\n")}))
        self.assert_single_failure(checks, "absent locally", "already exists locally")

    def test_local_tag_query_error_fails(self):
        checks, _ = self.run_checks(runner=FakeRunner({("git", "tag"): CommandResult(128, "")}))
        self.assert_single_failure(checks, "absent locally", "git tag --list failed")

    def test_existing_remote_tag_fails(self):
        remote = FakeRunner({("git", "ls-remote"): CommandResult(0, f"{SHA}\trefs/tags/v1.0.0\n")})
        checks, _ = self.run_checks(runner=remote, remote=True)
        self.assert_single_failure(checks, "absent on origin", "already exists on origin")

    def test_remote_tag_query_error_fails(self):
        remote = FakeRunner({("git", "ls-remote"): CommandResult(128, "")})
        checks, _ = self.run_checks(runner=remote, remote=True)
        self.assert_single_failure(checks, "absent on origin", "could not query origin")

    def test_unresolvable_commit_fails_and_skips_ancestry(self):
        runner = FakeRunner({("git", "rev-parse"): CommandResult(128, "")})
        checks, runner = self.run_checks(runner=runner, commit="no-such-ref")
        failures = self.failed(checks)
        self.assertEqual({check.name for check in failures},
                         {"commit resolves", "commit is contained in origin/main"})
        self.assertFalse(runner.invoked(("git", "merge-base")))

    def test_commit_argument_that_looks_like_an_option_is_rejected(self):
        checks, runner = self.run_checks(commit="--output=/tmp/x")
        self.assertIn("commit resolves", [check.name for check in self.failed(checks)])
        self.assertFalse(any("--output=/tmp/x" in call for call in runner.calls))

    def test_commit_outside_origin_main_fails(self):
        runner = FakeRunner({("git", "merge-base"): CommandResult(1, "")})
        checks, _ = self.run_checks(runner=runner)
        self.assert_single_failure(checks, "origin/main", "is not contained in origin/main")

    def test_origin_main_comparison_error_fails_with_fetch_hint(self):
        runner = FakeRunner({("git", "merge-base"): CommandResult(128, "")})
        checks, _ = self.run_checks(runner=runner)
        self.assert_single_failure(checks, "origin/main", "git fetch origin main")

    def test_modified_tracked_files_fail(self):
        runner = FakeRunner({("git", "status"): CommandResult(0, " M backend/app/main.py\n")})
        checks, _ = self.run_checks(runner=runner)
        self.assert_single_failure(checks, "no tracked changes", "modified or staged")

    def test_git_status_error_fails(self):
        runner = FakeRunner({("git", "status"): CommandResult(128, "")})
        checks, _ = self.run_checks(runner=runner)
        self.assert_single_failure(checks, "no tracked changes", "git status failed")

    def test_missing_ci_run_fails(self):
        runner = FakeRunner({("gh", "api"): CommandResult(0, json.dumps({"workflow_runs": []}))})
        checks, _ = self.run_checks(runner=runner, ci=True)
        self.assert_single_failure(checks, "succeeded", "no Lagaw CI run found")

    def test_ci_run_still_in_progress_fails(self):
        payload = json.dumps({"workflow_runs": [{"id": 9, "name": "Lagaw CI", "status": "in_progress",
                                                  "conclusion": None, "created_at": "2026-10-30T02:00:00Z"}]})
        runner = FakeRunner({("gh", "api"): CommandResult(0, payload)})
        checks, _ = self.run_checks(runner=runner, ci=True)
        self.assert_single_failure(checks, "succeeded", "latest run is in_progress")

    def test_ci_run_failure_fails(self):
        payload = json.dumps({"workflow_runs": [{"id": 9, "name": "Lagaw CI", "status": "completed",
                                                  "conclusion": "failure", "created_at": "2026-10-30T02:00:00Z"}]})
        runner = FakeRunner({("gh", "api"): CommandResult(0, payload)})
        checks, _ = self.run_checks(runner=runner, ci=True)
        self.assert_single_failure(checks, "succeeded", "concluded failure")

    def test_newest_ci_run_decides_not_an_older_success(self):
        payload = json.dumps({"workflow_runs": [
            {"id": 1, "name": "Lagaw CI", "status": "completed", "conclusion": "success",
             "created_at": "2026-10-29T01:00:00Z"},
            {"id": 2, "name": "Lagaw CI", "status": "completed", "conclusion": "failure",
             "created_at": "2026-10-30T01:00:00Z"},
        ]})
        runner = FakeRunner({("gh", "api"): CommandResult(0, payload)})
        checks, _ = self.run_checks(runner=runner, ci=True)
        self.assert_single_failure(checks, "succeeded", "concluded failure")

    def test_gh_query_error_fails(self):
        runner = FakeRunner({("gh", "api"): CommandResult(1, "")})
        checks, _ = self.run_checks(runner=runner, ci=True)
        self.assert_single_failure(checks, "succeeded", "could not query GitHub Actions")

    def test_unparseable_ci_response_fails(self):
        runner = FakeRunner({("gh", "api"): CommandResult(0, "<html>not json</html>")})
        checks, _ = self.run_checks(runner=runner, ci=True)
        self.assert_single_failure(checks, "succeeded", "unexpected response")

    def test_main_exits_one_and_refuses_to_tag_on_any_failure(self):
        (self.root / "frontend" / "pubspec.yaml").write_text("version: 0.9.0+1\n", encoding="utf-8")
        output = io.StringIO()
        with redirect_stdout(output):
            code = release.main(["--version", "1.0.0"], runner=FakeRunner(), root=self.root)
        self.assertEqual(code, 1)
        self.assertIn("[FAIL] frontend/pubspec.yaml", output.getvalue())
        self.assertIn("Do not tag.", output.getvalue())

    # Execution safety
    def test_every_command_is_an_argument_list_of_strings(self):
        _, runner = self.run_checks(remote=True, ci=True)
        self.assertTrue(runner.calls)
        for call in runner.calls:
            self.assertIsInstance(call, list)
            self.assertTrue(all(isinstance(part, str) for part in call))
            self.assertIn(call[0], {"git", "gh"})

    def test_default_runner_never_uses_a_shell(self):
        completed = type("Completed", (), {"returncode": 0, "stdout": "ok\n"})()
        with patch.object(release, "run", return_value=completed) as run_mock:
            result = release.default_runner(["git", "tag", "--list", "v1.0.0"], self.root)
        self.assertEqual(result, CommandResult(0, "ok\n"))
        args, kwargs = run_mock.call_args
        self.assertEqual(args[0], ["git", "tag", "--list", "v1.0.0"])
        self.assertFalse(kwargs.get("shell", False))

    def test_default_runner_reports_a_missing_binary_as_failure(self):
        with patch.object(release, "run", side_effect=FileNotFoundError("gh")):
            self.assertEqual(release.default_runner(["gh", "api", "x"], self.root).returncode, 127)


if __name__ == "__main__":
    unittest.main()
