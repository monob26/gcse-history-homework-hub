// Pupil UI only: real staged assets and engine, fictional intercepted RPCs, no hosted traffic.
const { chromium } = require("playwright");
const fs = require("node:fs"),
  path = require("node:path"),
  http = require("node:http"),
  os = require("node:os"),
  assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const root = path.resolve(__dirname, "../..");
(async () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "pupil-design-"));
  execFileSync("python3", [
    path.join(root, "scripts/prepare-pages.py"),
    "pupil",
    temp,
    "--environment",
    "test",
    "--test-config",
    path.join(root, "docs/r8/test-config.json"),
  ]);
  const output = path.join(root, "work/pupil-design-evidence");
  fs.mkdirSync(output, { recursive: true });
  const server = http.createServer((req, res) => {
    const f = path.join(
      temp,
      new URL(req.url, "http://localhost").pathname.replace(/\/$/, "/index.html"),
    );
    if (!fs.existsSync(f)) {
      res.writeHead(404).end();
      return;
    }
    res.setHeader(
      "Content-Type",
      f.endsWith(".js")
        ? "application/javascript"
        : f.endsWith(".css")
          ? "text/css"
          : f.endsWith(".png")
            ? "image/png"
            : f.endsWith(".svg")
              ? "image/svg+xml"
              : "text/html",
    );
    res.end(fs.readFileSync(f));
  });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const origin = "http://127.0.0.1:" + server.address().port;
  const browser = await chromium.launch({
    ...(process.env.PLAYWRIGHT_USE_BUNDLED_CHROMIUM === "1"
      ? {}
      : { executablePath: "/usr/bin/chromium" }),
    headless: true,
  });
  const outcomes = [];
  try {
    for (const [device, width, height] of [
      ["desktop", 1280, 900],
      ["mobile", 390, 844],
    ]) {
      for (const scenario of [
        "login",
        "dashboard",
        "in-progress",
        "not-passed-home",
        "completed",
        "overdue",
        "instructions",
        "question",
        "correct",
        "incorrect",
        "timeout",
        "passed",
        "not-passed",
        "resume",
        "offline",
        "exit",
      ]) {
        if (
          process.env.DESIGN_SCENARIOS &&
          !process.env.DESIGN_SCENARIOS.split(",").includes(scenario)
        )
          continue;
        const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
        page.setDefaultTimeout(6000);
        const errors = [],
          violations = [];
        let answered = false,
          calls = 0;
        page.on("pageerror", (e) => errors.push(e.message));
        await page.addInitScript(() =>
          document.addEventListener("securitypolicyviolation", (e) => {
            window.policyFailures = (window.policyFailures || []).concat(e.effectiveDirective);
          }),
        );
        await page.clock.install({ time: new Date("2026-11-19T12:00:00Z") });
        await page.clock.pauseAt(new Date("2026-11-19T12:00:01Z"));
        await page.route("**/*", (route) => {
          const url = new URL(route.request().url());
          if (url.origin === origin) return route.continue();
          assert.equal(
            url.origin,
            "https://ohkpvuhzvshjglbqyepq.supabase.co",
            "Only TEST may be intercepted",
          );
          assert.ok(url.pathname.startsWith("/rest/v1/rpc/"));
          calls++;
          const name = url.pathname.split("/").pop();
          let data;
          if (name === "get_current_pupil_homework")
            data = {
              valid_code: true,
              class_name: "Fictional class",
              year_group: 11,
              quiz_id: "00000000-0000-4000-8000-000000000001",
              quiz_title: "Germany 1918–1923",
              total_questions: 25,
              pass_mark: 20,
              attempts_taken: scenario === "not-passed-home" ? 1 : 0,
              highest_score: scenario === "not-passed-home" ? 16 : null,
              passed: scenario === "completed",
              unfinished_attempt_id: ["in-progress", "resume"].includes(scenario)
                ? "fictional-attempt"
                : null,
              due_at: scenario === "overdue" ? "2026-11-18T16:00:00Z" : "2026-11-20T16:00:00Z",
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
          else if (name === "open_pupil_question")
            data = {
              question_number: ["passed", "not-passed"].includes(scenario) ? 25 : 7,
              question_text: "What was the name given to the German government set up in 1919?",
              answer_options: [
                "The Kaiser's government",
                "The Weimar Republic",
                "The Nazi government",
                "The National Assembly",
              ],
              time_allowed_seconds: 45,
              seconds_remaining: 39,
            };
          else if (name === "submit_pupil_answer") {
            assert.equal(answered, false);
            answered = true;
            data = {
              answer_correct:
                scenario !== "incorrect" && scenario !== "not-passed" && scenario !== "timeout",
              correct_option: 1,
              feedback: "The German government set up in 1919 was the Weimar Republic.",
            };
          } else if (name === "complete_pupil_quiz")
            data = {
              total_questions: 25,
              final_score: scenario === "passed" ? 22 : 16,
              passed: scenario === "passed",
            };
          else throw Error("Unexpected RPC");
          return route.fulfill({ json: [data], headers: { "Access-Control-Allow-Origin": "*" } });
        });
        await page.goto(origin);
        if (scenario !== "login") {
          await page.locator("#code").fill("ABCDEFGHJKLM");
          await page.locator("#loginForm button").click();
          await page.locator("#homeContent button").waitFor();
          if (scenario === "in-progress")
            assert.match(await page.locator(".status").innerText(), /In progress/);
          if (scenario === "not-passed-home")
            assert.match(await page.locator(".status").innerText(), /Completed but not passed/);
          if (scenario === "completed") {
            assert.equal(await page.locator("#homeContent button").isDisabled(), true);
            assert.equal(await page.locator(".ribbon").innerText(), "COMPLETED HOMEWORK");
          }
          if (scenario === "overdue") {
            assert.equal(await page.locator(".overdue").innerText(), "Overdue");
            assert.match(await page.locator(".due").innerText(), /18 November/);
          }
          if (
            !["dashboard", "in-progress", "not-passed-home", "completed", "overdue"].includes(
              scenario,
            )
          ) {
            await page.locator("#homeContent button").click();
            if (scenario !== "resume" && scenario !== "instructions") {
              await page.locator("#startQuiz").click();
              await page
                .locator("#questionText")
                .filter({ hasText: "German government" })
                .waitFor();
              if (["correct", "incorrect", "passed", "not-passed"].includes(scenario)) {
                await page
                  .locator("#options button")
                  .nth(scenario === "incorrect" ? 0 : 1)
                  .click();
                await page.locator("#submitAnswer").click();
                await page.locator("#feedback").waitFor();
                assert.equal(await page.locator("#question").isVisible(), true);
                assert.equal(await page.locator("#options button").first().isDisabled(), true);
                if (["passed", "not-passed"].includes(scenario)) {
                  await page.locator("#nextQuestion").click();
                  await page.locator("#result").waitFor({ state: "visible" });
                  assert.equal(
                    await page.locator("#resultHeading").innerText(),
                    scenario === "passed" ? "You passed!" : "Not passed yet.",
                  );
                }
              }
              if (scenario === "timeout") {
                await page.clock.runFor(40000);
                await page.locator("#feedback").waitFor();
                assert.match(await page.locator("#feedback").innerText(), /Time is up/);
              }
              if (scenario === "exit") {
                await page.locator("#exitQuiz").click();
                await page.locator("#overlay").waitFor();
              }
              if (scenario === "offline") {
                await page.evaluate(() => window.dispatchEvent(new Event("offline")));
                await page.locator("#offline").waitFor({ state: "visible" });
                assert.match(await page.locator("#offlineMessage").innerText(), /timer continues/);
              }
            }
          }
        }
        assert.equal(
          await page.locator("body").evaluate((e) => e.scrollWidth <= innerWidth),
          true,
          "No horizontal overflow",
        );
        assert.equal(await page.locator("[id=chronology], .review-button, #show-more").count(), 0);
        assert.deepEqual(errors, []);
        assert.deepEqual(await page.evaluate(() => window.policyFailures || []), []);
        await page.screenshot({
          path: path.join(output, device + "-" + scenario + ".png"),
          fullPage: true,
        });
        outcomes.push({ device, scenario, result: "PASS", intercepted_rpc_calls: calls });
        await page.close();
      }
    }
    if (process.env.DESIGN_SCENARIOS) {
      const old = JSON.parse(
        fs.readFileSync(path.join(output, "visual-test-results.json"), "utf8"),
      );
      const keys = new Set(outcomes.map((x) => x.device + ":" + x.scenario));
      outcomes.push(...old.outcomes.filter((x) => !keys.has(x.device + ":" + x.scenario)));
    }
    fs.writeFileSync(
      path.join(output, "visual-test-results.json"),
      JSON.stringify(
        { scope: "Fictional intercepted TEST RPCs only; not hosted acceptance", outcomes },
        null,
        2,
      ) + "\n",
    );
    console.log(
      "PASS: " +
        outcomes.length +
        " desktop/mobile screen, status, feedback, timer and result checks; no hosted requests",
    );
  } finally {
    await browser.close();
    await new Promise((r) => server.close(r));
    fs.rmSync(temp, { recursive: true, force: true });
  }
})().catch((e) => {
  console.error("FAIL: pupil design " + e.message);
  process.exitCode = 1;
});
