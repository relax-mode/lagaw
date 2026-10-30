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

Dependabot (section 2 below) keeps these pins current by proposing SHA bumps.

## Pipeline optimization (Sprint 4)

Pending: this section is filled in with the baseline and the post-change
measurement described below.
