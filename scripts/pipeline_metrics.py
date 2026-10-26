"""Compute weekly pipeline metrics for `Lagaw CI` from the GitHub Actions API.

Prints a Markdown report covering the columns of the official weekly metrics log
(docs/official-instructions.md, section 5) plus per-job medians. Needs an
authenticated `gh` CLI; reads only public run metadata.

    python scripts/pipeline_metrics.py --since 2026-10-19 --until 2026-10-25
    python scripts/pipeline_metrics.py --since 2026-10-26 --until 2026-11-01 --jobs
"""

import argparse
import json
import statistics
import subprocess
from datetime import datetime

REPO = "relax-mode/lagaw"
WORKFLOW = "ci.yml"
PRODUCTION_JOBS = {"Deploy - Production", "Deploy - Cloud Run", "Deploy - Cloudflare Pages"}


def gh(*args):
    result = subprocess.run(["gh", *args, "-R", REPO], check=True, capture_output=True, text=True)
    return json.loads(result.stdout)


def gh_api(path):
    result = subprocess.run(["gh", "api", path], check=True, capture_output=True, text=True)
    return json.loads(result.stdout)


def ts(value):
    return datetime.fromisoformat(value)


def minutes(seconds):
    return f"{seconds / 60:.1f}"


def summary(values):
    if not values:
        return "n/a"
    values = sorted(values)
    p90 = values[min(len(values) - 1, round(0.9 * (len(values) - 1)))]
    return f"median {statistics.median(values):.0f} s, p90 {p90:.0f} s, mean {statistics.mean(values):.0f} s (n={len(values)})"


def deployed(job):
    """A deploy job can succeed while its gate skips the real deploy; require a deploy step that ran."""
    return job["name"] in PRODUCTION_JOBS and job["conclusion"] == "success" and any(
        step["name"].startswith("Deploy") and step["conclusion"] == "success" for step in job.get("steps", []))


def jobs_for(run_id):
    return gh_api(f"repos/{REPO}/actions/runs/{run_id}/jobs?per_page=100")["jobs"]


def job_seconds(job):
    if not job.get("started_at") or not job.get("completed_at") or job["conclusion"] in ("skipped", None):
        return None
    return (ts(job["completed_at"]) - ts(job["started_at"])).total_seconds()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--since", required=True, help="first day, YYYY-MM-DD (UTC)")
    parser.add_argument("--until", required=True, help="last day, YYYY-MM-DD (UTC)")
    parser.add_argument("--jobs", action="store_true", help="also report per-job durations")
    args = parser.parse_args()

    runs = gh("run", "list", "--workflow", WORKFLOW, "--created", f"{args.since}..{args.until}", "--limit", "500",
              "--json", "databaseId,event,headBranch,headSha,conclusion,status,createdAt,updatedAt")
    runs = [r for r in runs if r["status"] == "completed"]
    wall = {r["databaseId"]: (ts(r["updatedAt"]) - ts(r["createdAt"])).total_seconds() for r in runs}

    def ok(event, branch=None):
        return [wall[r["databaseId"]] for r in runs
                if r["event"] == event and r["conclusion"] == "success" and (branch is None or r["headBranch"] == branch)]

    success = sum(r["conclusion"] == "success" for r in runs)
    failure = sum(r["conclusion"] == "failure" for r in runs)
    cancelled = sum(r["conclusion"] == "cancelled" for r in runs)
    pr_times, main_times = ok("pull_request"), ok("push", "main")

    deploys, failed_deploys, recoveries, job_times, main_jobs = [], [], [], {}, {}
    for run in runs:
        if not (args.jobs or (run["event"] in ("push", "workflow_dispatch") and run["headBranch"] == "main")):
            continue
        jobs = jobs_for(run["databaseId"])
        on_main = run["headBranch"] == "main" and run["event"] in ("push", "workflow_dispatch")
        if on_main:
            main_jobs[run["headSha"]] = jobs
        for job in jobs:
            seconds = job_seconds(job)
            if seconds is not None:
                job_times.setdefault((run["event"], job["name"]), []).append(seconds)
            if on_main and deployed(job):
                deploys.append(job)
            if on_main and job["name"].startswith("Deploy") and job["conclusion"] == "failure":
                failed_deploys.append((job, run["databaseId"]))

    # Time to recover: failed deploy completion -> next successful run of the same deploy job.
    for job, run_id in failed_deploys:
        later = sorted(ts(j["completed_at"]) for js in main_jobs.values() for j in js
                       if j["name"] == job["name"] and j["conclusion"] == "success"
                       and ts(j["completed_at"]) > ts(job["completed_at"]))
        if later:
            recoveries.append((later[0] - ts(job["completed_at"])).total_seconds())

    # Lead time: PR merge -> completion of the first successful production deploy for the merge commit.
    lead = []
    merged = gh("pr", "list", "--state", "merged", "--search", f"merged:{args.since}..{args.until}", "--limit", "200",
                "--json", "number,mergedAt,mergeCommit")
    for pr in merged:
        sha = (pr.get("mergeCommit") or {}).get("oid")
        done = [ts(j["completed_at"]) for j in main_jobs.get(sha, [])
                if deployed(j)]
        if done:
            lead.append((min(done) - ts(pr["mergedAt"])).total_seconds())

    rate = 100 * success / (success + failure) if success + failure else 0
    print(f"## Lagaw CI, {args.since} to {args.until} (UTC)\n")
    print("| Avg PR pipeline time (min) | Main pipeline time (min) | Pipeline success rate (%) | Production deploys "
          "| Avg lead time, merge to live (min) | Failed deploys | Time to recover (min) |")
    print("| --- | --- | --- | --- | --- | --- | --- |")
    print(f"| {minutes(statistics.mean(pr_times)) if pr_times else 'n/a'} "
          f"| {minutes(statistics.mean(main_times)) if main_times else 'n/a'} "
          f"| {rate:.1f} | {len(deploys)} "
          f"| {minutes(statistics.mean(lead)) if lead else 'n/a'} | {len(failed_deploys)} "
          f"| {minutes(statistics.mean(recoveries)) if recoveries else 'n/a'} |\n")
    print(f"- Runs: {len(runs)} completed ({success} success, {failure} failure, {cancelled} cancelled; "
          "cancelled runs are excluded from the success rate).")
    print(f"- PR wall time (successful): {summary(pr_times)}.")
    print(f"- Main push wall time (successful): {summary(main_times)}.")
    print(f"- Merged PRs with a measured production deploy: {len(lead)} of {len(merged)}.")
    if failed_deploys:
        print("- Failed deploy jobs: " + ", ".join(
            f"[{job['name']} in {run_id}](https://github.com/{REPO}/actions/runs/{run_id})" for job, run_id in failed_deploys) + ".")
    if args.jobs:
        print("\n| Event | Job | Duration |\n| --- | --- | --- |")
        for (event, name), values in sorted(job_times.items()):
            print(f"| {event} | {name} | {summary(values)} |")


if __name__ == "__main__":
    main()
