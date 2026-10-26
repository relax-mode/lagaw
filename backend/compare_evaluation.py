"""Compare a fresh offline evaluation report with the committed baseline.

Prints a Markdown summary for the CI job summary and exits nonzero when quality
regressed: a previously passing case fails or disappears, field checks drop, or
a deterministic recommendation metric falls. It also reports whether the prompt,
configuration or fixtures changed, so a prompt edit shows its effect on quality.

    python compare_evaluation.py ../docs/evidence/week3-evaluation.json test-results/week3-evaluation.json
"""

import json
import sys
from pathlib import Path

TOLERANCE = 1e-6
IDENTIFIERS = ("prompt_sha256", "configuration_sha256", "fixture_sha256")


def cases(report, section):
    return {case["id"]: bool(case["passed"]) for case in report[section]["cases"]}


def compare(baseline, current):
    """Return (markdown lines, regression messages)."""
    regressions = []
    lines = ["## AI evaluation versus baseline", ""]

    changed = [key for key in IDENTIFIERS
               if baseline["identifiers"].get(key) != current["identifiers"].get(key)]
    if changed:
        lines.append(f"Changed since baseline: {', '.join(f'`{key}`' for key in changed)}. "
                     "Quality below reflects that change.")
    else:
        lines.append("Prompt, configuration and fixtures match the baseline.")
    lines += ["", "| Area | Baseline | Current |", "| --- | --- | --- |"]

    for section in ("extraction", "content"):
        before, after = cases(baseline, section), cases(current, section)
        lines.append(f"| {section} cases passed | {sum(before.values())}/{len(before)} "
                     f"| {sum(after.values())}/{len(after)} |")
        for case_id, passed in before.items():
            if passed and not after.get(case_id, False):
                state = "missing" if case_id not in after else "now failing"
                regressions.append(f"{section} case `{case_id}` {state}")

    before_fields = baseline["extraction"]["field_checks_passed"]
    after_fields = current["extraction"]["field_checks_passed"]
    lines.append(f"| extraction field checks | {before_fields}/{baseline['extraction']['field_checks_total']} "
                 f"| {after_fields}/{current['extraction']['field_checks_total']} |")
    if after_fields < before_fields:
        regressions.append(f"extraction field checks fell from {before_fields} to {after_fields}")

    for model, metrics in baseline["hybrid"]["summary"].items():
        for metric, value in metrics.items():
            now = current["hybrid"]["summary"].get(model, {}).get(metric)
            lines.append(f"| {model} {metric} | {value:.4f} | {'missing' if now is None else f'{now:.4f}'} |")
            if now is None or now < value - TOLERANCE:
                regressions.append(f"{model} {metric} fell from {value} to {now}")

    if current.get("failures"):
        regressions += [f"evaluation failure: {failure}" for failure in current["failures"]]

    lines.append("")
    if regressions:
        lines += ["**Quality regressed:**", ""] + [f"- {message}" for message in regressions]
    else:
        lines.append("**Quality held:** no case, field check or metric regressed.")
    return lines, regressions


def main(argv):
    if len(argv) != 3:
        sys.exit(__doc__)
    baseline, current = (json.loads(Path(path).read_text(encoding="utf-8")) for path in argv[1:])
    lines, regressions = compare(baseline, current)
    print("\n".join(lines))
    return 1 if regressions else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
