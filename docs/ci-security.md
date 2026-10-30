# CI/CD security and pipeline efficiency (Sprint 4)

This document records how the Lagaw GitHub Actions workflows are secured and
how the pipeline was measured. It covers Issue #119.

## 1. Third-party action pinning

Every third-party `uses:` is pinned to a full 40-character commit SHA, with the
release tag kept in a trailing comment for readability. The pinned version is
the latest release tag within the major version the workflows already used, so
no major-version upgrade happened in this change.

Verification for every row: `gh api repos/<owner>/<repo>/git/ref/tags/<tag>`
returned `object.type = commit` (no annotated-tag dereference was needed), and
`gh api repos/<owner>/<repo>/commits/<sha> --jq .sha` returned the same SHA.

| Action | Major used | Pinned tag | Commit SHA | How verified |
| --- | --- | --- | --- | --- |
| `actions/checkout` | v4 | v4.4.0 | `11d5960a326750d5838078e36cf38b85af677262` | ref type `commit`; commits endpoint matches |
| `actions/setup-python` | v5 | v5.6.0 | `a26af69be951a213d495a4c3e4e4022e16d87065` | ref type `commit`; commits endpoint matches |
| `actions/setup-node` | v4 | v4.4.0 | `49933ea5288caeca8642d1e84afbd3f7d6820020` | ref type `commit`; commits endpoint matches |
| `actions/upload-artifact` | v4 | v4.6.2 | `ea165f8d65b6e75b540449e92b4886f43607fa02` | ref type `commit`; commits endpoint matches |
| `dorny/paths-filter` | v3 | v3.0.4 | `0e4a8c6effa4802afeda77dc8d303f8176d7dfad` | ref type `commit`; commits endpoint matches |
| `subosito/flutter-action` | v2 | v2.23.0 | `1a449444c387b1966244ae4d4f8c696479add0b2` | ref type `commit`; commits endpoint matches |
| `google-github-actions/auth` | v2 | v2.1.13 | `c200f3691d83b41bf9bbd8638997a462592937ed` | ref type `commit`; commits endpoint matches |
| `google-github-actions/deploy-cloudrun` | v2 | v2.7.6 | `251330ba9a8a34bfbc1622895f42e1d53fd14522` | ref type `commit`; commits endpoint matches |
| `docker/setup-buildx-action` | v3 | v3.12.0 | `8d2750c68a42422c14e847fe6c8ac0403b4cbd6f` | ref type `commit`; commits endpoint matches |
| `docker/build-push-action` | v6 | v6.19.2 | `10e90e3645eae34f1e60eeb005ba3a3d33f178e8` | ref type `commit`; commits endpoint matches |

Service container image:

| Image | Tag | Digest | How verified |
| --- | --- | --- | --- |
| `postgrest/postgrest` | v12.2.3 | `sha256:729bf65c733b73f5b52777f0e4b853f22ed73aa67a22d38269d289779b0a8401` | Docker Hub registry v2 manifest GET (token from `auth.docker.io`); `Docker-Content-Digest` header matches the `sha256sum` of the returned manifest-list body. This is a multi-arch manifest-list digest. |

Newer majors exist upstream for most of these (for example `actions/checkout` v7, `google-github-actions/auth` v3). They were not adopted here because a major upgrade is a behaviour change; Dependabot proposes them as separate, reviewable PRs.

## 2. Dependabot

`.github/dependabot.yml` covers the ecosystems that exist in the repository: `github-actions` (`/`), `pip` (`/backend`), `npm` (`/`) and `pub` (`/frontend`). Updates run weekly on Monday (Asia/Manila), minor and patch updates are grouped per ecosystem, and each ecosystem is limited to 3 open PRs to limit noise. Dependabot does not bump the pinned Flutter SDK version (section 5); that is a manual change.

## 3. Secret scanning (`secret-scan` job)

- Runs on every pull request and push, never path-filtered, with `contents: read` only.
- Uses the gitleaks CLI, not `gitleaks-action` (which needs an organization licence). The release tarball's SHA-256 is hard-coded in the workflow and checked before extraction.
- Pull requests scan only the commits they add; pushes scan the pushed range, or full history if the previous SHA is unavailable. Output is `--redact`ed, no report file is written and nothing is uploaded.
- Baseline: a full-history scan found one finding, a deliberately fake literal in `backend/test_auth.py`. It is allowlisted in `.gitleaks.toml` by path **and** literal, so no rule is disabled and the same string elsewhere is still reported.
- **Policy when it fails:** treat the finding as real. Do not paste the value anywhere. Rotate the credential first, then remove it from the branch. An allowlist entry is acceptable only for a demonstrably synthetic value, with a comment saying why, reviewed in the PR.

## 4. Dependency audit (`dependency-audit` job)

- `pip-audit` on `backend/requirements.txt` and `npm audit --audit-level=high` on the root lockfile. The tools' own exit codes are ignored; `scripts/audit_gate.py` decides and fails closed on an unreadable report.
- Enforcement distinguishes **new** from **historical** findings: any advisory not listed in `.github/security/audit-allowlist.json` fails the job. An allowlist entry needs an advisory ID, package, reason and `review_by` date, and an entry past its date fails again while the finding exists.
- Baseline at the time of writing (October 30, 2026): pip-audit 0 vulnerabilities across 23 packages; npm audit 4 high advisories, all `undici` through `wrangler` 4.151.0 (deploy tooling only), allowlisted until 2026-12-31. Two moderate advisories are below the threshold. The job prints only advisory IDs and package names.
- Flutter/Dart has no audit tool in the pipeline; Dependabot `pub` updates are the only coverage. This is a known gap.

## 5. Permissions

Every job now declares `permissions: contents: read` explicitly. `id-token: write` remains only on `deploy-staging` and `deploy-backend`, the two jobs that authenticate to Google Cloud through Workload Identity Federation. `changes` keeps `pull-requests: read` for the path filter. Environments, `needs`, secrets and deploy steps are unchanged. The new jobs are not required status checks (branch protection requires only Backend, Database and Frontend); making them required is a manual repository setting.

## 6. GitHub settings that need a repository admin

Read-only API output on October 30, 2026 shows these are all **disabled**. They are not changed by this PR:

1. Settings, Code security: enable **Dependabot alerts** and **Dependabot security updates**.
2. Same page: enable **Secret scanning** and **Push protection** (free for public repositories; for a private repository these need GitHub Secret Protection).
3. Settings, Branches, `main` rule: optionally add `Secret scan - gitleaks` and `Dependency audit - pip and npm` to the required checks once they have passed on `main` a few times.

## 7. Pipeline optimization (Sprint 4)

**Bottleneck.** On `main` pushes the critical path is `Frontend - Flutter` followed by `Deploy - Staging` and then the production jobs. Each of three jobs runs `subosito/flutter-action` with `channel: stable` and no version, so the SDK cache key follows whatever stable currently is: a new Flutter release invalidates the cache in all three jobs at once, adds a cold download to that run, and makes builds non-reproducible.

**Change.** Pin `flutter-version: "3.47.8"` (with `channel: stable`) in all three jobs. 3.47.8 is the version those jobs resolved in run [40834627148](https://github.com/relax-mode/lagaw/actions/runs/40834627148) and in earlier runs, so the build input does not change. No test, build or smoke step was removed.

**Baseline (before the change).** Seconds per job, successful `Lagaw CI` runs triggered by pushes to `main`, from the GitHub Actions jobs API (`startedAt` to `completedAt`; each job's own run time, not including queue time). Runs: 40834627148, 40831682433, 40824669528, 40815760387, 40814899097, 40745998598, 40739574662, 40727856244. Not every run executed every job.

| Job | n | Values (s) | Median (s) |
| --- | --- | --- | --- |
| Frontend - Flutter | 8 | 104, 104, 97, 116, 98, 88, 86, 104 | 101 |
| Deploy - Staging | 6 | 108, 107, 131, 174, 186, 281 | 152 |
| Deploy - Production web | 6 | 77, 74, 83, 69, 73, 96 | 76 |

Within run 40834627148 the `Set up Flutter` step took 22 s (CI frontend), 21 s (staging) and 22 s (production web).

**Result.** Implemented, awaiting measurement. The expected benefit is stability rather than a lower median: it avoids the periodic cold-cache run (see the 281 s staging outlier, which was not diagnosed) and makes the SDK reproducible for the release. After merge, compare the same jobs on the next `main` pushes using `python3 scripts/pipeline_metrics.py --jobs` and record the numbers in `docs/pipeline-metrics.md`. A single post-merge run is not enough to claim a speed-up.

**Trade-off.** The SDK no longer follows stable automatically; bumping Flutter becomes an explicit one-line PR. Dependabot does not do this for us.

**Not done.** Splitting the web builds out of the deploy jobs would remove more time from the critical path but changes deploy ordering, so it was not attempted in this PR.
