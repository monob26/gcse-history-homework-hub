# REVIEW.md: History Homework Hub

Review date: 2026-11-14. Reviewed commits: `gcse-history-homework-hub@3e3d852` and `history-teacher-dashboard@6741666`.

This file is a task list for a coding assistant. It is not a set of standing rules. Delete it when every task is ticked.

`ADVERSARIAL.md` is its companion: 14 abuse tests to run against fictional data. Run it after R1, and again after R2, R3, R4 and R11.

## What this file needs

This file works with Claude Code or Codex. It needs an agent that can edit the files in the repository and run commands. A chat window alone can do R4, R5 and most of R10, but not R1, R9 or `ADVERSARIAL.md`.

Read the database through the Supabase MCP server (see R1). Do not ask the owner for screenshots of the Supabase dashboard.

## How to work through this file

1. Do one task per session, in the order shown. R1 comes first because later tasks need the database code in the repository.
2. Read the Evidence lines and open the files before you plan. Line numbers refer to the commits above.
3. Show the owner a plan before you change anything. Ask when a task says "Confirm first".
4. A task is done only when its "Done when" check passes. Then tick its box.
5. Check Supabase commands and settings against the current Supabase documentation before you run them.
6. Use fictional pupil data only. Never put a secret key, a service-role key or a password in any file.

## System as reviewed

1. `gcse-history-homework-hub/index.html` is the pupil page. A pupil enters a code, then takes a timed multiple-choice quiz. It calls five database functions in the `homework_api` schema through `fetch`: `get_current_pupil_homework`, `start_pupil_quiz`, `open_pupil_question`, `submit_pupil_answer`, `complete_pupil_quiz`.
2. `history-teacher-dashboard/index.html` is the teacher page. It signs in with Supabase Auth, calls `is_history_teacher` and `get_history_class_results`, and reads the tables `history_classes`, `history_quizzes` and `history_pupils`.
3. Both pages are hosted on GitHub Pages from `main` and share one Supabase project.
4. The database schema, row-level security policies and functions are not in either repository. This review could not see them.

## Keep these decisions

1. The server marks answers. The page learns `correct_option` only from the `submit_pupil_answer` response.
2. Only the publishable key is in browser code.
3. Pupils are identified by code, never by name.
4. Database text is escaped (`esc()` in the pupil page) or set with `textContent` (teacher page).
5. No framework and no build step. Keep it that way unless a task needs otherwise.

## Now: before any real pupil data

### [x] R1. Put the Supabase backend under version control

- Severity: high. Effort: medium.
- Evidence: both repositories contain only `README.md` and `index.html`. The pupil page depends on five functions (`gcse-history-homework-hub/index.html` line 42). The teacher page depends on two functions and three tables (`history-teacher-dashboard/index.html` lines 101, 102, 116, 122, 123).
- Why: every security guarantee lives in the database. It cannot be reviewed, tested, or restored from GitHub today.
- Do:
  1. Set up the Supabase CLI and link it to the project.
  2. Optional, while the data is fictional: connect the Supabase MCP server so that you can read the schema, logs and advisors directly. Scope it to this one project with `project_ref`. The owner removes the connection before real data goes in. Even with this access, make every change as a migration file.
  3. Export the schema only (tables, policies, functions, grants) for the `public` and `homework_api` schemas into `supabase/migrations/`. Export no row data.
  4. Check the exported SQL for secrets before you commit it.
  5. Add a section to the README that lists each function with its parameters and return fields.
  6. From now on, change the database through a new migration file, not through the dashboard editor.
- Done when: a fresh Supabase project built from `supabase/migrations/` serves both pages with fictional data.

### [ ] R2. Prove the access rules from outside

- Severity: high. Effort: small. Needs R1.
- Evidence: the teacher page reads tables in the exposed `public` schema (`history-teacher-dashboard/index.html` lines 101, 122, 123). Row-level security is the only protection for those tables. The first prototype called a function named `check_pupil_code` (commit `bf13f7d` in `gcse-history-homework-hub`).
- Why: the publishable key is public by design, so anyone can send any request with it.
- Do:
  1. Run the Supabase Security Advisor and fix every finding.
  2. Confirm that row-level security is enabled on every table.
  3. With the publishable key and no login, request each table and each function. A table must return no rows. A teacher-only function must refuse.
  4. Sign in as a teacher with no allocated classes. Confirm that the account sees no class, pupil or result.
  5. Confirm that each `SECURITY DEFINER` function sets a fixed `search_path` and that `EXECUTE` is granted only to the roles that need it.
  6. Drop `check_pupil_code` if it still exists. It tells a caller whether a code is valid and nothing else uses it.
  7. Confirm that public sign-up is disabled in Supabase Auth, and that the redirect allow-list holds only the dashboard URL.
  8. Run the tests in `ADVERSARIAL.md` and record the results in its table. Tests T1 to T4 cover this task.
- Done when: the checks in steps 3 and 4 exist as a repeatable script or SQL test in the repository, and they pass.

### [ ] R3. Make pupil codes hard to guess

- Severity: high. Effort: medium. Confirm first: are codes built from a class prefix plus a register number?
- Evidence: the prototype validated codes with `^[A-Z0-9]{5}-[0-9]{2,3}$` and gave the example `K7M4P-01` (commit `bf13f7d`). The teacher page sorts pupils by the number after the hyphen (`registerNumber`, `history-teacher-dashboard/index.html` line 70). `get_current_pupil_homework` returns `valid_code`, which confirms or denies any guess (`gcse-history-homework-hub/index.html` line 46).
- Why: the code is the pupil's only credential. If classmates share a prefix, one pupil can enter as another and use up or spoil that pupil's attempts.
- Do:
  1. Give each pupil an independent random code of at least 8 characters from an unambiguous alphabet (no `0`, `O`, `1`, `I`).
  2. Keep the register number as a separate column for sorting. Update `registerNumber` and the sort on line 86 to use it.
  3. Limit failed code checks inside the database functions, for example per client address per 10 minutes.
  4. Return the same response time and shape for valid and invalid codes where practical.
- Done when: a test shows that 20 wrong codes in a row are blocked, and no code can be derived from another.

### [ ] R4. Fix two timer bugs in the pupil page

- Severity: medium. Effort: small. Both bugs were reproduced with jsdom and a mocked backend.
- Bug A, expired question on resume:
  - Evidence: `start()` sets `busy=true` and awaits `openQuestion()` (line 57). `openQuestion()` calls `runTimer()` (line 63). When `seconds_remaining` is 0, `runTimer()` calls `submit(true)` (line 64). `submit()` returns at once because `busy` is still true (line 66). The `nextQuestion` handler has the same pattern (line 71).
  - Result: the timer shows `00:00`, no answer is sent, Submit stays disabled, and the pupil can only exit.
  - Do: let the timed-out submit run after `busy` clears, or pass a flag that bypasses the `busy` check for the timeout path.
- Bug B, Exit dialog pauses the clock:
  - Evidence: `exitQuiz` calls `stopTimer()` (line 73). `stay` calls `runTimer()`, which sets a new deadline from the stale `seconds` value (lines 64 and 74). After 3 seconds in the dialog the display still showed the old time.
  - Result: the page and the server disagree about the time left. The check `if(exitModal)return` inside the interval never runs because the interval is already stopped.
  - Do: keep the original deadline while the dialog is open, or call `open_pupil_question` again on `stay` and use its `seconds_remaining`.
- Confirm first: does the database reject or mark as wrong an answer that arrives after the time limit? If not, add that rule in the database, because a page-only timer can be ignored.
- Done when: a browser test covers both cases and passes.

### [ ] R5. Pin the Supabase library and add an integrity hash

- Severity: medium. Effort: small.
- Evidence: `history-teacher-dashboard/index.html` line 32 loads `https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js`. The `@2` tag floats and the tag has no `integrity` attribute.
- Why: this page takes teacher passwords. A changed or compromised CDN file would run with full access to them.
- Do: pin an exact version and add `integrity` and `crossorigin="anonymous"`, or copy the file into the repository and load it locally.
- Done when: the script tag names an exact version with a valid hash, and sign-in still works.

### [ ] R11. Stop one network from locking out every teacher

- Severity: medium. Effort: small. Added 2026-11-14 after a live test.
- Evidence: repeated sign-in attempts on the teacher page from one home network produced a rate limit. A second person on the same network could then not sign in. Supabase Auth counts these requests per network address, and a school usually shares one address.
- Why: one teacher with a forgotten password, or one pupil who hammers the login form from the school network, can block every teacher.
- Do:
  1. Confirm first: read the Auth logs to see which limit was reached.
  2. Review each value under Authentication, Rate Limits and set it on purpose for a school that shares one address.
  3. Add CAPTCHA to the sign-in and reset forms so that a higher limit does not help a script.
  4. Check the hourly cap on reset emails. Move to a custom SMTP service if the built-in cap is too low for a department.
  5. Show a plain message on the teacher page when Supabase returns a rate limit error, with the time to wait.
- Done when: tests T13 and T14 in `ADVERSARIAL.md` pass.

## Next

### [ ] R6. Merge into one repository with readable files

- Severity: medium. Effort: medium.
- Evidence: the longest line is 3,650 characters in the pupil page and 2,337 in the teacher page. `SUPABASE_URL` and the key are duplicated (pupil lines 26 and 27, teacher lines 36 and 37). The two stylesheets define different values for `--navy` (`#183348` and `#172b46`) and different fonts.
- Why: single-line CSS and dense JavaScript make diffs unreadable and make assistant edits error-prone. Two repositories hide the shared database from each page.
- Do:
  1. Create one repository with `pupil/`, `teacher/`, `shared/` and `supabase/`.
  2. Split each page into `index.html`, `styles.css` and `app.js`. Keep plain files with no build step.
  3. Move the Supabase URL, the key and the shared colours into `shared/`.
  4. Format everything with Prettier in a commit that changes nothing else.
  5. Keep the two public URLs working, or tell the owner which URLs change. Update `REDIRECT_URL` (teacher line 38) and the Supabase redirect allow-list if the dashboard URL changes.
- Done when: both pages behave as before and no line is longer than 120 characters.

### [ ] R7. Write the README and a short agent instructions file

- Severity: medium. Effort: small. Needs R1.
- Evidence: `gcse-history-homework-hub/README.md` has two lines and `history-teacher-dashboard/README.md` has one.
- Do:
  1. README: purpose, who uses each page, a diagram of pages and database, how to run locally, how to deploy, the function contract from R1.
  2. An agent instructions file, under 40 lines (`CLAUDE.md` for Claude Code, `AGENTS.md` for Codex): the project in three sentences, the folder map, the rules "fictional data only" and "no secret keys in the repository", and how to run the tests.
- Done when: a new session can explain the quiz flow from the repository alone.

### [ ] R8. Change the site through branches, and keep test apart from live

- Severity: medium. Effort: medium.
- Evidence: GitHub Pages serves `main`. All commits were made directly on `main`, most through the GitHub web editor. One commit message does not match its change: "Update print statement from 'Hello' to 'Goodbye'" (`1020628`) changed 47 lines of `index.html`.
- Why: once pupils use the site, a bad upload breaks homework at once.
- Do:
  1. Work on a branch and merge through a pull request with a message that describes the change.
  2. Keep a separate Supabase project for testing when the first project holds real data. Select the project in `shared/` config.
  3. Turn on two-factor authentication for the GitHub and Supabase accounts.
  4. In GitHub email settings, keep the email address private so that new commits do not publish a personal address.
- Done when: `main` is protected and the test site points at the test project.

### [ ] R9. Add automated tests where mistakes cost most

- Severity: medium. Effort: large. Needs R1.
- Evidence: neither repository contains a test or a workflow file.
- Do, in this order:
  1. Database tests (pgTAP or plain SQL scripts) for the access rules in R2.
  2. Database tests for the quiz functions: an answer needs a valid attempt token, a question cannot be answered twice, a late answer is refused, `start_pupil_quiz` resumes an unfinished attempt, and `complete_pupil_quiz` cannot finish an incomplete attempt.
  3. One Playwright test that plays a full quiz against mocked functions, including the two cases in R4.
  4. A GitHub Actions workflow that runs the tests on every pull request.
- Done when: the workflow is green on `main`.

## Later

### [ ] R10. Accessibility and polish

Each item is small. All line numbers are in `gcse-history-homework-hub/index.html` unless marked.

1. Answer options are plain buttons with a CSS class for the selected state (line 62). Use radio inputs, or `role="radio"` with `aria-checked`, so that a screen reader announces the selection.
2. The Exit dialog (line 23) sets `aria-modal` but does not move focus into the dialog, trap focus, or close on Escape.
3. `show()` (line 32) changes the screen without moving focus. Move focus to the new screen's heading.
4. `clock(60)` returns `00:60` (line 34). Format minutes and seconds.
5. The Exit message says "up to Question N-1" (line 73). It reads "Question 0" on the first question, and it understates by one after the current question is answered.
6. The instructions hard-code "45 seconds for Questions 1 to 20; 60 seconds for Questions 21 to 25" (line 16). Build this text from server values.
7. The `offline` listener (line 77) shows "The quiz is paused" on any screen, including the home screen.
8. Confirm first: the retry handler (line 76) calls `start_pupil_quiz` then `openQuestion()`. If the last answer was saved but `complete_pupil_quiz` failed, check that retry reaches the result screen and does not loop.
9. Confirm first: pupils with extra-time arrangements. Add a per-pupil time multiplier in the database if the school needs it.
10. Teacher page: in reset mode the email field is still required but unused (teacher lines 17 and 48).
11. Teacher page: when a quiz is selected, totals come from `liveRows` only and `classCodes` is unused (teacher lines 74 to 77). Merge the two lists so that a pupil with no attempt always appears. Confirm first what `get_history_class_results` returns.
12. Teacher page: `get_history_class_results` takes a class name while the pupil query takes a class id (teacher lines 101 and 102). Use the id in both.
13. Teacher page: the year tabs use `role="tab"` without tab panels or arrow-key support (teacher line 27). Plain buttons with `aria-pressed` are simpler and correct.
14. After R6, add a Content-Security-Policy meta tag that allows scripts from the site itself and connections to the Supabase project only.
15. Consider Supabase multi-factor sign-in for teacher accounts.

## Questions for the owner

1. Do all pupils in one class share the first five characters of their code? (R3)
2. Does `start_pupil_quiz` return the unfinished attempt, or start a new one? (R9, R10 item 8)
3. Does the database enforce the time limit? (R4)
4. Does `get_history_class_results` return a row for every pupil in the class? (R10 item 11)
5. Is public sign-up disabled in Supabase Auth? (R2)
6. Who will own the Supabase project and the GitHub account when real data goes in, and which region stores the data?
