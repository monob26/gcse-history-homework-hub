# Start here: R2–R4 handoff

Status recorded 15 November 2026, Europe/London. This is a handoff of existing work,
not a new test run or authorisation to deploy. REVIEW.md remains the primary authority;
ADVERSARIAL.md supplies the required abuse tests. Neither specification was changed
for this handoff. R1 is complete; R2, R3 and R4 remain incomplete. Do not start R5
or later work under the current instruction.

## Checkouts to use

- monob26/gcse-history-homework-hub: `review/r4-pupil-timers` contains R2, R3 and R4
  in sequence, plus the current handoff. Do not start from main or only the R2 branch.
- monob26/history-teacher-dashboard: `review/r3-pupil-code-sorting` contains the
  companion register-number change and its handoff.
- Existing implementation commits: hub 03268c8 (R2), 6027039 (R3), e606d4f (R4);
  teacher c2800b5 (R3). R1 was already pushed with separate explicit approval.
- These later review branches have NOT been pushed by this handoff. The owner will
  approve exact pushes separately. Do not merge or publish either website.

## Already hosted — do not reapply or recreate

Project: `inxsjdogxvqbvxydxmym`.

| Exact local migration | Hosted version | State |
| --- | --- | --- |
| supabase/migrations/20261115132031_harden_r2_access_rules.sql | 20261115201722 | Applied with owner approval |
| supabase/migrations/20261115140316_enforce_pupil_rpc_boundaries.sql | 20261115201739 | Applied with owner approval |
| supabase/hosted-fixtures/20261115203341_r2_hosted_access_fixtures.sql | 20261115203420 | Applied with owner approval |

The first two migrations tighten policies/grants, remove check_pupil_code, move
privileged helpers to an unexposed schema, normalise invalid inputs, preserve resumed
question deadlines and remove the five-second answer grace. Read-only post-deployment
structural verification passed. Security Advisor then reported only disabled leaked-
password protection. The owner declined Pro; that finding remains unresolved. Do not
waive REVIEW.md's requirement or mark R2 complete.

The owner manually created these three confirmed ordinary Auth accounts without
invitation emails:

| Test account | Auth UUID |
| --- | --- |
| r2-hosted-a-20261115@example.test | 535546ce-806c-491a-9ed9-a3e070ea95b0 |
| r2-hosted-b-20261115@example.test | 662e4309-a30f-4887-926a-6a2b83b88ce1 |
| r2-hosted-unallocated-20261115@example.test | 41f5cd97-c4bb-4048-9597-83e59a00847a |

The fixture migration added exactly 11 application records: 3 teacher approvals,
2 fictional Year 10 classes, 2 allocations (A→A, B→B), 2 fictional pupils and 2
explicitly synthetic completed attempts (21/25, 22/25). U has no classes. IDs are
in tests/adversarial/hosted/manifest.json. No new quiz/questions/answers were created;
these results reference existing quiz cd9fbeb8-e646-4d2f-b662-2b2044d8591c.
Do not recreate these records. Do not delete them without a separately approved
exact-record cleanup proposal. No pupil code/password/token is in this handoff.

The Site URL and sole redirect were previously verified as
https://monob26.github.io/history-teacher-dashboard/ and public signup was disabled.
Those are saved observations, not a new live check during this handoff.

## Local work not deployed

- R3 migration 20261115193842_independent_pupil_codes.sql is NOT hosted. Independent
  random codes, register_number, limiter and associated pupil/teacher page changes
  are local only. No hosted pupil code or attempt-token rotation was performed.
- R4 browser timer fixes are NOT published. The server deadline fix they rely on IS
  already hosted through the second R2 migration; no additional R4 SQL is needed.
- No R2–R4 GitHub push/merge or website publication has occurred in this handoff.

Do NOT blindly run `supabase db push`: the R1 baseline already exists but was not
registered in hosted migration history, and MCP-assigned R2/fixture versions differ
from local filenames. No baseline adoption/history repair has been authorised.
Environment-specific fixtures are deliberately outside supabase/migrations so they
are not automatically replayed during a fresh local schema rebuild.

## Passed evidence — do not rerun unnecessarily

| Scope | Recorded result | Evidence |
| --- | --- | --- |
| R1 | Schema export/catalog/grants checks and fresh local rebuild; both pages passed | docs/R1-VERIFICATION.md |
| Latest full local companion after R4 | T1–T12 passed; T13/T14 NOT RUN | docs/r4/full-adversarial.json |
| Additional local access/page checks | Unallocated teacher, invalid pupil RPCs and both-page smoke passed | docs/r4/full-adversarial.json |
| R3 | Upgrade preserves register/progress/deadline; random codes, throttle/recovery, fresh rebuild and sorting passed | docs/R3-REVIEW.md; docs/r3/ |
| R4 | Four real Chromium regressions fail before/pass after the fix | docs/r4/before.json; docs/r4/after.json |
| Hosted R2 deployment | Baseline matched; migrations succeeded; structural checks passed; only password-protection Advisor finding remained | docs/r2/hosted-deployment.json |
| Hosted fixtures | All 11 inserted records verified; U has no allocation; no answers; codes valid/distinct without exporting values | docs/r2/hosted-preparation/fixture-creation.json |
| Hosted-runner preparation | Nine OFFLINE guard/simulation checks passed; no hosted requests | docs/r2/hosted-preparation/offline-checks.txt |

Historical failures remain in docs/r2; later local passes do not erase them. Admin
SQL verification of fixtures is NOT proof of external RLS enforcement.
The required full companion reruns and acceptance criteria still apply when new
changes justify them; never relabel saved local results as hosted passes.

## Next authorised work, and the previous blocker

The owner explicitly approved the bounded hosted R2.3/R2.4 access checks and T1–T4,
including one signup attempt and conditional outsider T1/T2 if signup unexpectedly
returns a session. T13/T14 remain explicitly excluded. The normal run is 61 requests,
maximum 86 with outsider follow-up, hard cap 90; stop on any unexpected disclosure or
429. Owner presence is required by ADVERSARIAL.md. Do not assume account cleanup or
further hosted writes are authorised. See docs/r2/HOSTED-ACCESS-TEST-PROPOSAL.md.

NO hosted access test, teacher login or signup attempt has run in the original task.
It stopped because these three variables were absent in its running environment:

- R2_HOSTED_A_PASSWORD
- R2_HOSTED_B_PASSWORD
- R2_HOSTED_U_PASSWORD

The owner reports the NEW task has those variables. Verify presence only; never print
values or put them in command arguments, files, commits or reports. The public key is
already in index.html; no new PAT, server key or password reset is needed for login.
Do not read auth.users password hashes, mint tokens through SQL, reset passwords,
weaken confirmation/signup settings or request unrestricted access as a workaround.

Runner: tests/adversarial/hosted/run.py. Default mode is offline; --execute requires
reviewed plan hash and owner-presence marker. These flags record approval; they do
not grant it. The reviewed plan hash is in hosted-preparation/offline-plan.json.
The CLI uses hidden prompts; the Runner class also accepts an in-memory password
mapping, so a new task with environment access can use a local in-memory adapter
without echoing secrets or changing the reviewed request logic. Do not call the
existing LOCAL runner on the hosted project or reuse its fixture preparation.

Before execution, read REVIEW.md and ADVERSARIAL.md completely, read the proposal,
check the approved fixture/endpoint metadata without recreating anything and establish
owner presence. Preserve results in ADVERSARIAL.md's table and a redacted JSON report.
If signup is accepted, follow the spec where a session exists, mark T3 failed and stop;
if there is no session, report that follow-up remains blocked. No fixes mid-run.

The CURRENT task is authorised only to back up, scan and commit this handoff. It must
not execute even the previously approved tests during this handoff. The new task can
resume the already approved test scope with the owner present.

## Remaining blockers and approvals

- R2: leaked-password protection remains unresolved on Free; hosted external tests
  have not passed; T13/T14 not run. No Pro upgrade is approved.
- R3: hosted migration/code redistribution, trusted-client-IP verification and page
  deployment require explicit approval; do not rotate credentials silently.
- R4: local browser acceptance passed, but page publication and outstanding companion
  requirements remain open; keep its review checkbox unchecked.
- No T13/T14, additional hosted writes, migration-history repair, paid resources,
  GitHub push/merge or publication without the owner's separate specific approval.

All evidence in this file is existing evidence. No application/database/browser test
was run to prepare this handoff. The pending-file credential scan is documented in
docs/HANDOFF-SAFETY-CHECK.md and the local backup is outside the repositories.
