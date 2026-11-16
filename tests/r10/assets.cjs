// Loads the real pinned library from local disk; blocks every external request.
const { chromium } = require("playwright");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const http = require("node:http");
const crypto = require("node:crypto");
const root = path.resolve(__dirname, "../..");
(async () => {
  const html = fs.readFileSync(path.join(root, "teacher/index.html"), "utf8");
  const library = fs.readFileSync(path.join(root, "teacher/vendor/supabase-2.119.0.min.js"));
  const integrity = "sha384-" + crypto.createHash("sha384").update(library).digest("base64");
  assert.ok(html.includes('integrity="' + integrity + '"'));
  assert.ok(html.includes('src="./vendor/supabase-2.119.0.min.js"'));
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
    const page = await browser.newPage();
    const external = [],
      errors = [];
    page.on("pageerror", () => errors.push("exception"));
    await page.route("**/*", (route) => {
      if (new URL(route.request().url()).origin === origin) return route.continue();
      external.push(true);
      return route.abort();
    });
    await page.addInitScript(() => {
      window.policyFailures = [];
      document.addEventListener("securitypolicyviolation", (e) =>
        window.policyFailures.push(e.effectiveDirective),
      );
    });
    await page.goto(origin + "/teacher/");
    await page.waitForFunction(() => !!window.supabase?.createClient && !!client);
    assert.equal(await page.locator("#email").isEnabled(), true);
    assert.deepEqual(await page.evaluate(() => window.policyFailures), []);
    assert.deepEqual(errors, []);
    await page.evaluate(() => {
      const s = document.createElement("script");
      s.textContent = "window.untrustedInlineRan=true";
      document.body.append(s);
    });
    await page.waitForFunction(() => window.policyFailures.includes("script-src-elem"));
    assert.equal(await page.evaluate(() => window.untrustedInlineRan === true), false);
    await page.evaluate(async () => {
      try {
        await fetch("https://unlisted.invalid/test");
      } catch {}
    });
    await page.waitForFunction(() => window.policyFailures.includes("connect-src"));
    assert.deepEqual(external, []);
    console.log(
      "PASS: R10 local pinned library loads with SRI; CSP blocks inline scripts and off-project connections",
    );
  } finally {
    await browser.close();
    await new Promise((r) => server.close(r));
  }
})().catch(() => {
  console.error("FAIL: R10 pinned assets/CSP (details suppressed)");
  process.exitCode = 1;
});
