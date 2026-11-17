// Real TEST-only pupil smoke. No teacher authentication; no LIVE request is permitted.
const { chromium } = require("playwright");
const assert = require("node:assert/strict");
const fs = require("node:fs"),
  path = require("node:path"),
  crypto = require("node:crypto");
const root = path.resolve(__dirname, "../..");
let phase = "initialising";
const TEST = "https://ohkpvuhzvshjglbqyepq.supabase.co",
  SITE = "https://monob26.github.io/gcse-history-homework-hub-test/";
(async () => {
  assert.ok(process.env.PUPIL_DESIGN_TEST_CODE);
  const bundle = process.env.NODE_EXTRA_CA_CERTS
    ? fs.readFileSync(process.env.NODE_EXTRA_CA_CERTS, "utf8")
    : "";
  const pins = (
    bundle.match(/-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----/g) || []
  ).map((pem) =>
    crypto
      .createHash("sha256")
      .update(new crypto.X509Certificate(pem).publicKey.export({ type: "spki", format: "der" }))
      .digest("base64"),
  );
  const proxy = process.env.HTTPS_PROXY ? new URL(process.env.HTTPS_PROXY) : null;
  const browser = await chromium.launch({
    executablePath: "/usr/bin/chromium",
    headless: true,
    args: pins.length ? ["--ignore-certificate-errors-spki-list=" + pins.join(",")] : [],
    ...(proxy
      ? {
          proxy: {
            server: proxy.origin,
            bypass: "127.0.0.1,localhost",
            username: decodeURIComponent(proxy.username),
            password: decodeURIComponent(proxy.password),
          },
        }
      : {}),
  });
  const passed = [];

  try {
    const context = await browser.newContext({ serviceWorkers: "block" }),
      errors = [],
      violations = [];
    await context.route("**/*", (r) => {
      const u = new URL(r.request().url());
      if (u.origin === TEST || r.request().url().startsWith(SITE)) return r.continue();
      violations.push("blocked outside TEST");
      return r.abort();
    });
    const page = await context.newPage();
    page.setDefaultTimeout(20000);
    page.on("pageerror", () => errors.push("exception"));
    await page.addInitScript(() =>
      document.addEventListener("securitypolicyviolation", () => {
        window.designPolicyFailure = true;
      }),
    );
    async function login() {
      await page.goto(SITE);
      await page.locator("#code").fill(process.env.PUPIL_DESIGN_TEST_CODE);
      await page.locator("#loginForm button").click();
      await page.locator("#homeContent button").waitFor();
      assert.match(await page.locator("#homeContent").innerText(), /R8 Fictional Practice Quiz/);
    }
    phase = "TEST login and real assignment";
    await login();
    assert.match(await page.locator("#homeContent").innerText(), /Not started/);
    passed.push("real TEST pupil code and assigned quiz loaded");
    await page.locator("#homeContent button").click();
    assert.match(await page.locator("#instructionPass").innerText(), /80%.*20 out of 25/);
    assert.match(await page.locator("#instructionTiming").innerText(), /00:45/);
    await page.locator("#startQuiz").click();
    for (let n = 1; n <= 25; n++) {
      phase = "failed attempt question " + n;
      await page
        .locator("#qNumber")
        .filter({ hasText: `Question ${n} of 25` })
        .waitFor();
      assert.match(await page.locator("#questionText").innerText(), /Fictional practice question/);
      if (n === 2) {
        const before = await page.locator("#timer").innerText();
        await page.locator("#exitQuiz").click();
        await page.locator("#saveExit").click();
        await page.locator("#homeContent button").waitFor();
        assert.match(await page.locator("#homeContent").innerText(), /In progress/);
        await page.reload();
        await page.locator("#code").fill(process.env.PUPIL_DESIGN_TEST_CODE);
        await page.locator("#loginForm button").click();
        await page.locator("#homeContent button").click();
        await page.locator("#resumeQuiz").click();
        await page.locator("#qNumber").filter({ hasText: "Question 2 of 25" }).waitFor();
        const after = await page.locator("#timer").innerText();
        const sec = (s) => s.split(":").reduce((a, b) => a * 60 + Number(b), 0);
        assert.ok(sec(after) <= sec(before) + 1);
        passed.push(
          "save/exit, fresh-page code entry and server resume preserve progress/deadline",
        );
      }
      if (n === 3) {
        await context.setOffline(true);
        await page.locator("#offline").waitFor({ state: "visible" });
        await context.setOffline(false);
        await page.locator("#retryConnection").click();
        await page.locator("#question").waitFor({ state: "visible" });
        assert.match(await page.locator("#qNumber").innerText(), /Question 3 of 25/);
        passed.push("offline interruption/reconnection resumes same question");
      }
      await page.locator("#options button").filter({ hasText: "Option B" }).click();
      await page.locator("#submitAnswer").click();
      await page.locator("#feedback.wrong").waitFor();
      assert.equal(await page.locator("#options button").first().isDisabled(), true);
      await page.locator("#nextQuestion").click();
    }
    await page.locator("#result").waitFor({ state: "visible" });
    assert.equal(await page.locator("#resultScore").innerText(), "0 / 25");
    assert.equal(await page.locator("#resultHeading").innerText(), "Not passed yet.");
    passed.push("real failed attempt, locked answers and inline incorrect feedback");
    await page.screenshot({
      path: path.join(root, "work/pupil-design-evidence/hosted-not-passed.png"),
      fullPage: true,
    });
    await page.locator("#resultAction").click();
    await page.locator("#startQuiz").click();
    for (let n = 1; n <= 25; n++) {
      phase = "retry question " + n;
      await page
        .locator("#qNumber")
        .filter({ hasText: `Question ${n} of 25` })
        .waitFor();
      await page.locator("#options button").filter({ hasText: "Option A" }).click();
      await page.locator("#submitAnswer").click();
      await page.locator("#feedback.correct").waitFor();
      await page.locator("#nextQuestion").click();
    }
    await page.locator("#result").waitFor({ state: "visible" });
    assert.equal(await page.locator("#resultScore").innerText(), "25 / 25");
    assert.equal(await page.locator("#resultHeading").innerText(), "You passed!");
    passed.push("retry uses real shuffled options and saved 25/25 passed result");
    await page.screenshot({
      path: path.join(root, "work/pupil-design-evidence/hosted-passed.png"),
      fullPage: true,
    });
    await page.locator("#resultAction").click();
    await page.locator("#homeContent button").waitFor();
    assert.equal(await page.locator("#homeContent button").isDisabled(), true);
    assert.match(await page.locator(".status").innerText(), /Passed/);
    assert.equal(await page.locator(".ribbon").innerText(), "COMPLETED HOMEWORK");
    passed.push(
      "passed quiz remains visible under Completed Homework without invented review action",
    );
    assert.deepEqual(errors, []);
    assert.deepEqual(violations, []);
    assert.equal(await page.evaluate(() => !!window.designPolicyFailure), false);
    fs.writeFileSync(
      path.join(root, "work/pupil-design-evidence/hosted-results.json"),
      JSON.stringify(
        {
          scope: "Real isolated TEST Supabase and published TEST page; no mocked responses",
          passed,
          answer_submissions: 50,
          attempts_completed: 2,
          live_requests: 0,
          teacher_login_attempts: 0,
          emails_sent: 0,
          new_backend_functionality: false,
          credentials_or_codes_recorded: false,
        },
        null,
        2,
      ) + "\n",
    );
    console.log(
      "PASS: real TEST-only start, inline feedback, save/refresh/resume, offline recovery, failed attempt and successful retry; no LIVE requests",
    );
  } finally {
    await browser.close();
  }
})().catch(() => {
  console.error("FAIL: TEST-only pupil smoke at " + phase + "; private details suppressed");
  process.exitCode = 1;
});
