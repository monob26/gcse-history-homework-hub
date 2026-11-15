WITH funcs AS (
SELECT p.*, n.nspname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','homework_api','homework_private') AND p.prokind='f'
), tabs AS (
SELECT c.*,n.nspname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','homework_api','homework_private') AND c.relkind IN ('r','p')
)
SELECT jsonb_build_object(
'check_pupil_code_dropped',NOT EXISTS(SELECT 1 FROM funcs WHERE proname='check_pupil_code'),
'all_application_tables_have_rls',NOT EXISTS(SELECT 1 FROM tabs WHERE NOT relrowsecurity),
'every_table_has_explicit_policy',NOT EXISTS(SELECT 1 FROM tabs t WHERE NOT EXISTS(SELECT 1 FROM pg_policy pol WHERE pol.polrelid=t.oid)),
'definers_have_fixed_search_path',NOT EXISTS(SELECT 1 FROM funcs WHERE prosecdef AND NOT EXISTS(SELECT 1 FROM unnest(proconfig) c WHERE c LIKE 'search_path=%' AND c NOT LIKE '%$user%')),
'no_exposed_definer_executes_as_client',NOT EXISTS(SELECT 1 FROM funcs WHERE nspname IN ('public','homework_api') AND prosecdef AND (has_function_privilege('anon',oid,'EXECUTE') OR has_function_privilege('authenticated',oid,'EXECUTE'))),
'no_client_schema_creation',NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname IN ('public','homework_api','homework_private') AND (has_schema_privilege('anon',oid,'CREATE') OR has_schema_privilege('authenticated',oid,'CREATE'))),
'no_client_table_writes_or_truncate',NOT EXISTS(SELECT 1 FROM tabs t CROSS JOIN (VALUES ('anon'),('authenticated')) r(role) CROSS JOIN (VALUES ('INSERT'),('UPDATE'),('DELETE'),('TRUNCATE'),('REFERENCES'),('TRIGGER')) v(priv) WHERE has_table_privilege(r.role,t.oid,v.priv)),
'private_definer_grants_are_minimal',NOT EXISTS(SELECT 1 FROM funcs WHERE nspname='homework_private' AND (has_function_privilege('authenticated',oid,'EXECUTE') OR (has_function_privilege('anon',oid,'EXECUTE') AND proname NOT IN ('get_current_pupil_homework','start_pupil_quiz','open_pupil_question','submit_pupil_answer','complete_pupil_quiz')))),
'late_answer_grace_removed',position('time_allowed_seconds + 5' IN pg_get_functiondef('homework_private.submit_pupil_answer(uuid,uuid,integer)'::regprocedure))=0,
'server_clock_checked',position('clock_timestamp()' IN pg_get_functiondef('homework_private.submit_pupil_answer(uuid,uuid,integer)'::regprocedure))>0,
'register_number_not_added',NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='history_pupils' AND column_name='register_number'),
'application_table_count',(SELECT count(*) FROM tabs)
) AS checks;
