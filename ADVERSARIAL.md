# ADVERSARIAL.md: abuse tests for History Homework Hub

Date: 2026-11-14. Companion to `REVIEW.md`.

This file is a test plan for a coding assistant. Each test tries to misuse the system the way a curious pupil or an outsider could. Run it while the database holds fictional data only.

## Rules

1. Test only this Supabase project, with its owner present.
2. Use fictional pupil codes and test teacher accounts only.
3. Keep volumes low. No test needs more than 200 requests.
4. Change nothing during a test run. Record the result, then fix in a separate session through a migration file.
5. Stop and tell the owner at once if a test returns data that it should not.
6. Run the whole file again after the fixes, and again before real data goes in.

## Who might misuse this, and what is at stake

1. A curious or bored pupil. This is the most likely case. The pupil has a valid code, a phone and the page source.
2. An outsider. The repositories are public, so the project URL, the publishable key and every function name are public too.
3. An honest mistake, for example a teacher who mistypes a password many times on the school network.

The quiz questions and answers are not confidential. The things to protect are:

1. Result integrity: a score must mean that this pupil answered within the time limit.
2. Availability: pupils and teachers must be able to get in during homework week.
3. Pupil codes and teacher accounts.
4. The free-tier quotas of the project.

## Setup

1. Read `SUPABASE_URL` and the publishable key from the page source. Both are public by design.
2. Pupil functions live in the `homework_api` schema. Send the headers `apikey`, `Authorization: Bearer <key>`, `Content-Type: application/json`, `Accept-Profile: homework_api` and `Content-Profile: homework_api`. The `rpc()` function in the pupil page shows the exact call.
3. Create two test teachers, A and B, each with one class of fictional pupils. Create one test account that is not a teacher, if sign-up allows it (test T3).
4. Write the tests as one script in `tests/adversarial/` so that they can run again later.
5. Write results into the table at the end of this file.

## Access tests

### T1. A stranger reads the tables

- Do: with the publishable key and no login, request every table in `public` and `homework_api` through `/rest/v1/<table>?select=*`. Include `history_pupils`, `history_classes`, `history_quizzes` and the question, answer and attempt tables.
- Pass when: every request returns zero rows or a permission error. No request returns a question's correct answer.

### T2. A stranger calls teacher functions

- Do: with no login, call `is_history_teacher` and `get_history_class_results`. Then call every other function that the schema exposes and the pupil page does not use, including `check_pupil_code`.
- Pass when: teacher functions refuse or return nothing. No unused function is callable.

### T3. A stranger signs up

- Do: call `/auth/v1/signup` with a new email address and a password.
- Pass when: the request is refused. If an account is created, sign in with it and repeat T1 and T2 as that account. Every result must still pass.
- Why: a rule written "for any signed-in user" lets a self-made account read everything.

### T4. One teacher reads another teacher's class

- Do: sign in as teacher A. Request teacher B's rows in `history_classes` and `history_pupils`. Call `get_history_class_results` with B's class name.
- Pass when: A sees nothing that belongs to B.

## Pupil code tests

### T5. Guess codes

- Do: send 50 wrong codes to `get_current_pupil_homework` within one minute, then one valid code.
- Pass when: the guesses are slowed or blocked before the 50th, and the block clears for honest use within a stated time.
- Note: record how the block treats a whole class that shares one network address. A block per address can lock out a classroom.

### T6. Become a classmate

- Do: take one valid fictional code. Try the neighbouring codes, for example the same prefix with the next register number.
- Pass when: no valid code can be worked out from another.

## Quiz integrity tests

### T7. Answer without the attempt token

- Do: start a quiz. Call `open_pupil_question` and `submit_pupil_answer` with a wrong token, with no token, and with the token of a different attempt.
- Pass when: all three are refused with the same plain error.

### T8. Answer after the time limit

- Do: open a question, wait until the limit has passed, then submit the correct answer.
- Pass when: the database records the answer as timed out or wrong. The page timer must not be the only limit.

### T9. Answer twice

- Do: submit a wrong answer. Read `correct_option` from the response. Submit again for the same question with the correct option.
- Pass when: the second submit is refused and the first answer stands.

### T10. Skip or finish early

- Do: call `complete_pupil_quiz` after 3 answers. Call `open_pupil_question` twice in a row without answering. Run one attempt in two browser tabs.
- Pass when: an incomplete attempt cannot be completed, and an unanswered question cannot be skipped or timed twice.

### T11. Bad input

- Do: send `entered_answer` as 99, as -1, as text and as a 10,000-character string. Send a 10,000-character pupil code. Send an attempt id that is not a valid id.
- Pass when: each request gets a short, plain error. No response shows table names, column names or SQL.

## Availability tests

### T12. Fill the database

- Do: with one valid code, call `start_pupil_quiz` 200 times. Count the attempt rows and read `attempts_taken` before and after.
- Pass when: an unfinished attempt is reused, so the row count and the attempt count do not grow.

### T13. Lock out the teachers

- Do: from one network, send wrong passwords to the teacher sign-in until Supabase returns a rate limit error. Then sign in correctly as a different teacher from the same network. Record how long the block lasts and which limit in Authentication, Rate Limits was reached.
- Pass when: the owner knows the limit, has set it on purpose for a school that shares one address, and a short written note tells teachers what to do when it happens.

### T14. Exhaust the reset emails

- Do: request a password reset for the test teacher three times within an hour. Request a reset for an address that has no account.
- Pass when: each real request produces an email, and the response for an unknown address is the same as for a known one.
- Note: the built-in Supabase mail service has a low hourly cap. Check the current value in the Supabase documentation. A custom SMTP service removes the cap.

## Results

| Test | Date | Result (pass, fail, not run) | Evidence | Fix task |
| --- | --- | --- | --- | --- |
| T1 | 2026-11-15 | pass | LOCAL: 9 table requests: no rows; no correct answers returned; docs/r3/local-full-suite.json | R2; hosted deployment/verification pending |
| T2 | 2026-11-15 | pass | LOCAL: 16 teacher/unused RPC probes refused (false teacher predicate is a refusal); docs/r3/local-full-suite.json | R2; hosted deployment/verification pending |
| T3 | 2026-11-15 | pass | LOCAL: Signup refused explicitly with signup_disabled; docs/r3/local-full-suite.json | R2; hosted deployment/verification pending |
| T4 | 2026-11-15 | pass | LOCAL: Teacher A cannot read B classes, pupils or class results; docs/r3/local-full-suite.json | R2; hosted deployment/verification pending |
| T5 | 2026-11-15 | pass | LOCAL: 50 wrong codes sent within one minute; first block at 20; valid code shared at-most-10-second network block and recovered; valid/invalid row fields match; docs/r3/local-full-suite.json | R3; hosted deployment/verification pending |
| T6 | 2026-11-15 | pass | LOCAL: 3 neighbouring/legacy-register derivations refused without masking; random-generator independence checked separately in R3; docs/r3/local-full-suite.json | R3; hosted deployment/verification pending |
| T7 | 2026-11-15 | pass | LOCAL: All six invalid/missing/other-token requests refused; 1 distinct error shapes/messages; docs/r3/local-full-suite.json | R2; hosted deployment/verification pending |
| T8 | 2026-11-15 | pass | LOCAL: Correct answer submitted one second after the displayed server deadline was marked wrong; docs/r3/local-full-suite.json | R2; hosted deployment/verification pending |
| T9 | 2026-11-15 | pass | LOCAL: Second submission refused and the single original wrong answer stands; docs/r3/local-full-suite.json | R2; hosted deployment/verification pending |
| T10 | 2026-11-15 | pass | LOCAL: Repeated open and two-tab takeover preserve the original question deadline; early finish refused; docs/r3/local-full-suite.json | R2; hosted deployment/verification pending |
| T11 | 2026-11-15 | pass | LOCAL: 6/6 malformed inputs returned short plain refusal; docs/r3/local-full-suite.json | R2; hosted deployment/verification pending |
| T12 | 2026-11-15 | pass | LOCAL: 200 starts reused the existing unfinished attempt; row count and attempts_taken unchanged; docs/r3/local-full-suite.json | R2; hosted deployment/verification pending |
| T13 | 2026-11-15 | not run | LOCAL: Not run: requires approved hosted shared-network lockout test, current Auth limits/logs and teacher instructions; local Auth cannot establish the hosted limit; docs/r3/local-full-suite.json | R11; approved hosted test required |
| T14 | 2026-11-15 | not run | LOCAL: Not run: requires approved hosted reset emails, test inbox verification and current SMTP cap; local Mailpit cannot prove hosted delivery/quota; docs/r3/local-full-suite.json | R11; approved hosted test required |
