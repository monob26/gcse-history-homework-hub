# R4 — pupil timer regressions

Status: both page bugs fixed and browser acceptance checks passed locally.
The overall review remains open; hosted deployment and the companion's T13/T14
have not been authorised or completed. R2 and R3 remain incomplete.

## Server confirmation

Read-only inspection of hosted `homework_api.submit_pupil_answer(uuid,uuid,integer)`
confirmed that it checks the server clock but still contains a five-second grace.
The existing R2 migration `20261115140316_enforce_pupil_rpc_boundaries.sql`
removes that grace. The local T8 test verifies that an otherwise correct answer
one second after the displayed server deadline is marked wrong. No additional
or duplicate database migration is needed for R4. That stricter hosted rule still
requires approval and deployment of the reviewed R2 changes.

## Page changes

An expired question queues its timeout submission until `start` or `nextQuestion`
clears the shared busy guard. It sends a null answer once, using the ordinary
server-marking path. Opening another question or loading homework clears the queue.

The Exit dialog no longer stops the timer. Continue Quiz recalculates time from
its original absolute deadline rather than creating a new one. Expiry still
submits while the dialog is open; returning does not submit a second time.

## Repeatable evidence

Run `node tests/r4/timers.cjs` from the pupil repository. It uses Playwright with
system Chromium, a local HTTP server, fictional mocked RPC responses and a virtual
clock. All requests outside that local origin are blocked. No hosted writes occur.

`docs/r4/before.json` records all four failures against the pre-fix page;
`docs/r4/after.json` records all four passing after the fix:

1. Expired resume submits exactly one null answer and shows timeout feedback.
2. Expired next question does the same after the preceding answer.
3. Three seconds in the Exit dialog count down; Continue retains the deadline.
4. Expiry in the dialog submits once, and Continue does not submit again.

The required post-R4 companion run is recorded in
`docs/r4/full-adversarial.json`, including the real local database and two-page
smoke test. T13/T14 are explicitly not run: local mocks cannot establish hosted
shared-network lockout or reset-email delivery/quota.

No GitHub push, merge, hosted database write or publication was performed.
