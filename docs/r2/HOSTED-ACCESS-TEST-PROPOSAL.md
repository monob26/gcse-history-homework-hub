> Update: the owner subsequently approved fixture creation only. All 11 application
> records have now been inserted and administratively verified. Hosted version:
> 20261115203420. See hosted-preparation/fixture-creation.json. The earlier proposed
> SQL was implemented as one atomic DO statement, resolving approved Auth IDs by
> email. The owner later approved the bounded R2/T1–T4 test run, including the one signup
> attempt; none has run because passwords were absent in the original environment.
> T13/T14 and cleanup remain unapproved. See ../../HANDOFF.md for current authority.
> The original proposal
> below is retained as the record of what was presented.

# R2 hosted access tests — original proposal (see current update above)

Prepared 2026-11-15. Target: inxsjdogxvqbvxydxmym only.
The owner approved preparation, not setup or execution. No hosted account/record was
created/deleted, no signup attempted, and no hosted tests were run. Only a read-only
quiz metadata lookup was made to choose a reference quiz. REVIEW.md is unchanged.
R2/R3/R4 remain incomplete; leaked-password protection remains unresolved on Free.

## Exactly what would be created

### Three Auth accounts

| Role | Exact fictional email | Application approval | Allocation |
| --- | --- | --- | --- |
| Teacher A | r2-hosted-a-20261115@example.test | Approved teacher | Class A only |
| Teacher B | r2-hosted-b-20261115@example.test | Approved teacher | Class B only |
| Unallocated teacher U | r2-hosted-unallocated-20261115@example.test | Approved teacher | None |

These are reserved, non-deliverable test addresses, not real people. They are suitable
for password login when owner-provisioned as confirmed accounts; they are not suitable
for T14 delivery tests. Provision without invitation/confirmation email, with strong
random runtime-only passwords and the ordinary authenticated role. No admin user,
organisation membership or service role is granted. Auth assigns each UUID at creation;
the three actual IDs must be checked against these emails before inserting app rows.
Prefer owner provisioning; no server-side secret needs to be shared in chat.

### Eleven application records

| Table | Count | Exact identification/content |
| --- | --- | --- |
| history_teachers | 3 | One row for each newly assigned Auth UUID above |
| history_classes | 2 | R2 Fictional A 20261115 / R2 Fictional B 20261115; both Year 10 |
| history_teacher_classes | 2 | A → A and B → B only; no U allocation |
| history_pupils | 2 | One fictional pupil per fixture class; no names; random codes generated at setup and never logged |
| history_attempts | 2 | A score 21/25 and B score 22/25; completed, explicitly synthetic in saved_progress; no real quiz was taken |

The exact fixed class/pupil/allocation/attempt UUIDs are in
`tests/adversarial/hosted/manifest.json`. The complete proposed INSERT statements are
in `fixtures.proposed.sql` beside it. INSERT only: no upserts, updates, deletes or
existing-record replacement. A name/ID/code conflict must abort the whole transaction.
Auth accounts are separate from that transaction; if fixture insertion fails, leave
any newly created accounts in place and seek cleanup approval rather than deleting.

No quiz, question or answer record is created. The synthetic attempts reference the
existing published Year 10 quiz `cd9fbeb8-e646-4d2f-b662-2b2044d8591c`. Only its ID,
year and publication status were inspected; its content is not changed or exported.
A published quiz is necessary because get_history_class_results filters unpublished
quizzes out. Creating a new published quiz could replace current pupil homework, so
this proposal deliberately reuses the existing one. Reconfirm it is still published
before setup; if it is unavailable, stop and present a revised proposal.

The fixture SQL is prepared only, not executed or claimed database-tested. Any
approved insertion must respect REVIEW.md's migration-only workflow; this file is
not permission to execute raw SQL or deploy a new migration. The concrete application
route and Auth UUID substitutions must be reviewed before execution.

## Exactly what the test run would do

First sign in once as A, B and U (3 logins, no retry). Verify teacher approval and
that A and B each see their own fixture class/pupil/synthetic result. This positive
control prevents a broken or empty setup from making the negative tests look safe.

1. **T1:** Send 9 anonymous table-read requests using the existing public key. Each
   must return no rows or a genuine permission refusal. Missing tables do not count.
2. **T2:** Make 16 anonymous teacher/unused-function probes from the baseline inventory,
   including checks that moved/dropped helper endpoints are unavailable. Teacher calls
   must refuse; is_history_teacher=false is acceptable. Use nonexistent session IDs
   and deliberately invalid codes for unused helpers. Current exposed functions must
   be rechecked against metadata before execution; new endpoints require a revised plan.
3. **R2.3 pupil-function coverage:** Call the five pupil RPCs once each with invalid
   code/session inputs. They must return an invalid-code response or refuse the session.
   No valid pupil code is used and no quiz should start or answer be saved.
4. **T3:** Make exactly one signup attempt for
   `r2-hosted-outsider-20261115@example.test`, which must not already exist. Expected:
   signup_disabled. If it unexpectedly creates an account, mark failure. If it returns
   a session, repeat T1/T2 as required by ADVERSARIAL.md, then stop. If no usable session
   is returned, stop and report the remaining follow-up. Never silently clean it up.
5. **T4:** As A, request B's fixture class, pupil, attempt and class-result RPC. All must
   be invisible/refused. B's own positive control establishes that the data exists.
6. **R2.4:** As U, request classes, pupils, attempts, answers, quizzes, questions,
   allocations and legacy attempts; also request A's/B's class results. No data allowed.

Normal path: 61 HTTP requests. Unexpected accepted signup with a usable session can
add 25 outsider follow-up probes: maximum 86, below the hard cap of 90. No retries,
password-reset requests, bulk failed logins, T13 or T14 are implemented. Any 429 stops
immediately; no recovery polling or attempt to defeat a limit. Stop immediately on
unexpected disclosure and withhold response bodies from reports. Preserve failures;
no fixes or fixture changes during a run.

## Possible effects on the existing Homework Hub

Setup would add 14 total records (3 Auth + 11 app records) and consume a small amount
of storage. Administrators/global reports can see those explicitly fictional records.
Existing teachers are not allocated the new classes, and no current homework selection,
existing pupil code, attempt, saved answer, mark, Auth setting or website is changed.
The synthetic results are associated only with newly created fictional pupils.

Tests generate Auth sessions, security logs and ordinary request/quota usage. T3 is
intended to fail, but a signup misconfiguration could create a fourth account and
attempt a confirmation email (the reserved recipient is non-deliverable). Unexpected
function exposure could cause an unintended effect: invalid session/code inputs reduce
that risk but cannot guarantee refusal before the test has run. No intentional lockout
or mail delivery test is included. Tests cannot be promised to have zero side effects.

## Runner safeguards and verification

`tests/adversarial/hosted/run.py` is a separate hosted-only runner; the original local
runner still refuses hosted targets. Running the new runner without --execute prints
an offline plan and makes no requests. Execution requires the exact current plan SHA256,
an owner-present flag and separately obtained explicit approval. Flags do not supply
that approval. Only the pinned HTTPS project origin is used; redirects are refused,
proxies disabled, no admin endpoints, DELETE/UPDATE, recovery or logout endpoint allowed.
Normal teacher passwords and the public key are entered through hidden prompts; JWTs,
responses and pupil codes stay in memory and are absent from reports. No privileged
key is accepted. The runner cannot create fixtures or clean them up.

Nine offline tests pass: default makes no requests, execution rejects absent/wrong
approval markers, forbidden endpoints/methods refused, cap enforced, redirects refused,
disclosure stops, missing tables cannot pass, known RPC denial recognised, and the
full successful 61-request path simulated without network. Evidence:
`docs/r2/hosted-preparation/offline-checks.txt` and `offline-plan.json`.
This is NOT evidence of any hosted security test passing.

## Approvals still required, separately

1. Approve the exact fixture setup above, including who provisions the three Auth
   accounts. Review the final migration/application route with actual Auth UUIDs first.
2. After fixtures are ready, explicitly approve the bounded test run above with the
   owner present, including the one signup attempt and conditional outsider T1/T2.
3. Cleanup only after a separate exact-record deletion proposal and approval.

No new PAT is requested. Read access already exists. Normal teacher credentials can
be entered securely at execution; do not paste passwords/tokens into chat or commit them.
No paid upgrade, T13/T14, additional schema remediation, push, merge or publication is
included in either setup or test-run approval.
