"""Check schema-only export content and scan candidate files without printing secrets."""
import json
import os
import re
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from render_schema import render

migration = next((ROOT / 'supabase/migrations').glob('*_remote_schema.sql'))
assert migration.read_text() == render(), 'Baseline is not the deterministic snapshot rendering'
source = migration.read_text()
# Function bodies legitimately contain DML. Remove dollar-quoted bodies before
# checking that the migration has no top-level application-row export.
stripped = source
for tag in set(re.findall(r'\$[A-Za-z_][A-Za-z_0-9]*\$|\$\$', source)):
    stripped = re.sub(re.escape(tag) + r'.*?' + re.escape(tag), "''", stripped, flags=re.S)
assert not re.search(r'^\s*(INSERT|COPY|UPDATE|DELETE|TRUNCATE)\b', stripped, re.M | re.I)
assert not re.search(r'\bsetval\s*\(', stripped, re.I)
assert not re.search(r'CREATE\s+(ROLE|USER)\b', stripped, re.I)
print('PASS: baseline contains schema definitions, no exported rows, current sequence values or login creation')
supp = json.loads((ROOT / 'supabase/schema-supplement.json').read_text())
assert not supp['other_types'] and not supp['publications']
assert all(supp[k] == 0 for k in ['rules', 'collations', 'extended_statistics', 'column_grants'])
assert not supp['foreign_grantors']
assert all(x['kind'] in ('i', 'S') and x['persistence'] == 'p'
           and x['replica_identity'] == 'n' and x['tablespace'] == '0'
           for x in supp['unsupported'])
assert all(c['collation'] in (None, '"default"') and c['stats'] is None
           and c['compression'] == '' for c in supp['column_metadata'])
assert len(supp['comments']) == 1 and supp['comments'][0]['comment'] == 'standard public schema'
print('PASS: supplemental catalog has no unsupported application schema objects or custom column settings')
patterns = [
    r'sbp_[A-Za-z0-9_-]{12,}', r'sb_secret_[A-Za-z0-9_-]{12,}',
    r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    r'postgres(?:ql)?://[^\s:@]+:[^\s@]+@',
    r'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',
    r'(?i)\b(?:smtp_pass|db_password|service_role_key)\s*[:=]\s*[\"\'][^\"\']{8,}[\"\']',
]
# Match the actual runtime PAT without revealing it; files never receive it.
token = os.environ.get('SUPABASE_ACCESS_TOKEN')
failures = []
count = 0
for p in ROOT.rglob('*'):
    if not p.is_file() or any(part in {'.git', '.temp', '.branches', '__pycache__', 'node_modules'} for part in p.relative_to(ROOT).parts):
        continue
    try:
        content = p.read_text()
    except UnicodeDecodeError:
        continue
    count += 1
    if (token and token in content) or any(re.search(pattern, content) for pattern in patterns):
        failures.append(str(p.relative_to(ROOT)))
assert not failures, 'Potential secret in candidate files: ' + ', '.join(failures)
print(f'PASS: secret-pattern and runtime-token scan across {count} candidate files (no values printed)')
