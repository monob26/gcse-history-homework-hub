# R8 outstanding-item review — 16 November 2026

**R8 remains incomplete. The previous closure recommendation is withdrawn.** Core
isolation/publication/quiz acceptance passed, but real password-recovery email delivery and
successful use of a genuine recovery link have not passed. They must not be relabelled as complete
by narrowing the sign-off scope.

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

## Requirement-by-requirement disposition

| Item                                                                                         | Evidence/status                                                                                                              | Sign-off impact and resolution                                                                                            |
| -------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Separate test project, repositories and public configurations                                | Passed in prior evidence; no repeat needed                                                                                   | Complete                                                                                                                  |
| Both published sites, asset bytes, backend isolation                                         | Passed; teacher recovery-fix build also verified as below                                                                    | Complete                                                                                                                  |
| Teacher sign-in, class isolation, sign-out, saved quiz/results                               | Prior hosted acceptance passed at 25/25; affected teacher auth regressions passed after fix                                  | Complete                                                                                                                  |
| Local timers, timeout, exit/reload/resume                                                    | Passed in prior local run; unchanged pupil app                                                                               | Complete; not repeated                                                                                                    |
| Signup/anonymous sign-in restrictions, RLS, schema exposure                                  | Passed prior checks                                                                                                          | Complete; not repeated                                                                                                    |
| Recovery UI and failure handling                                                             | New mocked recovery success/expired-session regressions passed after a real form fix                                         | UI boundary passed; not email/token end-to-end acceptance                                                                 |
| Effective default recovery destination                                                       | Two invalid-link probes independently returned the intended test teacher URL                                                 | Behaviour verified, including rejection of one unlisted destination; not an exhaustive allow-list audit                   |
| Actual recovery email delivery                                                               | Existing fictional teacher's real recovery request failed HTTP 400 `email_address_invalid`                                   | Blocks full recovery acceptance; needs a valid controlled inbox and a matching test Auth user                             |
| Genuine recovery-link consumption, password reset, new-password sign-in and replay rejection | No genuine link available; not run                                                                                           | Blocks full recovery acceptance; needs received email or legitimate admin-generated recovery link                         |
| Exact Auth redirect allow-list and mail settings                                             | Owner-confirmed URL settings; Management API settings read previously 403, no DB-stored configuration, dashboard unavailable | Independent exact inspection blocked; needs permitted settings-read access or a redacted authoritative settings export    |
| Detailed branch-protection rules                                                             | Owner-confirmed; alternative CLI credential read returned 403                                                                | Independent rule inspection blocked; needs rules-read permission or authoritative export; no rule changes made            |
| Account 2FA/privacy settings                                                                 | Owner-confirmed                                                                                                              | Cannot independently inspect private account settings through the current connections; no account/security changes needed |
| Leaked-password protection                                                                   | Disabled, Supabase Free limitation explicitly accepted for documentation                                                     | Outstanding known limitation; no enablement attempts or plan changes                                                      |
| Existing R2/R11 and pass-mark presentation items                                             | Remain in the existing records                                                                                               | Separate unresolved work; no claim they passed or were fixed by R8                                                        |

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
