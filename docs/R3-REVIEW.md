# R3: independent pupil codes

Date: 2026-11-15. Status: implemented and verified locally; **not deployed**.
R2 remains incomplete. R3 is not ticked complete for the hosted application.

The owner confirmed that the original design used a shared class prefix and a
sequential register number. R3 work was explicitly requested to resolve the outstanding
code weaknesses without pretending R2 was complete. No hosted writes, pushes, merges
or publication occurred.

## Current handoff update

R3 is still not deployed. Only the two approved R2 security migrations and the
separately approved fictional fixture migration are hosted. The historical 466-pupil
aggregate predates the two new fixture pupils; it is not a current hosted row count.
The Pro upgrade was declined, and hosted access tests were approved but have not run.
See ../HANDOFF.md for migration IDs, fixtures and the credential-transfer blocker.
No additional test or hosted inspection was run to prepare this update.

## Read-only check of the hosted design (historical)

Aggregate-only MCP inspection found:

| Check | Result |
| --- | --- |
| Pupils | 466 |
| Codes matching the legacy prefix-number constraint | 466 |
| Populated classes | 17 |
| Classes whose pupils share one prefix | 16 |
| Classes numbered consecutively from one | 13 |
| Zero register suffixes | 0 |
| Classes with duplicate numeric register suffixes | 0 |
| Separate register_number column | Absent |

The current database therefore mostly follows the original design, but the prefix and
sequence pattern is not uniform across every class. The teacher page also still parsed
the number after the hyphen before the local change. No individual code, pupil row,
class name or attempt token was returned by the hosted inspection or saved in the report.
The hosted codes remain unchanged. Aggregate evidence is in r3-hosted-design-check.json.

## All four R3 implementation requirements

1. **Independent random codes:** the new migration generates 12 characters using
   pgcrypto's cryptographic random bytes and the 32-symbol alphabet
   `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`. It contains no class prefix or register component.
   Mapping each byte with a five-bit mask is unbiased for this 32-symbol alphabet.
   The code has 60 random bits; the unique database constraint remains enforced.
2. **Separate register number:** existing numeric suffixes are copied into the new
   positive integer register_number column before code rotation. The class-results RPC
   returns it; the teacher table query and sort use it. Both quiz and no-quiz display
   paths retain this field. Teacher display order no longer depends on a code's characters.
3. **Database failure limits:** both public code-checking entry points, homework lookup
   and quiz start, call the same private database guard. Twenty failures in a ten-minute
   observation window trigger a fixed ten-second cooldown. The budget resets after the
   cooldown; this is a burst/cooldown policy, NOT a strict twenty-per-ten-minute quota.
   Successful codes do not erase previous failures. Blocked requests cannot extend the
   deadline. Controlled HTTP statuses allow failed-start counter writes to commit;
   raising an SQL exception after the write would have rolled them back.
4. **Practical response consistency:** valid and ordinary invalid homework codes return
   the same 14 fields, with a 50 ms minimum processing floor. A local sample had median
   response times of 54.3 ms valid and 53.9 ms invalid. Those measurements are local
   observations, not a promise of identical Internet timing. Resource-invalid oversized
   inputs still receive a bounded plain error; valid codes necessarily return useful data.

The pupil page shows a plain cooldown/retry message instead of calling a code limit an
offline quiz. It preserves the entered code for retry. No framework or build step was added.

## Availability and trusted-network trade-offs

The failure budget is shared by the gateway-observed address. A known valid pupil on
that same school network is blocked for up to ten seconds after another caller reaches
the limit. This is intentional and was tested; it must be reviewed before deployment.
The server does not extend a block when callers retry, and honest use recovers naturally.
Already-active question/answer/completion RPCs and teacher Auth are not rate-limited here.

The guard uses the hosted edge's cf-connecting-ip metadata, or the last forwarded hop
under local Kong, and hashes the address. A missing/invalid address falls into one shared
bucket instead of unlimited access. Neither raw addresses nor guessed codes are stored
in the private counter table. Expired buckets are pruned in bounded batches.

The local test confirmed that forged leading X-Forwarded-For values did not change the
local gateway's bucket. That does NOT prove the hosted Cloudflare header trust boundary:
the hosted gateway must overwrite the selected metadata, and approved end-to-end testing
must confirm callers cannot choose arbitrary buckets. This is an explicit outstanding
deployment check, not a claimed hosted security pass.

## Migration and release implications

`supabase/migrations/20261115193842_independent_pupil_codes.sql` is new and depends on
the two locally prepared R2 migrations. It:

- Preserves register suffixes in register_number and indexes class/register order.
- Replaces the legacy code-format constraint and rotates every existing code.
- Supplies independent codes by default for new pupils.
- Rotates unfinished-attempt tokens to revoke any earlier leaked credential.
- Preserves saved answers, attempt IDs, marks, question positions and existing deadlines.
- Adds a private, RLS-protected failure counter with no direct client table privileges.
- Keeps code-check guard/helper implementations outside the exposed API schema.
- Updates the authorised teacher RPC to return register_number under invoker security/RLS.

No old/new code mapping or token is exported to files. After an approved hosted rollout,
authorised teachers would need to distribute the replacement codes securely. Existing
sessions with rotated attempt tokens would need to resume using the new pupil code.
Progress is retained; question time is not reset.

Apply the reviewed backend migrations BEFORE publishing the matching teacher page,
because its query requires register_number. Nothing has been deployed. Do not run a
blanket `db push` against the existing hosted database without reviewing R1 baseline
adoption: its tables already exist, and the R1 baseline is for reconstruction, not an
instruction to create those tables again. Each approved deployment must use reviewed
migration files and an explicit target/baseline plan.

## Verification

| Evidence | Result |
| --- | --- |
| docs/r3/local-code-tests.json | T5/T6 pass: all 50 wrong guesses sent within a minute; first block at 20; known valid code recovers; three neighbouring/register derivations refused without masking |
| docs/r3/local-upgrade.json | 10 fictional pupils rotated while preserving register numbers; 3 old codes and an old attempt token refused; answers, marks, progress and deadline preserved; new code resumes the same attempt |
| docs/r3/local-upgrade.json generator sample | 1,000 unique codes with the required length/alphabet; source algorithm independently uses cryptographic bytes, not pupil/class/register data |
| docs/r3/local-limiter.json | Mixed homework/start failures share one persistent budget; failed HTTP 400 starts count; forged leading local XFF values do not create new buckets; fixed block expiry, shared-network effect, recovery, timing/shape and browser message pass |
| docs/r3/local-access-structure.json | All R2 structural checks still pass with the private counter table |
| docs/r3/local-full-suite.json | T1-T12 pass locally; T13/T14 explicitly not run; original pages pass, including register-order assertions |
| docs/r3/local-fresh-rebuild.json | All migrations and revised seed replay from an empty local database; seeded codes random/unique; both original pages pass and register ordering is explicitly checked |
| SQL lint | public, homework_api and homework_private: no schema errors after R3 |

The code-generation independence claim comes from the generator's construction and
reviewed privileges, supported by sampling and neighbour tests. Sampling alone cannot
prove cryptographic unpredictability.

Only local fixtures were used. Runtime passwords, publishable/secret keys and attempt
tokens remained in memory; individual pupil codes are not included in test reports.
Historical R2 failures remain in docs/r2 rather than being erased by later passes.

### Repeating the checks

Set SUPABASE_CLI if CLI 2.81.3 is not on PATH. For browser tests, set
SUPABASE_JS_TEST_BUNDLE to the existing scratch UMD library. No hosted PAT is needed.

```sh
python tests/r3/verify_upgrade.py
python tests/r3/verify_limits.py
python tests/adversarial/run.py --phase r3-local --tests T1,T2,T3,T4,T5,T6,T7,T8,T9,T10,T11,T12,T13,T14 --smoke-pages --output docs/r3/new-suite.json
python tests/r3/verify_rebuild.py
```

The upgrade/rebuild scripts RESET ONLY the disposable local database. The upgrade script
can reuse an already-reset R2-only baseline after a setup interruption. Local config
disables unused Realtime, Storage and Studio services: CLI 2.81.3 otherwise tries to run
service initialisers even when start excluded them. After a reset the scripts explicitly
restart/wait for local PostgREST, because the CLI does not wait for its refreshed schema.
These changes affect local tooling only, not hosted settings.

The companion requires a full rerun after fixes, so a new full local run was necessary.
T13/T14 still require separately approved hosted network-limit/email tests and inbox
verification. Local Mailpit cannot satisfy their hosted acceptance requirements.

## What remains open

- R2 stays incomplete: no hosted remediation has been applied, leaked-password protection
  is unresolved on the Free plan, and T13/T14 have not passed.
- R3 is locally implemented/verified but remains unchecked for the hosted application:
  all 466 hosted codes are still legacy codes. Deployment, code redistribution and the
  trusted-header verification require the owner's explicit approval.
- No extra token/permissions were requested during this work. No hosted writes, pushes,
  merges, website publications or paid resources were performed.

## Documentation checked

- Supabase API security: https://supabase.com/docs/guides/api/securing-your-api
- Supabase function security: https://supabase.com/docs/guides/database/functions
- PostgREST request headers, response status and rollback behaviour:
  https://docs.postgrest.org/en/stable/references/transactions.html
