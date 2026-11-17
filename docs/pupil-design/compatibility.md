# Approved pupil design: TEST-only integration preflight

Status: blocked for a functional-scope decision before UI changes or TEST publication. This is a
preflight record, not an implemented design or acceptance pass. The complete supplied
`CODEX-INSTRUCTIONS.md` was read before changes. The approved HTML is the appearance specification;
its demo JavaScript and fictional homework must not replace the real engine.

## Verified isolation

- TEST project: `ohkpvuhzvshjglbqyepq`, History Homework Hub Test, ACTIVE_HEALTHY.
- LIVE project: `inxsjdogxvqbvxydxmym`; distinct from TEST.
- Existing pupil TEST preview: https://monob26.github.io/gcse-history-homework-hub-test/
- GitHub Pages source: separate repository `monob26/gcse-history-homework-hub-test`, `r8-pages:/`.
- Current TEST package: `26307664e6c2a88d0e51603f21931537c2e99570`.
- Public TEST `shared/config.js` and pupil CSP both point to TEST and exclude the LIVE project.
- The teacher TEST site is a separate repository, also serving `r8-pages:/`. It must not be changed.
- Canonical LIVE uses `main:/`; this feature branch must not be merged or published there.

All five supplied SHA-256 checksums matched, including approved HTML
`70a1a2fdd1737a41d5714b4d7c62a5fe46be76b51fd53b88bdaf79c33aa47ff6`. No TEST/LIVE database data,
settings or application deployment changed during this preflight.

## Functional conflicts requiring a decision

1. **Interactive chronology:** current `openQuestion()` requires four answer options and renders a
   radio group. The TEST `open_pupil_question` response has no question type. Submission sends one
   answer index. The prototype's reorderable chronology screen would add a new question type and
   answer representation; do not implement its demo behaviour or fabricate a chronology test pass.
2. **Multiple homework cards and completed history:** current `get_current_pupil_homework` returns
   one current/latest quiz for the pupil. There is no pupil quiz-history API. A real
   completed-history list, five-newest pagination and multiple concurrent assignments cannot be
   populated faithfully from the existing response. Do not copy the prototype's fictional cards or
   persist history locally.
3. **Review Answers:** neither an answer-review screen nor a review API/action exists. Passed
   homework currently has a disabled completed button; the passed result returns home and the failed
   result offers retry. Do not label one of those actions Review Answers or invent a review
   destination.

The handover explicitly says: “Stop and ask if ... the approved HTML conflicts with actual quiz
behaviour; the design requires new backend functionality”. It also forbids new APIs, schema and
functionality in this task. The owner was asked whether to apply the exact approved artwork/layout
only to supported existing states, preserving actual data/actions and omitting unsupported features,
or pause until the design/functionality are reconciled. No response means no approval.

## Work after that decision

Preserve existing timer/deadline, submit/lock, inline feedback, pass/fail, retries, offline and
save/resume logic. Extract approved artwork into self-hosted assets and keep restrictive CSP; no
external dependency, CDN, telemetry or prototype JavaScript. Reuse current server pass thresholds
and 12-character code rules. Change only pupil UI plus minimal wiring/tests. Compare each supported
state with the approved reference at desktop/mobile widths and perform fictional TEST smoke checks.
Publish only the isolated pupil TEST package, keep this PR draft, report actual test results and
unsupported screenshot states, then await owner approval. No merge or LIVE promotion.
