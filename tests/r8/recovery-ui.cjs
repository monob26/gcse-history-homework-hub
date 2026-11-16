// Focused recovery UI regression with a mocked Auth boundary. No real reset token/email.
const { chromium } = require("playwright");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const http = require("node:http");
const ROOT = path.resolve(__dirname, "../..");
(async () => {
  const server = http.createServer((req, res) => {
    const file = path.join(
      ROOT,
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
    for (const scenario of ["success", "expired"]) {
      const page = await browser.newPage();
      const exceptions = [];
      page.on("pageerror", () => exceptions.push(true));
      await page.route("**/*", (r) =>
        new URL(r.request().url()).origin === origin && !r.request().url().includes("/vendor/")
          ? r.continue()
          : r.abort(),
      );
      await page.addInitScript(
        ({ scenario }) => {
          let changed;
          const recoverySession = { user: { email: "fictional-recovery@example.test" } };
          window.recoveryTest = { updateCalls: 0, signOutCalls: 0, correctPassword: false };
          window.supabase = {
            createClient() {
              return {
                auth: {
                  onAuthStateChange(cb) {
                    changed = cb;
                  },
                  async getSession() {
                    changed("PASSWORD_RECOVERY", recoverySession);
                    return { data: { session: recoverySession } };
                  },
                  async updateUser({ password }) {
                    window.recoveryTest.updateCalls++;
                    window.recoveryTest.correctPassword = password === "Fictional-reset-value-only";
                    return {
                      data: {},
                      error:
                        scenario === "expired" ? { message: "Recovery session expired" } : null,
                    };
                  },
                  async signOut() {
                    window.recoveryTest.signOutCalls++;
                    changed("SIGNED_OUT", null);
                    return { error: null };
                  },
                },
                rpc: async () => ({ data: false, error: null }),
              };
            },
          };
        },
        { scenario },
      );
      await page.goto(origin + "/teacher/");
      await page.waitForFunction(
        () => document.querySelector("#authTitle").textContent === "Set a new password",
      );
      await page.locator("#password").fill("Fictional-reset-value-only");
      assert.equal(await page.locator("#authForm").evaluate((e) => e.checkValidity()), true);
      await page.locator("#submitAuth").click();
      // A real link identifies the account. Reset must not require typing another email.
      await page.waitForFunction(
        () => window.recoveryTest.updateCalls === 1,
        {},
        { timeout: 3000 },
      );
      const result = await page.evaluate(() => window.recoveryTest);
      assert.equal(result.correctPassword, true);
      if (scenario === "success") {
        await page.waitForFunction(() =>
          document.querySelector("#authMsg").textContent.includes("Password saved"),
        );
        assert.equal(result.signOutCalls, 1);
        assert.equal(await page.locator("#password").inputValue(), "");
        assert.equal(await page.locator("#email").isEnabled(), true);
      } else {
        await page.waitForFunction(
          () => document.querySelector("#authMsg").textContent === "Recovery session expired",
        );
        assert.equal(result.signOutCalls, 0);
        assert.equal(await page.locator("#submitAuth").isEnabled(), true);
      }
      assert.equal(await page.locator("#dashboard").isHidden(), true);
      assert.equal(exceptions.length, 0);
      console.log(
        "PASS: mocked recovery UI " + scenario + " (not end-to-end token/email acceptance)",
      );
      await page.close();
    }
  } finally {
    await browser.close();
    await new Promise((r) => server.close(r));
  }
})().catch(() => {
  console.error("FAIL: recovery UI regression (details suppressed)");
  process.exitCode = 1;
});
