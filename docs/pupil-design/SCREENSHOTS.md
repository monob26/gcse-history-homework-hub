# Pupil design screenshot comparison

Latest owner-approved adjustment: the dashboard now shares the existing quiz watercolour and
torn-paper background; the Reichstag welcome banner and all original dashboard geometry/text are
unchanged. Other screens are unchanged.

Desktop: 1280 × 900. Mobile: 390 × 844. Implementation images exercise the real UI with fictional
intercepted TEST RPC responses; they are not hosted acceptance evidence. Artwork is extracted
unchanged from the approved HTML.

The login matches the supplied HTML pixel-for-pixel at both sizes; 528 common-component style
comparisons pass. Remaining differences retain existing actions/information or omit functionality
the owner explicitly excluded.

| Screen          | Desktop implementation                          | Mobile implementation                          | Approved reference                                                                                                  |
| --------------- | ----------------------------------------------- | ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| login           | [View](screenshots/desktop-login.png)           | [View](screenshots/mobile-login.png)           | [Desktop](reference-screenshots/desktop-login.png) · [Mobile](reference-screenshots/mobile-login.png)               |
| dashboard       | [View](screenshots/desktop-dashboard.png)       | [View](screenshots/mobile-dashboard.png)       | [Desktop](reference-screenshots/desktop-home.png) · [Mobile](reference-screenshots/mobile-home.png)                 |
| in-progress     | [View](screenshots/desktop-in-progress.png)     | [View](screenshots/mobile-in-progress.png)     | [Desktop](reference-screenshots/desktop-home.png) · [Mobile](reference-screenshots/mobile-home.png)                 |
| not-passed-home | [View](screenshots/desktop-not-passed-home.png) | [View](screenshots/mobile-not-passed-home.png) | [Desktop](reference-screenshots/desktop-home.png) · [Mobile](reference-screenshots/mobile-home.png)                 |
| completed       | [View](screenshots/desktop-completed.png)       | [View](screenshots/mobile-completed.png)       | [Desktop](reference-screenshots/desktop-home.png) · [Mobile](reference-screenshots/mobile-home.png)                 |
| overdue         | [View](screenshots/desktop-overdue.png)         | [View](screenshots/mobile-overdue.png)         | [Desktop](reference-screenshots/desktop-home.png) · [Mobile](reference-screenshots/mobile-home.png)                 |
| instructions    | [View](screenshots/desktop-instructions.png)    | [View](screenshots/mobile-instructions.png)    | [Desktop](reference-screenshots/desktop-instructions.png) · [Mobile](reference-screenshots/mobile-instructions.png) |
| question        | [View](screenshots/desktop-question.png)        | [View](screenshots/mobile-question.png)        | [Desktop](reference-screenshots/desktop-question.png) · [Mobile](reference-screenshots/mobile-question.png)         |
| correct         | [View](screenshots/desktop-correct.png)         | [View](screenshots/mobile-correct.png)         | [Desktop](reference-screenshots/desktop-feedback.png) · [Mobile](reference-screenshots/mobile-feedback.png)         |
| incorrect       | [View](screenshots/desktop-incorrect.png)       | [View](screenshots/mobile-incorrect.png)       | [Desktop](reference-screenshots/desktop-feedback.png) · [Mobile](reference-screenshots/mobile-feedback.png)         |
| timeout         | [View](screenshots/desktop-timeout.png)         | [View](screenshots/mobile-timeout.png)         | [Desktop](reference-screenshots/desktop-feedback.png) · [Mobile](reference-screenshots/mobile-feedback.png)         |
| passed          | [View](screenshots/desktop-passed.png)          | [View](screenshots/mobile-passed.png)          | [Desktop](reference-screenshots/desktop-passed.png) · [Mobile](reference-screenshots/mobile-passed.png)             |
| not-passed      | [View](screenshots/desktop-not-passed.png)      | [View](screenshots/mobile-not-passed.png)      | [Desktop](reference-screenshots/desktop-failed.png) · [Mobile](reference-screenshots/mobile-failed.png)             |
| resume          | [View](screenshots/desktop-resume.png)          | [View](screenshots/mobile-resume.png)          | Existing state retained; no new mock-up screen                                                                      |
| offline         | [View](screenshots/desktop-offline.png)         | [View](screenshots/mobile-offline.png)         | Existing state retained; no new mock-up screen                                                                      |
| exit            | [View](screenshots/desktop-exit.png)            | [View](screenshots/mobile-exit.png)            | Existing state retained; no new mock-up screen                                                                      |

## Real TEST smoke evidence

[Hosted failed result](screenshots/hosted-not-passed.png) and
[hosted passed result](screenshots/hosted-passed.png) use real isolated TEST Supabase responses, not
mocked payloads. No LIVE request, teacher login or email was involved.
