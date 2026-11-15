"""Offline tests only: all network access is replaced by a refusing mock."""
import contextlib
import importlib.util
import io
from pathlib import Path
import sys
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('hosted_runner', Path(__file__).with_name('run.py'))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class Guards(unittest.TestCase):
    def runner(self):
        return m.Runner('sb_publishable_OFFLINE_PLACEHOLDER', {})

    def test_default_is_offline(self):
        with mock.patch.object(sys, 'argv', ['run.py']), mock.patch.object(m.urllib.request.OpenerDirector, 'open', side_effect=AssertionError('Network forbidden')), contextlib.redirect_stdout(io.StringIO()) as out:
            m.main()
        self.assertIn('OFFLINE PLAN ONLY', out.getvalue())

    def test_execution_requires_hash_and_presence(self):
        for args in [['--execute'], ['--execute', '--owner-present', '--approved-plan-sha256', 'wrong']]:
            with mock.patch.object(sys, 'argv', ['run.py'] + args), mock.patch.object(m.getpass, 'getpass', side_effect=AssertionError('Must reject before credentials')), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit):
                    m.main()

    def test_dangerous_endpoints_refused_before_network(self):
        r = self.runner()
        for method, path in [('POST', '/auth/v1/recover'), ('POST', '/auth/v1/admin/users'), ('DELETE', '/rest/v1/history_pupils'), ('GET', 'https://other.example/'), ('POST', '/auth/v1/logout')]:
            with self.assertRaises(m.Stop):
                r.request(method, path)
        self.assertEqual(r.count, 0)

    def test_request_cap(self):
        r = self.runner()
        r.count = m.BUDGET
        with self.assertRaises(m.Stop):
            r.request('GET', '/rest/v1/history_pupils?select=*')

    def test_redirect_not_followed(self):
        with self.assertRaises(m.Stop):
            m.NoRedirect().redirect_request(None, None, 302, '', {}, 'https://other.example/')

    def test_disclosure_stops(self):
        with self.assertRaises(m.Stop):
            self.runner().empty(200, [{'fictional': 'unexpected'}])

    def test_missing_table_not_pass(self):
        with self.assertRaises(m.Stop):
            self.runner().empty(404, {})

    def test_known_rpc_denial(self):
        self.runner().refused_result(400, {'code': 'P0001', 'message': 'You are not allocated to this class'})
        with self.assertRaises(m.Stop):
            self.runner().refused_result(400, {'code': 'P0001', 'message': 'Other error'})

    def test_simulated_success_and_account_scoping(self):
        r = self.runner()
        calls = []
        def fake(method, path, data=None, schema='public', token=None):
            calls.append((method, path))
            if path == '/auth/v1/token?grant_type=password':
                who = next(k for k,v in r.m['accounts'].items() if v == data['email'])
                return 200, {'access_token': who, 'user': {'email': data['email']}}
            if path == '/auth/v1/signup':
                return 400, {'error_code': 'signup_disabled'}
            if path.endswith('/rpc/is_history_teacher'):
                return (200, True) if token else (401, {})
            if '/rpc/get_history_class_results' in path:
                who = next((k for k in ['A','B'] if data['requested_class'] == r.m['classes'][k]['name']), None)
                if token == who:
                    return 200, [{'pupil_code': 'OFFLINE-SYNTHETIC', 'attempts': 1, 'highest_score': r.m['scores'][who]}]
                return (400, {'code': 'P0001', 'message': 'You are not allocated to this class'}) if token else (401, {})
            if '/rpc/get_current_pupil_homework' in path:
                return 200, [{'valid_code': False}]
            if '/rpc/' in path:
                return (400, {}) if path.rsplit('/',1)[-1] in m.PUPIL else (404, {})
            if '?select=*&id=eq.' in path and token in ['A','B']:
                ident = path.split('eq.')[1]
                if ident in (r.m['classes'][token]['id'], r.m['pupils'][token], r.m['attempts'][token]):
                    return 200, [{'id': ident}]
            if '?select=id,pupil_code&id=eq.' in path:
                return 200, [{'id': r.m['pupils'][token], 'pupil_code': 'OFFLINE-SYNTHETIC'}]
            return 200, []
        r.passwords = {who: 'OFFLINE-NOT-A-CREDENTIAL' for who in ['A','B','U']}
        with mock.patch.object(r, 'request', side_effect=fake):
            report = r.run()
        self.assertFalse(report['stopped'], report)
        self.assertTrue(all(v == 'pass' for v in report['results'].values()))
        self.assertEqual(len(calls), 61)
        self.assertLess(len(calls), m.BUDGET)
        self.assertEqual(sum(p == '/auth/v1/signup' for _,p in calls), 1)
        self.assertFalse(any('/recover' in p or '/admin' in p for _,p in calls))


if __name__ == '__main__':
    unittest.main()
