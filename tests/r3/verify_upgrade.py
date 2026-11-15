"""LOCAL-only upgrade test: fictional legacy codes -> R3, no credentials on disk.

Destructively resets only the disposable local Supabase project to the R2 migration,
prepares fictional fixtures, then applies the new R3 migration and checks preservation.
"""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import argparse
import time

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('adversarial', ROOT / 'tests/adversarial/run.py')
adv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adv)
CLI = os.environ.get('SUPABASE_CLI', 'supabase')
ENV = {**os.environ, 'DOCKER_HOST': 'unix:///var/run/docker.sock', 'SUPABASE_INTERNAL_IMAGE_REGISTRY': 'docker.io'}


def command(args):
    p = subprocess.run([CLI, *args, '--workdir', str(ROOT)], capture_output=True, text=True, env=ENV)
    assert p.returncode == 0, 'Local migration operation failed; credential-bearing output withheld'


def main(reuse=False):
    if reuse:
        assert not adv.sql("SELECT to_json(EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='history_pupils' AND column_name='register_number'));", True), 'Reuse requires the existing R2-only local baseline'
        print('Reusing the already-reset disposable LOCAL R2 baseline', flush=True)
    else:
        print('Resetting disposable LOCAL database to the R2 baseline', flush=True)
        command(['db', 'reset', '--local', '--version', '20261115140316', '--no-seed'])
    # CLI 2.81.3 does not restart/wait for PostgREST after recreating the database.
    # Explicitly refresh the local schema cache before preparing API fixtures.
    subprocess.run(['docker', '--host=unix:///var/run/docker.sock', 'restart',
                    'supabase_rest_gcse-history-homework-hub'], capture_output=True, check=True)
    runner = adv.Runner('r3-upgrade-fixtures')
    for _ in range(30):
        try:
            if runner.http('GET', '/rest/v1/')[0] == 200:
                break
        except Exception:
            pass
        time.sleep(0.5)
    else:
        raise RuntimeError('Local Data API did not become ready')
    runner.prepare()
    old_codes = dict(runner.people)
    attempt = runner.start('T12')
    q = runner.open(attempt)
    assert runner.answer(attempt, q['answer_options'].index('A'))[0] == 200
    runner.open(attempt)
    attempt_id = attempt['attempt_id']
    state = lambda: adv.sql(f"SELECT json_build_object('position',question_position,'deadline_start',question_started_at,'answers',(SELECT count(*) FROM public.history_answers WHERE attempt_id=a.id),'correct',(SELECT count(*) FROM public.history_answers WHERE attempt_id=a.id AND is_correct)) FROM public.history_attempts a WHERE id='{attempt_id}';", True)
    before = state()
    print('Applying R3 locally to the fictional upgrade fixture', flush=True)
    command(['migration', 'up', '--local'])
    after = state()
    assert after == before, 'R3 changed saved answers, marking, position or deadline'
    new_codes = {}
    for key, pupil_id in runner.ids.items():
        row = adv.sql(f"SELECT json_build_object('code',pupil_code,'register',register_number) FROM public.history_pupils WHERE id='{pupil_id}';", True)
        assert row['register'] == runner.registers[key], 'Register number changed during upgrade'
        assert row['code'] != old_codes[key], 'A legacy code was not rotated'
        assert len(row['code']) == 12 and set(row['code']) <= set('ABCDEFGHJKLMNPQRSTUVWXYZ23456789'), 'New code violates the length/alphabet rule'
        new_codes[key] = row['code']
    assert len(set(new_codes.values())) == len(new_codes), 'Duplicate generated codes'
    for key in ['T5', 'T6', 'T12']:
        status, body = runner.rpc('get_current_pupil_homework', {'entered_code': old_codes[key]})
        if status == 200 and body and body[0].get('valid_code'):
            raise adv.Disclosure('A retired fictional code was still accepted; response withheld')
        assert status == 200 and body[0]['valid_code'] is False, 'Old-code rejection was masked'
    status, _ = runner.rpc('open_pupil_question', runner.params(attempt))
    if status < 400:
        raise adv.Disclosure('A retired attempt token was still accepted; response withheld')
    runner.people = new_codes
    resumed = runner.start('T12')
    assert resumed['attempt_id'] == attempt_id, 'Upgrade lost the unfinished attempt'
    assert runner.open(resumed)['question_number'] == 2
    assert state() == before, 'Resumption changed saved progress or restarted the deadline'
    sample = adv.sql("WITH samples AS MATERIALIZED (SELECT homework_private.generate_pupil_code() AS code FROM generate_series(1,1000)) SELECT json_build_object('count',count(*),'distinct',count(DISTINCT code),'valid',bool_and(code ~ '^[A-HJ-NP-Z2-9]{12}$')) FROM samples;", True)
    assert sample == {'count': 1000, 'distinct': 1000, 'valid': True}, 'Generator sample failed'
    report = {'target': 'disposable local Supabase only', 'result': 'pass',
              'pupils_rotated_and_registers_preserved': len(new_codes),
              'retired_codes_tested_and_refused': 3,
              'retired_attempt_token_refused': True,
              'saved_answers_and_deadline_preserved': True,
              'new_code_resumes_existing_attempt': True,
              'generator_sample': sample, 'individual_codes_or_tokens_exported': False}
    path = ROOT / 'docs/r3/local-upgrade.json'
    path.write_text(json.dumps(report, indent=2) + '\n')
    print('PASS: rotation, register preservation, old-credential refusal, progress/deadline preservation and 1000-code sample', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--reuse-r2-baseline', action='store_true')
    main(parser.parse_args().reuse_r2_baseline)
