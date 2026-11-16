# R8 verification follow-up — 16 November 2026

Historical pre-acceptance note: local browser acceptance has since passed; see [R8 status](R8.md)
for current evidence and publication readiness.

R8 remains open. This note supplements draft PR #4; it does not authorize merging, publication or
changes to either live site or the live Supabase project.

## Evidence carried forward

The owner confirms manually configuring the test project's Site URL, redirect URL and exposed
schemas. Treat these as owner-confirmed, not independently inspected. The intended Site URL and sole
redirect are `https://monob26.github.io/history-teacher-dashboard-test/`. Intended exposed schemas
are `public` and `homework_api`; `homework_private` must remain unexposed.

Do not rerun passed checks without a new reason. Prior evidence covers runtime password availability
(value never displayed), test-host connectivity, both public test repositories being unpublished,
disabled signup and anonymous sign-in, a confirmed fictional teacher, RLS on all ten
application/private tables, denial of anonymous reads of four checked tables, and eight offline
staging guard tests. These checks do not establish teacher approval/allocation or browser
acceptance.

## Outstanding limitations and read-only alternatives

The configured Management API credential returned HTTP 403 for test Auth settings and PostgREST
configuration. This is a verification-access limitation, not evidence of incorrect configuration. Do
not repeatedly retry or broaden credentials merely to remove this limitation.

The strongest read-only alternative is the test project's Supabase dashboard: inspect Auth URL
Configuration and Data API exposed schemas. Record only those settings, with no passwords, tokens or
secret keys. An owner-provided redacted view can support the evidence record; direct assistant
inspection requires dashboard access. No settings need changing for inspection.

For behavioural schema verification, use bounded Data API GET requests with `Accept-Profile`
selecting each intended schema and the private schema. Use the public key and an existing known
read-only resource/function where necessary; interpret schema rejection separately from permission
denial or missing resources. These probes can demonstrate API exposure behaviour, but cannot
enumerate the Auth Site URL or redirect allow-list. The existing public-profile table denials alone
do not verify the other schemas. Database catalog queries can inspect RLS and grants, but do not by
themselves prove gateway schema configuration.

Supabase Free is in use. The Security Advisor reports leaked-password protection disabled. Record
this as an outstanding plan limitation; do not attempt to enable it repeatedly or change the plan.
See
<https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection>.

## Browser acceptance without publication

Local acceptance is possible without publishing either test repository. Use the exact PR #4 source
and its test-only staging configuration for two localhost servers. Keep the intended hosted redirect
unchanged. The teacher implementation uses `signInWithPassword`, which does not need a hosted
callback for ordinary password sign-in. Local acceptance does not validate hosted recovery
redirects.

Required setup and execution:

1. Stage pupil and teacher packages separately using `--environment test` and the PR's
   `docs/r8/test-config.json`. Confirm generated configuration points only to
   `ohkpvuhzvshjglbqyepq.supabase.co`.
2. Use a browser runner that can reach localhost, that test host and required static dependencies.
   Install dependencies from the existing lockfile if needed. Block all requests to the live
   Supabase host and both live page paths, and reject unexpected backend origins.
3. Verify the existing fictional teacher is approved and allocated only to the intended fictional
   class. A confirmed Auth account alone is insufficient. If approval/allocation is absent, prepare
   a reviewed test-only change and obtain the separate Supabase-change approval required by
   AGENTS.md before applying it. Never replay the original fixtures.
4. Supply the test teacher password directly from the runtime environment to the browser automation,
   without logs, traces, screenshots of filled credentials, saved sessions or committed artifacts.
   Use only fresh fictional test-project pupil codes; keep codes and attempt tokens out of reports.
5. Exercise teacher sign-in, permitted class/quiz/result display, exclusion of the unallocated
   class, refresh/session handling and sign-out. Exercise pupil code lookup, quiz start,
   server-timed questions, answer submission, completion and the corresponding teacher result. Check
   missing assets, console errors and network destinations. Reuse the existing mocked regression
   evidence; those tests are not substitutes for actual test-backend acceptance.
6. Record only sanitized outcomes and counts. Distinguish local acceptance from published-site
   acceptance and identify any unexercised cases explicitly.

These flows are not entirely read-only: sign-in creates a test Auth session and quiz execution
creates fictional test attempts/answers. They require authorized test-only activity; no live
credentials or data are used. Cleanup or fixture changes require separate approval under repository
instructions.

Local browser acceptance can establish application behaviour and test-backend isolation. It cannot
establish GitHub Pages routing, final public asset bytes, hosted-origin behaviour or successful
password-reset return to the intended public URL. Those require separately approved publication (and
a suitable controlled email account if recovery delivery is included). The fictional `.test` address
does not provide an email inbox. Do not send recovery emails as part of ordinary password sign-in
acceptance.

No new configuration probes or browser acceptance were performed for this documentation follow-up.
No password value was inspected. No remote files, Supabase settings or data, Pages settings, PR
state or deployments were changed.
