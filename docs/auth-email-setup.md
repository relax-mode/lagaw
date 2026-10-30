# Auth email setup: Resend SMTP for Supabase

Issues #112 (evaluate sender) and #113 (configure). Status: **PREPARED BUT BLOCKED BY
SENDER-DOMAIN VERIFICATION.** The team has selected Resend. The checker script and
this runbook are ready. Live configuration waits until the team owns a sending
domain and verifies it in Resend. Until then Supabase keeps its built-in mailer, which
sends 2 auth emails per hour per project.

Sources were fetched on **October 30, 2026**. Anything not confirmed there is marked
UNVERIFIED.

## Decision

- Provider: **Resend**, selected by the team. Brevo is not being evaluated further.
- Why the sender must change: Supabase's built-in mailer caps auth email at about
  2 per hour per project and delivers only to team members (see
  [flutter-authentication.md](flutter-authentication.md#hosted-auth-settings)).
- Resend requires a verified domain to send to anyone:
  "You must add and verify at least one domain to send emails with Resend."
  ([domains introduction](https://resend.com/docs/dashboard/domains/introduction))
- The team owns **no** custom sending domain yet. This is the blocker.

## Exact SMTP settings

From [Resend: Send with SMTP](https://resend.com/docs/send-with-smtp):

| Supabase field | Value | Source |
| --- | --- | --- |
| `smtp_host` | `smtp.resend.com` | Resend SMTP page |
| `smtp_port` | `465` (implicit TLS). Alternatives 2465 (implicit TLS), or 25, 587, 2587 (STARTTLS) | Resend SMTP page |
| `smtp_user` | `resend` | Resend SMTP page |
| `smtp_pass` | the Resend **sending** API key (`RESEND_API_KEY`) | Resend SMTP page |
| `smtp_admin_email` | an address on your **verified** domain, for example `noreply@<verified-domain>` | Supabase, Management API reference |
| `smtp_sender_name` | `Lagaw` | Supabase, Management API reference |
| `rate_limit_email_sent` | `30` per hour | Supabase SMTP page |

Supabase's Management API types `smtp_port` as a **string**, so the checker sends `"465"`.
([Management API reference](https://supabase.com/docs/reference/api/v1-update-auth-service-config))

## Staging and production are configured separately

- **Staging** is the development Supabase project. Its Site URL and redirects point to
  the staging web app, and staging pilots the sender.
- **Production** is its own Supabase project, with its own Site URL, redirects and
  SMTP settings. Each project's auth config is set in its own PATCH. A change applied
  to one never moves the other.
- The checker refuses identical staging and production refs. Each environment gets
  its own `--project-ref` or `*_SUPABASE_PROJECT_REF` value.
- Why separate: a mistake in staging must not change production email, and the
  production sender must be verified before production uses it.

Project refs are not secrets. They are passed as arguments or environment variables,
not hardcoded.

## Runbook

Run from the repository root. Use a DevOps shell where the names in `.env.example`
are exported from the secret store. Never print their values.

1. **Add the domain in Resend.** Dashboard, Domains, Add Domain. Use a domain the team
   controls.
2. **Add DNS records.** Copy the SPF, DKIM and DMARC records exactly as the Resend
   dashboard shows them. Resend's domain page recommends DMARC: "Implement DMARC and
   BIMI to build trust and improve inbox placement." The exact record types and values
   are UNVERIFIED here; use the dashboard, not this document.
3. **Verify in the dashboard.** Wait for the domain to show verified. The API cannot
   show this with a sending-only key (see troubleshooting). Confirm in the dashboard
   with an owner account.
4. **Create or confirm the sending key.** Resend dashboard, API Keys. The key needs
   sending permission. Store it as `RESEND_API_KEY` in the DevOps secret store.
5. **Set the sender.** Set `SMTP_ADMIN_EMAIL` to an address on the verified domain.
   Set `SMTP_SENDER_NAME` to `Lagaw` or leave it unset.
6. **Preflight (local, no network).**
   ```
   ../.venv/bin/python scripts/check_email_config.py preflight --env staging
   ```
   Fix every FAIL. A WARN for `resend.dev` or a free mail provider means the sender is
   test-only and `apply` refuses it.
7. **Plan (one read-only GET).**
   ```
   ../.venv/bin/python scripts/check_email_config.py plan --env staging
   ```
   Review the differing field list. `smtp_pass` always shows as `<redacted>`.
8. **Apply, with explicit authorization.** Only after a human approves the plan:
   ```
   ../.venv/bin/python scripts/check_email_config.py apply --env staging --execute --confirm staging
   ```
   Production adds `--production-authorized-by "<name and date of approval>"`, and it
   also needs its own preflight, plan and apply. The apply command verifies the result
   with a read-only GET.
9. **Confirm the rate limit.** Run `inspect --env staging`. `rate_limit_email_sent` should
   read `30`, and `smtp_pass_set` should read `True`.
10. **Run the verification procedure below** on staging, then repeat for production.

## Verification (authorized mailboxes only)

Never use real users or real personal inboxes. Use two accounts you control, and a
dedicated test account in the target project.

1. **Signup confirmation.** Sign up with an authorized test address. The confirmation
   email should arrive from the verified sender. Click the link. It must land on the
   environment's own web origin, not localhost or another environment.
2. **Password recovery.** Request a reset for the same test account. The email should
   arrive and the link should land on the environment's own web origin.
3. **Rate-limit check.** Confirm the hourly limit reads 30 in `inspect`. Do not
   exceed the limit with real traffic.
4. **Record the outcome** in `docs/sprint-log.md` (who ran it, date, pass or fail).
   Never record addresses, tokens or links.

Email confirmation **must stay enabled** in both projects. `mailer_autoconfirm` stays
`false`. The checker never reads or writes it.

## Troubleshooting

| Symptom | Likely cause | Action |
| --- | --- | --- |
| `GET /domains` returns 401 `restricted_api_key` | The key is restricted (sending-only). The key is valid; it cannot list domains. | Confirm domain status in the dashboard, or use a full-access key only for the check. Not a revoked key. |
| Send fails with 403, domain not verified | The sender domain is not verified. Resend requires a verified domain to send. | Finish step 2 and 3; re-check in the dashboard. |
| SMTP 535 authentication failed | `smtp_user` is not `resend`, or `smtp_pass` is not a valid sending key. Standard SMTP reply code; Resend's exact response is UNVERIFIED. | Check `inspect` (`smtp_user_set`, `smtp_pass_set`), then rotate or re-create the key and re-run `plan`. |
| Still "Too many attempts" on signup | Built-in mailer still active, or custom SMTP not saved. Supabase's built-in limit is 2 per hour. | Confirm `smtp_host` reads `smtp.resend.com` in `inspect`. |
| Supabase refuses the rate-limit change | Supabase refuses to raise `rate_limit_email_sent` until custom SMTP is saved (observed October 29, 2026). The PATCH carries SMTP and the limit together. | Run `plan` to see which fields still differ, then re-run `apply`. It is idempotent. |
| Confirmation link goes to localhost or the wrong environment | Site URL or Redirect URLs wrong. Supabase falls back to the Site URL when a redirect is not allow-listed. | Check the URL Configuration against [flutter-authentication.md](flutter-authentication.md#hosted-auth-settings). |
| Mail delivered only to the account owner | Sender is `onboarding@resend.dev` or another test sender. | Use an address on the verified domain. |

## What stays UNVERIFIED

- Exact DNS record types and values for SPF, DKIM and DMARC (use the Resend dashboard).
- Domain verification time and status values in Resend.
- Whether `rate_limit_email_sent` can be raised only with custom SMTP. Supabase's
  pages confirm the 30 default but not this rule. The sprint log records Supabase's
  refusal on October 29, 2026.
- Whether the Management API returns `smtp_pass` or `smtp_user` values. The checker
  reads only booleans for these fields and never prints them.
- The `Authorization: Bearer` header for the Management API. The sprint log records
  that the personal access token works, but this header format was not re-checked
  against the reference page.
- Resend's exact SMTP error replies (for example 403 and 535 bodies).

## Sources (fetched October 30, 2026)

- [Resend: Send with SMTP](https://resend.com/docs/send-with-smtp): host, username,
  password, ports and TLS modes, verified domain required.
- [Resend: Domains introduction](https://resend.com/docs/dashboard/domains/introduction):
  verified domain required; DMARC recommended.
- [Supabase: Custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp): built-in
  mailer 2 messages per hour; custom SMTP default 30 per hour.
- [Supabase Management API: update auth config](https://supabase.com/docs/reference/api/v1-update-auth-service-config):
  `PATCH /v1/projects/{ref}/config/auth`; `smtp_port` is a string;
  `rate_limit_email_sent` is an integer.
