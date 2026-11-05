# Lagaw — Brevo SMTP and Supabase Auth verification (S4-13)

**As of November 5, 2026.** This is the active runbook for [S4-13 / issue #113](https://github.com/relax-mode/lagaw/issues/113). The November 3 [provider comparison](auth-email-provider-evaluation.md) and [Resend-only helper](../scripts/check_email_config.py) are historical: **do not use the Resend helper to configure Brevo**. This document records what has actually been confirmed and keeps untested outcomes clearly separate.

## Verified and unverified evidence

| Environment / flow | State | Evidence and limitations |
| --- | --- | --- |
| Development custom SMTP / signup confirmation | **USER-CONFIRMED** | Team reports Brevo configured; an email was received by an authorized outside recipient and the account confirmation succeeded. This is human-observed, not independently verified from the Supabase Management API. |
| Development/staging recovery email delivery | **USER-CONFIRMED** | November 3 controlled mailbox received the recovery message. Its link originally opened the app without a password-update screen. |
| Recovery UI implementation | **CI-VERIFIED** | [PR #150](https://github.com/relax-mode/lagaw/pull/150) merged November 5 with reviewed Flutter tests; its [main-branch run](https://github.com/relax-mode/lagaw/actions/runs/41983280342) deployed staging and production web. |
| Staging recovery email, link, redirect and password update | **USER-CONFIRMED PASS, November 5** | An authorized tester confirms Brevo email delivery, correct link/redirect, the update form, and a successful password reset in staging. An earlier HTTP 422 during a password-update attempt did not recur in the successful subsequent test; the tester believes password reuse was likely, but the original provider error code was not captured. Separate old-password-rejection evidence was not provided. |
| Production Brevo Supabase Auth setup | **USER-CONFIRMED CONFIGURED, November 5** | Team reports that a dedicated Brevo credential was created and production Supabase Auth SMTP configured. Credential type and dashboard fields were not independently read or recorded. |
| Production sign-in and complete password recovery | **USER-CONFIRMED PASS, November 5** | Authorized tester reports production sign-in and end-to-end password recovery work. The user's report supports delivery/use of the reset link, updating the password and sign-in; no credentials, URLs or private account data were collected. Old-password-rejection was not separately reported. |
| Production signup **confirmation email** | **NOT YET EVIDENCED** | A successful production sign-in does not establish that a newly created account receives its confirmation email and can confirm via the production-origin link. This is the remaining independent live-email acceptance item. |
| Supabase Management API read | **BLOCKED** | On November 5, the existing Agent Hub `SUPABASE_PERSONAL_ACCESS_TOKEN` returned HTTP 401 for both project Auth-config GETs; it did not provide a trustworthy configuration read. No settings were changed. |

**S4-13 acceptance is not yet fully documented:** staging and production password recovery are user-confirmed successful, but a separate production **new-account signup-confirmation email** test is not reported. Treat the report as human-observed, not an independently audited provider/API or access-log verification. The password-reuse error diagnosis was plausible, not proven from a captured provider response.

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

## Acceptance follow-up

1. **Staging recovery — user-confirmed pass:** The tester reports the staging Brevo message, link, redirect, form and password change now work. See [issue #149](https://github.com/relax-mode/lagaw/issues/149). An explicit old-password sign-in rejection was not independently recorded.
2. **Production Brevo and recovery — user-confirmed pass:** The tester reports a separate production Brevo credential, Supabase SMTP setup, working production sign-in, and the complete recovery flow. This is stronger operational evidence than checking only whether a provider key exists. Exact management configuration, sender authentication and quotas remain unavailable to the current Management API PAT (HTTP 401); do not misrepresent these as inspected.
3. **Production signup confirmation — still pending explicit evidence:** From [production](https://lagaw.pages.dev), create one authorized *new* test account and confirm the signup email arrives, directs to the production origin and activates that account. Report only pass/fail/date and a redacted test role; do not record inbox addresses or URLs. Production sign-in/reset alone do not cover this separate acceptance criterion.
4. **Optional negative-case evidence:** If not already verified, confirm old passwords fail after reset on the authorized staging/production test accounts, then record the result without passwords. A previously submitted same password likely caused the staging HTTP 422; the exact Supabase error response was not captured, so this remains an inference.
5. **Closeout:** Once the production signup-confirmation result is documented, check the outstanding [S4-13 issue](https://github.com/relax-mode/lagaw/issues/113) tasks. Keep the [S4 recovery issue](https://github.com/relax-mode/lagaw/issues/149) negative-case acceptance explicit. Do not merge unrelated diagnostic changes merely to mark this recovery flow functional.

A screenshot of a success state or a redacted inbox receipt can support the manual acceptance record; do not publish email addresses, session tokens, recovery links, passwords, SMTP usernames/keys or full Auth-config API responses.

## Official references (reviewed November 5, 2026)

- [Brevo: Send transactional emails using Brevo SMTP](https://help.brevo.com/hc/en-us/articles/7924908994450-Send-transactional-emails-using-Brevo-SMTP) — SMTP host, login and key.
- [Brevo: SMTP troubleshooting](https://help.brevo.com/hc/en-us/articles/115000188150-Troubleshooting-Issues-with-Brevo-SMTP) — credential differences, sender verification and domain authentication.
- [Supabase: Custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp) — production delivery, per-project setup and quota.
- [Supabase: Password-based Auth](https://supabase.com/docs/guides/auth/passwords) — recovery and password update.
