# Review progress

Updated: 2026-11-15. Specification: REVIEW.md and ADVERSARIAL.md, read in full.
Source checkouts: pupil 3e3d852; teacher 6741666. Fictional data only.
The two approved R2 security migrations and the approved 11-record fixture migration
are hosted. Read HANDOFF.md first for current state; dated sections below retain history.
No R3/R4 deployment, hosted test project, pushes or website publication in this work.

| Order | Item | Status | Acceptance evidence / remaining work |
| --- | --- | --- | --- |
| 1 | R1 Backend under version control | Complete | CLI 2.81.3 link succeeded (exit 0) after owner updated the environment token. Existing MCP export, catalog equality, SQL/secret checks and fresh local rebuild/two-page acceptance evidence retained without repeating tests. See docs/R1-VERIFICATION.md. |
| 2 | R2 Outside access rules | In progress; blocked | T1-T12 now pass locally after R2/R3 fixes; R2.7 verified hosted. Two approved R2 hosted migrations applied and structural checks passed. Leaked-password protection, hosted external proof and T13/T14 remain unresolved. |
| 3 | R3 Unguessable pupil codes | Implemented and verified locally; not deployed | Owner confirmed legacy design; aggregate hosted inspection completed. Independent random codes, register field/sort and DB failure limits prepared locally. No hosted rotation or publication. See docs/R3-REVIEW.md. |
| 4 | R4 Timer bugs | Page fixes verified locally; overall review open | Four Chromium regressions pass (both original bugs reproduced first). Strict server deadline is now hosted via R2. Page publication and companion T13/T14 remain outstanding. See docs/R4-REVIEW.md. |
| 5 | R5 Library pin and integrity | Not started | Pin/hash or local copy and sign-in verification pending. |
| 6 | R11 Shared-network teacher access | Not started | Logs, deliberate limits, CAPTCHA, SMTP and T13/T14 pending. |
| 7 | R6 Repository consolidation | Not started | All restructuring and URL continuity checks pending. |
| 8 | R7 README and agent instructions | Not started | Full documentation/diagram/agent-file acceptance pending; R1 contracts alone do not complete R7. |
| 9 | R8 Branches and test/live separation | Not started | Protection, separate test configuration and account settings pending. |
| 10 | R9 Automated tests | Not started | Ordered database/browser/CI requirements and green main workflow pending. R1 smoke test is not R9 completion. |
| 11 | R10 Accessibility and polish | Not started | All 15 subitems and required confirmations pending. |

R1 details:

- [x] Existing CLI 2.81.3 reused; authentication was not repeated.
- [x] Successful CLI 2.81.3 link to inxsjdogxvqbvxydxmym (exit 0; updated owner-provided token).
- [x] Read-only MCP schema export of public and homework_api; no row data.
- [x] Deterministic local migration and source snapshots prepared.
- [x] SQL syntax/function lint, metadata equality and secret checks passed.
- [x] README documents every function's parameters and return fields/type.
- [x] Migration-only change workflow documented.
- [x] Fresh local Supabase rebuild from migrations with fictional seed data.
- [x] Both original pages served successfully against the rebuilt real local backend.
- [x] R1 complete: every required R1 step and its fresh-rebuild acceptance check has passed.

## All 14 adversarial tests

Current evidence is LOCAL and fictional only; no hosted adversarial run occurred.
Following the owner's confirmation of the legacy design, R3 fixes were prepared locally
without marking R2 complete. A full new run was required after those fixes and again after R4 by the
companion: T1-T12 passed; T13/T14 remain not run, not waived or counted as passed.
Historical failures and stop-on-disclosure runs remain in docs/r2/.

| Test | Latest local status | Evidence |
| --- | --- | --- |
| T1 | pass | 9 table requests: no rows; no correct answers returned |
| T2 | pass | 16 teacher/unused RPC probes refused (false teacher predicate is a refusal) |
| T3 | pass | Signup refused explicitly with signup_disabled |
| T4 | pass | Teacher A cannot read B classes, pupils or class results |
| T5 | pass | 50 wrong codes sent within one minute; first block at 20; valid code shared at-most-10-second network block and recovered; valid/invalid row fields match |
| T6 | pass | 3 neighbouring/legacy-register derivations refused without masking; random-generator independence checked separately in R3 |
| T7 | pass | All six invalid/missing/other-token requests refused; 1 distinct error shapes/messages |
| T8 | pass | Correct answer submitted one second after the displayed server deadline was marked wrong |
| T9 | pass | Second submission refused and the single original wrong answer stands |
| T10 | pass | Repeated open and two-tab takeover preserve the original question deadline; early finish refused |
| T11 | pass | 6/6 malformed inputs returned short plain refusal |
| T12 | pass | 200 starts reused the existing unfinished attempt; row count and attempts_taken unchanged |
| T13 | not run | Not run: requires approved hosted shared-network lockout test, current Auth limits/logs and teacher instructions; local Auth cannot establish the hosted limit |
| T14 | not run | Not run: requires approved hosted reset emails, test inbox verification and current SMTP cap; local Mailpit cannot prove hosted delivery/quota |

## R3 checklist

- [x] Owner confirmed the original class-prefix/register-number design.
- [x] Hosted aggregate-only inspection: 466 legacy-format codes, 17 populated classes,
  16 with one shared prefix, 13 sequential from one; no register_number column.
- [x] New local migration generates independent 12-character codes with a 32-symbol
  unambiguous alphabet and cryptographic randomness.
- [x] Preserve register numbers in their own column; update teacher query/RPC/sort.
- [x] Database limits cover both code-checking entry points and persist failed attempts.
- [x] Valid/invalid homework responses share fields and a 50 ms minimum processing floor.
- [x] T5/T6 and upgrade-preservation, limiter-recovery and browser checks pass locally.
- [x] Clean rebuild verification completed, including random seed codes, both pages and register sorting.
- [ ] Hosted migration/credential rotation and trusted-client-IP verification approved/completed.
- [ ] R3 marked complete: remains unchecked until the outstanding deployment checks are satisfied.

R2.7 remains verified on hosted Supabase. R2 is still incomplete: no hosted R2 migration
has been applied, leaked-password protection is unresolved on Free, and hosted T13/T14
are not authorised/completed. No R2 or R3 pushes, merges or publications occurred.

## R4 checklist

- [x] Read-only server timing confirmation: hosted clock check retains five-second grace.
- [x] Strict server deadline already prepared in R2 migration; local T8 verifies late answers marked wrong.
- [x] Expired resume and next-question timeouts submit once after busy clears.
- [x] Exit dialog preserves the original deadline, including expiry while open.
- [x] All four Chromium regression cases fail before and pass after the page fix.
- [ ] Entire companion complete: hosted T13/T14 remain not run, not waived.
- [x] Hosted R2 deadline fix applied with approval.
- [ ] R4 website deployment approved/completed.

R4 page acceptance checks passed locally. Its overall checkbox remains open while
the required companion run has outstanding tests and the page remains unpublished.

Post-R4 companion rerun: T1–T12 passed; T13/T14 not run. Additional access checks
and both-page smoke passed, including teacher register sorting. Evidence:
`docs/r4/full-adversarial.json`. R2 and R3 remain incomplete.

## Approved R2 hosted deployment update

- [x] Owner approved the two R2 migrations only.
- [x] Hosted schema, privileges and supplemental metadata match R1 before deployment.
- [x] Both exact approved SQL files applied successfully; hosted IDs recorded.
- [x] All hosted structural checks pass; database Advisor findings cleared.
- [ ] Remaining Advisor finding: leaked-password protection disabled (Pro+ feature).
- [ ] Hosted anonymous and fictional unallocated-teacher external checks passed.
- [ ] Full companion requirements satisfied, including outstanding T13/T14.

R2, R3 and R4 remain incomplete. No R3 code rotation or page publication was approved
or performed. Future deployments must account for the MCP-assigned R2 migration IDs
and the existing, unrecorded R1 baseline; do not blindly run db push.
Evidence: docs/r2/HOSTED-DEPLOYMENT.md and hosted-deployment.json.

Owner declined Pro upgrade: leaked-password protection remains unresolved; no change
to REVIEW.md and R2 remains incomplete. Hosted test prerequisites and explicit
approval boundaries are in docs/r2/HOSTED-TEST-PREREQUISITES.md; no tests authorised
or run by that assessment. R3/R4 remain incomplete; R5/later work not begun.

## Hosted R2 access preparation (not execution)

- [x] Separate project-pinned hosted runner and exact fictional fixture manifest prepared.
- [x] Nine offline guard/simulation tests passed; normal path 61 requests, hard cap 90.
- [x] Owner-facing setup/impact proposal prepared in docs/r2/HOSTED-ACCESS-TEST-PROPOSAL.md.
- [ ] Specific fixture creation and final migration/application route approved.
- [ ] Specific hosted T1–T4/R2.3/R2.4 run approved and executed.

Only existing quiz metadata was read for planning; no hosted fixtures, signup, test
requests or deletions occurred. T13/T14 excluded. REVIEW.md unchanged; R2/R3/R4 incomplete.

Owner manually created all three fictional Auth accounts. Read-only metadata confirms
all three emails confirmed, ordinary authenticated role, no teacher approvals or class
allocations yet. No passwords retrieved, login attempts, hosted fixture inserts or
tests. Exact Auth UUIDs and substituted fixture proposal are in
docs/r2/hosted-preparation/confirmed-accounts.json and fixtures.review.sql.
R2/R3/R4 remain incomplete; remaining fixture creation needs separate approval.

## Approved hosted R2 fixtures created

- [x] Owner explicitly approved creating only the 11 proposed application records.
- [x] Read-only preflight: confirmed accounts, no conflicts/allocations/approvals, approved quiz still published, R2 schema unchanged.
- [x] Atomic fixture migration applied; 3 approvals + 2 classes + 2 allocations + 2 pupils + 2 synthetic attempts verified.
- [x] Unallocated teacher has zero classes; no fixture answers; codes valid/distinct without exporting values.
- [x] Hosted access-test execution approved for R2/T1–T4 only; T13/T14 excluded.
- [ ] Hosted access tests run and passed.

Hosted migration version 20261115203420; local environment-specific migration in
supabase/hosted-fixtures/. No existing pupil/teacher records updated or deleted;
no Auth account changes, sign-ins, signups, emails, T13/T14, pushes or publication.
Only admin read-only insertion verification occurred, not external-access tests.
R2/R3/R4 remain incomplete; leaked-password-protection finding remains unresolved.
Evidence: docs/r2/hosted-preparation/fixture-creation.json.

## Current handoff status (15 November 2026)

- [x] Both repository histories and all tracked/nonignored working files backed up locally.
- [x] Pending files reviewed/scanned for secrets; no runtime credentials are included.
- [x] HANDOFF.md records hosted migration versions, existing fixtures and saved evidence.
- [x] Existing permission assessment copied into docs with its superseded details identified.
- [x] R2/T1–T4 execution approval preserved; no hosted test/login/signup attempted.
- [ ] Handoff GitHub pushes approved and performed.

The original task cannot see the three test-password variables. The owner reports the
new task has them; transfer the files and evidence, not secrets. Do not recreate
fixtures or replay completed tests. No tests, hosted changes, pushes, merges or
publication during handoff preparation. R2/R3/R4 remain incomplete; REVIEW.md unchanged.
