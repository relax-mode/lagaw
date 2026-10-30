"""Read-only release readiness checks. Never creates, moves, or pushes a tag.

Usage: python scripts/release_check.py --version 1.0.0 [--commit SHA] [--remote] [--ci]

Checks that the version is X.Y.Z; CHANGELOG.md has a heading for it or an Unreleased
candidate; docs/release-notes/vX.Y.Z.md exists; frontend/pubspec.yaml is X.Y.Z+N; the
tag vX.Y.Z is absent locally (and on origin with --remote); the commit is contained in
origin/main; tracked files are unchanged; and, with --ci, the latest Lagaw CI run for the
commit succeeded. Prints a PASS/FAIL checklist and exits 1 when any check fails.

Git and gh run only as argument lists through one runner. Their output is never printed,
only the fixed check names and short details. No environment variables or credentials are read.
"""

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from subprocess import TimeoutExpired, run

REPO = "relax-mode/lagaw"
CI_WORKFLOW_NAME = "Lagaw CI"
ROOT = Path(__file__).resolve().parents[1]
SEMVER = re.compile(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)")
PUBSPEC_VERSION = re.compile(r"^version:[ \t]*(\d+\.\d+\.\d+)\+(\d+)[ \t]*$", re.MULTILINE)
COMMIT_ARG = re.compile(r"[0-9A-Za-z][0-9A-Za-z._/-]{0,199}")
FULL_SHA = re.compile(r"[0-9a-f]{40}|[0-9a-f]{64}")


@dataclass(frozen=True)
class CommandResult:
    returncode: int
    stdout: str = ""


@dataclass(frozen=True)
class Check:
    name: str
    passed: bool
    detail: str


def default_runner(args, cwd):
    """Run one command as an argument list (never through a shell)."""
    try:
        done = run(args, cwd=cwd, capture_output=True, text=True, check=False, timeout=120)
    except (OSError, TimeoutExpired):
        return CommandResult(127, "")
    return CommandResult(done.returncode, done.stdout)


def check_version(version):
    ok = SEMVER.fullmatch(version) is not None
    detail = "X.Y.Z" if ok else "expected X.Y.Z without a leading v"
    return Check("version is semantic", ok, detail)


def check_changelog(root, version):
    name = f"CHANGELOG.md has a heading for {version} or an Unreleased candidate"
    try:
        lines = (root / "CHANGELOG.md").read_text(encoding="utf-8").splitlines()
    except OSError:
        return Check(name, False, "CHANGELOG.md is missing or unreadable")
    release_heading = re.compile(rf"##\s+\[v?{re.escape(version)}\](\s|$)")
    candidate_heading = re.compile(
        rf"##\s+\[Unreleased\].*\bv?{re.escape(version)}\b.*candidate", re.IGNORECASE)
    for line in lines:
        if release_heading.match(line) or candidate_heading.match(line):
            return Check(name, True, line.strip())
    return Check(name, False, "no matching release or Unreleased candidate heading")


def check_release_notes(root, version):
    name = f"release notes docs/release-notes/v{version}.md exist"
    notes = root / "docs" / "release-notes" / f"v{version}.md"
    draft = root / "docs" / "release-notes" / f"v{version}-draft.md"
    if notes.is_file():
        return Check(name, True, f"v{version}.md present")
    if draft.is_file():
        return Check(name, False, f"only the draft exists; promote it to v{version}.md before tagging")
    return Check(name, False, f"v{version}.md is missing")


def check_pubspec(root, version):
    name = f"frontend/pubspec.yaml version is {version}+N"
    try:
        text = (root / "frontend" / "pubspec.yaml").read_text(encoding="utf-8")
    except OSError:
        return Check(name, False, "frontend/pubspec.yaml is missing or unreadable")
    match = PUBSPEC_VERSION.search(text)
    if match is None:
        return Check(name, False, "no X.Y.Z+N version line found")
    found = match.group(1)
    if found != version:
        return Check(name, False, f"found {found}+{match.group(2)}")
    return Check(name, True, f"found {found}+{match.group(2)}")


def check_local_tag(runner, root, tag):
    name = f"tag {tag} is absent locally"
    result = runner(["git", "tag", "--list", tag], root)
    if result.returncode != 0:
        return Check(name, False, "git tag --list failed")
    if tag in result.stdout.split():
        return Check(name, False, f"{tag} already exists locally")
    return Check(name, True, "not found")


def check_remote_tag(runner, root, tag):
    name = f"tag {tag} is absent on origin"
    result = runner(["git", "ls-remote", "--tags", "origin", f"refs/tags/{tag}"], root)
    if result.returncode != 0:
        return Check(name, False, "could not query origin (git ls-remote failed)")
    if result.stdout.strip():
        return Check(name, False, f"{tag} already exists on origin")
    return Check(name, True, "not found on origin")


def resolve_commit(runner, root, commit):
    if COMMIT_ARG.fullmatch(commit) is None:
        return None
    result = runner(["git", "rev-parse", "--verify", "--quiet", f"{commit}^{{commit}}"], root)
    sha = result.stdout.strip()
    if result.returncode != 0 or FULL_SHA.fullmatch(sha) is None:
        return None
    return sha


def check_commit_in_main(runner, root, sha):
    name = "commit is contained in origin/main"
    result = runner(["git", "merge-base", "--is-ancestor", sha, "origin/main"], root)
    if result.returncode == 0:
        return Check(name, True, f"{sha[:12]} is an ancestor of origin/main")
    if result.returncode == 1:
        return Check(name, False, f"{sha[:12]} is not contained in origin/main")
    return Check(name, False, "could not compare with origin/main (run git fetch origin main)")


def check_clean_tree(runner, root):
    name = "working tree has no tracked changes"
    result = runner(["git", "status", "--porcelain", "--untracked-files=no"], root)
    if result.returncode != 0:
        return Check(name, False, "git status failed")
    if result.stdout.strip():
        return Check(name, False, "tracked files are modified or staged")
    return Check(name, True, "clean (untracked files are not checked)")


def check_ci(runner, root, sha, repo):
    name = f"latest {CI_WORKFLOW_NAME} run for {sha[:12]} succeeded"
    result = runner(["gh", "api", f"repos/{repo}/actions/runs?head_sha={sha}&per_page=50"], root)
    if result.returncode != 0:
        return Check(name, False, "could not query GitHub Actions with gh")
    try:
        data = json.loads(result.stdout)
    except ValueError:
        return Check(name, False, "unexpected response from GitHub Actions")
    runs = [item for item in (data.get("workflow_runs", []) if isinstance(data, dict) else [])
            if isinstance(item, dict) and item.get("name") == CI_WORKFLOW_NAME]
    if not runs:
        return Check(name, False, f"no {CI_WORKFLOW_NAME} run found for this commit")
    latest = max(runs, key=lambda item: str(item.get("created_at", "")))
    if latest.get("status") != "completed":
        return Check(name, False, f"latest run is {latest.get('status')}")
    if latest.get("conclusion") != "success":
        return Check(name, False, f"latest run concluded {latest.get('conclusion')}")
    return Check(name, True, f"run {latest.get('id')} succeeded")


def run_checks(version, *, root=ROOT, commit="HEAD", remote=False, ci=False,
               runner=default_runner, repo=REPO):
    version_check = check_version(version)
    if not version_check.passed:
        return [version_check]
    tag = f"v{version}"
    checks = [
        version_check,
        check_changelog(root, version),
        check_release_notes(root, version),
        check_pubspec(root, version),
        check_local_tag(runner, root, tag),
    ]
    if remote:
        checks.append(check_remote_tag(runner, root, tag))
    sha = resolve_commit(runner, root, commit)
    if sha is None:
        checks.append(Check("commit resolves", False, f"cannot resolve {commit!r}"))
        checks.append(Check("commit is contained in origin/main", False, "skipped: commit did not resolve"))
    else:
        checks.append(Check("commit resolves", True, sha[:12]))
        checks.append(check_commit_in_main(runner, root, sha))
    checks.append(check_clean_tree(runner, root))
    if ci:
        if sha is None:
            checks.append(Check(f"latest {CI_WORKFLOW_NAME} run succeeded", False,
                                "skipped: commit did not resolve"))
        else:
            checks.append(check_ci(runner, root, sha, repo))
    return checks


def main(argv=None, *, runner=default_runner, root=ROOT):
    parser = argparse.ArgumentParser(description="Read-only Lagaw release readiness checks.")
    parser.add_argument("--version", required=True, help="release version, for example 1.0.0")
    parser.add_argument("--commit", default="HEAD", help="commit to release (default: HEAD)")
    parser.add_argument("--remote", action="store_true", help="also check that origin has no such tag")
    parser.add_argument("--ci", action="store_true", help="check the latest Lagaw CI run via gh")
    parser.add_argument("--root", type=Path, default=root, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    checks = run_checks(args.version, root=args.root, commit=args.commit, remote=args.remote,
                        ci=args.ci, runner=runner)
    for check in checks:
        status = "PASS" if check.passed else "FAIL"
        print(f"[{status}] {check.name}: {check.detail}")
    failed = [check for check in checks if not check.passed]
    if failed:
        print(f"Result: FAIL ({len(failed)} of {len(checks)} checks failed). Do not tag.")
        return 1
    print(f"Result: PASS ({len(checks)} checks). The tag may be created by a human release owner.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
