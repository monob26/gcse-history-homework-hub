# GCSE History Homework Hub

Plain HTML pupil quiz page backed by Supabase. The teacher page lives in the sibling
`history-teacher-dashboard` repository until the separately reviewed R6 consolidation.

## R1 backend baseline

The backend baseline is in `supabase/migrations/20261115123856_remote_schema.sql`.
It was exported through read-only Supabase MCP catalog queries from project
`inxsjdogxvqbvxydxmym`. Only `public` and `homework_api` definitions were exported:
9 tables, 1 identity sequence, 62 columns, 42 constraints, 19 indexes, 21 functions,
7 policies, table RLS settings, a table trigger, an event trigger, and 245 privilege entries.
No hosted application rows, Auth rows, sequence current values or credentials were exported.

The baseline preserves the existing backend, including legacy functions and permissions.
It does not claim that the security review has passed. See `REVIEW-PROGRESS.md`.

## Rebuild a disposable local Supabase project

Requirements: Supabase CLI **2.81.3**, Docker, Python 3, Node.js and Playwright Chromium.
Keep the teacher repository alongside this repository for the two-page acceptance test.
No framework or application build step is required.

```sh
supabase start
supabase db reset --local
python scripts/render_schema.py --check
python tests/r1/verify_export.py
python tests/r1/verify_catalog.py
supabase migration list --local
```

If the default image registry is unavailable and Docker Hub is allowed, the CLI supports
`SUPABASE_INTERNAL_IMAGE_REGISTRY=docker.io`. Use the environment’s configured Docker socket.
Local test credentials are generated at runtime; do not copy CLI status output into files.

`supabase/seed.sql` contains handwritten fictional classes, codes and a 25-question quiz.
It contains no passwords or Auth users. `tests/r1/pages.cjs` creates its fictional local
teacher with a fresh random password kept only in memory, then authorises that account locally.

For the browser acceptance check, download the teacher page’s Supabase UMD script into
a scratch directory and supply its path as `SUPABASE_JS_TEST_BUNDLE`:

```sh
SUPABASE_JS_TEST_BUNDLE=/path/to/scratch/supabase.min.js node tests/r1/pages.cjs
```

Set `SUPABASE_CLI` if the CLI is not on PATH, and `TEACHER_REPO` if the sibling checkout
is elsewhere. Install Playwright and its Chromium browser in the test tooling environment.
Run this test only after a fresh local reset. It changes local fictional fixtures.
The test serves both original pages with only their connection settings substituted in memory,
uses the actual rebuilt API, and blocks requests to every non-loopback host.

## Export provenance and completeness

`supabase/schema-snapshot.json`, `schema-privileges.json` and `schema-supplement.json`
retain the MCP schema metadata. The queries are in `tests/r1/`. No row data is included.
`scripts/render_schema.py` deterministically renders the baseline; unsupported object shapes
fail assertions rather than being silently discarded. `verify_catalog.py` compares rebuilt
tables, columns, constraints, indexes, function definitions, policies, triggers, ownership,
RLS settings, grants, sequence settings and managed default privileges to the source snapshot.

Three default-privilege groups owned by `supabase_admin` are Supabase platform prerequisites.
The normal migration role cannot alter them. The migration asserts an exact match to their
exported privileges and fails if the target differs. It restores all application-owned grants.
Standard Supabase Auth schemas, roles, extensions and platform services must already exist.
Platform Auth configuration, accounts, CAPTCHA/SMTP secrets and hosted migration history are
not part of this schema-only export. The local config is for testing, not a hosted settings backup.

CLI 2.81.3 successfully linked this local checkout to `inxsjdogxvqbvxydxmym` after the
owner updated the environment token. No credentials were added to tracked files.
See `docs/R1-VERIFICATION.md` for the completed R1 checks and permission evidence.
No hosted database changes, hosted migration-history changes, hosted test project,
GitHub push or website publication occurred.

## Database changes from now on

Create every change with `supabase migration new <descriptive_name>`, then edit the generated
migration and verify a fresh local rebuild. Do not use the hosted dashboard SQL editor.
Never apply this baseline to the existing populated project as if it were a new migration.
Its eventual hosted migration-history adoption needs a separately reviewed and approved plan.
Do not run `db push`, `db reset --linked`, hosted seeds or hosted migration repair without approval.

## Function contracts

All option indexes are zero-based. Pupil RPC calls use the `homework_api` profile; teacher
RPC calls use `public`. Table-returning RPCs return arrays; the pupil page unwraps the first row.
Attempt tokens are credentials: keep them in memory and never log them.
`pass_mark` is an absolute correct-answer count (currently 20 of 25), not a percentage.
Arguments and return fields below are taken from PostgreSQL, not inferred from the pages.

| Function | Parameters | Return fields/type | EXECUTE roles in source |
| --- | --- | --- | --- |
| `homework_api._ensure_attempt_shuffle` | `v_attempt_id uuid` | `void` | `postgres` |
| `homework_api.check_published_attempt` | `entered_attempt_id uuid, entered_attempt_token uuid` | `boolean` | `postgres` |
| `homework_api.check_pupil_code` | `entered_code text` | `boolean` | `anon`, `authenticated`, `postgres`, `service_role` |
| `homework_api.complete_pupil_quiz` | `entered_attempt_id uuid, entered_attempt_token uuid` | `TABLE(final_score integer, total_questions integer, passed boolean)` | `anon`, `postgres` |
| `homework_api.complete_quiz_test` | `entered_attempt_id uuid` | `TABLE(final_score integer, total_questions integer, passed boolean)` | `postgres` |
| `homework_api.get_current_pupil_homework` | `entered_code text` | `TABLE(valid_code boolean, class_name text, year_group integer, quiz_id uuid, quiz_title text, topic text, week_number integer, due_at timestamp with time zone, total_questions integer, pass_mark integer, attempts_taken integer, highest_score integer, passed boolean, unfinished_attempt_id uuid)` | `anon`, `authenticated`, `postgres` |
| `homework_api.get_pupil_attempt_status` | `entered_code text, entered_quiz_id uuid` | `TABLE(quiz_id uuid, attempts integer, highest_score integer, passed boolean, unfinished_attempt_id uuid, unfinished_attempt_token uuid, next_question integer)` | `authenticated`, `postgres` |
| `homework_api.get_pupil_questions` | `entered_attempt_id uuid, entered_attempt_token uuid` | `TABLE(question_number integer, question_text text, answer_options jsonb, time_allowed_seconds integer)` | `postgres` |
| `homework_api.mark_quiz_test` | `entered_quiz_id uuid, submitted_answers jsonb` | `TABLE(score integer, total_questions integer, passed boolean)` | `postgres` |
| `homework_api.mark_test_answer` | `entered_question_id uuid, entered_answer integer` | `boolean` | `postgres` |
| `homework_api.open_pupil_question` | `entered_attempt_id uuid, entered_attempt_token uuid` | `TABLE(question_number integer, question_text text, answer_options jsonb, time_allowed_seconds integer, seconds_remaining integer)` | `anon`, `postgres` |
| `homework_api.save_marked_test_attempt` | `entered_pupil_code text, entered_quiz_id uuid, submitted_answers jsonb` | `TABLE(attempt_number integer, score integer, total_questions integer, passed boolean)` | `postgres` |
| `homework_api.save_quiz_result` | `entered_code text, entered_quiz_id uuid, entered_score integer` | `jsonb` | `postgres` |
| `homework_api.set_question_start_time` | `(none)` | `trigger` | `PUBLIC`, `postgres` |
| `homework_api.start_pupil_quiz` | `entered_code text, entered_quiz_id uuid` | `TABLE(attempt_id uuid, attempt_token uuid)` | `anon`, `postgres` |
| `homework_api.start_quiz_test` | `entered_code text, entered_quiz_id uuid` | `uuid` | `postgres` |
| `homework_api.submit_answer_test` | `entered_attempt_id uuid, entered_answer integer` | `TABLE(answer_correct boolean, correct_option integer, feedback text, next_question integer)` | `postgres` |
| `homework_api.submit_pupil_answer` | `entered_attempt_id uuid, entered_attempt_token uuid, entered_answer integer` | `TABLE(answer_correct boolean, correct_option integer, feedback text, next_question integer)` | `anon`, `postgres` |
| `public.get_history_class_results` | `requested_class text, requested_quiz uuid` | `TABLE(pupil_code text, attempts bigint, highest_score integer, homework_status text)` | `authenticated`, `postgres`, `service_role` |
| `public.is_history_teacher` | `(none)` | `boolean` | `authenticated`, `postgres` |
| `public.rls_auto_enable` | `(none)` | `event_trigger` | `PUBLIC`, `postgres` |

### Page-facing behaviour

- `get_current_pupil_homework`: resolves a normalised code and latest published quiz for its year;
  reports completed attempt count, best score, pass state and unfinished attempt ID.
- `start_pupil_quiz`: validates current published homework and rejects already-passed homework;
  resumes an unfinished attempt and rotates its token, or creates an attempt.
- `open_pupil_question`: validates the session, establishes question/option shuffle, opens the
  current question and returns its remaining seconds without revealing the correct answer.
- `submit_pupil_answer`: accepts an option index or SQL/JSON null for timeout; checks the token,
  marks on the server, saves the answer and reveals the correct display index and explanation.
  The exported implementation has a five-second server grace period after the displayed limit.
- `complete_pupil_quiz`: requires the expected count of distinct saved answers, calculates the
  score server-side, saves completion, and returns the pass decision.
- `is_history_teacher`: tests membership of the approved teacher table for `auth.uid()`.
- `get_history_class_results`: requires an approved teacher allocated to the named class;
  returns every pupil, including pupils with no attempt, for a published quiz in the class year.

Other functions are legacy helpers, restricted internal helpers or trigger functions. Their
presence is recorded faithfully; removal and access remediation belong to later review items.

### Legacy JSON result

`homework_api.save_quiz_result` is not used by either page. Its JSONB return is:

- Invalid input: `success: false`, `message: text`.
- Accepted score: `success: true`, `attempt_id: uuid`, `attempt_number: integer`,
  `score: integer`, `passed: boolean`.

This helper trusts a client-supplied score and is preserved only as part of the baseline;
its source EXECUTE grant is restricted to `postgres`. Do not expose it to clients.

## R2 work in progress

Two new migrations have been applied only locally:

- `20261115132031_harden_r2_access_rules.sql`: restricts grants, removes the unused
  code-check function and isolates privileged implementations in `homework_private`.
- `20261115140316_enforce_pupil_rpc_boundaries.sql`: gives invalid sessions consistent
  errors, rejects malformed input plainly, removes the five-second late-answer grace
  period and preserves question deadlines during session takeover.

The five pupil page-facing RPC names and JSON return fields are preserved. The three
attempt-session API wrappers now accept attempt IDs/tokens as text UUID strings so
malformed values can be handled inside a controlled boundary. Their token parameters
default to NULL for consistent missing-token refusal; submit's answer is JSONB at the
boundary (numeric 0-3 or null), then validated before calling the typed private function.
The R1 function table above records the exported baseline, not these later signatures.
Teacher read RPCs use invoker security and RLS. Do not expose homework_private via the API.

Repeatable local access checks (single shell line):

```sh
python tests/adversarial/run.py --phase local-r2 --tests T1,T2,T3,T4 --output docs/r2/new-access-run.json
```

The runner provisions fictional local teachers through the local Auth admin API because
public signup is disabled. Passwords and keys remain in memory. After a reported disclosure
and an owner-authorised continuation, targeted remaining tests can run in a separate run.
Fixes are never applied during a test run. Use `--smoke-pages` with `--tests ''` and set
`SUPABASE_JS_TEST_BUNDLE` to reuse the R1 browser assertions against isolated R2 fixtures.

R2 remains incomplete. After the authorised local R3 fixes, T1-T12 pass locally; T13/T14 are not run,
and no complete clean full-suite pass is claimed. R2.7 is verified on hosted Supabase;
hosted migrations and leaked-password protection still require owner action.
See docs/R2-REVIEW.md and docs/r2/current-test-summary.json.

## R3: independent pupil codes (local, not deployed)

`20261115193842_independent_pupil_codes.sql` preserves the old suffix in a separate
`history_pupils.register_number` integer column and rotates every pupil code to an
independent 12-character value. The generator uses pgcrypto cryptographic bytes and
`ABCDEFGHJKLMNPQRSTUVWXYZ23456789`; no class prefix or register information is encoded.
Future pupils receive generated codes by default; supply register_number separately.
The revised seed creates fictional pupils without hardcoded codes.

The authorised class-results RPC now additionally returns `register_number integer`.
The teacher page selects and sorts by that field; deploy the database migration before
publishing the matching teacher page. Both HTML changes remain local.

Failed code checks through both homework lookup and quiz start share a database counter
per gateway-observed address. Twenty failures in the observation window trigger a
10-second cooldown. Blocked requests do not extend it; the budget resets after cooldown.
This is a burst/cooldown policy, not a promise of a strict twenty-per-ten-minute quota.
A valid pupil sharing that address is temporarily blocked too; active quiz RPCs and
teacher Auth are unaffected. The pupil page shows a plain retry message.

Before hosted deployment, verify the gateway's trusted client-IP header handling. Local
Kong testing rejects forged leading XFF values; it does not prove the hosted Cloudflare
trust boundary. The migration revokes old pupil codes and unfinished-attempt tokens,
while preserving saved progress and question deadlines. New codes must be distributed
through an authorised teacher workflow after approved deployment; do not export them
into documentation, migrations or test reports. No hosted rotation has occurred.

See docs/R3-REVIEW.md for evidence, trade-offs, scripts and remaining approval requirements.
