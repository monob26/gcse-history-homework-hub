# Review progress

Updated: 2026-11-15. Specification: REVIEW.md and ADVERSARIAL.md, read in full.
Source checkouts: pupil 3e3d852; teacher 6741666. Fictional data only.
No hosted database writes, hosted test project, pushes or website publication.

| Order | Item | Status | Acceptance evidence / remaining work |
| --- | --- | --- | --- |
| 1 | R1 Backend under version control | Complete | CLI 2.81.3 link succeeded (exit 0) after owner updated the environment token. Existing MCP export, catalog equality, SQL/secret checks and fresh local rebuild/two-page acceptance evidence retained without repeating tests. See docs/R1-VERIFICATION.md. |
| 2 | R2 Outside access rules | In progress; blocked | Two new migrations pass local access, boundary and page checks. R2.7 verified hosted. T5/T6 fail, T13/T14 pending; hosted deployment and leaked-password protection unresolved. See docs/R2-REVIEW.md. |
| 3 | R3 Unguessable pupil codes | Not started | Confirmation, independent codes, register field, throttling and tests pending. |
| 4 | R4 Timer bugs | Not started | Confirmation and both browser regression tests pending. |
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
The earlier runs stopped on disclosures as required. After the owner asked to continue,
a new targeted run tested the remaining safe local cases; failed checks were fixed in a
separate migration and rerun. Historical failures are retained in docs/r2/.

| Test | Current local status | Evidence / remaining work |
| --- | --- | --- |
| T1 | pass | 9 table requests: no rows; no correct answers returned |
| T2 | pass | 16 teacher/unused RPC probes refused (false teacher predicate is a refusal) |
| T3 | pass | Signup refused explicitly with signup_disabled |
| T4 | pass | Teacher A cannot read B classes, pupils or class results |
| T5 | fail | No throttle before guess 50 |
| T6 | fail | A neighbouring fictional pupil code was derived and accepted; response withheld |
| T7 | pass | All six invalid/missing/other-token requests refused; 1 distinct error shapes/messages |
| T8 | pass | Correct answer submitted one second after the displayed server deadline was marked wrong |
| T9 | pass | Second submission refused and the single original wrong answer stands |
| T10 | pass | Repeated open and two-tab takeover preserve the original question deadline; early finish refused |
| T11 | pass | 6/6 malformed inputs returned short plain refusal |
| T12 | pass | 200 starts reused the existing unfinished attempt; row count and attempts_taken unchanged |
| T13 | not run | Not run: requires approved hosted shared-network lockout test, current Auth limits/logs and teacher instructions; local Auth cannot establish the hosted limit |
| T14 | not run | Not run: requires approved hosted reset emails, test inbox verification and current SMTP cap; local Mailpit cannot prove hosted delivery/quota |

The approved unallocated-teacher check passes locally. Structural RLS/search-path/grant
checks and a complete 25-question pupil/teacher page regression also pass after the
boundary fixes. See docs/r2/current-test-summary.json.

R2.7 is VERIFIED on hosted Supabase: Site URL and sole redirect entry are both
`https://monob26.github.io/history-teacher-dashboard/`, and public signup is disabled.
R2 is not complete: hosted remediation/verification, leaked-password protection, T5/T6
and the required full adversarial process remain unresolved. No later review item has
been marked complete. No R2 changes have been pushed, merged, published or applied hosted.
