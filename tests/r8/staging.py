"""Offline staging guards: never contact GitHub, Supabase or a browser."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/prepare-pages.py'
spec = importlib.util.spec_from_file_location('prepare_pages', SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class Staging(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        # Deliberately fictional values; no actual project or credential.
        self.config = {
            'supabaseUrl': 'https://abcdefghijklmnopqrst.supabase.co',
            'publishableKey': 'sb_publishable_fictional_offline_test',
            'teacherRedirectUrl': 'https://test.invalid/teacher/',
        }
        self.file = self.folder / 'config.json'

    def write(self):
        self.file.write_text(json.dumps(self.config))
        return self.file

    def run_stage(self, page, *args):
        return subprocess.run(
            [sys.executable, str(SCRIPT), page, str(self.folder / page), *args],
            capture_output=True, text=True,
        )

    def test_current_packages_preserve_config(self):
        before = (ROOT / 'shared/config.js').read_bytes()
        for page in ['pupil', 'teacher']:
            self.assertEqual(self.run_stage(page).returncode, 0)
            self.assertEqual((self.folder / page / 'shared/config.js').read_bytes(), before)
            self.assertEqual((self.folder / page / 'index.html').read_text(), module.entry(page))
        self.assertEqual((ROOT / 'shared/config.js').read_bytes(), before)

    def test_test_packages_override_only_staged_config(self):
        before = (ROOT / 'shared/config.js').read_bytes()
        for page in ['pupil', 'teacher']:
            result = self.run_stage(page, '--environment', 'test', '--test-config', str(self.write()))
            self.assertEqual(result.returncode, 0, result.stderr)
            staged = (self.folder / page / 'shared/config.js').read_text()
            self.assertIn(self.config['supabaseUrl'], staged)
            self.assertIn(self.config['teacherRedirectUrl'], staged)
            generated = (self.folder / page / 'index.html').read_text()
            live = 'https://inxsjdogxvqbvxydxmym.supabase.co'
            self.assertEqual(generated, module.entry(page).replace('connect-src ' + live,
                             'connect-src ' + self.config['supabaseUrl']))
            self.assertNotIn('connect-src ' + live, generated)
            source_page = (self.folder / page / page / 'index.html').read_text()
            self.assertIn('connect-src ' + self.config['supabaseUrl'], source_page)
            self.assertNotIn('connect-src ' + live, source_page)

        self.assertEqual((ROOT / 'shared/config.js').read_bytes(), before)

    def test_test_mode_requires_explicit_config_before_writing(self):
        for args in [('--environment', 'test'), ('--test-config', str(self.write()))]:
            self.assertNotEqual(self.run_stage('pupil', *args).returncode, 0)
            self.assertFalse((self.folder / 'pupil').exists())

    def test_current_project_cannot_be_test_target(self):
        self.config['supabaseUrl'] = 'https://inxsjdogxvqbvxydxmym.supabase.co'
        with self.assertRaises(ValueError):
            module.test_config(self.write())

    def test_secret_key_is_rejected_before_output(self):
        self.config['publishableKey'] = 'sb_secret_fictional_rejected_value'
        result = self.run_stage('teacher', '--environment', 'test', '--test-config', str(self.write()))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.folder / 'teacher').exists())
        self.assertNotIn(self.config['publishableKey'], result.stderr)

    def test_live_redirect_is_rejected(self):
        self.config['teacherRedirectUrl'] = 'https://monob26.github.io/history-teacher-dashboard/'
        with self.assertRaises(ValueError):
            module.test_config(self.write())

    def test_url_credentials_and_non_origin_are_rejected(self):
        for value in ['http://abcdefghijklmnopqrst.supabase.co',
                      'https://user:password@abcdefghijklmnopqrst.supabase.co',
                      'https://abcdefghijklmnopqrst.supabase.co/rest/v1']:
            self.config['supabaseUrl'] = value
            with self.assertRaises(ValueError):
                module.test_config(self.write())

    def test_unknown_config_keys_rejected(self):
        self.config['serviceRoleKey'] = 'fictional-not-a-key'
        with self.assertRaises(ValueError):
            module.test_config(self.write())


if __name__ == '__main__':
    unittest.main()
