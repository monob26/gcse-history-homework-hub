# Remaining hosted test prerequisites and approval boundaries

2026-11-15. The owner declined a Supabase Pro upgrade. Leaked-password protection
remains unresolved; REVIEW.md is unchanged and R2 remains incomplete. No hosted
tests, fixtures, Auth changes, emails or new settings were applied for this assessment.
The two previously approved R2 migrations remain deployed.

## Access verification: R2.3/R2.4 and T1–T4

Prepare a separate explicitly gated hosted mode in tests/adversarial/; the existing
runner refuses non-local targets and must not simply have that safeguard removed.
Use the known project URL/publishable key, current schema inventory and fixed fixture
IDs. Keep passwords, JWTs and reset/session tokens in memory and out of reports.
Do not reuse local fixture preparation on hosted: it creates a published quiz that
could become current homework. Review a hosted-specific fixture/cleanup script first.

Required fictional fixtures:

- Teacher A allocated only to fictional class A.
- Teacher B allocated only to fictional class B.
- An approved teacher with no allocated classes.
- Fictional pupils and enough isolated quiz/result data to establish positive controls
  and prove A cannot read B's data. Do not publish a new current homework quiz.
- A new owner-controlled test address for the signup probe; it must not already exist.

Existing suitable fixtures can be reused after checking their allocations. Otherwise,
account creation, teacher approvals/allocations, fictional data insertion and eventual
cleanup are separately reviewable hosted writes, requiring explicit approval. The owner
can create Auth accounts rather than providing any server-side key.

Tests: T1 anonymously requests every exposed application table; T2 anonymously probes
teacher/unused functions (including absence of dropped functions) with fixture/invalid
identifiers; T3 attempts signup once and, if accepted, tests that account per the spec;
T4 signs in as A and probes B's classes/pupils/results. R2.4 separately signs in as the
unallocated approved teacher and checks all relevant table/RPC reads. Positive controls
must prove fixtures are accessible to B before negative results are accepted. Stop on
unexpected disclosure, withhold raw data, retain failure evidence; do not fix mid-run.

Approval needed: these specific hosted probes, teacher sign-ins and the signup attempt
(which could create an account/send email if configuration is wrong), plus any needed
fixture creation/cleanup. Owner present as required by ADVERSARIAL.md.

## T13: shared-network lockout

Read current Auth rate-limit settings and relevant time-bounded logs first. Agree a
quiet window with the owner present, when legitimate teachers will not use the shared
source address. Use two fictional teacher accounts from the same observed public IP.

Send wrong passwords until the first rate-limit response, with a pre-agreed hard cap
of at most 200 requests. Then attempt the other teacher's correct login from that same
address, record the response, identify the precise Auth limit through logs/settings,
and measure recovery with bounded probes informed by Retry-After. All probes count
within the cap. If reaching the limit or measuring recovery requires exceeding the
cap/window, stop and record incomplete; do not alter limits just to manufacture a pass.

Approval needed: deliberately triggering the hosted Auth limit, accepting temporary
shared-network sign-in disruption and consuming Auth quota. Written teacher guidance
must be prepared, and the owner must deliberately approve the applicable school-network
limit values for the test to pass. The test can fail; permission to run it is not a
promise of a pass. Any later limit/CAPTCHA change is a separate action with separate
approval. Do not start R11 implementation under approval for this test.

## T14: reset emails

Read SMTP enablement, relevant non-secret provider settings, Auth email-send cap and
per-recipient recovery cooldown first. Never retrieve/store SMTP passwords. Confirm
remaining provider/project quota and recipient eligibility. Official current docs use
a shared configuration value for the built-in hourly cap; do not assume a numeric cap
from old notes. Built-in SMTP restricts delivery to organisation-team email addresses.
Do not add organisation members to work around that restriction.

Use an owner-controlled deliverable inbox attached to a fictional Auth teacher and
a different owner-controlled deliverable address/alias that has no Auth account.
The owner can verify receipt; no mailbox password or unrestricted mailbox access is
needed. Send exactly three resets for the known account within one hour, spaced beyond
the configured cooldown, and one reset for the unknown address. Compare response
status/body after normalising request identifiers, and record actual receipt of each
of the three known-account messages. Do not follow reset links or change passwords.
Never copy reset links/tokens into reports.

Approval needed: four hosted recovery requests, actual external email delivery, quota
consumption and owner inbox verification. If existing configuration cannot deliver all
three legitimate messages, record blocked/fail as appropriate. Do not change SMTP,
raise limits, purchase services, disable confirmation or waive acceptance requirements.

## Minimum access; no new token requested

- Public Data API/Auth probes: existing publishable key; no PAT scope is required.
- Teacher reads: normal test-teacher login/session; no privileged role/service key.
- Schema/Advisor/log inspection: Database — Read, Advisors — Read, Logs — Read;
  supplied by existing MCP connection (Logs previously verified).
- Current limits/SMTP/signup/redirect inspection: Auth Config — Read; exposed-schema
  inspection: Data API Config — Read; supplied by the existing scoped token in prior
  verification. Recheck read access before testing; no replacement requested now.
- Creating Auth accounts automatically requires a server-only Auth Admin credential,
  not merely a Management API read permission. Prefer owner provisioning. API Key
  Secrets — Read or an unrestricted token is not needed for the tests themselves.
- Approved SQL fixtures can use the established MCP migration route; Migrations —
  Read-write was demonstrated by the two R2 deployments. Access is not approval.
- Conditional only, after a separate concrete proposal: Auth Config — Read-write plus
  Project Settings — Read-write for rate-limit/SMTP/CAPTCHA configuration changes.
  Neither is needed merely to run tests with the existing configuration.

No GitHub permission, CLI relink, database password, Pro upgrade or publication is
required for the proposed tests. R2/R3/R4 remain incomplete regardless of this plan.

Sources checked:
- https://supabase.com/docs/guides/auth/testing-auth-flows
- https://supabase.com/docs/guides/auth/auth-smtp
- https://supabase.com/docs/guides/deployment/going-into-prod
- Local REVIEW.md R2 and ADVERSARIAL.md setup/T1–T4/T13/T14.
