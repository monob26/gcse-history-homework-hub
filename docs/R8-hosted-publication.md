# R8 core hosted publication and acceptance — passed; full R8 incomplete

Current status: **core hosted flows passed, but full R8 sign-off is withheld.** The
[outstanding-item review](R8-outstanding-review.md) supersedes the prior closure recommendation and
records the recovery-form fix deployed as teacher package `3920b4a`. Genuine email delivery and
recovery-link use remain untested/blocked. The results below preserve the original core run against
the listed packages.

## Published releases

| Page    | Verified public URL                                         | Test repository branch                            | Package commit |
| ------- | ----------------------------------------------------------- | ------------------------------------------------- | -------------- |
| Pupil   | <https://monob26.github.io/gcse-history-homework-hub-test/> | `monob26/gcse-history-homework-hub-test:r8-pages` | `5a230b2`      |
| Teacher | <https://monob26.github.io/history-teacher-dashboard-test/> | `monob26/history-teacher-dashboard-test:r8-pages` | `41fdc9d`      |

The owner enabled Pages from `r8-pages:/` after the integration could not create Pages sites.
Read-only Pages API responses now report `status: built`, `build_type: legacy` and the intended
branch/root source for both repositories. Both public URLs returned HTTP 200. All seven deployed
content files per site (HTML, JS, CSS and release provenance) matched the reviewed package byte for
byte. The `.nojekyll` build marker was not included in the HTTP byte comparison. Asset hashes and
release provenance are in [the evidence manifest](r8/hosted-acceptance.json).

Both packages record source commit `a5abe3c`; later source commits only added test
runner/documentation changes, so application redeployment was unnecessary. The public configuration
points exclusively to test Supabase project `ohkpvuhzvshjglbqyepq`. No credentials, pupil codes or
attempt tokens are included.

## Hosted browser results

Ran `node tests/r8/browser.cjs --hosted` using headless system Chromium, separate pupil/teacher
browser contexts, actual published assets and the actual isolated Supabase backend. No backend
mocking, saved browser state, screenshots, traces or payload logging were used. All checks below
passed:

- Teacher password sign-in, Class A display and session persistence after reload.
- RLS excluded unallocated Class B; a direct results RPC for Class B was refused.
- Data API rejected `homework_private` with HTTP 406/PGRST106. Public teacher reads and
  `homework_api` pupil calls succeeded.
- Pupil code lookup, quiz start and all 25 submitted answers were marked by the server. Final score
  **25/25, passed** was saved; the completed-homework button prevented another attempt through the
  pupil page.
- After reload, the teacher displayed the same pupil's saved score and passed status. Sign-out hid
  the dashboard and remained effective after another reload.
- Forgot-password UI sent a real recovery request with `redirect_to` equal to the published **test
  teacher URL**, received a successful response and displayed the expected non-enumerating
  confirmation. The probe used a nonexistent fictional email; a read-only Auth-user existence query
  confirmed no account for that address. No existing account was sent a recovery email or had its
  password changed. Back-to-sign-in stayed on the published test URL.
- Requests were confined to the two exact test URL prefixes, the isolated Supabase origin and the
  exact pinned CDN script. Sharing the `monob26.github.io` origin did not permit live website paths.
  No unexpected-origin request was observed.
- Page/CDN assets loaded and no uncaught exceptions or application console errors occurred.
  Deliberate class/schema-denial HTTP errors are expected. One request was cancelled (`ERR_ABORTED`)
  during sign-out/navigation; subsequent state checks passed, so no application fix was required.

A fresh fictional pupil prepared during the preceding publication attempt was used. Its completed
attempt and 25 answers remain in the test project. Previously passed local timer, timeout and resume
evidence was reused rather than rerun; hosted completion covered all-correct marking. No new fixture
provisioning or permissions changes were necessary in this continuation.

## Fixes and access history

No application problem was found in hosted acceptance. Earlier runner corrections (proxy/CA
handling, hidden-field cleanup and the schema probe) are recorded in [R8](R8.md). The previous
GitHub Pages creation HTTP 403 was an integration-access limitation; the owner enabling Pages
resolved publication. The earlier shared browser fallback was blocked by its URL security policy; no
workaround was used. Those historical blockers no longer prevent the published-site runner.

The owner authorized publication, test data, routine test fixes, commits and test deployments. No
merge, live deployment, production data access, real pupil data, plan upgrade or broader security
change occurred. Draft PR #4 stays open/draft.

## Explicit outstanding limitations

- **Exact Auth URL settings:** Site URL and the allowed redirect list remain owner-confirmed. The
  existing Supabase Management API 403 is documented; it was not retried. Successful hosted sign-in
  and the correct recovery request target are behavioural evidence, not independent enumeration of
  those settings.
- **Recovery email/link:** No controlled inbox exists for the fictional `.test` account. Email
  delivery, actual recovery-link redirection, link consumption and password change were not tested.
  The successful recovery request does not prove the exact allow-list or a complete recovery flow.
  Track this as deferred Auth acceptance, not as a passed check. Ordinary password sign-in needs no
  callback.
- **Supabase Free:** Leaked-password protection remains disabled as an outstanding plan limitation;
  no enablement or upgrade was attempted.
- Detailed branch-protection settings remain integration-unreadable, with prior owner confirmation
  retained. Existing R2/R11 limitations and the known pass-mark presentation discrepancy remain
  outside this isolated release-verification change. They are not resolved by this acceptance run.

The core results above remain valid. They do not complete password-recovery acceptance. **Keep R8
open**; follow the outstanding-item review for the remaining real recovery sequence and
exact-settings evidence. No full sign-off or closure is recommended until those requirements are
addressed.
