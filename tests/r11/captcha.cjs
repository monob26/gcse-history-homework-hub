// Mocked CAPTCHA provider and Auth HTTP boundary; not proof of hosted enforcement.
const { chromium } = require("playwright");
const fs = require("node:fs"),
  path = require("node:path"),
  http = require("node:http"),
  os = require("node:os"),
  assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const root = path.resolve(__dirname, "../..");
(async () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "r11-captcha-"));
  execFileSync("python3", [
    path.join(root, "scripts/prepare-pages.py"),
    "teacher",
    temp,
    "--environment",
    "test",
    "--test-config",
    path.join(root, "docs/r8/test-config.json"),
    "--test-captcha-site-key",
    "fictional-public-site-key",
  ]);
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
    for (const scenario of ["token-lifecycle", "provider-failure"]) {
      const p = await browser.newPage();
      p.setDefaultTimeout(5000);
      let calls = 0;
      const errors = [];
      p.on("pageerror", () => errors.push("exception"));
      await p.route("**/*", (route) => {
        const u = new URL(route.request().url());
        if (u.origin === origin) return route.continue();
        if (u.origin === "https://challenges.cloudflare.com") {
          if (scenario === "provider-failure") return route.abort();
          return route.fulfill({
            contentType: "application/javascript",
            body: 'window.turnstile={ready(){throw new Error("ready must not be called with async loading")},render(element,options){window.providerOptions=options;window.providerResets=0;return "widget";},reset(){window.providerResets++}};',
          });
        }
        assert.equal(u.origin, "https://ohkpvuhzvshjglbqyepq.supabase.co");
        calls++;
        assert.equal(
          route.request().postDataJSON().gotrue_meta_security.captcha_token,
          "fictional-captcha",
        );
        return route.fulfill({
          status: u.pathname.endsWith("/recover") ? 200 : 400,
          contentType: "application/json",
          headers: { "Access-Control-Allow-Origin": "*" },
          body: JSON.stringify(
            u.pathname.endsWith("/recover")
              ? {}
              : { error_code: "invalid_credentials", msg: "Fictional refusal" },
          ),
        });
      });
      await p.goto(origin + "/");
      await p.locator("#email").fill("fictional@example.test");
      await p.locator("#password").fill("Fictional-value-only");
      assert.equal(await p.locator("#submitAuth").isDisabled(), true);
      await p
        .locator("#authForm")
        .evaluate((f) => f.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true })));
      assert.equal(calls, 0);
      if (scenario === "provider-failure") {
        await p.locator("#captchaStatus").filter({ hasText: "could not load" }).waitFor();
        assert.equal(await p.locator("#submitAuth").isDisabled(), true);
      } else {
        await p.waitForFunction(() => !!window.providerOptions);
        await p.evaluate(() => window.providerOptions.callback("fictional-captcha"));
        assert.equal(await p.locator("#submitAuth").isEnabled(), true);
        await p.evaluate(() => window.providerOptions["expired-callback"]());
        assert.equal(await p.locator("#submitAuth").isDisabled(), true);
        await p.evaluate(() => window.providerOptions.callback("fictional-captcha"));
        await p.locator("#submitAuth").click();
        await p.locator("#authMsg").filter({ hasText: "Fictional refusal" }).waitFor();
        assert.equal(calls, 1);
        assert.equal(await p.locator("#submitAuth").isDisabled(), true);
        assert.ok(await p.evaluate(() => window.providerResets > 0));
        await p.locator("#forgot").click();
        assert.equal(await p.locator("#submitAuth").isDisabled(), true);
        await p.evaluate(() => window.providerOptions.callback("fictional-captcha"));
        await p.locator("#submitAuth").click();
        await p.locator("#authMsg").filter({ hasText: "If the address belongs" }).waitFor();
        assert.equal(calls, 2);
        assert.equal(await p.locator("#submitAuth").isDisabled(), true);
      }
      if (scenario === "token-lifecycle") {
        await p.evaluate(() => setMode("reset"));
        assert.equal(await p.locator("#authCaptcha").isHidden(), true);
        assert.equal(await p.locator("#submitAuth").isEnabled(), true);
        await p.evaluate(() => setMode("signin"));
        assert.equal(await p.locator("#submitAuth").isDisabled(), true);
        assert.equal(calls, 2);
      }
      assert.deepEqual(errors, []);
      console.log("PASS: R11 CAPTCHA " + scenario + " (mocked provider, no hosted validation)");
      await p.close();
    }
  } finally {
    await browser.close();
    await new Promise((r) => server.close(r));
    fs.rmSync(temp, { recursive: true, force: true });
  }
})().catch(() => {
  console.error("FAIL: R11 CAPTCHA integration (details suppressed)");
  process.exitCode = 1;
});
