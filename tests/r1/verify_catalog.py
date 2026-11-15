"""Compare a local rebuild against the MCP schema-only snapshot, without reading rows."""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTAINER = 'supabase_db_gcse-history-homework-hub'


def sql(query):
    result = subprocess.run(
        ['docker', '--host=unix:///var/run/docker.sock', 'exec', '-i', CONTAINER,
         'psql', '-U', 'postgres', '-d', 'postgres', '-X', '-A', '-t', '-v', 'ON_ERROR_STOP=1'],
        input=query, capture_output=True, text=True, check=True,
    )
    return json.loads(result.stdout)


def canonical(x):
    relations = {r['oid']: r['schema'] + '.' + r['name'] for r in x['relations'] or []}
    out = {}
    # Extension installation is a Supabase platform prerequisite, not application DDL.
    for key in ['schemas', 'relations', 'columns', 'constraints', 'indexes', 'functions',
                'policies', 'triggers', 'types', 'views', 'event_triggers']:
        rows = []
        for row in x[key] or []:
            row = dict(row)
            row.pop('oid', None)
            row.pop('acl', None)  # Compared as exploded privileges below.
            if 'relation' in row:
                row['relation'] = relations[row['relation']]
            if 'definition' in row:
                row['definition'] = row['definition'].replace('\r\n', '\n')
            rows.append(row)
        out[key] = sorted(rows, key=lambda r: json.dumps(r, sort_keys=True))
    return out


if __name__ == '__main__':
    expected = json.loads((ROOT / 'supabase/schema-snapshot.json').read_text())
    actual = sql((ROOT / 'tests/r1/catalog.sql').read_text())
    a, b = canonical(expected), canonical(actual)
    failures = []
    for key in a:
        if a[key] != b[key]:
            failures.append(key)
            print(f'FAIL: {key}; expected {len(a[key])}, got {len(b[key])}')
            # Definitions are schema metadata, but keep diagnostic output brief.
            print('Missing:', [r.get('name', r.get('policyname', r.get('relation'))) for r in a[key] if r not in b[key]])
            print('Different:', [r.get('name', r.get('policyname', r.get('relation'))) for r in b[key] if r not in a[key]])
        else:
            print(f'PASS: {key} ({len(a[key])})')
    extra = json.loads((ROOT / 'supabase/schema-privileges.json').read_text())
    actual_extra = sql((ROOT / 'tests/r1/privileges.sql').read_text())
    for key in extra:
        norm = lambda rows: sorted(rows or [], key=lambda r: json.dumps(r, sort_keys=True))
        if norm(extra[key]) != norm(actual_extra[key]):
            failures.append(key)
            print(f'FAIL: {key}')
            print('Missing:', [r for r in norm(extra[key]) if r not in norm(actual_extra[key])][:10])
            print('Different:', [r for r in norm(actual_extra[key]) if r not in norm(extra[key])][:10])
        else:
            print(f'PASS: {key} ({len(extra[key] or [])})')
    supplement = json.loads((ROOT / 'supabase/schema-supplement.json').read_text())
    actual_supplement = sql((ROOT / 'tests/r1/supplement.sql').read_text())
    for key in supplement:
        norm = lambda value: sorted(value, key=lambda r: json.dumps(r, sort_keys=True)) if isinstance(value, list) else value
        if norm(supplement[key]) != norm(actual_supplement[key]):
            failures.append('supplement.' + key)
            print(f'FAIL: supplemental {key}')
        else:
            print(f'PASS: supplemental {key}')
    assert not failures, 'Catalog differs: ' + ', '.join(failures)
