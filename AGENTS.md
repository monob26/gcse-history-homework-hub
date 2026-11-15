# Agent instructions

This is a static GCSE History homework service backed by Supabase. Pupils enter independent codes
and complete server-marked timed quizzes. Approved teachers sign in to see only their allocated
classes and results.

- `pupil/`: pupil HTML, CSS and JavaScript; `teacher/`: teacher source files.
- `shared/`: public configuration and page-scoped colour palettes.
- `supabase/`: historical migrations, catalog metadata and fictional local seed.
- `tests/r6/`: mocked browser regressions; `docs/R6.md`: deployment details.
- `scripts/prepare-pages.py`: static copy tool; root `index.html` is generated.
- This hub is canonical; `history-teacher-dashboard` is a deployment mirror.
- Fictional data only. No secret keys in the repository.
- Never log or commit passwords, teacher sessions, pupil codes or attempt tokens.
- Obtain separate owner approval before pushing, merging, publishing or changing Supabase.
- Do not replay hosted fixtures, rotate codes or clean up data without approval.
- Never blindly push/reset the hosted database or repair migration history.
- Preserve both public URLs, the Auth redirect, R5 integrity protection and server marking.
- Read README.md's current RPC contract; the R1 baseline alone is superseded.
- Keep plain static files; do not introduce an application build or unrelated work.
- Use `npm ci`, then `npm run format:check` for maintained source formatting.
- Check these docs with `npx --no-install prettier --check README.md AGENTS.md`.
- Run `npm run test:r6` for relevant frontend changes (Linux `/usr/bin/chromium`).
- Those browser tests mock the backend and block external requests; no hosted writes.
- For documentation-only edits, check links/contracts/formatting; reuse prior test evidence.
- Update canonical page source, regenerate deployment copies, and review before release.
