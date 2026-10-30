"""Tests for scripts/audit_gate.py using inline pip-audit and npm audit fixtures."""

from __future__ import annotations

import datetime as dt
import importlib.util
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("audit_gate", ROOT / "scripts" / "audit_gate.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)

TODAY = dt.date(2026, 10, 30)


def pip_report(*vulns: tuple[str, str]) -> dict:
    """Build a pip-audit JSON document with one dependency per (id, name) pair."""
    dependencies = [
        {"name": name, "version": "1.0.0", "vulns": [{"id": vuln_id, "fix_versions": []}]}
        for vuln_id, name in vulns
    ]
    return {"dependencies": dependencies, "fixes": []}


def npm_report(*advisories: tuple[str, str, str]) -> dict:
    """Build an npm audit JSON document from (package, GHSA id, severity) triples."""
    vulnerabilities: dict[str, dict] = {}
    for package, advisory_id, severity in advisories:
        record = vulnerabilities.setdefault(
            package, {"name": package, "severity": severity, "via": [], "isDirect": False}
        )
        record["via"].append(
            {
                "source": 1,
                "name": package,
                "severity": severity,
                "url": f"https://github.com/advisories/{advisory_id}",
                "range": "<1.0.0",
            }
        )
    return {"auditReportVersion": 2, "vulnerabilities": vulnerabilities}


def allowlist(*entries: tuple[str, str, str]) -> dict:
    return {
        "schema": 1,
        "entries": [
            {"id": vuln_id, "package": package, "reason": "test", "review_by": review_by}
            for vuln_id, package, review_by in entries
        ],
    }


def write(tmp_path: Path, name: str, data: object) -> Path:
    path = tmp_path / name
    path.write_text(json.dumps(data), encoding="utf-8")
    return path


def run(tmp_path: Path, *, pip=None, npm=None, allow=None, today=TODAY) -> int:
    args = ["--allowlist", str(write(tmp_path, "allow.json", allow or allowlist()))]
    if pip is not None:
        args += ["--pip-audit", str(write(tmp_path, "pip.json", pip))]
    if npm is not None:
        args += ["--npm-audit", str(write(tmp_path, "npm.json", npm))]
    return gate.main(args, today=today)


def test_clean_reports_pass(tmp_path, capsys):
    assert run(tmp_path, pip={"dependencies": [], "fixes": []}, npm=npm_report()) == 0
    assert "0 new" in capsys.readouterr().out


def test_new_pip_vulnerability_blocks(tmp_path, capsys):
    code = run(tmp_path, pip=pip_report(("PYSEC-2099-1", "examplepkg")))
    out = capsys.readouterr().out
    assert code == 1
    assert "BLOCKING (not allowlisted): pip: PYSEC-2099-1 examplepkg" in out


def test_allowlisted_pip_vulnerability_is_visible_but_passes(tmp_path, capsys):
    code = run(
        tmp_path,
        pip=pip_report(("PYSEC-2099-1", "examplepkg")),
        allow=allowlist(("PYSEC-2099-1", "examplepkg", "2026-12-31")),
    )
    out = capsys.readouterr().out
    assert code == 0
    assert "accepted (allowlisted): pip: PYSEC-2099-1 examplepkg" in out


def test_allowlist_matches_id_and_package_together(tmp_path):
    code = run(
        tmp_path,
        pip=pip_report(("PYSEC-2099-1", "otherpkg")),
        allow=allowlist(("PYSEC-2099-1", "examplepkg", "2026-12-31")),
    )
    assert code == 1


def test_npm_high_and_critical_block_but_moderate_is_ignored(tmp_path, capsys):
    npm = npm_report(
        ("undici", "GHSA-aaaa-aaaa-aaaa", "high"),
        ("lodash", "GHSA-bbbb-bbbb-bbbb", "critical"),
        ("miniflare", "GHSA-cccc-cccc-cccc", "moderate"),
    )
    assert run(tmp_path, npm=npm) == 1
    out = capsys.readouterr().out
    assert "npm: GHSA-aaaa-aaaa-aaaa undici" in out
    assert "npm: GHSA-bbbb-bbbb-bbbb lodash" in out
    assert "GHSA-cccc-cccc-cccc" not in out


def test_npm_allowlisted_high_passes(tmp_path):
    npm = npm_report(("undici", "GHSA-aaaa-aaaa-aaaa", "high"))
    code = run(tmp_path, npm=npm, allow=allowlist(("GHSA-aaaa-aaaa-aaaa", "undici", "2026-12-31")))
    assert code == 0


def test_expired_review_date_blocks_while_finding_remains(tmp_path, capsys):
    npm = npm_report(("undici", "GHSA-aaaa-aaaa-aaaa", "high"))
    code = run(
        tmp_path,
        npm=npm,
        allow=allowlist(("GHSA-aaaa-aaaa-aaaa", "undici", "2026-10-01")),
    )
    assert code == 1
    assert "allowlist review date passed" in capsys.readouterr().out


def test_expired_entry_without_matching_finding_does_not_block(tmp_path):
    code = run(
        tmp_path,
        npm=npm_report(),
        allow=allowlist(("GHSA-gone-gone-gone", "undici", "2020-01-01")),
    )
    assert code == 0


def test_repeated_npm_advisory_is_reported_once(tmp_path, capsys):
    npm = npm_report(
        ("undici", "GHSA-aaaa-aaaa-aaaa", "high"),
        ("undici", "GHSA-aaaa-aaaa-aaaa", "high"),
    )
    run(tmp_path, npm=npm)
    assert capsys.readouterr().out.count("GHSA-aaaa-aaaa-aaaa undici") == 1


def test_npm_error_document_fails_closed(tmp_path):
    error_doc = {"error": {"code": "ENOTFOUND", "summary": "registry unreachable"}}
    assert run(tmp_path, npm=error_doc) == 2


def test_missing_allowlist_fields_fail_closed(tmp_path):
    bad = {"entries": [{"id": "PYSEC-1", "package": "x", "reason": ""}]}
    assert run(tmp_path, pip={"dependencies": [], "fixes": []}, allow=bad) == 2


def test_malformed_review_date_fails_closed(tmp_path):
    bad = allowlist(("PYSEC-1", "x", "next-year"))
    assert run(tmp_path, pip={"dependencies": [], "fixes": []}, allow=bad) == 2


def test_unreadable_json_fails_closed(tmp_path):
    broken = tmp_path / "pip.json"
    broken.write_text("{not json", encoding="utf-8")
    allow = write(tmp_path, "allow.json", allowlist())
    assert gate.main(["--pip-audit", str(broken), "--allowlist", str(allow)], today=TODAY) == 2


def test_requires_at_least_one_report(tmp_path):
    allow = write(tmp_path, "allow.json", allowlist())
    with pytest.raises(SystemExit):
        gate.main(["--allowlist", str(allow)], today=TODAY)


def test_repository_allowlist_loads_and_covers_current_npm_findings():
    entries = gate.load_allowlist(ROOT / ".github" / "security" / "audit-allowlist.json")
    assert ("GHSA-xjj6-f33q-929c", "undici") in entries
