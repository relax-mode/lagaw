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
| Production signup **confirmation email** | **USER-CONFIRMED PASS, November 5** | The authorized tester explicitly confirms the production signup-confirmation flow works, in addition to production sign-in and recovery. This is a real user-reported functional result, not an independently audited inbox/provider log. |
| Supabase Management API read | **BLOCKED** | On November 5, the existing Agent Hub `SUPABASE_PERSONAL_ACCESS_TOKEN` returned HTTP 401 for both project Auth-config GETs; it did not provide a trustworthy configuration read. No settings were changed. |

**S4-13 live functional acceptance is user-confirmed COMPLETE:** staging recovery, production signup confirmation, production sign-in and production password recovery all work according to the authorized tester. This is human-observed evidence, not independently audited provider/API or access-log verification. The earlier staging password-reuse diagnosis is plausible, not proven from a captured provider response. Old-password-rejection negative testing for the separate #149 issue was not explicitly reported.

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
3. **Production signup confirmation — user-confirmed pass:** The tester expressly confirms the production signup-confirmation flow works. This is distinct from the already confirmed production sign-in and recovery checks. No test mailbox, confirmation token or personal data is stored. Independent admin/log inspection was not possible with the stored management PAT (401).
4. **Optional negative-case evidence:** If not already verified, confirm old passwords fail after reset on the authorized staging/production test accounts, then record the result without passwords. A previously submitted same password likely caused the staging HTTP 422; the exact Supabase error response was not captured, so this remains an inference.
5. **Closeout:** The tester has confirmed the separate production signup-confirmation result and production recovery. [S4-13 issue #113](https://github.com/relax-mode/lagaw/issues/113) may be closed on this human-observed evidence, with the credential inspection (PAT 401) limitation recorded. Keep [#149](https://github.com/relax-mode/lagaw/issues/149) old-password-rejection negative-case acceptance explicit. Do not merge an unrelated diagnostic change merely to mark the flow functional.

A screenshot of a success state or a redacted inbox receipt can support the manual acceptance record; do not publish email addresses, session tokens, recovery links, passwords, SMTP usernames/keys or full Auth-config API responses.

## Official references (reviewed November 5, 2026)

- [Brevo: Send transactional emails using Brevo SMTP](https://help.brevo.com/hc/en-us/articles/7924908994450-Send-transactional-emails-using-Brevo-SMTP) — SMTP host, login and key.
- [Brevo: SMTP troubleshooting](https://help.brevo.com/hc/en-us/articles/115000188150-Troubleshooting-Issues-with-Brevo-SMTP) — credential differences, sender verification and domain authentication.
- [Supabase: Custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp) — production delivery, per-project setup and quota.
- [Supabase: Password-based Auth](https://supabase.com/docs/guides/auth/passwords) — recovery and password update.
