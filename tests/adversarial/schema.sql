-- R2 structural checks; read-only, no pupil rows or credentials in output.
SELECT jsonb_build_object(
  'all_application_tables_have_rls', NOT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('public','homework_api','homework_private')
      AND c.relkind IN ('r','p') AND NOT c.relrowsecurity),
  'definers_have_fixed_search_path', NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname IN ('public','homework_api','homework_private') AND p.prosecdef
      AND NOT (coalesce(p.proconfig,'{}') && ARRAY['search_path=""','search_path=pg_catalog'])),
  'no_exposed_definer_executes_as_client', NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname IN ('public','homework_api') AND p.prosecdef
      AND (has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE'))),
  'private_definer_grants_are_minimal', NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='homework_private' AND p.prosecdef AND
      (has_function_privilege('authenticated',p.oid,'EXECUTE') OR
       has_function_privilege('anon',p.oid,'EXECUTE') <>
       (p.proname IN ('get_current_pupil_homework','start_pupil_quiz','open_pupil_question','submit_pupil_answer','complete_pupil_quiz')))),
  'check_pupil_code_dropped', NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname IN ('public','homework_api','homework_private') AND p.proname='check_pupil_code'),
  'no_client_table_writes_or_truncate', NOT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    CROSS JOIN (VALUES ('anon'),('authenticated')) r(role_name)
    CROSS JOIN (VALUES ('INSERT'),('UPDATE'),('DELETE'),('TRUNCATE'),('TRIGGER'),('REFERENCES'),('MAINTAIN')) v(privilege)
    WHERE n.nspname IN ('public','homework_api','homework_private') AND c.relkind IN ('r','p')
      AND has_table_privilege(r.role_name,c.oid,v.privilege)),
  'every_table_has_explicit_policy', NOT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('public','homework_api','homework_private') AND c.relkind IN ('r','p')
      AND NOT EXISTS (SELECT 1 FROM pg_policy p WHERE p.polrelid=c.oid)),
  'no_client_schema_creation', NOT EXISTS (
    SELECT 1 FROM pg_namespace n CROSS JOIN (VALUES ('anon'),('authenticated'))r(role_name)
    WHERE n.nspname IN ('public','homework_api','homework_private')
      AND has_schema_privilege(r.role_name,n.oid,'CREATE'))
) AS results;
