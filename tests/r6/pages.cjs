// Real Chromium, fictional mocked RPCs, virtual time; no network request may leave this origin.
const { chromium } = require("playwright");
const fs = require("fs"),
  http = require("http"),
  assert = require("assert/strict");
const root = require("path").resolve(__dirname, "../..");

(async () => {
  const server = http.createServer((req, res) => {
    const pathname = new URL(req.url, "http://localhost").pathname;
    const file = require("path").join(root, pathname === "/" ? "index.html" : pathname);
    res.setHeader(
      "Content-Type",
      file.endsWith(".css")
        ? "text/css"
        : file.endsWith(".js")
          ? "application/javascript"
          : "text/html",
    );
    res.end(fs.readFileSync(file));
  });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const origin = "http://127.0.0.1:" + server.address().port;
  const browser = await chromium.launch({
    ...(process.env.PLAYWRIGHT_USE_BUNDLED_CHROMIUM === "1"
      ? {}
      : { executablePath: "/usr/bin/chromium" }),
    headless: true,
    args: ["--no-sandbox"],
  });
  const results = [];
  try {
    for (const scenario of [
      "expired-resume",
      "expired-next",
      "dialog-keeps-deadline",
      "dialog-expires",
      "full-quiz",
      "cooldown",
    ]) {
      if (process.env.R6_SCENARIO && process.env.R6_SCENARIO !== scenario) continue;
      const page = await browser.newPage();
      let opens = 0,
        answers = [],
        completed = false;
      const errors = [];
      page.on("pageerror", (e) => errors.push(e.message));
      await page.route("**/*", async (route) => {
        const u = new URL(route.request().url());
        if (!u.pathname.startsWith("/rest/v1/rpc/")) {
          assert.equal(u.origin, origin, "External network forbidden");
          return route.continue();
        }
        const name = u.pathname.split("/").pop(),
          p = route.request().postDataJSON();
        if (scenario === "cooldown") {
          return route.fulfill({
            status: 429,
            headers: {
              "Content-Type": "application/json",
              "Retry-After": "7",
              "Access-Control-Allow-Origin": "*",
              "Access-Control-Expose-Headers": "Retry-After",
            },
            body: JSON.stringify({ message: "Fictional cooldown" }),
          });
        }
        let data;
        if (name === "get_current_pupil_homework")
          data = {
            valid_code: true,
            year_group: 10,
            class_name: "Fictional class",
            quiz_id: "00000000-0000-4000-8000-000000000001",
            quiz_title: "Fictional quiz",
            total_questions: 25,
            pass_mark: 20,
            attempts_taken: 0,
            passed: completed,
            unfinished_attempt_id: scenario === "expired-resume" ? "fictional-attempt" : null,
          };
        else if (name === "get_pupil_quiz_timing")
          data = {
            time_limits: [
              { seconds: 45, questions: 20 },
              { seconds: 60, questions: 5 },
            ],
          };
        else if (name === "start_pupil_quiz")
          data = { attempt_id: "fictional-attempt", attempt_token: "fictional-token" };
        else if (name === "open_pupil_question") {
          opens++;
          data = {
            question_number: opens,
            question_text: "Fictional question",
            answer_options: ["A", "B", "C", "D"],
            time_allowed_seconds: 45,
            seconds_remaining:
              scenario === "expired-resume" || (scenario === "expired-next" && opens === 2)
                ? 0
                : 45,
          };
        } else if (name === "submit_pupil_answer") {
          answers.push(p.entered_answer);
          data = {
            answer_correct: p.entered_answer === 0,
            correct_option: 0,
            feedback: "Fictional feedback",
          };
        } else if (name === "complete_pupil_quiz") {
          completed = true;
          data = { total_questions: 25, final_score: 25, passed: true };
        } else throw Error("Unexpected RPC " + name);
        await route.fulfill({ json: data });
      });
      try {
        await page.clock.install({ time: new Date("2026-01-01T00:00:00Z") });
        await page.clock.pauseAt(new Date("2026-01-01T00:00:01Z"));
        await page.goto(origin);
        await page.locator("#code").fill("ABCDEFGHJKLM");
        await page.locator("#loginForm button").click();
        if (scenario === "cooldown") {
          await page.locator("#loginError").filter({ hasText: "Please wait 7 seconds" }).waitFor();
          assert.deepEqual(errors, []);
          results.push({ scenario, status: "PASS" });
          continue;
        }
        if (scenario === "full-quiz") {
          await page.locator("#homeContent").filter({ hasText: "25 questions" }).waitFor();
          assert.match(await page.locator("#homeContent").innerText(), /20\/25 \(80%\) to pass/);
        }
        await page.locator("#homeContent button").click();
        if (scenario === "full-quiz")
          assert.equal(
            await page.locator("#instructionDetails").innerText(),
            "25 questions in total.",
          );
        await page.locator(scenario === "expired-resume" ? "#resumeQuiz" : "#startQuiz").click();
        await page.locator("#question").waitFor({ state: "visible" });
        if (scenario === "full-quiz") {
          for (let n = 1; n <= 25; n++) {
            await page
              .locator("#qNumber")
              .filter({ hasText: `Question ${n} of 25` })
              .waitFor();
            await page.locator("#options button").nth(0).click();
            await page.locator("#submitAnswer").click();
            await page.locator("#feedback").waitFor({ state: "visible" });
            await page.locator("#nextQuestion").click();
          }
          await page.locator("#result").waitFor({ state: "visible" });
          assert.equal(
            await page.locator("#instructionPass").innerText(),
            "80% to pass (20 out of 25).",
          );
          assert.equal(await page.locator("#resultScore").innerText(), "25 / 25");
          assert.deepEqual(answers, Array(25).fill(0));
          await page.locator("#resultAction").click();
          await page.locator("#home").waitFor({ state: "visible" });
          assert(await page.locator("#homeContent button").isDisabled());
          assert.deepEqual(errors, []);
          results.push({ scenario, status: "PASS" });
          continue;
        }
        if (scenario === "expired-next") {
          await page.locator("#options button").nth(1).click();
          await page.locator("#submitAnswer").click();
          await page.locator("#nextQuestion").click();
          await page.locator("#qNumber").filter({ hasText: "Question 2 of" }).waitFor();
        }
        if (scenario.startsWith("expired")) {
          await page.clock.runFor(400);
          await page.locator("#feedback").waitFor({ state: "visible" });
          assert.deepEqual(answers, scenario === "expired-next" ? [1, null] : [null]);
          await page.locator("#feedback").waitFor({ state: "visible" });
          assert.match(await page.locator("#feedback").innerText(), /Time is up/);
          await page.clock.runFor(1000);
          assert.equal(answers.length, scenario === "expired-next" ? 2 : 1);
        } else {
          await page.locator("#exitQuiz").click();
          await page.clock.runFor(scenario === "dialog-expires" ? 46000 : 3000);
          if (scenario === "dialog-expires") {
            await page.locator("#feedback").waitFor({ state: "visible" });
            assert.deepEqual(answers, [null]);
            assert.equal(await page.locator("#timer").innerText(), "00:00");
          } else {
            assert.equal(await page.locator("#timer").innerText(), "00:42");
            assert.equal(answers.length, 0);
          }
          await page.locator("#stay").click();
          await page.clock.runFor(1000);
          assert.equal(
            await page.locator("#timer").innerText(),
            scenario === "dialog-expires" ? "00:00" : "00:41",
          );
          assert.deepEqual(answers, scenario === "dialog-expires" ? [null] : []);
        }
        assert.deepEqual(errors, []);
        results.push({ scenario, status: "PASS" });
      } catch (e) {
        results.push({ scenario, status: "FAIL", reason: e.message });
      } finally {
        await page.close();
      }
    }
  } finally {
    await browser.close();
    await new Promise((r) => server.close(r));
  }
  const result = {
    scope: "R6 split pupil assets with fictional RPC responses; no hosted requests",
    results,
  };
  console.log(JSON.stringify(result, null, 2));
  if (results.some((r) => r.status === "FAIL")) process.exitCode = 1;
})().catch((e) => {
  console.error(e.message);
  process.exitCode = 1;
});
