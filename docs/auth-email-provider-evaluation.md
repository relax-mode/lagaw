# Supabase Auth email provider evaluation — November 3, 2026

**Issue:** [#112](https://github.com/relax-mode/lagaw/issues/112) (provider decision). **Implementation follow-up:** [#113](https://github.com/relax-mode/lagaw/issues/113).

**Decision:** Retain **Resend** as the team's chosen SMTP provider, as previously recorded in [the setup runbook](auth-email-setup.md). This is a *provider-selection decision*, not evidence that a working custom sender has been configured. **Neither staging nor production has verified custom SMTP delivery.** The team has no controlled sending domain, so Resend's general-recipient delivery prerequisite is still unmet.

## Verified provider comparison

| Question | Brevo | Resend |
| --- | --- | --- |
| Compatible with Supabase custom SMTP? | Yes; Supabase explicitly lists Brevo among supported SMTP services. Sender and account approval still apply. | Yes; Supabase explicitly lists Resend, and the [Resend SMTP guide](https://resend.com/docs/send-with-smtp) provides host, TLS ports and authentication settings. |
| Free allowance (public pricing, checked Nov 3, 2026) | **300 emails/day**, including transactional emails, according to [Brevo's plan overview](https://help.brevo.com/hc/en-us/articles/208589409-About-Brevo-s-pricing-plans). Additional sends may be queued according to [Brevo's free-plan help](https://help.brevo.com/hc/en-us/articles/8292912279954-Add-or-remove-emails-from-your-plan). | **3,000 emails/month, up to 100/day**, and **3 verified domains**, according to [Resend pricing](https://resend.com/pricing). |
| Sender/domain verification | Brevo requires a verified individual sender or authenticated sending domain. Domain authentication is emphasized for major mailbox-provider requirements; a verified sender alone is not proof of reliable domain-less delivery to arbitrary users. See [Brevo SMTP troubleshooting](https://help.brevo.com/hc/en-us/articles/115000188150-Troubleshooting-Issues-with-Brevo-SMTP). | Resend requires at least one verified sending domain for general-recipient sending. See [Resend domains](https://resend.com/docs/dashboard/domains/introduction). |
| Team configuration and evidence | No approved Brevo SMTP sender, account activation, authorized recipient test or custom-domain ownership is recorded. Thus **UNVERIFIED** as a practical fallback. | The team has selected Resend and committed a safe preflight/plan/apply helper ([PR #123](https://github.com/relax-mode/lagaw/pull/123)). The key's sending-only scope was observed in the Oct 30 review; sender-domain verification, custom SMTP apply and delivery tests remain **NOT PERFORMED**. |
| Decision implication | Higher published daily allowance, but switching would require an account/sender verification process and its own delivery tests; **not a demonstrated shortcut** around the current blocker. | Chosen provider already has prepared configuration and runbook. The missing domain prevents promoting the configuration into staging and production. |

**Supabase baseline:** Its built-in auth sender is not intended for production: current limits are **2 messages/hour per project** and sending only to pre-authorized team addresses. With custom SMTP Supabase starts at **30 messages/hour** (separate from the provider's daily/monthly quota). Sources: [Supabase custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp), [Auth limits](https://supabase.com/docs/guides/auth/rate-limits), and [testing hosted auth email flows](https://supabase.com/docs/guides/auth/testing-auth-flows).

## Evidence of testing and limitations

- **Completed:** reviewed published provider requirements and pricing on November 3, 2026, checked existing project's Oct 30 setup record and confirmed the safe configuration helper and its tests had already passed CI in [PR #123](https://github.com/relax-mode/lagaw/pull/123).
- **Not attempted:** a live Brevo SMTP message, Resend sender-domain verification, or Resend SMTP delivery to an authorized inbox. The team has no verified sending domain; an SMTP connection or API key alone does **not** prove working confirmation or recovery email.
- **Not attempted:** live production Auth configuration changes. Do not disable email confirmation or use a test sender to claim unrestricted delivery.
- **Still required by #113:** obtain a controlled sending domain, add its DNS records, verify it through Resend, configure staging with the existing runbook, run signup-confirmation and password-recovery tests to authorized mailboxes, then repeat only after approval in production. Record date, environment, observed arrival and link handling without any addresses, tokens or secrets.
- **Decision review trigger:** If no controlled domain will be obtained before Demo Day, explicitly revisit whether a Brevo verified-sender setup can satisfy the actual recipient and domain-authentication requirements. Treat this as a new evidence-gathering exercise, not a proven fallback.

## Sources and scope

Public documentation checked **November 3, 2026**. Plan limits and sender policies may change; confirm again at setup. This is a documentation-only evaluation. No service, email provider account, secret, API credential, deployment or live recipient was changed.
