// R1 acceptance smoke test: actual exported backend, fictional local data, unchanged page sources.
// No hosted requests; credentials exist only in memory. Run after a fresh `db reset --local`.
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const { randomBytes } = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const { chromium } = require('playwright');

const root = path.resolve(__dirname, '../..');
const cli = process.env.SUPABASE_CLI || 'supabase';
const teacherRoot = process.env.TEACHER_REPO || path.resolve(root, '../history-teacher-dashboard');
const libraryPath = process.env.SUPABASE_JS_TEST_BUNDLE;
assert(libraryPath, 'Set SUPABASE_JS_TEST_BUNDLE to a local copy of the teacher page CDN script');
const env = { ...process.env, DOCKER_HOST: 'unix:///var/run/docker.sock' };
const local = JSON.parse(execFileSync(cli, ['status', '--workdir', root, '--output', 'json'], { env, stdio: ['ignore', 'pipe', 'pipe'] }));
const api = local.API_URL;
assert.equal(new URL(api).hostname, '127.0.0.1', 'Refuse any hosted backend');
const publicKey = local.ANON_KEY;
assert(publicKey, 'Local anonymous API key missing');
const password = randomBytes(30).toString('base64url');
const email = `r1-teacher-${randomBytes(6).toString('hex')}@example.test`;

async function main() {
  const signup = await fetch(api + '/auth/v1/signup', {
    method: 'POST', headers: { apikey: publicKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  assert(signup.ok, 'Local fictional teacher signup failed');
  const account = await signup.json();
  const id = account.user?.id || account.id;
  assert.match(id, /^[0-9a-f-]{36}$/);
  const setup = `INSERT INTO public.history_teachers(user_id) VALUES ('${id}');
    INSERT INTO public.history_teacher_classes(user_id,class_id)
    VALUES ('${id}','10000000-0000-4000-8000-000000000001');`;
  execFileSync('docker', ['--host=unix:///var/run/docker.sock', 'exec', '-i',
    'supabase_db_gcse-history-homework-hub', 'psql', '-U', 'postgres', '-d', 'postgres',
    '-X', '-v', 'ON_ERROR_STOP=1'], { input: setup, stdio: ['pipe', 'pipe', 'pipe'] });

  function localPage(file) {
    let source = fs.readFileSync(file, 'utf8');
    assert(source.includes('https://inxsjdogxvqbvxydxmym.supabase.co'));
    source = source.replaceAll('https://inxsjdogxvqbvxydxmym.supabase.co', api);
    source = source.replace(/const SUPABASE_(KEY|PUBLISHABLE_KEY)='[^']+';/,
      (_, suffix) => `const SUPABASE_${suffix}=${JSON.stringify(publicKey)};`);
    source = source.replace('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js', '/supabase-test.js');
    return source;
  }
  const server = http.createServer((req, res) => {
    if (req.url === '/supabase-test.js') {
      res.setHeader('Content-Type', 'application/javascript');
      res.end(fs.readFileSync(libraryPath));
    } else if (req.url === '/pupil/' || req.url === '/teacher/') {
      res.setHeader('Content-Type', 'text/html');
      res.end(localPage(req.url === '/pupil/' ? path.join(root, 'index.html') : path.join(teacherRoot, 'index.html')));
    } else { res.statusCode = 404; res.end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  server.unref();
  const base = `http://127.0.0.1:${server.address().port}`;
  const executablePath = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ||
    (fs.existsSync('/usr/bin/chromium') ? '/usr/bin/chromium' : undefined);
  const browser = await chromium.launch({ headless: true, executablePath });
  try {
    const context = await browser.newContext();
    const external = [];
    await context.route('**/*', route => {
      const u = new URL(route.request().url());
      if (u.hostname !== '127.0.0.1') { external.push(u.hostname); return route.abort(); }
      return route.continue();
    });
    const pupil = await context.newPage();
    await pupil.goto(base + '/pupil/');
    await pupil.locator('#code').fill('TESTA-01');
    await pupil.locator('#loginForm button').click();
    await pupil.locator('#home:not(.hidden)').waitFor();
    assert.match(await pupil.locator('#homeContent').innerText(), /Fictional R1 Practice Quiz/);
    console.log('PASS: pupil page loads fictional homework through the rebuilt backend');
    await pupil.locator('#homeContent button').click();
    await pupil.locator('#startQuiz').click();
    for (let n = 1; n <= 25; n++) {
      await pupil.locator('#question:not(.hidden)').waitFor();
      await pupil.waitForFunction(n => document.getElementById('qNumber').textContent === `Question ${n} of 25`, n);
      await pupil.getByRole('button', { name: 'Option A', exact: true }).click();
      await pupil.locator('#submitAnswer').click();
      await pupil.locator('#nextQuestion:not(.hidden)').waitFor();
      assert.match(await pupil.locator('#feedback').innerText(), /Correct!/);
      await pupil.locator('#nextQuestion').click();
    }
    await pupil.locator('#result:not(.hidden)').waitFor();
    assert.equal(await pupil.locator('#resultScore').innerText(), '25/25');
    assert.equal(await pupil.locator('#resultHeading').innerText(), 'Homework Complete!');
    console.log('PASS: all five pupil RPCs serve a complete 25-question quiz and save the result');
    const teacher = await context.newPage();
    await teacher.goto(base + '/teacher/');
    await teacher.locator('#email').fill(email);
    await teacher.locator('#password').fill(password);
    await teacher.locator('#submitAuth').click();
    await teacher.locator('#dashboard:not([hidden])').waitFor();
    await teacher.waitForFunction(() => document.getElementById('total').textContent === '2');
    assert.equal(await teacher.locator('#completed').innerText(), '1');
    assert.equal(await teacher.locator('#passed').innerText(), '1');
    assert.equal(await teacher.locator('#missing').innerText(), '1');
    assert.match(await teacher.locator('#results').innerText(), /TESTA-01/);
    assert.match(await teacher.locator('#results').innerText(), /TESTA-02/);
    assert.doesNotMatch(await teacher.locator('#results').innerText(), /TESTB-01/);
    console.log('PASS: teacher Auth, both teacher RPCs and three table reads display the saved result and unattempted pupil');
    assert.equal(external.length, 0, 'A page attempted to contact a non-local host');
    console.log('PASS: both pages used loopback only; hosted Supabase and websites untouched');
  } finally { await browser.close(); await new Promise(resolve => server.close(resolve)); }
}

main().catch(error => {
  // Avoid dumping HTTP bodies, browser state or credential-bearing command results.
  console.error('FAIL:', String(error.message).replaceAll(password, '[REDACTED]').replaceAll(publicKey, '[REDACTED]'));
  process.exitCode = 1;
});
