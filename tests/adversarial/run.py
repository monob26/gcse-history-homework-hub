"""Repeatable R2 and T1-T14 runner. Local fictional fixtures only; no credentials on disk.

Fixture preparation is separate from the test phase. No fixes occur during a run.
Stop the run immediately on unexpected data disclosure. Hosted execution is deliberately
not enabled: the owner's approval and safe test-account setup are prerequisites.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import secrets
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[2]
CLI = os.environ.get('SUPABASE_CLI', 'supabase')
CONTAINER = 'supabase_db_gcse-history-homework-hub'
PUPIL_API = {'get_current_pupil_homework', 'start_pupil_quiz', 'open_pupil_question',
             'submit_pupil_answer', 'complete_pupil_quiz'}
ZERO = '00000000-0000-4000-8000-000000000000'


def sql(query, result=False):
    p = subprocess.run(['docker', '--host=unix:///var/run/docker.sock', 'exec', '-i',
                        CONTAINER, 'psql', '-U', 'postgres', '-d', 'postgres', '-X',
                        '-v', 'ON_ERROR_STOP=1', '-A', '-t'],
                       input=query, capture_output=True, text=True)
    if p.returncode:
        raise RuntimeError('Local fixture/inspection SQL failed; response withheld')
    return json.loads(p.stdout) if result else None


class Disclosure(Exception):
    pass


class Runner:
    def __init__(self, phase):
        self.phase = phase
        env = {**os.environ, 'DOCKER_HOST': 'unix:///var/run/docker.sock'}
        p = subprocess.run([CLI, 'status', '--workdir', str(ROOT), '--output', 'json'],
                           capture_output=True, text=True, env=env, check=True)
        self.local = json.loads(p.stdout)
        self.url = self.local['API_URL']
        assert urllib.parse.urlsplit(self.url).hostname == '127.0.0.1', 'Refuse hosted execution'
        self.public = self.local['PUBLISHABLE_KEY']
        self.admin = self.local['SECRET_KEY']
        self.results = {f'T{n}': {'result': 'not run', 'evidence': 'Not reached'} for n in range(1, 15)}
        self.extra = {}
        self.requests = 0
        self.test_requests = 0
        self.people = {}
        self.accounts = {}
        self.ids = {}

    def http(self, method, path, data=None, bearer=None, schema=None, admin=False):
        self.requests += 1
        self.test_requests += 1
        headers = {'apikey': self.admin if admin else self.public, 'Content-Type': 'application/json'}
        # ADVERSARIAL.md's public bearer-key shape is used for anonymous RPC/table probes.
        headers['Authorization'] = 'Bearer ' + (bearer or (self.admin if admin else self.public))
        if schema:
            headers.update({'Accept-Profile': schema, 'Content-Profile': schema})
        req = urllib.request.Request(self.url + path, headers=headers, method=method,
                                     data=None if data is None else json.dumps(data).encode())
        try:
            with urllib.request.urlopen(req, timeout=20) as response:
                status, body = response.status, response.read()
        except urllib.error.HTTPError as error:
            status, body = error.code, error.read()
        try:
            body = json.loads(body)
        except (ValueError, UnicodeError):
            body = None
        return status, body

    def rpc(self, name, params, schema='homework_api', bearer=None):
        return self.http('POST', '/rest/v1/rpc/' + name, params, bearer, schema)

    def prepare(self):
        suffix = secrets.token_hex(4)
        self.quiz = str(uuid.uuid4())
        self.classes = {k: str(uuid.uuid4()) for k in ['A', 'B']}
        self.class_names = {k: f'R2 Fictional {k} {suffix}' for k in ['A', 'B']}
        for who in ['A', 'B', 'unallocated']:
            email = f'r2-{who.lower()}-{suffix}@example.test'
            password = secrets.token_urlsafe(30)
            status, body = self.http('POST', '/auth/v1/admin/users',
                                     {'email': email, 'password': password, 'email_confirm': True}, admin=True)
            assert status in (200, 201), 'Local fictional teacher provisioning failed'
            self.accounts[who] = (email, password, body['id'])
        statements = []
        for who, (_, _, user_id) in self.accounts.items():
            uuid.UUID(user_id)
            statements.append(f"INSERT INTO public.history_teachers(user_id) VALUES ('{user_id}');")
        for who, class_id in self.classes.items():
            statements += [f"INSERT INTO public.history_classes(id,class_name,year_group) VALUES ('{class_id}','{self.class_names[who]}',10);",
                           f"INSERT INTO public.history_teacher_classes(user_id,class_id) VALUES ('{self.accounts[who][2]}','{class_id}');"]
        prefix = ''.join(secrets.choice('ABCDEFGHJKLMNPQRSTUVWXYZ23456789') for _ in range(5))
        for n, key in enumerate(['T5', 'T6', 'T7', 'other', 'T8', 'T9', 'T10', 'T11', 'T12', 'B'], 1):
            pupil_id = str(uuid.uuid4())
            code = prefix + '-' + str(n).zfill(2)
            self.people[key] = code
            self.ids[key] = pupil_id
            group = 'B' if key == 'B' else 'A'
            statements.append(f"INSERT INTO public.history_pupils(id,pupil_code,class_id) VALUES ('{pupil_id}','{code}','{self.classes[group]}');")
        statements += [f"""INSERT INTO public.history_quizzes(id,quiz_title,year_group,topic,week_number,total_questions,pass_mark,is_published,created_at)
            VALUES ('{self.quiz}','R2 Fictional Quiz',10,'Fictional security fixture',1,25,20,true,clock_timestamp());""",
            f"""INSERT INTO public.history_questions(quiz_id,question_number,question_type,question_text,answer_options,correct_answer,explanation,time_allowed_seconds)
            SELECT '{self.quiz}',n,'multiple_choice','Fictional question '||n,'[\"A\",\"B\",\"C\",\"D\"]'::jsonb,'0'::jsonb,'Fictional explanation',45 FROM generate_series(1,25)n;"""]
        sql('\n'.join(statements))
        self.tables = sql("SELECT coalesce(json_agg(json_build_object('schema',n.nspname,'name',c.relname)), '[]'::json) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','homework_api') AND c.relkind IN ('r','p');", True)
        self.functions = json.loads((ROOT / 'supabase/schema-snapshot.json').read_text())['functions']
        # T12 starts with an existing unfinished attempt, as the test requires.
        # This occurs during fixture preparation, not while the test is running.
        self.start('T12')

    def login(self, who):
        email, password, _ = self.accounts[who]
        status, body = self.http('POST', '/auth/v1/token?grant_type=password', {'email': email, 'password': password})
        assert status == 200, 'Fictional teacher sign-in failed'
        return body['access_token']

    def tables_empty(self, bearer=None, filters=None):
        for table in self.tables:
            query = '/rest/v1/' + table['name'] + '?select=*' + (filters or '')
            status, body = self.http('GET', query, bearer=bearer, schema=table['schema'])
            if status == 200 and body:
                raise Disclosure('A table returned rows to a caller who must see none; response withheld')
            assert (status == 200 and body == []) or status in (401, 403, 404), 'Unexpected table response'

    def T1(self):
        self.tables_empty()
        return f'{len(self.tables)} table requests: no rows; no correct answers returned'

    def T2(self, bearer=None):
        tested = 0
        for f in sorted(self.functions, key=lambda f: (f['schema'], f['name'])):
            if f['schema'] == 'homework_api' and f['name'] in PUPIL_API:
                continue
            params = {}
            for arg in filter(None, f['identity'].split(',')):
                name, typ = arg.strip().split(' ', 1)
                params[name] = self.people['T6'] if name in ('entered_code', 'entered_pupil_code') else self.class_names['B'] if name == 'requested_class' else self.quiz if name in ('requested_quiz', 'entered_quiz_id') else ZERO if typ == 'uuid' else [] if typ == 'jsonb' else 0
            status, body = self.rpc(f['name'], params, f['schema'], bearer)
            tested += 1
            if 200 <= status < 300 and body not in (None, [], False):
                raise Disclosure('An unused/teacher function returned data to an unauthorised caller; response withheld')
            assert status in (401, 403, 404) or (f['name'] == 'is_history_teacher' and body in (False, [], None)), 'Unused function remains callable'
        return f'{tested} teacher/unused RPC probes refused (false teacher predicate is a refusal)'

    def T3(self):
        status, body = self.http('POST', '/auth/v1/signup',
                                 {'email': 'r2-outsider-' + secrets.token_hex(5) + '@example.test', 'password': secrets.token_urlsafe(30)})
        if 200 <= status < 300:
            token = body.get('access_token')
            if not token:
                return False, 'Signup accepted; no immediately usable session to repeat T1/T2'
            self.tables_empty(token)
            self.T2(token)
            return False, 'Signup accepted; signed-in T1/T2 repeated without disclosure'
        assert status in (400, 403, 422), 'Unexpected signup response'
        assert isinstance(body, dict) and body.get('error_code', body.get('code')) == 'signup_disabled', 'Signup was refused for a reason other than disabled signup'
        return 'Signup refused explicitly with signup_disabled'

    def T4(self):
        token = self.login('A')
        for name, field, value in [('history_classes', 'id', self.classes['B']), ('history_pupils', 'class_id', self.classes['B'])]:
            status, body = self.http('GET', '/rest/v1/' + name + '?select=*&' + field + '=eq.' + value, bearer=token, schema='public')
            if status == 200 and body:
                raise Disclosure('Teacher A read teacher B data; response withheld')
            assert (status == 200 and body == []) or status in (401, 403), 'Cross-class table access not refused'
        status, body = self.rpc('get_history_class_results', {'requested_class': self.class_names['B'], 'requested_quiz': self.quiz}, 'public', token)
        if status == 200 and body:
            raise Disclosure('Teacher A obtained teacher B results; response withheld')
        assert status >= 400 or body in (None, []), 'Cross-class RPC not refused'
        return 'Teacher A cannot read B classes, pupils or class results'

    def unallocated(self):
        token = self.login('unallocated')
        for table in ['history_classes', 'history_pupils', 'history_attempts', 'history_quizzes']:
            status, body = self.http('GET', '/rest/v1/' + table + '?select=*', bearer=token, schema='public')
            if status == 200 and body:
                raise Disclosure('Unallocated teacher read class/pupil/result data; response withheld')
            assert (status == 200 and body == []) or status in (401, 403)
        for class_name in self.class_names.values():
            status, body = self.rpc('get_history_class_results', {'requested_class': class_name, 'requested_quiz': self.quiz}, 'public', token)
            if status == 200 and body:
                raise Disclosure('Unallocated teacher obtained results; response withheld')
            assert status >= 400 or body in (None, [])
        return 'Unallocated approved teacher sees no classes, pupils, quizzes, attempts or class results'

    def pupil_functions(self):
        for f in self.functions:
            if f['schema'] != 'homework_api' or f['name'] not in PUPIL_API:
                continue
            params = {arg.strip().split(' ', 1)[0]: ZERO for arg in f['identity'].split(',')}
            if 'entered_code' in params:
                params['entered_code'] = 'R2-INVALID'
            if 'entered_answer' in params:
                params['entered_answer'] = None
            status, body = self.rpc(f['name'], params)
            assert status >= 400 or f['name'] == 'get_current_pupil_homework', 'Invalid pupil session accepted'
        return 'All five used pupil RPCs requested anonymously with invalid credentials'

    def start(self, key):
        status, body = self.rpc('start_pupil_quiz', {'entered_code': self.people[key], 'entered_quiz_id': self.quiz})
        assert status == 200 and body, 'Fictional attempt start failed'
        return body[0]

    def params(self, attempt):
        return {'entered_attempt_id': attempt['attempt_id'], 'entered_attempt_token': attempt['attempt_token']}

    def open(self, attempt):
        status, body = self.rpc('open_pupil_question', self.params(attempt))
        assert status == 200 and body, 'Open failed'
        return body[0]

    def answer(self, attempt, value):
        return self.rpc('submit_pupil_answer', {**self.params(attempt), 'entered_answer': value})

    def T5(self):
        blocked = None
        for n in range(50):
            status, body = self.rpc('get_current_pupil_homework', {'entered_code': 'WRONG-' + str(n)})
            if status == 429 or (status >= 400 and isinstance(body, dict) and any(w in body.get('message', '').lower() for w in ['rate', 'limit', 'many'])):
                blocked = n + 1
                break
        self.rpc('get_current_pupil_homework', {'entered_code': self.people['T5']})
        return False, 'No throttle before guess 50' if blocked is None else f'Blocked at {blocked}; recovery interval/shared-network clearance still needs verification'

    def T6(self):
        code = self.people['T6']
        prefix, number = code.split('-')
        neighbour = prefix + '-' + str(int(number) + 1).zfill(2)
        status, body = self.rpc('get_current_pupil_homework', {'entered_code': neighbour})
        valid = status == 200 and body and body[0].get('valid_code') is True
        if valid:
            raise Disclosure('A neighbouring fictional pupil code was derived and accepted; response withheld')
        return 'Neighbouring code not accepted; code-generation independence also requires an R3 review'

    def T7(self):
        attempt, other = self.start('T7'), self.start('other')
        errors = []
        for name in ['open_pupil_question', 'submit_pupil_answer']:
            for variant in [ZERO, None, other['attempt_token']]:
                params = self.params(attempt)
                if variant is None:
                    params.pop('entered_attempt_token')
                else:
                    params['entered_attempt_token'] = variant
                if name == 'submit_pupil_answer': params['entered_answer'] = 0
                status, body = self.rpc(name, params)
                if status < 400:
                    raise Disclosure('Invalid/missing/other attempt token was accepted; response withheld')
                errors.append((status, body.get('message') if isinstance(body, dict) else None))
        return (len(set(errors)) == 1, f'All six invalid/missing/other-token requests refused; {len(set(errors))} distinct error shapes/messages')

    def T8(self):
        attempt = self.start('T8')
        question = self.open(attempt)
        # This is the required real wait, not a database timestamp alteration.
        time.sleep(question['time_allowed_seconds'] + 1)
        status, body = self.answer(attempt, question['answer_options'].index('A'))
        assert status == 200 and body[0]['answer_correct'] is False, 'Late correct answer credited'
        return 'Correct answer submitted one second after the displayed server deadline was marked wrong'

    def T9(self):
        attempt = self.start('T9')
        q = self.open(attempt)
        status, body = self.answer(attempt, q['answer_options'].index('B'))
        assert status == 200 and body[0]['answer_correct'] is False
        status2, _ = self.answer(attempt, body[0]['correct_option'])
        stored = sql(f"SELECT json_build_object('rows',count(*),'correct',bool_or(is_correct)) FROM public.history_answers WHERE attempt_id='{attempt['attempt_id']}';", True)
        ok = status2 >= 400 and stored == {'rows': 1, 'correct': False}
        return ok, 'Second submission refused and the single original wrong answer stands' if ok else 'Second submit changed or duplicated the original answer'

    def T10(self):
        attempt = self.start('T10')
        started_at = lambda: sql(f"SELECT to_json(question_started_at) FROM public.history_attempts WHERE id='{attempt['attempt_id']}';", True)
        q1 = self.open(attempt)
        initial_start = started_at()
        q2 = self.open(attempt)
        repeated_ok = q1['question_number'] == q2['question_number'] and started_at() == initial_start
        for _ in range(3):
            q = self.open(attempt)
            assert self.answer(attempt, q['answer_options'].index('A'))[0] == 200
        early_status, _ = self.rpc('complete_pupil_quiz', self.params(attempt))
        self.open(attempt)
        before_takeover = started_at()
        takeover = self.start('T10')
        old_status, _ = self.rpc('open_pupil_question', self.params(attempt))
        new_q = self.open(takeover)
        takeover_preserves_timer = started_at() == before_takeover
        # Also exercise two literal browser tabs. Credentials go over stdin only.
        js = r'''
const {chromium}=require('playwright');
const fs=require('node:fs');
(async()=>{
 const x=JSON.parse(fs.readFileSync(0,'utf8'));
 const browser=await chromium.launch({headless:true,executablePath:fs.existsSync('/usr/bin/chromium')?'/usr/bin/chromium':undefined});
 try {
  const context=await browser.newContext();
  await context.route('**/*',r=>new URL(r.request().url()).hostname==='127.0.0.1'?r.continue():r.abort());
  const one=await context.newPage(),two=await context.newPage();
  await one.goto(x.url+'/auth/v1/health'); await two.goto(x.url+'/auth/v1/health');
  const call=async(page,name,params)=>page.evaluate(async({url,key,name,params})=>{
   const r=await fetch(url+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:key,Authorization:'Bearer '+key,'Content-Type':'application/json','Content-Profile':'homework_api','Accept-Profile':'homework_api'},body:JSON.stringify(params)});
   return {status:r.status,body:await r.json()};
  },{url:x.url,key:x.key,name,params});
  const newer=await call(two,'start_pupil_quiz',{entered_code:x.code,entered_quiz_id:x.quiz});
  const old=await call(one,'open_pupil_question',x.old);
  const n=newer.body[0];
  const fresh=await call(two,'open_pupil_question',{entered_attempt_id:n.attempt_id,entered_attempt_token:n.attempt_token});
  console.log(JSON.stringify({oldRefused:old.status>=400,newWorks:fresh.status===200&&fresh.body[0].question_number===4}));
 }finally{await browser.close()}
})().catch(()=>{console.error('Two-tab verification failed; credential-bearing details withheld');process.exitCode=1});
'''
        p = subprocess.run(['node', '-e', js], input=json.dumps({'url': self.url, 'key': self.public,
                           'code': self.people['T10'], 'quiz': self.quiz, 'old': self.params(takeover)}),
                           capture_output=True, text=True)
        assert p.returncode == 0, 'Two-browser-tab check could not execute'
        self.requests += 6  # two health-page navigations and four RPC requests
        self.test_requests += 6
        tabs = json.loads(p.stdout)
        browser_takeover_preserves_timer = started_at() == before_takeover
        ok = repeated_ok and early_status >= 400 and old_status >= 400 and new_q['question_number'] == 4 and all(tabs.values()) and takeover_preserves_timer and browser_takeover_preserves_timer
        return ok, ('Repeated open and two-tab takeover preserve the original question deadline; early finish refused' if ok else 'Takeover restarted the current question timer or another skip/finish/session check failed')

    def T11(self):
        attempt = self.start('T11')
        self.open(attempt)
        probes = [('submit_pupil_answer', {**self.params(attempt), 'entered_answer': value}) for value in [99, -1, 'text', 'X' * 10000]]
        probes += [('get_current_pupil_homework', {'entered_code': 'X' * 10000}), ('open_pupil_question', {'entered_attempt_id': 'not-an-id', 'entered_attempt_token': ZERO})]
        bad = 0
        for name, params in probes:
            status, body = self.rpc(name, params)
            message = body.get('message', '') if isinstance(body, dict) else ''
            entire = json.dumps(body).lower()
            if any(word in entire for word in ['history_', 'column name', 'select ', 'insert into ', 'update public.', 'sql statement']):
                raise Disclosure('Malformed input exposed database identifiers or SQL; response withheld')
            plain = status >= 400 and len(message) <= 200 and not any(word in entire for word in ['history_', 'column', 'sql', 'uuid', 'integer'])
            bad += not plain
        return bad == 0, f'{len(probes) - bad}/{len(probes)} malformed inputs returned short plain refusal'

    def T12(self):
        pid = self.ids['T12']
        counts = lambda: sql(f"SELECT json_build_object('rows',(SELECT count(*) FROM public.history_attempts WHERE pupil_id='{pid}'),'attempts_taken',(SELECT attempts_taken FROM homework_api.get_current_pupil_homework('{self.people['T12']}')));", True)
        before = counts()
        ids = set()
        for _ in range(200):
            attempt = self.start('T12')
            ids.add(attempt['attempt_id'])
        after = counts()
        return len(ids) == 1 and after == before, '200 starts reused the existing unfinished attempt; row count and attempts_taken unchanged'

    def T13(self):
        return None, 'Not run: requires approved hosted shared-network lockout test, current Auth limits/logs and teacher instructions; local Auth cannot establish the hosted limit'

    def T14(self):
        return None, 'Not run: requires approved hosted reset emails, test inbox verification and current SMTP cap; local Mailpit cannot prove hosted delivery/quota'

    def page_smoke(self):
        # Reuse the R1 browser assertions without editing the R1 evidence/script.
        # Provisioning and fixture selection are adapted in memory for disabled signup
        # and isolated R2 data. No credentials are written to disk.
        source = (ROOT / 'tests/r1/pages.cjs').read_text()
        source = source.replace("const root = path.resolve(__dirname, '../..');",
                                "const fixture = JSON.parse(fs.readFileSync(0, 'utf8'));\nconst root = fixture.root;")
        source = source.replace("const password = randomBytes(30).toString('base64url');", 'const password = fixture.password;')
        source = source.replace("const email = `r1-teacher-${randomBytes(6).toString('hex')}@example.test`;", 'const email = fixture.email;')
        first = source.index('  const signup =')
        last = source.index('  function localPage(file)')
        source = source[:first] + source[last:]
        source = source.replace(".fill('TESTA-01')", '.fill(fixture.code)')
        source = source.replace('/Fictional R1 Practice Quiz/', '/R2 Fictional Quiz/')
        source = source.replace("{ name: 'Option A', exact: true }", "{ name: 'A', exact: true }")
        source = source.replace("await teacher.locator('#dashboard:not([hidden])').waitFor();",
                                "await teacher.locator('#dashboard:not([hidden])').waitFor();\n    await teacher.locator('#weekSelect').selectOption(fixture.quiz);\n    await teacher.waitForFunction(() => document.getElementById('completed').textContent === '1');")
        source = source.replace("document.getElementById('total').textContent === '2'", "document.getElementById('total').textContent === '9'")
        source = source.replace("teacher.locator('#missing').innerText(), '1'", "teacher.locator('#missing').innerText(), '8'")
        source = source.replace('/TESTA-01/', 'new RegExp(fixture.code)').replace('/TESTA-02/', 'new RegExp(fixture.otherCode)').replace('/TESTB-01/', 'new RegExp(fixture.foreignCode)')
        email, password, _ = self.accounts['A']
        fixture = {'root': str(ROOT), 'email': email, 'password': password, 'code': self.people['T5'],
                   'otherCode': self.people['T6'], 'foreignCode': self.people['B'], 'quiz': self.quiz}
        p = subprocess.run(['node', '-e', source], input=json.dumps(fixture), capture_output=True, text=True)
        assert p.returncode == 0, 'Full pupil/teacher page regression failed; credential-bearing diagnostics withheld'
        assert p.stdout.count('PASS:') == 4, 'Browser regression did not finish all four assertion groups'
        return {'result': 'pass', 'evidence': 'Original pupil page completes all 25 questions at 25/25 through the new wrappers; original teacher page displays that result and 8 unattempted allocated pupils; loopback requests only'}

    def run(self, selected):
        stopped = False
        for n in range(1, 15):
            name = 'T' + str(n)
            if name not in selected:
                continue
            self.test_requests = 0
            try:
                value = getattr(self, name)()
                ok, evidence = value if isinstance(value, tuple) else (True, value)
                result = 'not run' if ok is None else 'pass' if ok else 'fail'
            except Disclosure as error:
                result, evidence, stopped = 'fail', str(error), True
            except (AssertionError, RuntimeError) as error:
                result, evidence = 'fail', str(error)
            assert self.test_requests <= 200, 'Request budget exceeded'
            self.results[name] = {'result': result, 'evidence': evidence, 'requests': self.test_requests}
            print(name, result, evidence, flush=True)
            if stopped:
                print('STOPPED: unexpected data disclosure; no later tests executed', flush=True)
                break
        if not stopped and selected.intersection({'T1', 'T2', 'T3', 'T4'}):
            for name in ['unallocated', 'pupil_functions']:
                try:
                    self.extra[name] = {'result': 'pass', 'evidence': getattr(self, name)()}
                except Disclosure as error:
                    self.extra[name] = {'result': 'fail', 'evidence': str(error)}
                    stopped = True
                    break
                except AssertionError as error:
                    self.extra[name] = {'result': 'fail', 'evidence': str(error)}
        return {'date': datetime.date.today().isoformat(), 'target': 'local fictional Supabase only',
                'phase': self.phase, 'stopped_on_disclosure': stopped, 'tests': self.results,
                'R2_additional': self.extra, 'http_requests': self.requests}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--phase', required=True)
    parser.add_argument('--tests', default='T1,T2,T3,T4')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--smoke-pages', action='store_true')
    args = parser.parse_args()
    runner = Runner(args.phase)
    runner.prepare()
    report = runner.run(set(args.tests.split(',')))
    if args.smoke_pages:
        assert not report['stopped_on_disclosure'], 'Do not run browser regression after disclosure'
        try:
            report['R2_additional']['page_smoke'] = runner.page_smoke()
        except AssertionError as error:
            report['R2_additional']['page_smoke'] = {'result': 'fail', 'evidence': str(error)}
        print('R2 page regression', report['R2_additional']['page_smoke']['result'], flush=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    raise SystemExit(1 if report['stopped_on_disclosure'] or any(v['result'] == 'fail' for v in [*report['tests'].values(), *report['R2_additional'].values()]) else 0)
