"""Render the read-only MCP catalog export; deliberately supports only observed objects.

No row data or sequence current values are accepted. Unsupported shapes fail closed.
The baseline preserves existing permissions, including findings to investigate in R2.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
Q = lambda s: '"' + s.replace('"', '""') + '"'
L = lambda s: "'" + s.replace("'", "''") + "'"


def render():
    x = json.loads((ROOT / 'supabase/schema-snapshot.json').read_text())
    extra = json.loads((ROOT / 'supabase/schema-privileges.json').read_text())
    assert not x['types'] and not x['views'], 'Extend exporter for new object types'
    assert all(r['kind'] in ('r', 'S') and not r['partition'] and not r['options'] for r in x['relations'])
    assert all(not c['generated'] and not c['acl'] for c in x['columns'])
    tables = {r['oid']: r for r in x['relations'] if r['kind'] == 'r'}
    name = lambda r: Q(r['schema']) + '.' + Q(r['name'])
    out = ['-- Schema-only baseline from read-only Supabase MCP catalog queries.',
           '-- Source: inxsjdogxvqbvxydxmym; source commits: 3e3d852 / 6741666.',
           '-- No application rows, Auth rows, passwords, keys, or sequence current values.',
           '-- Baseline preserves the source; it is not a security remediation.',
           'SET check_function_bodies = false;', 'SET search_path = public, extensions;']
    for n in x['schemas']:
        out += [f'CREATE SCHEMA IF NOT EXISTS {Q(n["name"])};',
                f'ALTER SCHEMA {Q(n["name"])} OWNER TO {Q(n["owner"])};']
    for r in sorted(tables.values(), key=name):
        cols = []
        for c in sorted((c for c in x['columns'] if c['relation'] == r['oid']), key=lambda c: c['number']):
            s = Q(c['name']) + ' ' + c['type']
            if c['identity']:
                seq = next(s for s in extra['sequence_details'] if s['table_name'] == r['name'] and s['column_name'] == c['name'])
                s += ' GENERATED ' + ('ALWAYS' if c['identity'] == 'a' else 'BY DEFAULT') + ' AS IDENTITY ('
                s += f'SEQUENCE NAME {Q(seq["schema"])}.{Q(seq["name"])} START WITH {seq["start"]} INCREMENT BY {seq["increment"]} MINVALUE {seq["min"]} MAXVALUE {seq["max"]} CACHE {seq["cache"]}'
                s += ' CYCLE)' if seq['cycle'] else ' NO CYCLE)'
            elif c['default'] is not None:
                s += ' DEFAULT ' + c['default']
            if c['not_null']:
                s += ' NOT NULL'
            cols.append(s)
        out += [f'CREATE TABLE {name(r)} (\n  ' + ',\n  '.join(cols) + '\n);',
                f'ALTER TABLE {name(r)} OWNER TO {Q(r["owner"])};']
    assert all(s['dependency_type'] == 'i' for s in extra['sequence_details']), 'Non-identity sequence needs explicit rendering'
    for c in sorted(x['constraints'], key=lambda c: (c['type'] == 'f', c['name'])):
        out.append(f'ALTER TABLE {name(tables[c["relation"]])} ADD CONSTRAINT {Q(c["name"])} {c["definition"]};')
    for i in x['indexes']:
        if not i['constraint']:
            out.append(i['definition'] + ';')
    for f in sorted(x['functions'], key=lambda f: (f['schema'], f['name'])):
        out += [f['definition'].replace('\r\n', '\n').rstrip() + ';',
                f'ALTER FUNCTION {name(f)}({f["identity"]}) OWNER TO {Q(f["owner"])};']
    for t in x['triggers']:
        assert t['enabled'] == 'O'
        out.append(t['definition'] + ';')
    for r in tables.values():
        out.append(f'ALTER TABLE {name(r)} ' + ('ENABLE' if r['rls'] else 'DISABLE') + ' ROW LEVEL SECURITY;')
        out.append(f'ALTER TABLE {name(r)} ' + ('FORCE' if r['force_rls'] else 'NO FORCE') + ' ROW LEVEL SECURITY;')
    for p in x['policies']:
        s = f'CREATE POLICY {Q(p["policyname"])} ON {Q(p["schemaname"])}.{Q(p["tablename"])} AS {p["permissive"]} FOR {p["cmd"]} TO '
        s += ', '.join('PUBLIC' if r == 'public' else Q(r) for r in p['roles'])
        if p['qual'] is not None:
            s += ' USING (' + p['qual'] + ')'
        if p['with_check'] is not None:
            s += ' WITH CHECK (' + p['with_check'] + ')'
        out.append(s + ';')
    # Reset factory defaults, then restore every observed privilege and grant option.
    roles = sorted({g['grantee'] for g in extra['grants']} | {'PUBLIC', 'anon', 'authenticated', 'service_role', 'postgres'})
    role = lambda s: 'PUBLIC' if s == 'PUBLIC' else Q(s)
    objects = {}
    for g in extra['grants']:
        key = (g['kind'], g['schema'], g['name'], g['identity'], g['owner'])
        objects.setdefault(key, []).append(g)
    for (kind, schema, obj, identity, owner), grants in sorted(objects.items(), key=lambda i: str(i[0])):
        if kind.startswith('default_'):
            target = {'r': 'TABLES', 'S': 'SEQUENCES', 'f': 'FUNCTIONS'}[kind[-1]]
            if owner == 'supabase_admin':
                # Supabase owns these defaults. Normal migration credentials cannot
                # change them: verify the prerequisite rather than silently omit it.
                expected = sorted([[g['grantee'], g['privilege'], g['grantable']] for g in grants])
                expected_sql = L(json.dumps(expected))
                schema_sql = L(schema) if schema else "''"
                out.append(f"""DO $baseline$ BEGIN
  IF (SELECT jsonb_agg(jsonb_build_array(grantee, privilege_type, is_grantable)
                      ORDER BY grantee COLLATE \"C\", privilege_type COLLATE \"C\", is_grantable)
      FROM (SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee)::text END AS grantee,
                   a.privilege_type, a.is_grantable
            FROM pg_default_acl d
            LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace
            CROSS JOIN LATERAL aclexplode(d.defaclacl) a
            WHERE pg_get_userbyid(d.defaclrole) = 'supabase_admin'
              AND coalesce(n.nspname, '') = {schema_sql}
              AND d.defaclobjtype = {L(kind[-1])}) actual)
     IS DISTINCT FROM {expected_sql}::jsonb THEN
    RAISE EXCEPTION 'Supabase-managed default privileges differ from exported baseline ({target})';
  END IF;
END $baseline$;""")
                continue
            prefix = f'ALTER DEFAULT PRIVILEGES FOR ROLE {Q(owner)}' + (f' IN SCHEMA {Q(schema)}' if schema else '')
            for r in roles:
                out.append(f'{prefix} REVOKE ALL ON {target} FROM {role(r)};')
            for g in grants:
                out.append(f'{prefix} GRANT {g["privilege"]} ON {target} TO {role(g["grantee"])}' + (' WITH GRANT OPTION' if g['grantable'] else '') + ';')
        else:
            target = kind.upper() + ' ' + (Q(obj) if kind == 'schema' else Q(schema) + '.' + Q(obj))
            if kind == 'function':
                target += '(' + identity + ')'
            for r in roles:
                out.append(f'REVOKE ALL ON {target} FROM {role(r)};')
            for g in grants:
                out.append(f'GRANT {g["privilege"]} ON {target} TO {role(g["grantee"])}' + (' WITH GRANT OPTION' if g['grantable'] else '') + ';')
    for e in x['event_triggers']:
        assert e['enabled'] == 'O' and e['function'] == 'rls_auto_enable'
        tags = ', '.join(L(t) for t in e['tags'])
        out.append(f"DO $baseline$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_event_trigger WHERE evtname = {L(e['name'])}) THEN CREATE EVENT TRIGGER {Q(e['name'])} ON {e['event']} WHEN TAG IN ({tags}) EXECUTE FUNCTION public.rls_auto_enable(); END IF; END $baseline$;")
    return '\n\n'.join(out) + '\n'


if __name__ == '__main__':
    import sys
    target = next((ROOT / 'supabase/migrations').glob('*_remote_schema.sql'))
    if '--check' in sys.argv:
        assert target.read_text() == render(), 'Migration differs from schema snapshot'
        print('PASS: migration matches schema snapshot')
    else:
        target.write_text(render())
        print('Rendered schema baseline')
