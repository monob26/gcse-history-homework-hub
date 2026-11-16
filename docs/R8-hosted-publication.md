# R8 hosted publication — blocked on GitHub Pages access

Status on 16 November 2026: publication explicitly approved by the owner; both isolated packages
pushed successfully. **Neither test site has been published or hosted-browser accepted. R8 remains
open.**

## Completed work

- Pushed local acceptance commit `a5abe3c` to the existing `chore/r8-release-isolation` branch of
  the canonical hub. Draft PR #4 remains unmerged; no writes were made to either live repository's
  main branch.
- Regenerated each static package with the test-only config. Scanned deployment files for configured
  runtime credential values; none were present. Added `.nojekyll` and public source provenance
  (`r8-release.json`). No pupil codes, tokens, credentials or fixture records are included in either
  public package.
- Pushed pupil package to `monob26/gcse-history-homework-hub-test:r8-pages` and teacher package to
  `monob26/history-teacher-dashboard-test:r8-pages`.
- Added one fresh fictional pupil for hosted acceptance through the approved test-only DML. It has
  not been used for a hosted quiz. Existing class allocation and completed local acceptance data
  remain intact.
- Prepared `node tests/r8/browser.cjs --hosted`. It permits only the two exact test URL prefixes,
  the isolated Supabase origin and the pinned CDN asset. In particular, sharing the
  `monob26.github.io` origin does not allow live site paths. No hosted browser acceptance results
  are claimed for this unrun mode.

## Concrete blocker

Repository metadata reported admin/push access. The integration accepted both branch pushes, but
`POST /repos/{owner}/{repo}/pages` with legacy branch-based publication, source `r8-pages:/`,
returned **HTTP 403, Resource not accessible by integration** for each test repository. Repository
push permission does not confer Pages configuration permission. The Pages MCP action is not
available.

The shared browser was tried for the unsupported Pages settings operation, using the cloud-desktop
skill. Browser navigation/observation failed; the documented fallback returned an explicit browser
URL security-policy rejection and instructed against workarounds. No alternative browser surface or
policy bypass was tried. This is separate from the Supabase Management API 403 and was not an
automatic approval-review rejection.

No Pages site was created by these failed requests. No build or deployment success is claimed. Do
not infer website publication merely from the pushed package branches.

## Required access and continuation

The GitHub connection must have Pages write permission for both test repositories, or the owner can
enable Pages in each test repository's Settings > Pages using **Deploy from a branch**, branch
**r8-pages**, folder **/ (root)**. No broader production permissions or changes are needed. Do not
change either live site. This is an access prerequisite; publication already has owner approval.

Once access is available, continue without requesting publication approval again:

1. Enable/verify Pages for the two test repositories and wait for successful builds.
2. Fetch every deployed artifact and compare its bytes with its reviewed package; verify the test
   public configuration and source provenance.
3. Run the prepared hosted suite with the runtime teacher password. The new origin requires actual
   teacher sign-in/class-boundary checks, quiz completion and matching saved results, reload and
   sign-out checks, and asset/network checks. Reuse local timer/resume evidence rather than
   repeating those unchanged tests.
4. Exercise the recovery request using a nonexistent fictional email and verify its `redirect_to` is
   the published test teacher URL. This does not send mail to an existing user or prove email
   delivery, consumption of a real recovery link, or the exact server allow-list. Successful
   password sign-in needs no redirect.
5. Record hosted evidence and reassess closure. Keep PR #4 unmerged and all live resources
   unchanged.

## Continuing limitations

Local browser acceptance passed, as recorded in [R8](R8.md). The test Auth URL settings remain
owner-confirmed; the Supabase Management API 403 prevents exact independent settings inspection.
Schema exposure was verified through the Data API. Supabase Free leaked-password protection remains
an outstanding limitation; no enablement attempt was repeated. Recovery-link delivery/consumption
requires an appropriate controlled inbox, which the fictional `.test` account does not provide.
Existing R2/R11 limitations remain separate.

**Recommendation: keep R8 open until both test sites are actually published and hosted acceptance
passes.** Do not close it on the strength of local acceptance or branch publication alone.
