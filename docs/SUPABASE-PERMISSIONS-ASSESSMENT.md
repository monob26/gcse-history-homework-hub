> Historical permissions assessment, retained for the new task. Since this was written,
> MCP migration application succeeded for the two R2 migrations and the fixture
> migration. Auth Config/Data API reads were also previously verified with the scoped
> token. The owner declined Pro and has not authorised additional hosted writes.
> No new token is required for the approved public-key/teacher-session access tests.
> Read HANDOFF.md for the current state; do not act on superseded requests below.

# Supabase permissions assessment: remaining REVIEW.md tasks

Assessment date: 15 November 2026.
Project: `inxsjdogxvqbvxydxmym` — GCSE History Homework Hub.
Authority: `REVIEW.md`, supported by `ADVERSARIAL.md`.

The earlier “Auth Config — Read only” request covered the immediate Auth blocker,
not the whole remaining review. This assessment covers all of R2–R11, including
R10’s 15 subitems and the adversarial tests.

No R2 implementation work or permission changes were performed during this assessment.
No credentials or secret values are included in this document.

## What the existing MCP connection provides

Read-only capability checks succeeded for:

| Exact permission name | Verified MCP capability |
| --- | --- |
| **Database — Read** | SQL/schema inspection |
| **Advisors — Read** | Security Advisor results, confirmed during R2 |
| **Logs — Read** | Log queries |
| **Migrations — Read** | Hosted migration-history inspection |
| **Project Settings — Read** | Project details |
| **Organization Settings — Read** | Organisation details and subscription plan |

The available MCP tools do **not** expose Auth configuration or Data API configuration management.

Migration-application and project-creation tools are listed, but their write permissions
have **not** been verified. Testing them would risk making changes. Successful reads do
not establish that the whole connection is read-only, either.

## Permissions needed for the remaining review

These names match Supabase’s token settings.

| Permission | REVIEW.md requirements | Is Read sufficient? | When needed / existing access |
| --- | --- | --- | --- |
| **Database** | R2: RLS, function definitions and grants. R3: code-generation/throttling inspection. R4: server timing confirmation. R9: database verification. R10: retry, results and extra-time behaviour | **Yes for inspection.** Hosted changes should use migrations | Needed throughout; **already supplied by MCP** |
| **Advisors** | R2.1: inspect and resolve every Security Advisor finding | **Yes** to obtain findings; fixes require other permissions | Needed now; **already supplied by MCP** |
| **Auth Config** | R2.7: signup and redirects; R2.1: leaked-password protection. R11: limits, CAPTCHA and SMTP. R6: redirects if URLs change. R10.15: project MFA configuration, if chosen | **Read** for inspection; **Read-write** for changes | Read needed now; **missing from available MCP tools** |
| **Data API Config** | R2: verify exposed schemas/functions and ensure the proposed private implementation schema is not exposed | **Read** for inspection; **Read-write only if exposure settings need correction** | Read needed now. Existing MCP database inspection did not reveal the configured exposed-schema list |
| **Logs** | R11.1 and T13: identify the Auth limit reached | **Yes** | Needed for R11; **already supplied by MCP** |
| **Migrations** | Apply reviewed database fixes for R2, R3, R4 if required, and R10’s database changes; deploy the baseline/fixes to R8’s test project | **Read** for history; **Read-write** to apply migrations | Write needed only after deployment approval. MCP read works; write remains unverified |
| **Project Settings** | Project identity/health; R8 test-project verification. Also required alongside Auth Config when changing Auth settings | **Read** for inspection. **Read-write is additionally required for Auth configuration updates** | Read already supplied by MCP; write only for later approved changes |
| **Organization Settings** | Check plan eligibility for R2’s leaked-password finding; inspect organisation details/cost information for R8 | **Yes** | **Already supplied by MCP** |
| **Organization Projects** | R8.2: create the separate hosted test project | **No—Read-write** is required to create it | Later, **only if the owner authorises the assistant to create it**. Unnecessary if the owner creates it |
| **API Keys** | Obtain a new test project’s publishable key for R8; configure the pages after project selection | **Yes** | Later. The existing project’s public key is already in its page source; no retrieval is needed now |
| **Projects (account-wide)** | Supporting project discovery and MCP `get_cost` for R8 | **Yes** | Conditional later tooling permission. Not needed to inspect the known current project |

Two particularly important details:

- Updating Auth configuration through the Management API requires **both
  Auth Config — Read-write and Project Settings — Read-write**. Auth Config alone is insufficient.
- **Database — Read-write is not required for the planned migration-only deployment
  route.** Migrations — Read-write applies the reviewed migration files, including their SQL data changes.

## Additional permissions only if CLI 2.81.3 links the future test project

R1’s completed link does not need repeating merely because its token was revoked.
Local commands with explicit `--local` do not require hosted permissions.

If R8 uses the same CLI linking workflow, these additional reads apply:

| Exact permission name | Purpose | Access / timing |
| --- | --- | --- |
| **API Keys** | CLI key lookup | Read; future linking |
| **API Key Secrets** | CLI 2.81.3 requests `reveal=true` | Read; future linking only |
| **Database Config** | Read PostgreSQL configuration | Read; future linking |
| **Connection Pooling** | Discover session-pooler configuration | Read; future linking |
| **Network Restrictions** | Read database network restrictions | Read; future linking |
| **Storage Config** | CLI reads Storage configuration even though this application does not use Storage | Read; future linking |

CLI linking also reads **Project Settings, Auth Config and Data API Config**, already covered above.

**API Key Secrets — Read is sensitive:** it permits retrieval of server keys that can
bypass RLS. It is unnecessary for current inspections, local tests and ordinary pupil/teacher tests.

The CLI’s temporary-login fallback should be avoided: it requires
**Database — Read-write** and creates a hosted database login.

## Requirements that a Supabase token does not solve

- **R5, R7, most of R6 and most of R10:** local file changes need no Supabase permission.
- **R9:** local database/browser tests and a CI workflow using local Supabase need no
  hosted PAT. GitHub workflow, protection and merge permissions are separate.
- **R8.3:** enabling two-factor authentication on the owner’s Supabase account requires
  the owner’s account action. A project PAT does not replace it.
- **R10.15:** teacher MFA enrolment uses the teacher’s authenticated session; enabling
  project MFA configuration may require the Auth configuration writes above.
- **Adversarial tests:** require fictional codes, test teacher accounts and sometimes
  inbox access. Quiz submissions, signup attempts and reset requests can change hosted
  state **without any Management API write permission**.
- Creating test teachers through the Auth Admin API requires a server-side
  secret/service-role credential. The owner can provision those accounts instead;
  broad key-secret access is not inherently required.
- CAPTCHA and custom SMTP require their providers’ credentials and possibly paid services.
- MCP reports the organisation is on **Free**. Supabase documents leaked-password
  protection as **Pro or above**. A stronger token cannot remove that entitlement blocker.

## What this means before creating another token

For the **current missing inspections**, the minimum additional token access is:

- **Auth Config — Read**
- **Data API Config — Read**

Scope it to **`inxsjdogxvqbvxydxmym`**. MCP already covers the other verified reads.

For later approved changes, the relevant additions are **Migrations — Read-write**,
**Auth Config — Read-write plus Project Settings — Read-write**, and conditionally
**Data API Config — Read-write**. Project creation and CLI linking have the separate
conditional requirements above.

A token scoped only to today’s project cannot be assumed to cover R8’s
**not-yet-created test project**. That future project will need its own explicit
scope/connection. Repeated replacement of a broad token can be avoided by retaining
the working MCP connection and deciding separately who performs those later administrative actions.

Granting any permission would still **not authorise** hosted changes, GitHub pushes,
merges or publication. Those actions continue to require the owner’s explicit approval.

## Official sources

- [Scoped-token permission table](https://supabase.com/docs/guides/platform/personal-access-tokens)
- [Management API specification](https://api.supabase.com/api/v1-json)
- [API-key permission guidance](https://supabase.com/docs/guides/api/api-keys)
- [CLI 2.81.3 linking source](https://github.com/supabase/cli/blob/v2.81.3/internal/link/link.go)
- [CLI 2.81.3 revealed-key request](https://github.com/supabase/cli/blob/v2.81.3/internal/utils/tenant/client.go)
- [Password security and leaked-password protection](https://supabase.com/docs/guides/auth/password-security)
