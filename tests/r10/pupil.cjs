// Mocked RPC boundary; no request reaches a hosted resource.
const { chromium } = require("playwright");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const http = require("node:http");
const root = path.resolve(__dirname, "../..");
let phase = "setup";
(async () => {
  const server = http.createServer((req, res) => {
    const file = path.join(
      root,
      new URL(req.url, "http://localhost").pathname.replace(/\/$/, "/index.html"),
    );
    res.setHeader(
      "Content-Type",
      file.endsWith(".js")
        ? "application/javascript"
        : file.endsWith(".css")
          ? "text/css"
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
  });
  try {
    for (const scenario of [
      "keyboard-modal",
      "finish-retry",
      "finish-committed",
      "last-answer-retry",
      "saved-final-resume",
    ]) {
      phase = scenario;
      const page = await browser.newPage();
      page.setDefaultTimeout(5000);
      let saved = scenario === "saved-final-resume" ? 2 : 0,
        finished = false,
        finishCalls = 0,
        starts = 0;
      const errors = [],
        violations = [];
      page.on("pageerror", () => errors.push("exception"));
      await page.addInitScript(() => {
        document.addEventListener("securitypolicyviolation", (e) => {
          window.cspViolations = (window.cspViolations || []).concat(e.violatedDirective);
        });
      });
      await page.route("**/*", async (route) => {
        const u = new URL(route.request().url());
        if (!u.pathname.startsWith("/rest/v1/rpc/")) {
          if (u.origin !== origin) {
            violations.push(u.origin);
            return route.abort();
          }
          return route.continue();
        }
        const name = u.pathname.split("/").pop();
        let data,
          status = 200;
        if (name === "get_current_pupil_homework")
          data = {
            valid_code: true,
            year_group: 10,
            quiz_id: "quiz",
            quiz_title: "Fictional quiz",
            total_questions: 2,
            pass_mark: 2,
            attempts_taken: finished ? 1 : 0,
            highest_score: finished ? 2 : null,
            passed: finished,
            unfinished_attempt_id: saved ? "attempt" : null,
          };
        else if (name === "get_pupil_quiz_timing")
          data = { time_limits: [{ seconds: 90, questions: 2 }] };
        else if (name === "start_pupil_quiz") {
          starts++;
          data = { attempt_id: "attempt", attempt_token: "token" };
        } else if (name === "open_pupil_question") {
          if (saved === 2) {
            status = 400;
            data = { message: "All questions answered; complete the quiz" };
          } else
            data = {
              question_number: saved + 1,
              question_text: "Fictional question " + (saved + 1),
              answer_options: ["A", "B", "C", "D"],
              time_allowed_seconds: 90,
              seconds_remaining: 90,
            };
        } else if (name === "submit_pupil_answer") {
          saved++;
          data = { answer_correct: true, correct_option: 0, feedback: "Fictional feedback" };
          if (scenario === "last-answer-retry" && saved === 2) {
            status = 503;
            data = { message: "Fictional lost response" };
          }
        } else if (name === "complete_pupil_quiz") {
          finishCalls++;
          if (scenario === "finish-committed" && finishCalls === 1) {
            finished = true;
            status = 503;
            data = { message: "Fictional lost completion response" };
          } else if (scenario === "finish-committed" && finishCalls === 2) {
            status = 400;
            data = { message: "Invalid or completed attempt" };
          } else if (scenario === "finish-retry" && finishCalls === 1) {
            status = 503;
            data = { message: "Fictional temporary failure" };
          } else {
            finished = true;
            data = { total_questions: 2, final_score: 2, passed: true };
          }
        } else throw Error("Unexpected mocked RPC");
        return route.fulfill({
          status,
          contentType: "application/json",
          headers: { "Access-Control-Allow-Origin": "*" },
          body: JSON.stringify(Array.isArray(data) ? data : status === 200 ? [data] : data),
        });
      });
      await page.clock.install();
      await page.goto(origin + "/pupil/");
      await page.evaluate(() => window.dispatchEvent(new Event("offline")));
      assert.equal(await page.locator("#login").isVisible(), true);
      assert.match(await page.locator("#status").innerText(), /offline/);
      await page.locator("#code").fill("ABCDEFGHJKLM");
      await page.locator("#loginForm button").click();
      await page.locator("#homeContent button").click();
      assert.equal(await page.evaluate(() => document.activeElement.tagName === "H2"), true);
      if (scenario !== "saved-final-resume")
        assert.match(
          await page.locator("#instructionTiming").innerText(),
          /2 questions: 01:30 each/,
        );
      await page.locator(scenario === "saved-final-resume" ? "#resumeQuiz" : "#startQuiz").click();
      if (scenario === "saved-final-resume") {
        await page.locator("#result").waitFor({ state: "visible" });
        assert.equal(finishCalls, 1);
      } else {
        await page.locator("#question").waitFor({ state: "visible" });
        if (scenario === "keyboard-modal") {
          assert.equal(await page.locator("#timer").innerText(), "01:30");
          assert.match(await page.locator("#questionTiming").innerText(), /01:30/);
          assert.equal(
            await page.locator("#questionText").evaluate((e) => e === document.activeElement),
            true,
          );
          const radios = page.getByRole("radio");
          await radios.nth(0).focus();
          await page.keyboard.press("ArrowRight");
          assert.equal(await radios.nth(1).getAttribute("aria-checked"), "true");
          assert.equal(await radios.nth(0).getAttribute("aria-checked"), "false");
          await page.locator("#exitQuiz").click();
          assert.equal(
            await page.locator("#stay").evaluate((e) => e === document.activeElement),
            true,
          );
          assert.match(await page.locator("#exitProgress").innerText(), /No answers/);
          await page.keyboard.press("Shift+Tab");
          assert.equal(
            await page.locator("#saveExit").evaluate((e) => e === document.activeElement),
            true,
          );
          await page.keyboard.press("Tab");
          assert.equal(
            await page.locator("#stay").evaluate((e) => e === document.activeElement),
            true,
          );
          await page.clock.runFor(3000);
          await page.keyboard.press("Escape");
          assert.equal(await page.locator("#overlay").isHidden(), true);
          assert.equal(await page.locator("#timer").innerText(), "01:27");
          assert.equal(
            await page.locator("#exitQuiz").evaluate((e) => e === document.activeElement),
            true,
          );
          await page.locator("#submitAnswer").click();
          await page.locator("#feedback").waitFor({ state: "visible" });
          await page.locator("#exitQuiz").click();
          assert.match(await page.locator("#exitProgress").innerText(), /through Question 1/);
          await page.keyboard.press("Escape");
          await page.evaluate(() => window.dispatchEvent(new Event("offline")));
          assert.match(
            await page.locator("#offlineMessage").innerText(),
            /server timer continues/i,
          );
        } else {
          for (let i = 0; i < 2; i++) {
            await page.locator("#question").waitFor({ state: "visible" });
            await page.getByRole("radio").nth(0).click();
            await page.locator("#submitAnswer").click();
            if (i === 1 && scenario === "last-answer-retry") break;
            await page.locator("#feedback").waitFor({ state: "visible" });
            await page.locator("#nextQuestion").click();
          }
          await page.locator("#offline").waitFor({ state: "visible" });
          await page.locator("#retryConnection").click();
          if (scenario === "finish-committed") {
            await page.locator("#home").waitFor({ state: "visible" });
            assert.equal(await page.locator("#homeContent button").isDisabled(), true);
          } else {
            await page.locator("#result").waitFor({ state: "visible" });
            assert.equal(await page.locator("#resultScore").innerText(), "2 / 2");
          }
          assert.equal(saved, 2);
          assert.equal(starts, scenario === "last-answer-retry" ? 2 : 1);
        }
      }
      assert.deepEqual(errors, []);
      assert.deepEqual(violations, []);
      assert.deepEqual(await page.evaluate(() => window.cspViolations || []), []);
      console.log("PASS: R10 " + scenario);
      await page.close();
    }
  } finally {
    await browser.close();
    await new Promise((r) => server.close(r));
  }
})().catch(() => {
  console.error("FAIL: R10 " + phase + " (details suppressed)");
  process.exitCode = 1;
});
