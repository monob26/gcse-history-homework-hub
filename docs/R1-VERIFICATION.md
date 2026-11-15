# R1 evidence: schema export and local rebuild

Date: 2026-11-15. R1 remains in progress because successful CLI linking is outstanding.

## Source and export

Both clean local checkouts matched the commits cited in REVIEW.md: pupil 3e3d852 and
teacher 6741666. Schema metadata was read through the existing Supabase MCP connection
for inxsjdogxvqbvxydxmym. No hosted application rows or Auth rows were queried/exported.

The complete observed public/homework_api schema was captured in schema-snapshot.json,
schema-privileges.json and schema-supplement.json. Catalog queries are in tests/r1/.
The CLI created migration 20261115123856_remote_schema.sql; render_schema.py populates it.

Exported: 2 schemas, 9 tables, 1 identity sequence, 62 columns, 42 constraints, 19 indexes,
21 functions, 7 RLS policies, 1 table trigger, 1 event trigger and 245 privilege entries.
The export also records default ACLs and function/table ownership. All function bodies
were exported, including restricted legacy helpers; they were not rewritten as security fixes.

Supplementary catalog inspection found no custom views/types, rewrite rules, collations,
extended statistics, column grants, foreign grantors or realtime publication memberships.
Column settings, schema comment and sequence bounds were verified against the rebuilt copy.

Supabase-admin-owned default privileges cannot be changed by the normal migration role.
The baseline checks those three managed ACL groups for exact equality and fails on mismatch.
It restores all application-owned grants. Standard Supabase platform schemas, roles and
extensions are prerequisites. No role passwords, current sequence values or row data are exported.

## Passed checks

1. `supabase start` succeeded locally using CLI 2.81.3 and its Docker Hub registry option.
2. `supabase db reset --local` recreated the database, replayed the migration and loaded
   the handwritten fictional seed. Exit 0. No --linked reset was used.
3. `python tests/r1/verify_catalog.py` passed every comparison: schemas, relations, columns,
   constraints, indexes, complete function definitions, policies, triggers, event trigger,
   245 grants, sequence settings, managed defaults and all supplementary metadata.
4. `supabase migration list --local` showed 20261115123856 applied to the local database.
5. `supabase db lint --local --schema public,homework_api --fail-on error` exited 0:
   "No schema errors found".
6. `python tests/r1/verify_export.py` passed schema-only/DML checks, supported-object checks,
   secret-pattern checks and the exact runtime-token scan without displaying secret values.
7. `tests/r1/pages.cjs` passed against the actual rebuilt local API:
   - Original pupil page loaded fictional homework.
   - All 25 questions were answered, server-marked and completed at 25/25 using all five RPCs.
   - Original teacher page signed in with an in-memory random test password.
   - Both teacher RPCs and the three table reads displayed two allocated pupils, one completion,
     one pass and one pupil without an attempt; no other class pupil appeared.
   - Browser routing allowed loopback hosts only; no hosted API or website request occurred.
8. A fresh read-only hosted catalog query still matched the source schema snapshot.

The browser test substitutes local connection constants and the locally served CDN bundle
in memory. Neither index.html was edited. Its CDN test bundle resolved to supabase-js
2.119.0, SHA256 71e670ca67ad5df7fe3d919f119f30267b44df80df27ac3ac63254a0ba2319df.
The floating production script is unchanged and remains R5 work.

## Remaining R1 step and exact CLI permission evidence

The existing CLI link was refused api_gateway_keys_read. No additional token/permissions
were requested, and no link retry with broader access was attempted.

CLI 2.81.3 link calls GetApiKeys, which sets reveal=true. Therefore its key request needs
BOTH API Keys Read (api_gateway_keys_read) and API Key Secrets Read
(api_gateway_keys_secret_read), not just API Keys Read. This is now confirmed by official
source: Studio's FGA refinement makes secret-read an additional requirement of reveal=true,
and the official documentation generator explains the same rule explicitly.

- CLI pinned source: https://github.com/supabase/cli/blob/v2.81.3/internal/utils/tenant/client.go
- CLI link path: https://github.com/supabase/cli/blob/v2.81.3/internal/link/link.go
- Permission rule: https://github.com/supabase/supabase/blob/ad6988956920b40a368b50288f11ac853a7480d5/apps/studio/lib/fga-refinements.ts
- Documentation rule: https://github.com/supabase/supabase/blob/ad6988956920b40a368b50288f11ac853a7480d5/apps/docs/spec/sections/generateAccessControlPartials.mts

This confirms the key-request requirements, not that every other link configuration read
is already permitted. The earlier consolidated audit lists those separate read permissions.
Secret-read is sensitive: retrieved server keys can themselves bypass database RLS.

The R1 fresh local rebuild/page acceptance check passed. R1 is not ticked complete because
the specification also requires linking. No fresh hosted test project is necessary for
the demonstrated local acceptance check, and none was created.

## Security observations carried forward, not marked passed

The read-only hosted Security Advisor returned 2 informational findings for RLS-enabled
tables without policies, 7 anonymous SECURITY DEFINER execution warnings, 6 authenticated
SECURITY DEFINER execution warnings and disabled leaked-password protection. These include
intentional pupil API entry points as well as legacy/helper exposure requiring R2 assessment.
No advisor findings were fixed on the hosted project.

- RLS policy findings: https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy
- Anonymous function findings: https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable
- Authenticated function findings: https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable
- Password protection: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection

No T1–T14 test is marked passed. No hosted writes, migration-history repair, resource creation,
GitHub push or website publication occurred. Future schema changes must use new migration files.
