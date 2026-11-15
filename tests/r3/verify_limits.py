"""Real local HTTP tests for persistent failure limits, gateway metadata and recovery."""
import importlib.util
import json
import os
from pathlib import Path
import statistics
import subprocess
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('adversarial', ROOT / 'tests/adversarial/run.py')
adv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adv)


def main():
    r = adv.Runner('r3-limiter-verification')
    r.prepare()
    requests = 0
    # These are reserved documentation addresses. Kong must append its observed peer
    # instead of letting a caller choose a different bucket using a leading XFF value.
    for fake in ['198.51.100.17', '203.0.113.23']:
        req = urllib.request.Request(r.url + '/rest/v1/rpc/get_current_pupil_homework', method='POST',
            headers={'apikey': r.public, 'Authorization': 'Bearer ' + r.public,
                     'Content-Type': 'application/json', 'Content-Profile': 'homework_api',
                     'Accept-Profile': 'homework_api', 'X-Forwarded-For': fake},
            data=json.dumps({'entered_code': 'R3-WRONG-FORWARDED'}).encode())
        with urllib.request.urlopen(req, timeout=20) as response:
            assert response.status == 200
            response.read()
        requests += 1
    counters = adv.sql("SELECT json_build_object('buckets',count(*),'failures',max(failures)) FROM homework_private.pupil_code_failures;", True)
    assert counters == {'buckets': 1, 'failures': 2}, 'Forged leading forwarded addresses changed the local gateway bucket'
    first_block = None
    for n in range(3, 21):
        if n % 2:
            status, _ = r.rpc('start_pupil_quiz', {'entered_code': 'R3-WRONG-' + str(n), 'entered_quiz_id': r.quiz})
        else:
            status, _ = r.rpc('get_current_pupil_homework', {'entered_code': 'R3-WRONG-' + str(n)})
        requests += 1
        if status == 429:
            first_block = first_block or n
        else:
            assert status in (200, 400), 'Unexpected failed-code response'
    assert first_block == 20, 'Mixed lookup/start failures did not persist into the twentieth-request block'
    expiry = lambda: adv.sql("SELECT to_json(max(blocked_until)) FROM homework_private.pupil_code_failures;", True)
    original_expiry = expiry()
    status, body = r.rpc('get_current_pupil_homework', {'entered_code': r.people['B']})
    requests += 1
    assert status == 429 and body[0]['valid_code'] is False, 'A second pupil sharing the network did not share the bounded block'
    retry = r.last_retry_after
    assert 0 < retry <= 10
    assert expiry() == original_expiry, 'Blocked requests extended the cooldown'
    time.sleep(retry + 0.25)
    status, body = r.rpc('get_current_pupil_homework', {'entered_code': r.people['B']})
    requests += 1
    assert status == 200 and body[0]['valid_code'] is True, 'Honest use did not recover'
    shape = sorted(body[0])
    valid_times, invalid_times = [], []
    for n in range(5):
        for valid in [True, False]:
            began = time.monotonic()
            status, row = r.rpc('get_current_pupil_homework', {'entered_code': r.people['B'] if valid else 'R3-TIMING-' + str(n)})
            elapsed = time.monotonic() - began
            requests += 1
            assert status == 200 and sorted(row[0]) == shape
            (valid_times if valid else invalid_times).append(elapsed)
    a, b = statistics.median(valid_times), statistics.median(invalid_times)
    assert min(a, b) >= 0.045 and abs(a - b) <= 0.05, 'Timing floor or practical valid/invalid timing parity failed'
    # Five failures remain. Trigger the same shared cooldown for the real pupil page.
    for n in range(15):
        status, _ = r.rpc('get_current_pupil_homework', {'entered_code': 'R3-UI-' + str(n)})
        requests += 1
    assert status == 429
    js = r'''
const {chromium}=require('playwright');const fs=require('node:fs'),http=require('node:http'),assert=require('node:assert/strict');
(async()=>{
 const x=JSON.parse(fs.readFileSync(0,'utf8'));
 let html=fs.readFileSync(x.root+'/index.html','utf8').replaceAll('https://inxsjdogxvqbvxydxmym.supabase.co',x.api);
 html=html.replace(/const SUPABASE_KEY='[^']+';/,'const SUPABASE_KEY='+JSON.stringify(x.key)+';');
 const server=http.createServer((req,res)=>{res.setHeader('Content-Type','text/html');res.end(html)});
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));server.unref();
 const browser=await chromium.launch({headless:true,executablePath:fs.existsSync('/usr/bin/chromium')?'/usr/bin/chromium':undefined});
 try{
  const context=await browser.newContext();await context.route('**/*',r=>new URL(r.request().url()).hostname==='127.0.0.1'?r.continue():r.abort());
  const page=await context.newPage();await page.goto('http://127.0.0.1:'+server.address().port+'/');
  await page.locator('#code').fill(x.code);await page.locator('#loginForm button').click();
  await page.waitForFunction(()=>document.getElementById('loginError').textContent.includes('Too many code attempts'));
  assert(await page.locator('#login').isVisible());assert(await page.locator('#offline').isHidden());
  await page.waitForTimeout(10500);
  await page.locator('#loginForm button').click();await page.locator('#home:not(.hidden)').waitFor();
  console.log(JSON.stringify({plainCooldownMessage:true,recovered:true}));
 }finally{await browser.close();await new Promise(resolve=>server.close(resolve))}
})().catch(()=>{console.error('Local cooldown browser test failed; credential-bearing details withheld');process.exitCode=1});
'''
    p = subprocess.run(['node', '-e', js], input=json.dumps({'root': str(ROOT), 'api': r.url, 'key': r.public, 'code': r.people['B']}), capture_output=True, text=True)
    assert p.returncode == 0, 'The local pupil cooldown/recovery browser test failed'
    browser = json.loads(p.stdout)
    assert all(browser.values())
    report = {'target': 'local fictional Supabase only', 'result': 'pass',
              'forged_leading_xff_did_not_change_local_bucket': True,
              'mixed_get_and_start_first_block': first_block,
              'failed_start_counters_survive_http_400': True,
              'shared_network_effect': 'A known valid pupil sharing the address is also blocked for at most 10 seconds; active quiz RPCs are unaffected',
              'blocked_requests_do_not_extend_cooldown': True, 'honest_use_recovers': True,
              'same_valid_invalid_fields': True,
              'valid_median_ms': round(a * 1000, 1), 'invalid_median_ms': round(b * 1000, 1),
              'pupil_browser': browser, 'driver_http_requests': requests,
              'production_header_trust_verified': False,
              'production_note': 'Hosted Cloudflare client-IP header trust and end-to-end enforcement still require approved verification; local proof is not a hosted pass'}
    (ROOT / 'docs/r3/local-limiter.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PASS: persistent mixed-endpoint limit, local XFF handling, shared-network recovery, timing/shape and pupil browser message', flush=True)


if __name__ == '__main__':
    main()
