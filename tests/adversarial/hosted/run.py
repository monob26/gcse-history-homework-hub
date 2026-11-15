"""Hosted R2/T1–T4 only. Preparation is offline by default. No fixture/admin API code.
Execution flags record a separately obtained owner approval; they do not grant it.
"""
import argparse
import datetime
import getpass
import hashlib
import json
from pathlib import Path
import secrets
import urllib.error
import urllib.parse
import urllib.request

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PROJECT = 'inxsjdogxvqbvxydxmym'
URL = 'https://' + PROJECT + '.supabase.co'
PUPIL = {'get_current_pupil_homework', 'start_pupil_quiz', 'open_pupil_question', 'submit_pupil_answer', 'complete_pupil_quiz'}
ZERO = '00000000-0000-4000-8000-000000000000'
BUDGET = 90


class Stop(Exception):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise Stop('Redirect refused; credentials were not forwarded')


def manifest():
    return json.loads((HERE / 'manifest.json').read_text())


def plan_hash():
    # Bind approval to fixture SQL, inventory, test code and exact manifest.
    paths = [HERE / 'manifest.json', HERE / 'fixtures.proposed.sql', HERE / 'run.py', ROOT / 'supabase/schema-snapshot.json']
    return hashlib.sha256(b''.join(p.read_bytes() for p in paths)).hexdigest()


class Runner:
    def __init__(self, key, passwords):
        self.m = manifest()
        if self.m['project_ref'] != PROJECT:
            raise Stop('Project mismatch')
        self.key, self.passwords = key, passwords
        self.count = 0
        self.results = {}
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        self.snapshot = json.loads((ROOT / 'supabase/schema-snapshot.json').read_text())
        self.tokens = {}

    def request(self, method, path, data=None, schema='public', token=None):
        # Only known-origin REST reads/RPC probes and the four planned Auth requests.
        parsed = urllib.parse.urlsplit(path)
        if parsed.scheme or parsed.netloc or not path.startswith('/') or '..' in path or '#' in path:
            raise Stop('Unsafe path refused')
        allowed = (method == 'GET' and path.startswith('/rest/v1/')) or (method == 'POST' and path.startswith('/rest/v1/rpc/')) or (method == 'POST' and path in ('/auth/v1/signup', '/auth/v1/token?grant_type=password'))
        if not allowed or '/admin/' in path or '/recover' in path:
            raise Stop('Endpoint/method outside approved R2 scope')
        if self.count >= BUDGET:
            raise Stop('Hard request cap reached')
        self.count += 1
        headers = {'apikey': self.key, 'Authorization': 'Bearer ' + (token or self.key), 'Content-Type': 'application/json', 'Accept-Profile': schema, 'Content-Profile': schema}
        req = urllib.request.Request(URL + path, method=method, headers=headers, data=None if data is None else json.dumps(data).encode())
        try:
            with self.opener.open(req, timeout=20) as r:
                status, body = r.status, r.read(2_000_001)
        except urllib.error.HTTPError as e:
            status, body = e.code, e.read(2_000_001)
        except (OSError, ValueError):
            raise Stop('Transport error; raw response withheld') from None
        if len(body) > 2_000_000:
            raise Stop('Response too large; body withheld')
        try:
            obj = json.loads(body)
        except (ValueError, UnicodeError):
            raise Stop('Non-JSON response; body withheld') from None
        if status == 429:
            raise Stop('Rate limit encountered; no retries or lockout test authorised')
        return status, obj

    def rpc(self, name, params, schema='public', token=None):
        return self.request('POST', '/rest/v1/rpc/' + name, params, schema, token)

    def empty(self, status, body):
        if status == 200 and body not in ([], None):
            raise Stop('Unexpected disclosure; body withheld; stop immediately')
        if not ((status == 200 and body in ([], None)) or status in (401, 403)):
            raise Stop('Unexpected access refusal; not counted as a pass')

    def login(self, who):
        status, body = self.request('POST', '/auth/v1/token?grant_type=password', {'email': self.m['accounts'][who], 'password': self.passwords[who]})
        if status != 200 or not isinstance(body, dict) or not body.get('access_token'):
            raise Stop('Fictional teacher login failed; no retry')
        if body.get('user', {}).get('email') != self.m['accounts'][who]:
            raise Stop('Wrong test account returned')
        self.tokens[who] = body['access_token']

    def positive(self, who):
        token = self.tokens[who]
        status, approved = self.rpc('is_history_teacher', {}, token=token)
        if status != 200 or approved is not True:
            raise Stop('Teacher approval positive control failed')
        if who == 'U':
            return
        for table, ident in [('history_classes', self.m['classes'][who]['id']), ('history_pupils', self.m['pupils'][who]), ('history_attempts', self.m['attempts'][who])]:
            status, rows = self.request('GET', '/rest/v1/' + table + '?select=*&id=eq.' + ident, token=token)
            if status != 200 or not isinstance(rows, list) or len(rows) != 1 or rows[0].get('id') != ident:
                raise Stop('Fixture positive control failed; no negative result accepted')
        status, pupils = self.request('GET', '/rest/v1/history_pupils?select=id,pupil_code&id=eq.' + self.m['pupils'][who], token=token)
        if status != 200 or len(pupils) != 1:
            raise Stop('Fixture pupil control failed')
        status, rows = self.rpc('get_history_class_results', {'requested_class': self.m['classes'][who]['name'], 'requested_quiz': self.m['quiz_id']}, token=token)
        if status != 200 or not isinstance(rows, list) or len(rows) != 1 or rows[0].get('pupil_code') != pupils[0]['pupil_code'] or rows[0].get('attempts') != 1 or rows[0].get('highest_score') != self.m['scores'][who]:
            raise Stop('Class-result positive control failed')

    def t1(self, token=None):
        relations = [r for r in self.snapshot['relations'] if r['kind'] in ('r', 'p')]
        for table in relations:
            status, body = self.request('GET', '/rest/v1/' + table['name'] + '?select=*', schema=table['schema'], token=token)
            self.empty(status, body)

    def t2(self, token=None):
        for f in sorted(self.snapshot['functions'], key=lambda f: (f['schema'], f['name'])):
            if f['schema'] == 'homework_api' and f['name'] in PUPIL:
                continue
            params = {}
            for arg in filter(None, f['identity'].split(',')):
                name, typ = arg.strip().split(' ', 1)
                params[name] = self.m['classes']['B']['name'] if name == 'requested_class' else self.m['quiz_id'] if name in ('requested_quiz', 'entered_quiz_id') else 'R2-DELIBERATELY-INVALID' if 'code' in name else ZERO if typ == 'uuid' else [] if typ == 'jsonb' else 0
            status, body = self.rpc(f['name'], params, f['schema'], token)
            if status == 200 and f['name'] == 'is_history_teacher' and body is False:
                continue
            if 200 <= status < 300:
                raise Stop('Unused/teacher function unexpectedly callable; response withheld')
            if status not in (401, 403, 404):
                raise Stop('Unexpected RPC response; not a pass')

    def refused_result(self, status, body):
        if status == 400 and isinstance(body, dict) and body.get('code') == 'P0001' and body.get('message') == 'You are not allocated to this class':
            return
        self.empty(status, body)

    def pupil_probes(self):
        for name in sorted(PUPIL):
            params = {'entered_code': 'R2-DELIBERATELY-INVALID'} if name == 'get_current_pupil_homework' else {'entered_code': 'R2-DELIBERATELY-INVALID', 'entered_quiz_id': self.m['quiz_id']} if name == 'start_pupil_quiz' else {'entered_attempt_id': ZERO, 'entered_attempt_token': ZERO}
            if name == 'submit_pupil_answer':
                params['entered_answer'] = None
            status, body = self.rpc(name, params, 'homework_api')
            if name == 'get_current_pupil_homework':
                row = body[0] if isinstance(body, list) and len(body) == 1 else body
                if status != 200 or not isinstance(row, dict) or row.get('valid_code') is not False or any(row.get(k) is not None for k in ('class_name', 'quiz_id', 'unfinished_attempt_id')):
                    raise Stop('Invalid code unexpectedly returned pupil/session data')
            elif status not in (400, 401, 403):
                raise Stop('Invalid pupil session not refused')

    def unallocated(self):
        t = self.tokens['U']
        for table in ['history_classes', 'history_pupils', 'history_attempts', 'history_answers', 'history_quizzes', 'history_questions', 'history_teacher_classes', 'history_quiz_attempts']:
            self.empty(*self.request('GET', '/rest/v1/' + table + '?select=*', token=t))
        for group in ['A', 'B']:
            status, body = self.rpc('get_history_class_results', {'requested_class': self.m['classes'][group]['name'], 'requested_quiz': self.m['quiz_id']}, token=t)
            self.refused_result(status, body)

    def t4(self):
        t = self.tokens['A']
        for table, field, ident in [('history_classes', 'id', self.m['classes']['B']['id']), ('history_pupils', 'class_id', self.m['classes']['B']['id']), ('history_attempts', 'pupil_id', self.m['pupils']['B'])]:
            self.empty(*self.request('GET', '/rest/v1/' + table + '?select=*&' + field + '=eq.' + ident, token=t))
        self.refused_result(*self.rpc('get_history_class_results', {'requested_class': self.m['classes']['B']['name'], 'requested_quiz': self.m['quiz_id']}, token=t))

    def t3(self):
        status, body = self.request('POST', '/auth/v1/signup', {'email': self.m['signup_email'], 'password': secrets.token_urlsafe(32)})
        if 200 <= status < 300:
            self.results['T3'] = 'fail: signup accepted; account/email side effect may have occurred'
            # The spec requires T1/T2 as the outsider if a session exists. Stop
            # instead if signup produced no usable session; never request mail again.
            token = body.get('access_token') if isinstance(body, dict) else None
            if token:
                self.t1(token)
                self.t2(token)
                self.results['outsider_followup'] = 'T1/T2 passed as unexpected outsider'
            raise Stop('Signup accepted; stop and obtain separate cleanup approval')
        if status not in (400, 403, 422) or not isinstance(body, dict) or body.get('error_code', body.get('code')) != 'signup_disabled':
            raise Stop('Signup refusal did not prove disabled signup')
        self.results['T3'] = 'pass'

    def run(self):
        report = {'project': PROJECT, 'scope': 'hosted R2 access only; T13/T14 forbidden', 'plan_sha256': plan_hash(), 'date': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'results': self.results, 'stopped': False}
        stage = 'positive_controls'
        try:
            for who in ['A', 'B', 'U']:
                self.login(who)
                self.positive(who)
            self.results[stage] = 'pass'
            for stage, fn in [('T1', self.t1), ('T2', self.t2), ('R2.3_pupil_invalid_credentials', self.pupil_probes), ('T3', self.t3), ('T4', self.t4), ('R2.4_unallocated', self.unallocated)]:
                fn()
                self.results[stage] = 'pass'
        except Stop as e:
            report['stopped'] = True
            self.results[stage] = self.results.get(stage, 'not passed')
            report['stop_reason'] = str(e)
        except Exception:
            report['stopped'] = True
            self.results[stage] = 'not passed'
            report['stop_reason'] = 'Unexpected runner/response error; raw detail withheld'
        finally:
            report['requests'] = self.count
            for k in ['T1', 'T2', 'T3', 'T4', 'R2.4_unallocated']:
                self.results.setdefault(k, 'not run')
            self.tokens.clear()
            self.passwords.clear()
        return report


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--execute', action='store_true')
    p.add_argument('--approved-plan-sha256')
    p.add_argument('--owner-present', action='store_true')
    args = p.parse_args()
    if not args.execute:
        print(json.dumps({'mode': 'OFFLINE PLAN ONLY: no requests', 'project': PROJECT, 'manifest': manifest(), 'plan_sha256': plan_hash(), 'request_cap': BUDGET}, indent=2))
        return
    if not args.owner_present or args.approved_plan_sha256 != plan_hash():
        p.error('Specific owner approval/presence and exact reviewed plan hash required')
    key = getpass.getpass('Existing publishable key (hidden): ')
    if not key.startswith('sb_publishable_'):
        p.error('Only a publishable key is accepted; server secrets forbidden')
    passwords = {who: getpass.getpass('Password for fictional teacher ' + who + ' (hidden): ') for who in ['A', 'B', 'U']}
    report = Runner(key, passwords).run()
    print(json.dumps(report, indent=2))
    raise SystemExit(1 if report['stopped'] else 0)


if __name__ == '__main__':
    main()
