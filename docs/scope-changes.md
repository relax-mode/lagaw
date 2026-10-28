# Scope changes

## 2026-10-14: DeepSeek preference extraction

The team selected DeepSeek instead of the Gemini provider named in the original pitch. The backend, configuration, and pitch now reflect this decision. Structured preference extraction, backend schema validation, and the self-developed recommendation model retain their scope. Report this provider change at the next consultation.

## 2026-10-26: Shared staging instead of per-pull-request previews

The pitch planned a Cloudflare Pages preview for every frontend pull request. The team instead uses one shared staging environment: Cloud Run `lagaw-api-staging` with the development database, and Pages `staging`. Every merge to `main` deploys there first and is promoted to production only after staging passes its smoke checks.

A per-PR preview of the web app alone would still call the production API, or would need a backend per PR, which free Cloud Run quotas and the per-origin CORS policy make impractical. Pull requests remain fully checked by CI. Recorded by CyGray under [#58](https://github.com/relax-mode/lagaw/issues/58); report it at the next consultation.

## 2026-10-29: Backend authentication rollout before Flutter sessions

Andrew directed #79 to proceed independently so #80 and teammate follow-up can
be handled afterward. Existing Flutter demo-token calls will receive 401 after
backend cutover until #80 supplies Supabase access tokens. This is a temporary
integration limitation; the final functional frontend requirement remains.

For this authentication migration only, production promotion is paused by a
required `aranxshx` reviewer on the existing production GitHub Environment.
Staging still deploys through CI and uses development Supabase. Verify staging,
prepare the production schema and its own smoke account/configuration, then
approve promotion. Restore the previous reviewer setting after the rollout.
The existing protected-branch restriction is retained. This changes release
ordering; it does not reduce the reviewed-PR, CI or deployed-acceptance criteria.

Completed October 29: #92 merged as `7186a08`; staging and production deployment
and backend ownership verification passed in order. The temporary production
reviewer was removed afterward, preserving the original protected-branch policy.
Automatic promotion is restored. [Final backend evidence](evidence/authentication-79.md)
records acceptance, cleanup and the explicit remaining #80 limitation.

