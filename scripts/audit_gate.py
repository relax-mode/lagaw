"""Gate dependency audit results against a committed allowlist.

Reads pip-audit JSON and/or npm audit JSON, then fails when a vulnerability is
neither allowlisted nor below the npm high threshold. Historical findings that
are explicitly accepted in the allowlist stay visible in the output but do not
block. Newly introduced findings block the build.

Only IDs and package names are printed. Advisory descriptions are never echoed,
so the log stays small and free of untrusted text.

Exit codes: 0 pass, 1 blocking findings or expired allowlist entries,
2 unreadable or malformed input.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from pathlib import Path

NPM_BLOCKING_SEVERITIES = frozenset({"high", "critical"})
REQUIRED_ENTRY_FIELDS = ("id", "package", "reason", "review_by")


class GateInputError(Exception):
    """Raised when an input file cannot be read or has an unexpected shape."""


def load_json(path: Path) -> object:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise GateInputError(f"cannot read JSON from {path}: {type(exc).__name__}") from exc


def parse_pip_audit(data: object) -> list[tuple[str, str]]:
    """Return (vulnerability ID, package name) pairs from pip-audit JSON."""
    if not isinstance(data, dict) or not isinstance(data.get("dependencies"), list):
        raise GateInputError("pip-audit JSON has no 'dependencies' list")
    findings: list[tuple[str, str]] = []
    for dependency in data["dependencies"]:
        if not isinstance(dependency, dict):
            raise GateInputError("pip-audit dependency entry is not an object")
        name = str(dependency.get("name", "?"))
        for vuln in dependency.get("vulns", []) or []:
            if not isinstance(vuln, dict) or not vuln.get("id"):
                raise GateInputError("pip-audit vulnerability entry has no id")
            findings.append((str(vuln["id"]), name))
    return findings


def npm_advisory_id(via: dict) -> str:
    url = str(via.get("url", ""))
    if "/advisories/" in url:
        return url.rsplit("/", 1)[-1]
    return str(via.get("source", "unknown"))


def parse_npm_audit(data: object, threshold: frozenset[str]) -> list[tuple[str, str]]:
    """Return (advisory ID, package name) pairs at or above the threshold."""
    if not isinstance(data, dict):
        raise GateInputError("npm audit JSON is not an object")
    if "error" in data and "vulnerabilities" not in data:
        raise GateInputError("npm audit reported an error instead of results")
    vulnerabilities = data.get("vulnerabilities")
    if not isinstance(vulnerabilities, dict):
        raise GateInputError("npm audit JSON has no 'vulnerabilities' object")
    findings: list[tuple[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for package, record in vulnerabilities.items():
        if not isinstance(record, dict):
            raise GateInputError("npm audit package entry is not an object")
        for via in record.get("via", []) or []:
            # String entries point at another package; the advisory is the object.
            if not isinstance(via, dict):
                continue
            if str(via.get("severity", "")).lower() not in threshold:
                continue
            key = (npm_advisory_id(via), str(package))
            if key not in seen:
                seen.add(key)
                findings.append(key)
    return findings


def load_allowlist(path: Path) -> dict[tuple[str, str], dt.date]:
    """Return {(id, package): review_by} from the committed allowlist."""
    data = load_json(path)
    if not isinstance(data, dict) or not isinstance(data.get("entries"), list):
        raise GateInputError("allowlist must be an object with an 'entries' list")
    entries: dict[tuple[str, str], dt.date] = {}
    for entry in data["entries"]:
        if not isinstance(entry, dict):
            raise GateInputError("allowlist entry is not an object")
        missing = [field for field in REQUIRED_ENTRY_FIELDS if not entry.get(field)]
        if missing:
            raise GateInputError(f"allowlist entry missing fields: {', '.join(missing)}")
        try:
            review_by = dt.date.fromisoformat(str(entry["review_by"]))
        except ValueError as exc:
            raise GateInputError("allowlist review_by must be YYYY-MM-DD") from exc
        entries[(str(entry["id"]), str(entry["package"]))] = review_by
    return entries


def evaluate(
    sources: list[tuple[str, list[tuple[str, str]]]],
    allowlist: dict[tuple[str, str], dt.date],
    today: dt.date,
) -> tuple[list[str], list[str], list[str]]:
    """Return (historical, new, expired) lines for the report."""
    historical: list[str] = []
    new: list[str] = []
    matched: set[tuple[str, str]] = set()
    for source, findings in sources:
        for vuln_id, package in findings:
            key = (vuln_id, package)
            line = f"{source}: {vuln_id} {package}"
            if key in allowlist:
                matched.add(key)
                historical.append(line)
            else:
                new.append(line)
    expired = [
        f"{vuln_id} {package} (review_by {review_by.isoformat()})"
        for (vuln_id, package), review_by in sorted(allowlist.items())
        if review_by < today and (vuln_id, package) in matched
    ]
    return historical, new, expired


def main(argv: list[str] | None = None, today: dt.date | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--pip-audit", type=Path, help="pip-audit JSON report")
    parser.add_argument("--npm-audit", type=Path, help="npm audit JSON report")
    parser.add_argument("--allowlist", type=Path, required=True, help="allowlist JSON")
    args = parser.parse_args(argv)
    if args.pip_audit is None and args.npm_audit is None:
        parser.error("provide --pip-audit and/or --npm-audit")
    today = today or dt.date.today()

    try:
        allowlist = load_allowlist(args.allowlist)
        sources: list[tuple[str, list[tuple[str, str]]]] = []
        if args.pip_audit is not None:
            sources.append(("pip", parse_pip_audit(load_json(args.pip_audit))))
        if args.npm_audit is not None:
            sources.append(
                ("npm", parse_npm_audit(load_json(args.npm_audit), NPM_BLOCKING_SEVERITIES))
            )
    except GateInputError as exc:
        print(f"audit gate input error: {exc}", file=sys.stderr)
        return 2

    historical, new, expired = evaluate(sources, allowlist, today)
    for line in historical:
        print(f"accepted (allowlisted): {line}")
    for line in new:
        print(f"BLOCKING (not allowlisted): {line}")
    for line in expired:
        print(f"BLOCKING (allowlist review date passed): {line}")
    print(
        f"audit gate: {len(historical)} allowlisted, {len(new)} new, "
        f"{len(expired)} expired allowlist entries"
    )
    return 1 if new or expired else 0


if __name__ == "__main__":
    sys.exit(main())
