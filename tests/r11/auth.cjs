// Real local SDK and mocked HTTP errors. No request leaves the test boundary.
const { chromium } = require("playwright");
const fs = require("node:fs"),
  path = require("node:path"),
  http = require("node:http"),
  assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../..");
(async () => {
  const server = http.createServer((req, res) => {
    const f = path.join(
      root,
      new URL(req.url, "http://localhost").pathname.replace(/\/$/, "/index.html"),
    );
    res.setHeader(
      "Content-Type",
      f.endsWith(".js") ? "application/javascript" : f.endsWith(".css") ? "text/css" : "text/html",
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
  try {
    for (const scenario of ["server-wait", "unknown-wait", "email-only"]) {
      const p = await browser.newPage();
      p.setDefaultTimeout(5000);
      let calls = 0;
      await p.clock.install();
      await p.route("**/*", (route) => {
        const u = new URL(route.request().url());
        if (u.pathname.endsWith("/shared/auth-captcha.js"))
          return route.fulfill({
            contentType: "application/javascript",
            body: "window.HISTORY_CAPTCHA = {};",
          });
        if (u.origin === origin) return route.continue();
        assert.ok(
          u.origin === "https://inxsjdogxvqbvxydxmym.supabase.co" &&
            u.pathname.startsWith("/auth/v1/"),
        );
        calls++;
        return route.fulfill({
          status: 429,
          contentType: "application/json",
          headers: {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Expose-Headers": "Retry-After",
            ...(scenario === "server-wait" ? { "Retry-After": "3" } : {}),
          },
          body: JSON.stringify({
            code: 429,
            error_code:
              scenario === "email-only" ? "over_email_send_rate_limit" : "over_request_rate_limit",
            msg: "Fictional limit",
          }),
        });
      });
      await p.goto(origin + "/teacher/");
      await p.locator("#email").fill("fictional@example.test");
      if (scenario === "email-only") await p.locator("#forgot").click();
      else await p.locator("#password").fill("Fictional-value-only");
      await p.locator("#submitAuth").click();
      await p.locator("#authMsg").filter({ hasText: "temporarily limited" }).waitFor();
      assert.equal(calls, 1);
      assert.equal(await p.locator("#submitAuth").isDisabled(), true);
      // Direct duplicate DOM submission must also be refused; a disabled button alone is insufficient.
      await p.locator("#authForm").evaluate((form) => {
        form.dispatchEvent(new Event("submit", { cancelable: true, bubbles: true }));
      });
      assert.equal(calls, 1);
      if (scenario === "server-wait") {
        assert.match(await p.locator("#authMsg").innerText(), /Try again in 3 seconds/);
        await p.clock.runFor(3000);
        assert.equal(await p.locator("#submitAuth").isEnabled(), true);
      } else {
        assert.match(
          await p.locator("#authMsg").innerText(),
          /server did not provide a retry time/,
        );
        if (scenario === "email-only") {
          await p.locator("#back").click();
          assert.equal(await p.locator("#submitAuth").isEnabled(), true);
          await p.locator("#forgot").click();
          assert.equal(await p.locator("#submitAuth").isDisabled(), true);
        } else {
          await p.clock.runFor(59000);
          assert.equal(await p.locator("#submitAuth").isDisabled(), true);
          await p.clock.runFor(1000);
          assert.equal(await p.locator("#submitAuth").isEnabled(), true);
        }
      }
      assert.equal(await p.evaluate(() => retrySeconds("invalid")), null);
      console.log("PASS: R11 " + scenario);
      await p.close();
    }
  } finally {
    await browser.close();
    await new Promise((r) => server.close(r));
  }
})().catch(() => {
  console.error("FAIL: R11 auth backoff (details suppressed)");
  process.exitCode = 1;
});
