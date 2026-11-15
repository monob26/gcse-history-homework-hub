# Approved R2 hosted deployment

2026-11-15: the owner explicitly approved applying only the two R2 migration files
to `inxsjdogxvqbvxydxmym`. Before any write, the full schema catalog, exploded
privileges and supplemental metadata matched the R1 snapshots. No application rows
were read/exported in that comparison. Baseline evidence is in predeploy-*.json.

Both migrations succeeded through the Supabase MCP apply_migration tool:

| Local file | Hosted migration version |
| --- | --- |
| 20261115132031_harden_r2_access_rules.sql | 20261115201722 |
| 20261115140316_enforce_pupil_rpc_boundaries.sql | 20261115201739 |

The tool assigns hosted versions at execution time. Contents/hashes and returned
success are recorded in hosted-deployment.json. This mapping must be honoured in
future deployment tooling. Do not blindly use db push: R1's baseline already exists
but is not recorded in hosted history, and the R2 versions differ from local filenames.
No history repair, filename rewrite, baseline adoption or extra migration was applied.

## Hosted verification

The repeatable read-only query `tests/r2/hosted-structure.sql` passed all checks:
9 application tables have RLS and explicit policies; check_pupil_code is absent;
definers have fixed search paths; exposed definers are not client-executable;
private helper grants are minimal; clients cannot create schemas or write/truncate
application tables. The deployed answer function checks the server clock and its
five-second grace is removed. register_number remains absent, confirming R3 was
not deployed. No code/token rotation occurred.

A fresh Security Advisor reports only `auth_leaked_password_protection`.
All previously recorded database-policy/definer findings are absent. This does not
substitute for anonymous HTTP or fictional unallocated-teacher verification.

R2 remains incomplete. The remaining leaked-password finding requires Pro or above
according to current official documentation, and no plan upgrade/Auth change was
approved. Hosted external-access verification and approved fictional-account tests
remain outstanding. T13/T14 remain NOT RUN; no test account was created, password
attempts made or reset email sent during this deployment.

No push, merge or publication occurred. The R3 and R4 branches remain local.
