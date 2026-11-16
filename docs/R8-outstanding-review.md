# R8 outstanding-item review — 16 November 2026

**R8 acceptance COMPLETE on 16 November 2026. No genuine R8 acceptance blocker remains.** PR #4
remains draft and unmerged. Completion does not authorize a merge or any live change.

## Final acceptance review

The owner manually checked the TEST Supabase Auth settings and reported:

- Site URL: `https://monob26.github.io/history-teacher-dashboard-test/`.
- Redirect allow-list: exactly that one URL; no wildcards or live URLs.
- Custom SMTP disabled; Supabase default email service in use.

These settings are **owner-verified, not independently API-verified**. The
[settings record](r8/owner-verified-auth-settings.json) preserves that provenance. The previous
Management API 403 remains an inspection limitation, but the requested owner evidence resolves the
settings acceptance gap. No settings were changed or API reads retried.

| Acceptance criterion                                                                                                                 | Final disposition and existing evidence                                                          |
| ------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------ |
| Separate TEST project, repositories and public configuration                                                                         | Passed; provisioning and staging evidence in [R8](R8.md)                                         |
| Published TEST sites, asset bytes and backend isolation                                                                              | Passed; [hosted publication](R8-hosted-publication.md) and [manifest](r8/hosted-acceptance.json) |
| Teacher sign-in, allocated-class access, denial of unallocated class, reload and sign-out                                            | Passed; local and hosted acceptance                                                              |
| Pupil lookup, server marking, quiz completion and matching saved teacher results                                                     | Passed; local 24/25 including timeout, hosted 25/25                                              |
| Timers, timeout, exit/reload/resume                                                                                                  | Passed; existing local acceptance and regression evidence                                        |
| Signup/anonymous sign-in restrictions, RLS and schema exposure                                                                       | Passed; existing checks and bounded hosted schema denial                                         |
| Recovery form and expired-session failure handling                                                                                   | Passed; focused UI regressions and affected teacher regressions                                  |
| Recovery email receipt, genuine link redirect, password save, old-password rejection, new-password sign-in and link replay rejection | Passed; [real emailed recovery evidence](r8/recovery-acceptance.json)                            |
| Exact TEST Site URL, sole redirect and SMTP mode                                                                                     | Owner-verified as above; independent API inspection not claimed                                  |
| Release protection and account 2FA/privacy                                                                                           | Prior owner confirmations retained; independent detailed-rule/account inspection not claimed     |
| Leaked-password protection                                                                                                           | Documented accepted Supabase Free limitation; not claimed enabled                                |
| Existing R2/R11 limitations and pass-mark presentation                                                                               | Separate unresolved work retained; not relabelled as passed or fixed by R8                       |

All R8 acceptance requirements are satisfied by the existing behavioural evidence and explicitly
labelled owner verification. No previously passed test was repeated for this final review. Only
documentation, evidence consistency, links, formatting and secret checks were performed. No live
resources, deployments, Auth settings or test data were changed during finalisation.

## Current continuation: genuine emailed recovery passed

The owner supplied `R8_TEST_ADMIN_KEY` privately and explicitly authorized a dedicated Gmail
plus-alias for the fictional TEST teacher. The key returned HTTP 200 from the TEST Auth admin users
endpoint. It was never sent to the live project, browser, repository or logs. No negative probe
against live was performed; this verifies its TEST operation without making a cross-project claim.

Created one confirmed fictional Auth account and approved that same account in
`public.history_teachers` in TEST only, with no class allocations. The original teacher account and
`R8_TEST_A_PASSWORD` remain unchanged. Recovery was requested from the actual published TEST teacher
page. The request returned HTTP 200 with the correct TEST redirect, and the connected Gmail inbox
received its recovery email. The actual received link was privately consumed in a clean browser
context; no admin-generated link, mocked Auth response or fabricated session was substituted.

All remaining recovery checks passed against real hosted Auth:

- Emailed link redirected to the published TEST teacher reset form.
- Recovery identity populated the disabled email field; no email re-entry was needed.
- A newly generated private password was saved and the recovery session signed out.
- The old password returned HTTP 400 `invalid_credentials`.
- The new password signed in the approved fictional teacher; sign-out succeeded.
- The same emailed link was rejected in a fresh context with `otp_expired`, no session and no reset
  form.
- Requests stayed within the TEST backend, exact TEST teacher path and pinned CDN; no browser
  exceptions.

The first runner completed password saving, then stopped because its assertion expected the
`error_code` response field while this Auth response used `code`. The corrected runner resumed the
remaining checks only. No recovery email, consumed-link success or password save was repeated.
Evidence: [recovery acceptance](r8/recovery-acceptance.json). Secrets, passwords, mailbox identity,
email contents, recovery links and sessions are excluded from the evidence. The dedicated account
remains in TEST; sessions were signed out. No live resource or application deployment changed.

The former exact-settings blocker is resolved by the owner-verified settings recorded above.
Successful delivery to the approved alias is demonstrated; delivery to arbitrary addresses is not
claimed. The default email service remains subject to its normal restrictions.

## Historical pre-key review (superseded where noted above)

The following records explain earlier blockers and prior checks. Their statements about unavailable
admin access, absence of an authorized alias, and untested genuine recovery are historical; the
final acceptance review and recovery continuation above supersede them. All sections below are
historical.

## Gmail connection follow-up

Gmail is now connected and its profile/search tools work. The connection blocker is resolved. No
personal mailbox address, email body, recovery link or token is recorded here. A narrowly scoped
recent R8/project search returned no messages. The user explicitly prohibits using the personal
Gmail identity as the teacher login or changing its password; no personal address or plus-alias was
used to create an Auth user or request recovery.

A read-only query restricted to R8-prefixed Auth users still found only the original confirmed
`r8-test-teacher-a@example.test` account. No separate deliverable test identity is configured.
Available Gmail tools read/manage existing mail; they do not provision a distinct mailbox. No test
Auth admin credential is available, and the already documented key/settings 403s were not retried.
No password, email identity, settings or application deployment was changed in this follow-up.

To proceed, a dedicated deliverable test identity with readable mail (or explicit permission for an
identified test alias) and test-project-only Auth administration access are required. An existing
test secret/service-role key can be supplied as a masked runtime variable `R8_TEST_ADMIN_KEY`, never
in chat or the repository. That allows creating a confirmed ordinary recovery-test user and
generating a genuine recovery link without touching the original teacher password. It does not by
itself grant Management API settings-read access or establish SMTP delivery. For actual delivery,
the dedicated address must be accepted by the existing mailer; if default-mailer restrictions reject
it, suitable test-only SMTP configuration is also needed. Adding mailbox users to the Supabase
organization solely to bypass mailer restrictions would unnecessarily broaden access and is not
proposed.

Full recovery remains blocked; Gmail connection alone is not a recovery pass.

## Work completed in this review

### Recovery-form defect fixed and deployed

A focused browser test emitted `PASSWORD_RECOVERY` at a mocked Auth boundary. The page showed the
reset form but left its email input empty and required. HTML form validation prevented saving a new
password unless another email was entered. This is a genuine application defect at the recovery UI
boundary, although the test does not establish a real token or email flow.

The fix uses the recovery session's email as the displayed identity, disables editing that field in
reset mode, removes its required constraint in that mode, and clears the password after successful
saving. Normal sign-in/recovery-request modes retain an editable required email field. Backend
identity remains the Auth session, not the form's email text.

- `node tests/r8/recovery-ui.cjs`: success and expired-session cases passed with a mocked Auth
  client. It checks form submission without typing an email, update invocation, success
  sign-out/password clearing and recoverable failure handling.
- `node tests/r6/teacher.cjs`: all six affected teacher scenarios passed. The unchanged pupil
  regression and completed quizzes were not unnecessarily rerun.
- Source fix commit: `285a225`. Test teacher package: `3920b4a`, from that source. Pages reported
  the new package built; deployed `teacher/app.js` and release provenance matched exactly. Only the
  separate test teacher site was redeployed.
- `node tests/r8/browser.cjs --hosted --auth-only`: real hosted sign-in, sign-out,
  recovery-request/back controls and reload state passed after the update. Requests remained within
  test origins, with assets loaded and no application exceptions. A request cancellation during
  sign-out/navigation was observed as in prior runs.

No real Auth password was changed. The mock password is synthetic test data and no recovery/session
tokens were fabricated or copied from database internals.

### Additional independent Auth behaviour

`tests/r8/auth-redirects.py` uses a deliberately invalid token, does not follow redirects, and
records only safe destination/error fields. Both probes returned HTTP 303 and `otp_expired`:

1. Without `redirect_to`, destination was
   `https://monob26.github.io/history-teacher-dashboard-test/`.
2. With an unlisted `https://r8-unlisted.invalid/recovery/` destination, Auth fell back to that same
   test teacher URL. The unlisted host was never contacted.

This independently verifies the effective default destination and refusal of that particular
off-list destination. It does not enumerate every allowed URL or prove that the intended URL was
explicitly listed rather than accepted as the Site URL fallback. The original settings-read 403 was
not retried.

## Recovery delivery investigation and blockers

A single real `/auth/v1/recover` request for the existing confirmed fictional teacher returned HTTP
400 `email_address_invalid`. Earlier success for a nonexistent email only exercised the
non-enumerating response; it did not test sending mail. The `.test` address cannot provide an
Internet inbox.

Current [Supabase SMTP documentation](https://supabase.com/docs/guides/auth/auth-smtp) explains that
the built-in mail service only delivers to project-team addresses. Custom SMTP supports other
addresses, including on Free, but requires sender service configuration and credentials. The actual
project's SMTP configuration cannot be enumerated with the current permissions, so no assumption is
made about whether it uses default or custom SMTP. At the initial review neither an SMTP credential
nor a mailbox connection was available; Gmail is now connected as described above. Email capability
discovery found Gmail/Outlook integrations, initially with none connected; Gmail has since
connected. An email integration alone does not create a mailbox, a matching Auth user or sender
authorization.

A legitimate Auth admin `generateLink(type: recovery)` would allow token/link consumption testing
without email delivery. It does not test delivery itself. The alternate test-project key-inventory
endpoint returned HTTP 403, so there is no authorized admin credential available for that API. No
key was exposed or created, and that blocked endpoint was not retried. Ordinary signed-in teacher
sessions cannot generate administrative recovery links.

SQL inspection found no `auth.config`/`auth.settings` table and zero rows in `auth.instances`; it
provides no runtime URL/SMTP configuration here. No password hash/session/recovery-token
manipulation or server-file access was attempted. The read-only dashboard attempt failed before a
usable page was available with “Browser Use could not read requirements”; no settings were observed
or changed.

Local Supabase Mailpit can demonstrate a local email flow, but cannot verify sending, redirects or
token handling in this hosted test project. A mocked reset form, a forged URL/session, changing a
password while already signed in, or a custom send-email hook would also not prove the existing
hosted email flow. No new email provider, public mailbox, security-reducing configuration, paid
plan, or alternative architecture was introduced to manufacture a pass.

## Minimum access needed to finish independently

Provide a valid dedicated controlled test inbox (through a confirmed email connection or private
IMAP/test-inbox access) and a confirmed ordinary test Auth user for that inbox. For the default
Supabase mailer the address must already be a permitted project-team address; otherwise configure a
suitable test-only SMTP sender. An arbitrary new mailbox will not necessarily receive default mail.

A test-project-only Auth admin connection, supplied privately, would let the assistant create the
matching fictional user and generate links. Permitted settings-read access is needed to inspect the
full allow-list/SMTP settings. No live credential or real pupil data is needed. Do not send keys or
reset links in chat. Broader production privileges are unnecessary.

Once those access prerequisites exist, execute the remaining real sequence: request recovery from
the published teacher page, observe email receipt, privately open its authentic single-use link,
verify the actual redirect and reset form, set a fresh test password, verify old-password rejection
and new-password sign-in, sign out, and confirm link reuse is rejected. Keep password/token values
and email contents out of logs and commits. Use a dedicated recovery-test account rather than
changing `R8_TEST_A_PASSWORD` silently.

**Full R8 sign-off is withheld until the real recovery sequence is completed and remaining
exact-settings evidence is resolved or explicitly accepted as a verification limitation.** Existing
core passes remain valid. No live resource or main branch was changed; PR #4 stays draft and
unmerged.
