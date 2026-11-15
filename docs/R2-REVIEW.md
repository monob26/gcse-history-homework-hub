# R2: prove the access rules from outside

Status: **incomplete**. Evidence date: 2026-11-15.
Hosted project: `inxsjdogxvqbvxydxmym`. R1 remains complete.
R2 changes are local only on `review/r2-access-rules`; no R2 database writes, pushes,
merges, publications or paid resources were performed.

## Current outcome

All nine hosted application tables have RLS enabled and the hosted R2.7 Auth settings
are verified. Repeatable local tests pass for T1-T4 and T7-T12, the approved teacher
with no allocated classes, the structural access rules and both original pages.
T5/T6 remain failed; T13/T14 are not run. No complete clean full-suite pass is claimed.
Hosted migration application and leaked-password protection also remain unresolved.

## Security findings and prepared fixes

1. The unused `check_pupil_code` function confirms guesses without login. The local
   baseline T2 reproduced this and immediately stopped. The first new migration drops it.
2. Hosted grants allow signed-in accounts to call `get_pupil_attempt_status`, whose
   exported definition can return an unfinished attempt token. No live token was fetched.
   The first migration moves legacy/internal helpers out of the exposed API and revokes
   unnecessary execution grants.
3. Excess table grants include TRUNCATE, which RLS does not protect. This is excessive
   SQL privilege, not proof of a REST truncate endpoint. The first migration removes it
   and all other unneeded client table writes.
4. T5/T6 found no guess throttling and a derivable neighbouring code in the fictional
   local fixture. Those failures remain recorded for R3; no code-generation changes or
   confirmations required by R3 have been silently bypassed.
5. T7 initially refused all six invalid-token requests but used three error forms.
   The second migration normalises absent, wrong and other-attempt tokens. T7 now passes.
6. T8 initially credited an answer one second after the displayed deadline because the
   original server allowed five extra seconds. The second migration removes that grace
   period. The real 46-second test now passes; no timestamp was altered to simulate expiry.
7. A stronger T10 check found session takeover resetting the question deadline. The
   second migration preserves the stored question start time while rotating the token.
   Repeated opens and two literal browser tabs now preserve the original deadline.
8. T11 initially gave short plain refusals for only two of six malformed inputs. The
   second migration validates text UUID/session inputs, JSON answer input and oversized
   pupil codes before database casts can leak raw errors. All six probes now pass.
9. The hosted Advisor reports disabled leaked-password protection. The organisation
   is on Free; official documentation makes that feature Pro-or-above. No upgrade or
   exception to REVIEW.md's "fix every finding" requirement has been assumed.

## All eight R2 requirements

| Requirement | Current evidence / remaining work |
| --- | --- |
| 1. Advisor and fix every finding | Hosted Advisor read: 2 no-policy informational findings, 7 anonymous and 6 authenticated SECURITY DEFINER execution warnings, plus disabled leaked-password protection. Local SQL remediation prepared and tested. Local DB advisor has no findings but its older lint set does not inspect hosted Auth or all current hosted lints. Explicit structural checks cover exposed definers. Hosted application, fresh hosted verification and the password-protection finding remain unresolved. |
| 2. RLS on every table | Hosted MCP confirms all 9 application tables have RLS enabled. Structural check also passes locally after both migrations. |
| 3. Every table/function requested anonymously | Local T1: all 9 table requests return no rows or permission errors. Local T2: 16 unused/teacher RPC probes refused. All 5 used pupil RPCs also refused invalid credentials after the second migration. Repeatable script included; hosted post-fix proof is pending. |
| 4. Teacher without classes | Approved fictional teacher signed in locally and saw no class, pupil, quiz, attempt or class-result data. Repeatable test passed. |
| 5. Definer search paths and grants | Hosted definitions use fixed paths. Local structural checks pass after both migrations: only needed private definer execution, no exposed client-executable definer, no client table writes or schema creation. |
| 6. Drop check_pupil_code | First migration drops without CASCADE. Absence verified locally; hosted function remains until deployment is explicitly approved. |
| 7. Signup and redirects | VERIFIED hosted: disable_signup=true; Site URL and sole redirect are https://monob26.github.io/history-teacher-dashboard/. Owner corrected settings manually; the assistant only verified them. No more permission is needed for these completed reads. |
| 8. Adversarial tests recorded | T1-T4 and T7-T12 pass locally; T5/T6 fail; T13/T14 not run. Prior disclosure runs stopped immediately. The owner subsequently requested continuation, so the remaining safe local tests ran in a new invocation. Historical failures and the latest results are all retained. Full clean suite and hosted tests remain pending. |

R2 is not ticked complete even though its specific anonymous/unallocated-teacher scripts
pass locally: the remaining requirements have not all been satisfied.

## Two new migration files

1. `supabase/migrations/20261115132031_harden_r2_access_rules.sql`
   - Drops the unused code-check function without CASCADE.
   - Moves privileged implementations and legacy helpers into `homework_private`.
   - Keeps the five pupil API names as unprivileged wrappers in `homework_api`.
   - Restricts private helper execution and keeps private schema exposure disabled.
   - Changes teacher read RPCs to SECURITY INVOKER with RLS-enforced reads.
   - Adds own-approval and explicit legacy-deny policies; revokes unused table/function grants.
2. `supabase/migrations/20261115140316_enforce_pupil_rpc_boundaries.sql`
   - Preserves the current question timer on resumed-session token rotation.
   - Enforces the displayed server deadline, without the former five-second extension.
   - Gives malformed/missing/wrong session input consistent plain refusals.
   - Validates answer values and excessive code length without exposing raw cast errors.

Both were applied only with `supabase migration up --local`. The original R1 baseline
was not edited. These files contain schema/function changes, not exported pupil rows or
hosted fixtures. The pending Auth proposal now contains only password_hibp_enabled=true;
redirect and signup settings are already correct and need no repeat change.

### API compatibility

The names, JSON parameter names and successful response fields used by both pages remain
unchanged. Three API wrappers now take attempt IDs/tokens as text UUID strings instead
of SQL uuid parameters so malformed values can be rejected inside the function. Their
missing-token defaults normalise refusals. Submit's answer is JSONB at the API boundary,
validated as numeric 0-3 or null before entering the typed private implementation.
All original HTML files remain unchanged. A full page regression proves valid clients
still complete and display a 25-question quiz against the rebuilt local backend.

## Verification and evidence

Latest machine-readable results: `docs/r2/current-test-summary.json`.
The date, local target and evidence file are recorded for each test in ADVERSARIAL.md.

- `hosted-security-advisor.json`, `hosted-rls.json`, `hosted-function-access.json`: read-only MCP evidence.
- `hosted-config-inspection.json`: selected non-secret Auth/Data API settings after owner corrections.
- `baseline-access.json`: baseline T1 passed, T2 disclosed unused-function data and stopped.
- `local-access.json`: T1-T3 passed; teacher test exposed a local provider-configuration mistake.
- `local-access-auth.json`: T3/T4 and the unallocated-teacher checks passed after correcting local email login.
- `local-remaining-suite.json`: T5 failed, T6 disclosed a derived fictional code and stopped.
- `local-continuation.json`: new owner-authorised local run; T7/T8/T11 initially failed, T9/T12 passed.
- `local-timer-baseline.json`: strengthened T10 failed on timer restart; this supersedes its earlier narrower pass.
- `local-boundary-fixes.json`: T7-T11 passed after the second migration, including strengthened T10.
- `local-schema-after-boundary-fixes.json`: all eight structural checks passed.
- `local-updated-rpc-probes.json`: all five modified pupil RPCs probed anonymously with invalid credentials.
- `local-page-regression.json`: original pupil page achieved 25/25; original teacher page displayed
  that completion and 8 unattempted allocated pupils. All browser requests were loopback only.
- SQL lint after both migrations: `supabase db lint --local --schema public,homework_api,homework_private
  --fail-on error` exited 0 with "No schema errors found".

Only checks affected by the new RPC/timer changes were repeated. T9 was repeated because
its submit function changed. T10 was strengthened because the first version did not
prove deadline preservation. The page regression reused the R1 assertions with isolated
R2 fixtures and runtime-only provisioning, because signup is now disabled.

## Repeatable local tests

Set SUPABASE_CLI if CLI 2.81.3 is not on PATH. Apply pending local migrations, then:

```sh
python tests/adversarial/run.py --phase local-r2 --tests T1,T2,T3,T4 --output docs/r2/new-access-run.json
python tests/adversarial/run.py --phase local-boundaries --tests T7,T8,T9,T10,T11,T12 --output docs/r2/new-boundary-run.json
```

For the browser regression, set SUPABASE_JS_TEST_BUNDLE to the scratch UMD library and run:

```sh
python tests/adversarial/run.py --phase local-pages --tests '' --smoke-pages --output docs/r2/new-page-run.json
```

The runner refuses hosted targets, uses fictional pupils/teachers and keeps all passwords,
keys and tokens in memory. Fixture preparation occurs before each test phase; no fixes
are applied during a run. It stops immediately on unauthorised disclosure and withholds
raw responses. No test exceeds 200 HTTP requests. T8 waits for the real deadline.
T12 verifies the actual attempts_taken function value and attempt row count around
200 starts of an already unfinished attempt. Full-suite reruns remain required after
fixes and before real data; targeted results do not claim that the whole suite passed.

T13/T14 currently report NOT RUN rather than simulating success with local Auth/Mailpit.
They require separately approved hosted test accounts, owner presence, bounded shared-IP
attempts, current Auth logs/limits and actual inbox verification. Their safe hosted
implementation/execution is still pending; no placeholder result is a completed test.

## Remaining owner decisions / genuine blockers

- **Hosted migrations:** explicit approval is required before applying either reviewed
  SQL file. No R2 hosted writes have occurred. The available MCP migration tool has not
  been exercised to probe its write permissions.
- **Leaked passwords:** R2.1 cannot be fully satisfied on the current Free plan using
  Supabase's documented feature. The owner must decide about the paid entitlement or
  explicitly amend the requirement. No upgrade or silent exception is authorised.
- **T5/T6:** code generation and throttling still need R3's required confirmation and
  fixes. They are not waived or marked passed. R3 itself has not been marked started/completed.
- **T13/T14:** hosted lockout/email tests are not authorised by an instruction to continue
  local work; separate explicit permission and safe fictional test accounts are needed.

R2.7 is complete; R2 as a whole remains incomplete. No further inspection token is
needed for the verified Auth/Data API reads. Any future write needs both explicit
approval and the appropriate scoped capability; approval is not inferred from token access.

## Official sources

- Functions: https://supabase.com/docs/guides/database/functions
- API grants and private schemas: https://supabase.com/docs/guides/api/securing-your-api
- No-policy finding: https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy
- Anonymous definer finding: https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable
- Authenticated definer finding: https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable
- Password security and plan requirement: https://supabase.com/docs/guides/auth/password-security
- Scoped permissions: https://supabase.com/docs/guides/platform/personal-access-tokens
