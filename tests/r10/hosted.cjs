// Genuine hosted TEST backend. Deliberate transport failures are labelled, never mocked data.
const { chromium } = require("playwright");
const fs = require("node:fs");
const { X509Certificate, createHash } = require("node:crypto");
const assert = require("node:assert/strict");
const TEST = "https://ohkpvuhzvshjglbqyepq.supabase.co";
const PUPIL = "https://monob26.github.io/gcse-history-homework-hub-test/";
const TEACHER = "https://monob26.github.io/history-teacher-dashboard-test/";
let browser,
  phase = "setup";
const diagnostics = [];
const passes = [];
function check(name, value) {
  assert.ok(value);
  passes.push(name);
  console.log("PASS: " + name);
}
(async () => {
  // Trust only the public-key pins from the environment's supplied proxy CA bundle.
  // No blanket ignoreHTTPSErrors; request allow-list remains enforced.
  const caBundle = process.env.NODE_EXTRA_CA_CERTS
    ? fs.readFileSync(process.env.NODE_EXTRA_CA_CERTS, "utf8")
    : "";
  const pins = (
    caBundle.match(/-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----/g) || []
  ).map((pem) =>
    createHash("sha256")
      .update(new X509Certificate(pem).publicKey.export({ type: "spki", format: "der" }))
      .digest("base64"),
  );
  const proxyUrl = process.env.HTTPS_PROXY ? new URL(process.env.HTTPS_PROXY) : null;
  browser = await chromium.launch({
    executablePath: "/usr/bin/chromium",
    headless: true,
    args: pins.length ? ["--ignore-certificate-errors-spki-list=" + pins.join(",")] : [],
    ...(proxyUrl
      ? {
          proxy: {
            server: proxyUrl.origin,
            bypass: "127.0.0.1,localhost",
            username: decodeURIComponent(proxyUrl.username),
            password: decodeURIComponent(proxyUrl.password),
          },
        }
      : {}),
  });

  const contexts = [],
    violations = [],
    exceptions = [],
    policyFailures = [];
  async function context() {
    const c = await browser.newContext({ serviceWorkers: "block" });
    contexts.push(c);
    await c.addInitScript(() =>
      document.addEventListener("securitypolicyviolation", () => {
        window.r10PolicyFailed = true;
      }),
    );
    await c.route("**/*", (route) => {
      const url = route.request().url();
      if (new URL(url).origin === TEST || url.startsWith(PUPIL) || url.startsWith(TEACHER))
        return route.continue();
      violations.push("blocked");
      return route.abort();
    });
    c.on("page", (p) => {
      p.setDefaultTimeout(20000);
      p.on("pageerror", () => exceptions.push("exception"));
      p.on("response", (r) => {
        const u = new URL(r.url());
        if (u.origin === TEST) diagnostics.push({ path: u.pathname, status: r.status() });
      });
    });
    return c;
  }
  try {
    const tc = await context(),
      t = await tc.newPage();
    phase = "teacher sign-in with local library and CSP";
    await t.goto(TEACHER);
    await t.locator("#email").fill("r8-test-teacher-a@example.test");
    await t.locator("#password").fill(process.env.R8_TEST_A_PASSWORD);
    await t.locator("#submitAuth").click();
    try {
      await t.locator("#dashboard").waitFor({ state: "visible" });
    } catch (error) {
      const text = await t.locator("#authMsg").innerText();
      console.log(
        JSON.stringify({
          diagnostics,
          invalidCredentials: /invalid.*credentials/i.test(text),
          rateLimit: /rate|too many/i.test(text),
          libraryMissing: /library/i.test(text),
          unapproved: /approved|authoris|access not granted/i.test(text),
          cspFailed: await t.evaluate(() => !!window.r10PolicyFailed),
        }),
      );
      throw error;
    }
    await t.waitForFunction(() =>
      [...document.querySelectorAll("#results tr")].some((r) => r.cells[0]?.textContent === "1"),
    );
    check(
      "hosted teacher signs in using local integrity-checked library under CSP",
      await t.evaluate(() => !!window.supabase?.createClient && !window.r10PolicyFailed),
    );
    check(
      "teacher uses class IDs and pressed year controls",
      (await t.locator("#classSelect").inputValue()) !== "R8 Fictional Class A" &&
        (await t.locator('[data-year="10"]').getAttribute("aria-pressed")) === "true",
    );
    const row = await t
      .locator("#results tr")
      .evaluateAll((rows) =>
        rows
          .map((r) => [...r.cells].map((c) => c.textContent))
          .find((r) => r[0] === "1" && r[4] === "Not completed"),
      );
    if (!row) throw Error("Unused existing fictional pupil required");
    const pupilCode = row[1];
    check(
      "teacher includes existing pupils with no attempts",
      Number(await t.locator("#total").innerText()) === 4 && row[2] === "0",
    );
    const pc = await context(),
      p = await pc.newPage();
    let answerRequests = 0,
      lastAnswerLost = false,
      completionLost = false,
      completionRequests = 0;
    await p.route(TEST + "/auth/**", (r) => r.abort());
    await p.route(TEST + "/rest/v1/rpc/submit_pupil_answer", async (route) => {
      try {
        answerRequests++;
        if (answerRequests === 25) {
          const response = await route.fetch();
          assert.ok(response.ok());
          lastAnswerLost = true;
          await response.dispose();
          return route.abort("failed");
        }
        return route.continue();
      } catch {
        diagnostics.push({ transport: "answer failure" });
        return route.abort();
      }
    });
    await p.route(TEST + "/rest/v1/rpc/complete_pupil_quiz", async (route) => {
      try {
        completionRequests++;
        if (!completionLost) {
          const response = await route.fetch();
          assert.ok(response.ok());
          completionLost = true;
          await response.dispose();
          return route.abort("failed");
        }
        return route.continue();
      } catch {
        diagnostics.push({ transport: "completion failure" });
        return route.abort();
      }
    });
    phase = "hosted server timing instructions";
    await p.goto(PUPIL);
    await p.locator("#code").fill(pupilCode);
    await p.locator("#loginForm button").click();
    await p.locator("#homeContent button").click();
    check(
      "hosted instruction durations come from current TEST quiz rows",
      /20 questions: 00:45 each.*5 questions: 01:00 each/.test(
        await p.locator("#instructionTiming").innerText(),
      ),
    );
    await p.locator("#startQuiz").click();
    await p.locator("#question").waitFor({ state: "visible" });
    phase = "hosted radio and modal keyboard interaction";
    const radios = p.getByRole("radio");
    await radios.nth(0).focus();
    await p.keyboard.press("ArrowRight");
    check(
      "hosted radio selection exposes checked state",
      (await radios.nth(1).getAttribute("aria-checked")) === "true",
    );
    await p.locator("#exitQuiz").click();
    check(
      "hosted modal enters focus and reports zero saved answers",
      (await p.locator("#stay").evaluate((e) => e === document.activeElement)) &&
        /No answers/.test(await p.locator("#exitProgress").innerText()),
    );
    await p.keyboard.press("Shift+Tab");
    check(
      "hosted modal traps reverse tab",
      await p.locator("#saveExit").evaluate((e) => e === document.activeElement),
    );
    await p.keyboard.press("Escape");
    check(
      "hosted Escape restores quiz focus",
      (await p.locator("#overlay").isHidden()) &&
        (await p.locator("#exitQuiz").evaluate((e) => e === document.activeElement)),
    );
    phase = "real quiz answers for changed final-save recovery path";
    for (let n = 1; n <= 25; n++) {
      await p.waitForFunction(
        (n) => document.querySelector("#qNumber").textContent === `Question ${n} of 25`,
        n,
      );
      await p.getByRole("radio", { name: "Option A", exact: true }).click();
      await p.locator("#submitAnswer").click();
      if (n < 25) {
        await p.locator("#feedback").waitFor({ state: "visible" });
        await p.locator("#nextQuestion").click();
      }
    }
    await p.locator("#offline").waitFor({ state: "visible" });
    check(
      "saved final answer response deliberately lost after real server success",
      lastAnswerLost && answerRequests === 25,
    );
    phase = "resume saved final answer and lose completion response";
    await p.locator("#retryConnection").click();
    await p.waitForFunction(() => document.querySelector("#retryConnection") && !busy);
    await p.locator("#offline").waitFor({ state: "visible" });
    check(
      "retry completes saved final question without another submission",
      completionLost && completionRequests === 1 && answerRequests === 25,
    );
    phase = "recover already committed completion";
    await p.locator("#retryConnection").click();
    await p.locator("#home").waitFor({ state: "visible" });
    check(
      "lost completion response recovers to authoritative saved homework summary",
      (await p.locator("#homeContent button").isDisabled()) &&
        /25\/25/.test(await p.locator("#homeContent").innerText()) &&
        completionRequests === 2,
    );
    phase = "teacher reads saved result through class-ID API";
    await t.reload();
    await t.waitForFunction(() =>
      [...document.querySelectorAll("#results tr")].some(
        (r) =>
          r.cells[0]?.textContent === "1" &&
          r.cells[3]?.textContent === "25/25" &&
          r.cells[4]?.textContent === "Passed",
      ),
    );
    check("class-ID results show genuinely saved completed pupil", true);
    await t.locator("#signOut").click();
    await t.locator("#authForm").waitFor({ state: "visible" });
    check(
      "no outside requests, browser exceptions or CSP violations",
      violations.length === 0 &&
        exceptions.length === 0 &&
        (await p.evaluate(() => !window.r10PolicyFailed)) &&
        (await t.evaluate(() => !window.r10PolicyFailed)),
    );
    const evidence = {
      date: new Date().toISOString(),
      project: "ohkpvuhzvshjglbqyepq",
      passes,
      backend: "real hosted TEST Supabase; no mocked payloads",
      fault_injection:
        "final answer and completion responses deliberately dropped only after real server success",
      new_fixtures: false,
      existing_fictional_pupil_used: true,
      completed_score: "25/25",
      live_resources_changed: false,
    };
    fs.writeFileSync("work/r10-hosted-acceptance.json", JSON.stringify(evidence, null, 2) + "\n");
  } finally {
    for (const c of contexts) await c.close();
  }
})()
  .catch(() => {
    console.error("FAIL: " + phase + " (details suppressed)");
    process.exitCode = 1;
  })
  .finally(async () => {
    if (browser) await browser.close();
  });
