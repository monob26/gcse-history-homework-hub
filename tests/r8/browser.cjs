// Real isolated backend acceptance. No screenshots, traces, storage files or payload logs.
const { chromium } = require("playwright");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const http = require("node:http");
const { X509Certificate, createHash } = require("node:crypto");
const ROOT = path.resolve(__dirname, "../..");
const TEST = "https://ohkpvuhzvshjglbqyepq.supabase.co";
const CDN = "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.119.0/dist/umd/supabase.min.js";
let phase = "setup";
const passed = [];
const hosted = process.argv.includes("--hosted");
const authOnly = process.argv.includes("--auth-only");
const afterTeacher = process.argv.includes("--after-teacher");
function check(name, condition) {
  if (!condition) throw new Error("Assertion failed");
  passed.push(name);
  console.log("PASS: " + name);
}
(async () => {
  if (!process.env.R8_TEST_A_PASSWORD) throw new Error("Missing runtime credential");
  const servers = [],
    contexts = [];
  let browser;
  const violations = [],
    pageErrors = [],
    assetFailures = [];
  const backendPaths = new Set();
  async function serve(folder) {
    const server = http.createServer((req, res) => {
      const name = new URL(req.url, "http://localhost").pathname;
      const file = path.resolve(folder, "." + (name.endsWith("/") ? name + "index.html" : name));
      if (!file.startsWith(folder + path.sep)) {
        res.writeHead(403).end();
        return;
      }
      if (!fs.existsSync(file)) {
        res.writeHead(404).end();
        return;
      }
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
    servers.push(server);
    return "http://127.0.0.1:" + server.address().port;
  }
  try {
    const pupilOrigin = hosted
      ? "https://monob26.github.io/gcse-history-homework-hub-test/"
      : await serve(path.join(ROOT, "work/r8-pupil"));
    const teacherOrigin = hosted
      ? "https://monob26.github.io/history-teacher-dashboard-test/"
      : await serve(path.join(ROOT, "work/r8-teacher"));
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
    async function context() {
      const c = await browser.newContext({ serviceWorkers: "block" });
      contexts.push(c);
      await c.route("**/*", (route) => {
        const url = new URL(route.request().url());
        if (url.origin === TEST) backendPaths.add(url.pathname);
        if (
          url.origin === TEST ||
          (hosted
            ? [pupilOrigin, teacherOrigin].some((base) => url.href.startsWith(base))
            : [pupilOrigin, teacherOrigin].includes(url.origin)) ||
          url.href === CDN
        )
          return route.continue();
        violations.push(url.hostname);
        return route.abort();
      });
      c.on("page", (p) => {
        p.setDefaultTimeout(15000);
        p.on("pageerror", () => pageErrors.push("exception"));
        p.on("requestfailed", (r) =>
          console.log(
            "Network diagnostic: " +
              new URL(r.url()).hostname +
              " " +
              (r.failure()?.errorText || "failed"),
          ),
        );
        p.on("console", (m) => {
          if (
            m.type() === "error" &&
            !m.text().startsWith("Failed to load resource: the server responded with a status of")
          )
            pageErrors.push("console");
        });
        p.on("response", (r) => {
          if (
            ((hosted
              ? [pupilOrigin, teacherOrigin].some((base) => r.url().startsWith(base))
              : r.url().startsWith("http://127.0.0.1:")) ||
              r.url() === CDN) &&
            r.status() >= 400
          )
            assetFailures.push(true);
        });
      });
      return c;
    }
    const tc = await context(),
      pc = await context();
    const t = await tc.newPage(),
      p = await pc.newPage();
    phase = "teacher sign-in";
    await t.goto(teacherOrigin, { waitUntil: "domcontentloaded" });
    await t.locator("#email").fill("r8-test-teacher-a@example.test");
    await t.locator("#password").fill(process.env.R8_TEST_A_PASSWORD);
    await t.locator("#submitAuth").click();
    await t.locator("#dashboard").waitFor({ state: "visible" });
    // Clear filled credentials immediately; preserve only the in-memory browser session.
    await t.locator("#password").evaluate((e) => {
      e.value = "";
    });
    await t.waitForFunction(() =>
      [...document.querySelectorAll("#results tr td:first-child")].some(
        (e) => Number(e.textContent) >= 100,
      ),
    );
    if (!afterTeacher)
      check(
        "teacher sign-in and allocated class display",
        (await t.locator("#classSelect option").allTextContents()).join("|") ===
          "R8 Fictional Class A",
      );
    if (authOnly) {
      phase = "targeted teacher auth after recovery fix";
      await t.reload();
      await t.locator("#dashboard").waitFor({ state: "visible" });
      await t.locator("#signOut").click();
      await t.locator("#authForm").waitFor({ state: "visible" });
      check("sign-in email remains enabled after sign-out", await t.locator("#email").isEnabled());
      await t.locator("#forgot").click();
      check(
        "recovery request form accepts email and hides password",
        (await t.locator("#email").isEnabled()) && (await t.locator("#passwordGroup").isHidden()),
      );
      await t.locator("#back").click();
      check(
        "back from recovery restores the sign-in controls",
        (await t.locator("#email").isEnabled()) && (await t.locator("#passwordGroup").isVisible()),
      );
      await t.reload();
      await t.locator("#authForm").waitFor({ state: "visible" });
      check(
        "updated teacher sign-out persists after reload",
        await t.locator("#dashboard").isHidden(),
      );
      check(
        "targeted auth stays within test origins with assets loaded",
        violations.length === 0 && assetFailures.length === 0 && pageErrors.length === 0,
      );
      console.log("Targeted teacher auth passed; full recovery email/token flow remains untested.");
      return;
    }
    const rows = await t
      .locator("#results tr")
      .evaluateAll((rows) => rows.map((r) => [...r.cells].map((c) => c.textContent)));
    const fresh = rows.filter((r) => Number(r[0]) >= 100 && r[4] === "Not completed").at(-1);
    if (!fresh) throw new Error("Fresh fictional pupil required");
    const pupilCode = fresh[1],
      register = fresh[0];
    const quiz = await t.locator("#weekSelect").inputValue();
    phase = "unallocated class denial";
    if (!afterTeacher) {
      const isolation = await t.evaluate(async (quiz) => {
        const classesResult = await client.from("history_classes").select("class_name");
        const denied = await client.rpc("get_history_class_results", {
          requested_class: "R8 Fictional Class B",
          requested_quiz: quiz,
        });
        return {
          onlyA:
            !classesResult.error &&
            classesResult.data.length === 1 &&
            classesResult.data[0].class_name === "R8 Fictional Class A",
          denied: !!denied.error && /not allocated/i.test(denied.error.message),
        };
      }, quiz);
      check("RLS and results RPC exclude unallocated Class B", isolation.onlyA && isolation.denied);
    }
    phase = "schema exposure";
    const privateHidden = await t.evaluate(async () => {
      const r = await fetch(
        window.HISTORY_CONFIG.supabaseUrl + "/rest/v1/pupil_code_failures?select=count&limit=0",
        {
          headers: {
            apikey: window.HISTORY_CONFIG.publishableKey,
            "Accept-Profile": "homework_private",
          },
        },
      );
      const d = await r.json();
      return r.status === 406 && d.code === "PGRST106";
    });
    check("private schema rejected by Data API", privateHidden);
    phase = "teacher refresh";
    await t.reload();
    await t.locator("#dashboard").waitFor({ state: "visible" });
    check("teacher session survives reload", true);
    phase = "pupil lookup/start";
    await p.goto(pupilOrigin);
    await p.locator("#code").fill(pupilCode);
    await p.locator("#loginForm button").click();
    await p.locator("#homeContent button").click();
    await p.locator("#startQuiz").click();
    await p.locator("#question").waitFor({ state: "visible" });
    check(
      "pupil lookup and real quiz start through homework_api",
      (await p.locator("#qNumber").innerText()) === "Question 1 of 25",
    );
    async function answer() {
      await p.locator("#options button").filter({ hasText: "Option A" }).click();
      await p.locator("#submitAnswer").click();
      await p.locator("#feedback").waitFor({ state: "visible" });
      assert.match(await p.locator("#feedback").innerText(), /Correct!/);
    }
    await answer();
    await p.locator("#nextQuestion").click();
    await p.waitForFunction(
      () =>
        document.querySelector("#qNumber").textContent === "Question 2 of 25" &&
        !document.querySelector("#question").classList.contains("hidden"),
    );
    if (!hosted) {
      phase = "pupil resume";
      await p.locator("#exitQuiz").click();
      await p.locator("#saveExit").click();
      await p.reload();
      await p.locator("#code").fill(pupilCode);
      await p.locator("#loginForm button").click();
      await p.locator("#homeContent button").click();
      await p.locator("#resumeQuiz").click();
      await p.locator("#question").waitFor({ state: "visible" });
      check(
        "saved answer and current question survive exit/reload/resume",
        (await p.locator("#qNumber").innerText()) === "Question 2 of 25",
      );
      phase = "server deadline";
      // Wait for the actual backend deadline; no browser clock or timer mocking.
      await p.locator("#feedback").waitFor({ state: "visible", timeout: 55000 });
      check(
        "actual question timeout is submitted and marked",
        /Time is up/.test(await p.locator("#feedback").innerText()),
      );
    } else {
      phase = "hosted answer submission";
      await answer();
      check("hosted second answer marked by real backend", true);
    }
    phase = "remaining questions";
    for (let q = 3; q <= 25; q++) {
      await p.locator("#nextQuestion").click();
      await p.waitForFunction(
        (q) =>
          document.querySelector("#qNumber").textContent === `Question ${q} of 25` &&
          !document.querySelector("#question").classList.contains("hidden"),
        q,
      );
      await answer();
    }
    await p.locator("#nextQuestion").click();
    await p.locator("#result").waitFor({ state: "visible" });
    check(
      hosted
        ? "hosted full quiz completion (25/25, passed)"
        : "server marking and full quiz completion (24/25, passed)",
      (await p.locator("#resultScore").innerText()) === (hosted ? "25/25" : "24/25") &&
        (await p.locator("#resultHeading").innerText()) === "Homework Complete!",
    );
    await p.locator("#resultAction").click();
    await p.locator("#home").waitFor({ state: "visible" });
    check(
      "completed homework prevents another attempt",
      await p.locator("#homeContent button").isDisabled(),
    );
    phase = "teacher saved result";
    await t.reload();
    await t.waitForFunction(
      ({ register, expected }) =>
        [...document.querySelectorAll("#results tr")].some(
          (r) =>
            r.cells[0]?.textContent === register &&
            r.cells[3]?.textContent === expected &&
            r.cells[4]?.textContent === "Passed",
        ),
      { register, expected: hosted ? "25/25" : "24/25" },
    );
    check("teacher displays the same persisted pupil result", true);
    phase = "sign-out";
    await t.locator("#signOut").click();
    await t.locator("#dashboard").waitFor({ state: "hidden" });
    await t.reload();
    await t.locator("#authForm").waitFor({ state: "visible" });
    check(
      "sign-out persists after reload and removes dashboard access",
      await t.locator("#dashboard").isHidden(),
    );
    if (hosted) {
      phase = "hosted recovery request target";
      await t.locator("#forgot").click();
      // No account exists for this address: exercise the request without emailing a user.
      await t.locator("#email").fill("r8-no-account-recovery@example.test");
      const recoveryRequest = t.waitForRequest(
        (r) => new URL(r.url()).pathname === "/auth/v1/recover",
      );
      const recoveryResponse = t.waitForResponse(
        (r) => new URL(r.url()).pathname === "/auth/v1/recover",
      );
      await t.locator("#submitAuth").click();
      const request = await recoveryRequest;
      const response = await recoveryResponse;
      check(
        "recovery request targets the published test teacher URL",
        new URL(request.url()).searchParams.get("redirect_to") === teacherOrigin && response.ok(),
      );
      await t.waitForFunction(() =>
        document.querySelector("#authMsg").textContent.includes("If the address belongs"),
      );
      await t.locator("#back").click();
      check("hosted sign-in stays on the test URL", t.url() === teacherOrigin);
    }
    check(
      "all backend traffic confined to isolated project",
      violations.length === 0 &&
        [...backendPaths].some((x) => x.includes("/auth/v1/token")) &&
        [...backendPaths].some((x) => x.endsWith("/complete_pupil_quiz")),
    );
    check("all page and CDN assets load", assetFailures.length === 0);
    // Expected denied API probes can generate browser HTTP console errors. Count separately.
    check("no uncaught browser exceptions", pageErrors.length === 0);
    console.log(
      hosted
        ? "Hosted R8 acceptance completed."
        : "Local R8 acceptance completed; no publication performed.",
    );
  } finally {
    for (const c of contexts) await c.close();
    if (browser) await browser.close();
    for (const s of servers) await new Promise((r) => s.close(r));
  }
})().catch((e) => {
  console.error("Error category: " + (e.name === "TimeoutError" ? "timeout" : "other"));
  // Playwright/assertion errors may include DOM text or filled secrets. Never print them.
  console.error("FAIL: " + phase + " (details suppressed to protect credentials and codes)");
  process.exitCode = 1;
});
