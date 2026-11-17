# Approved pupil design — TEST review

Preview: https://monob26.github.io/gcse-history-homework-hub-test/

Draft PR: https://github.com/monob26/gcse-history-homework-hub/pull/9

The approved appearance is integrated into the existing pupil app. The owner explicitly approved
Option 1: the supplied HTML is a visual reference only. Unsupported chronology interaction, quiz
history, Review Answers, prototype navigation and demo data are omitted. No new screen, question
type, API or backend functionality was added. Passed homework retains the existing disabled
completed action; results retain their existing return/retry actions.

## Isolation and preservation

The TEST preview is served by the separate `gcse-history-homework-hub-test` repository from
`r8-pages:/`, with public config/CSP pinned to TEST project `ohkpvuhzvshjglbqyepq`. LIVE project
`inxsjdogxvqbvxydxmym` is excluded from the outgoing package. The canonical feature branch and draft
PR are not merged. LIVE hub/teacher heads remain `3c8e298245e805eb58ad8ab9b33818c229838a1d` and
`632973e4c8384aed2fe6292505d9034aa779c7ed`.

Teacher source, Supabase migrations/policies, shared LIVE config, dependency lock, authentication,
SMTP and rate settings are unchanged. No LIVE pupil records, codes, class allocations, quiz data or
secrets were accessed or modified for this design work. The real smoke test used one existing,
unused fictional TEST pupil; no new pupil/class or teacher account was required. It completed two
TEST attempts and fifty answer submissions. No teacher sign-in or recovery email was attempted.

The RPC requests/payloads, session-start handling and timer/timeout implementation remain
byte-identical to the base release; see [preservation checks](preservation.json). Other presentation
changes retain server marking/pass truth, keyboard radio behaviour, server-derived timing,
submission locking, inline correct-answer/explanation feedback, original class/week/topic and
attempt/score data, save/exit, refresh/resume, offline retry and result navigation.

## Visual evidence

[Desktop/mobile screenshot gallery](SCREENSHOTS.md) includes 32 supported states, plus real TEST
passed/failed results. [Comparison evidence](visual-comparison.json) records all 528 common visual
style checks passing. Code entry matches the approved geometry, typography and colours at both
widths; mobile is pixel-identical and desktop differs only in negligible antialiased edge pixels.

Three original artwork assets are extracted unchanged from the approved HTML. No generic imagery,
external fonts, CDN assets, dependencies, telemetry or screenshot-as-UI substitute is used. Only
question screens/inline question feedback use the quieter watercolour; all other art follows the
approved reference. Existing functional controls and timing information necessarily add content
where the demo omitted them; no existing functionality is removed to force a screenshot match.

## Verification

| Check                                                                     | Result                                                                |
| ------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| All five supplied input checksums                                         | PASS                                                                  |
| Separate TEST project/repository/Pages branch; public TEST config and CSP | PASS                                                                  |
| Existing R6 browser regressions                                           | PASS: six pupil and eight teacher scenarios                           |
| R10 pupil keyboard, modal, final-answer/completion retry regressions      | PASS: five scenarios                                                  |
| Staging guards                                                            | PASS: eleven checks                                                   |
| New desktop/mobile visual and state tests                                 | PASS: thirty-two scenarios; no overflow, exceptions or CSP violations |
| Approved visual style checks                                              | PASS: 528 comparisons                                                 |
| Real TEST start, submit, inline feedback and locking                      | PASS                                                                  |
| Real TEST save/exit, fresh-page login/resume and preserved deadline       | PASS                                                                  |
| Real TEST offline recovery, failed attempt and successful retry           | PASS                                                                  |
| Real TEST completed status with existing completed action                 | PASS                                                                  |
| Source formatting and whitespace checks                                   | PASS                                                                  |

[Real TEST smoke results](hosted-results.json) are separate from
[intercepted-response screen tests](visual-test-results.json). Existing security/database evidence
is reused; no rate-limit burst, password reset, LIVE quiz or schema operation was repeated.
Published package provenance/byte verification and CI run links are recorded in draft PR #9.

## Review boundary

No unresolved functional question remains after the owner's Option 1 clarification. Review Answers,
history and chronology are deliberate omissions, not hidden unfinished features. The PR remains
DRAFT. Await explicit owner approval and school/Veritau clearance; do not merge, promote or deploy
this design LIVE.
