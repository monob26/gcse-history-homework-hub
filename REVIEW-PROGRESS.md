# Review progress

Updated: 2026-11-15. Specification: REVIEW.md and ADVERSARIAL.md, read in full.
Source checkouts: pupil 3e3d852; teacher 6741666. Fictional data only.
No hosted database writes, hosted test project, pushes or website publication.

| Order | Item | Status | Acceptance evidence / remaining work |
| --- | --- | --- | --- |
| 1 | R1 Backend under version control | Complete | CLI 2.81.3 link succeeded (exit 0) after owner updated the environment token. Existing MCP export, catalog equality, SQL/secret checks and fresh local rebuild/two-page acceptance evidence retained without repeating tests. See docs/R1-VERIFICATION.md. |
| 2 | R2 Outside access rules | Not started | All required external access checks, fixes and repeatable tests pending. |
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

The full companion is available in ADVERSARIAL.md. No adversarial run has occurred.
The R1 page smoke test is not a substitute for any of these tests.
Run the entire suite after R1 and again after R2, R3, R4 and R11, and before real data.
Hosted attempts, account creation, resets and rate-limit tests require explicit approval.
Owner presence, fictional data, low volumes and stop-on-disclosure rules still apply.

| Test | Status | Evidence needed |
| --- | --- | --- |
| T1 Stranger reads tables | Not run | All table endpoints return no rows or permission errors. |
| T2 Stranger calls teacher/unused functions | Not run | Every required function invocation and refusal recorded. |
| T3 Stranger signs up | Not run | Signup refused; if created, signed-in T1/T2 repeat. |
| T4 Teacher cross-class access | Not run | A cannot read B's rows/results. |
| T5 Guess codes | Not run | 50-code throttling, recovery interval and shared-network effect. |
| T6 Become a classmate | Not run | No valid code derivable from another. |
| T7 Missing/wrong/other attempt tokens | Not run | All three refused with the same plain error. |
| T8 Late answer | Not run | Server records timeout/wrong after the limit. |
| T9 Answer twice | Not run | Second submit refused; first answer unchanged. |
| T10 Skip/finish/two tabs | Not run | No early completion, skipping or timer restart. |
| T11 Bad input | Not run | Every specified malformed input gets plain errors without schema details. |
| T12 200 starts | Not run | Attempt row count and attempts_taken do not grow. |
| T13 Teacher network lockout | Not run | Actual hosted limit, deliberate configuration and teacher instructions. |
| T14 Reset email exhaustion | Not run | Three real reset emails and indistinguishable unknown-address response. |
