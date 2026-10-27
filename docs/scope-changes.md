# Scope changes

## 2026-10-14: DeepSeek preference extraction

The team selected DeepSeek instead of the Gemini provider named in the original pitch. The backend, configuration, and pitch now reflect this decision. Structured preference extraction, backend schema validation, and the self-developed recommendation model retain their scope. Report this provider change at the next consultation.

## 2026-10-26: Shared staging instead of per-pull-request previews

The pitch planned a Cloudflare Pages preview for every frontend pull request. The team instead uses one shared staging environment: Cloud Run `lagaw-api-staging` with the development database, and Pages `staging`. Every merge to `main` deploys there first and is promoted to production only after staging passes its smoke checks.

A per-PR preview of the web app alone would still call the production API, or would need a backend per PR, which free Cloud Run quotas and the per-origin CORS policy make impractical. Pull requests remain fully checked by CI. Recorded by CyGray under [#58](https://github.com/relax-mode/lagaw/issues/58); report it at the next consultation.

