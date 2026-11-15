"""Rebuild all migrations and revised fictional seeds on LOCAL Supabase only."""
import importlib.util
import json
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('upgrade', ROOT / 'tests/r3/verify_upgrade.py')
upgrade = importlib.util.module_from_spec(spec)
spec.loader.exec_module(upgrade)


def main():
    print('Rebuilding disposable LOCAL Supabase from every migration and revised seed', flush=True)
    upgrade.command(['db', 'reset', '--local'])
    subprocess.run(['docker', '--host=unix:///var/run/docker.sock', 'restart',
                    'supabase_rest_gcse-history-homework-hub'], capture_output=True, check=True)
    runner = upgrade.adv.Runner('r3-clean-rebuild')
    for _ in range(30):
        try:
            if runner.http('GET', '/rest/v1/')[0] == 200:
                break
        except Exception:
            pass
        time.sleep(0.5)
    else:
        raise RuntimeError('Local Data API did not become ready')
    seed = upgrade.adv.sql("SELECT json_build_object('pupils',count(*),'valid_codes',bool_and(pupil_code ~ '^[A-HJ-NP-Z2-9]{12}$'),'separate_registers',bool_and(register_number>0),'unique_codes',count(DISTINCT pupil_code)=count(*)) FROM public.history_pupils;", True)
    assert seed == {'pupils': 3, 'valid_codes': True, 'separate_registers': True, 'unique_codes': True}, 'Revised local seed does not satisfy R3'
    runner.prepare()
    page = runner.page_smoke()
    assert page['result'] == 'pass' and page['separate_register_order_verified']
    report = {'target': 'disposable local Supabase only', 'result': 'pass',
              'all_migrations_and_seed_replayed': True, 'seed': seed,
              'original_page_regression': page, 'individual_codes_or_tokens_exported': False}
    (ROOT / 'docs/r3/local-fresh-rebuild.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PASS: fresh schema, random fictional seed codes, both pages and separate register sorting', flush=True)


if __name__ == '__main__':
    main()
