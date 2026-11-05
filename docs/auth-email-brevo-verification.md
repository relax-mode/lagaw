# Lagaw — Brevo SMTP and Supabase Auth verification (S4-13)

**As of November 5, 2026.** This is the active runbook for [S4-13 / issue #113](https://github.com/relax-mode/lagaw/issues/113). The November 3 [provider comparison](auth-email-provider-evaluation.md) and [Resend-only helper](../scripts/check_email_config.py) are historical: **do not use the Resend helper to configure Brevo**. This document records what has actually been confirmed and keeps untested outcomes clearly separate.

## Verified and unverified evidence

| Environment / flow | State | Evidence and limitations |
| --- | --- | --- |
| Development custom SMTP / signup confirmation | **USER-CONFIRMED** | Team reports Brevo configured; an email was received by an authorized outside recipient and the account confirmation succeeded. This is human-observed, not independently verified from the Supabase Management API. |
| Development/staging recovery email delivery | **USER-CONFIRMED** | November 3 controlled mailbox received the recovery message. Its link originally opened the app without a password-update screen. |
| Recovery UI implementation | **CI-VERIFIED** | [PR #150](https://github.com/relax-mode/lagaw/pull/150) merged November 5 with reviewed Flutter tests; its [main-branch run](https://github.com/relax-mode/lagaw/actions/runs/41983280342) deployed staging and production web. |
| Fresh recovery link → change password → new login | **UNVERIFIED** | Needs a fresh link after the deployed fix. A delivered email or HTTP 200 from `/auth/v1/recover` does not prove password recovery succeeds. |
| Production SMTP, signup and recovery | **UNVERIFIED** | Production is a different Supabase project. Development success does not establish its sender, Auth configuration, mail delivery, links or hourly limits. |
| Supabase Management API read | **BLOCKED** | On November 5, the existing Agent Hub `SUPABASE_PERSONAL_ACCESS_TOKEN` returned HTTP 401 for both project Auth-config GETs; it did not provide a trustworthy configuration read. No settings were changed. |

These observations must not be presented as full S4-13 acceptance until both production email flows and the recovery action are verified on authorized accounts.

## Brevo settings (manual Supabase dashboard configuration)

**Staging and production must be configured independently** in their own Supabase dashboards, under Authentication → SMTP Settings, using the exact Brevo credentials granted to the team. Never paste keys into an issue, PR, command line history, frontend build or shared evidence file.

| Supabase SMTP field | Brevo setting |
| --- | --- |
| Host | `smtp-relay.brevo.com` |
| Port / encryption | Use Brevo's supported port with matching TLS behavior (commonly `587` with STARTTLS; also consult Brevo's port guidance). |
| Username | Brevo's **SMTP login** from SMTP & API (not the relay host and not assumed to equal the dashboard sign-in). |
| Password | The separate **Brevo SMTP key**, not the Brevo account password or API key. |
| Sender email | A sender explicitly verified/approved in Brevo, or an address from an authenticated sending domain. |
| Sender name | `Lagaw` |

Verify the Brevo transactional-sending status and sender approval in the Brevo dashboard. A successful development send proves that recipient received that message; it does **not** by itself establish domain DNS authentication or unrestricted, reliable production deliverability. For production, check sender-domain SPF/DKIM/DMARC and the provider's requirements. Keep Supabase email confirmation **enabled**, avoid modifying `mailer_autoconfirm`, and check the configured Auth email rate limit rather than assuming the default built-in limit remains.

**Credential preflight without revealing values:** Check in the dashboards that the intended environment has a configured Brevo relay, an approved From sender, and the correct project-specific URL allowlist. The existing `scripts/check_email_config.py` compares against Resend-only constants and **must not** be used to inspect/plan/apply Brevo as though it were the configured provider. Use Supabase's UI until a correctly scoped management PAT works; the stale PAT's HTTP 401 is not evidence that SMTP is broken.

## Complete the remaining acceptance checks

1. **Development/staging recovery:** On [staging](https://staging.lagaw.pages.dev), request a *new* password-reset email for a dedicated authorized test account. Follow its freshly received link, confirm the Lagaw new-password form opens, set a new password, sign out, and verify the **new** password signs in while the **old** password fails. Expired/invalid links should show a safe error; do not log the link, token or password. See [issue #149](https://github.com/relax-mode/lagaw/issues/149).
2. **Production configuration:** In the production Supabase project, independently inspect SMTP host, sender approval, URL configuration, confirmation setting and hourly quota. Configure the selected Brevo sender only after the team approves the production change; this document is **not** an authorization to apply configuration. The production Site URL and redirect allowlist must point at [the production web app](https://lagaw.pages.dev), not staging or localhost.
3. **Production signup confirmation:** From the production app, create one authorized test account and verify the actual email arrives and the confirmation link activates that account on the production origin. Record only the observed result and date, never personal addresses or confirmation URLs.
4. **Production recovery:** For that authorized test account, request a new recovery email; verify delivery, the correct production-origin new-password form, password update, new-password login and old-password rejection.
5. **Finish evidence:** Save a redacted test record to the sprint log or `docs/evidence/` with date, environment, test role, expected outcome, actual outcome, CI link and any failure codes. Update issue #113 checkboxes **only** when production SMTP and both production flows have been verified. Keep issue #149 open until the deployed recovery acceptance is demonstrated.

A screenshot of a success state or a redacted inbox receipt can support the manual acceptance record; do not publish email addresses, session tokens, recovery links, passwords, SMTP usernames/keys or full Auth-config API responses.

## Official references (reviewed November 5, 2026)

- [Brevo: Send transactional emails using Brevo SMTP](https://help.brevo.com/hc/en-us/articles/7924908994450-Send-transactional-emails-using-Brevo-SMTP) — SMTP host, login and key.
- [Brevo: SMTP troubleshooting](https://help.brevo.com/hc/en-us/articles/115000188150-Troubleshooting-Issues-with-Brevo-SMTP) — credential differences, sender verification and domain authentication.
- [Supabase: Custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp) — production delivery, per-project setup and quota.
- [Supabase: Password-based Auth](https://supabase.com/docs/guides/auth/passwords) — recovery and password update.
