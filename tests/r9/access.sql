BEGIN;
\ir helpers.sql
INSERT INTO auth.users(id) VALUES
 ('90000000-0000-4000-8000-000000000001'),
 ('90000000-0000-4000-8000-000000000002'),
 ('90000000-0000-4000-8000-000000000003');
INSERT INTO public.history_teachers(user_id) VALUES
 ('90000000-0000-4000-8000-000000000001'),
 ('90000000-0000-4000-8000-000000000002');
INSERT INTO public.history_teacher_classes(user_id,class_id) VALUES
 ('90000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001');
-- Both classes have real fictional attempts, so an empty result cannot pass vacuously.
INSERT INTO public.history_attempts(pupil_id,quiz_id,attempt_number) VALUES
 ('20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',1),
 ('20000000-0000-4000-8000-000000000003','30000000-0000-4000-8000-000000000001',1);
SELECT pg_temp.check_true(NOT EXISTS (
 SELECT FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN ('public','homework_private') AND c.relkind='r' AND NOT c.relrowsecurity
), 'RLS enabled on all application and private tables');
SELECT pg_temp.check_true(to_regprocedure('homework_api.check_pupil_code(text)') IS NULL,
 'legacy code oracle removed');
SELECT pg_temp.check_true(NOT EXISTS (
 SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('public','homework_api','homework_private') AND p.prosecdef
 AND NOT coalesce(p.proconfig @> ARRAY['search_path=""']
  OR p.proconfig @> ARRAY['search_path=pg_catalog'],false)
), 'all application SECURITY DEFINER functions fix a safe search_path');
SET LOCAL ROLE anon;
DO $$ DECLARE t record; BEGIN
 FOR t IN SELECT tablename FROM pg_tables WHERE schemaname='public' LOOP
  PERFORM pg_temp.refuses(format('SELECT * FROM public.%I',t.tablename),'42501','permission denied');
 END LOOP;
 PERFORM pg_temp.refuses('SELECT public.is_history_teacher()','42501','permission denied');
 PERFORM pg_temp.refuses($q$SELECT * FROM public.get_history_class_results('Fictional Class A',
 '30000000-0000-4000-8000-000000000001')$q$,'42501','permission denied');
END $$;
SELECT pg_temp.check_true(true, 'anonymous table reads and teacher functions refused');
RESET ROLE;
DO $$ DECLARE fn record; role_name text; allowed boolean; BEGIN
 FOR fn IN SELECT p.oid,n.nspname,p.proname FROM pg_proc p
 JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('public','homework_api','homework_private') LOOP
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
   allowed := role_name='anon' AND fn.nspname='homework_api' AND fn.proname IN
    ('quiz_session','get_pupil_quiz_timing','get_current_pupil_homework','start_pupil_quiz','open_pupil_question','submit_pupil_answer','complete_pupil_quiz')
    OR role_name='anon' AND fn.nspname='homework_private' AND fn.proname IN
    ('qm_home_list','qm3_session','get_pupil_quiz_timing','get_current_pupil_homework','start_pupil_quiz','open_pupil_question','submit_pupil_answer','complete_pupil_quiz')
    OR role_name='authenticated' AND fn.nspname='public' AND fn.proname IN
    ('is_history_teacher','get_history_class_results','get_history_class_results_by_id',
     'quiz_manager_class_results','quiz_manager_classes','quiz_manager_import',
     'quiz_manager_release','quiz_manager_validate','quiz_manager_write')
    OR role_name='authenticated' AND fn.nspname='homework_private' AND fn.proname IN
    ('qm3_release','qm3_results','qm_classes','qm_import','qm_validate','qm_write');
   PERFORM pg_temp.check_true(has_function_privilege(role_name,fn.oid,'EXECUTE')=allowed,
     'function EXECUTE allow-list: '||role_name||' '||fn.nspname||'.'||fn.proname);
  END LOOP;
 END LOOP;
END $$;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='90000000-0000-4000-8000-000000000002';
DO $$ DECLARE t text; n bigint; BEGIN
 FOREACH t IN ARRAY ARRAY['history_classes','history_pupils','history_quizzes','history_attempts','history_teacher_classes'] LOOP
  EXECUTE format('SELECT count(*) FROM public.%I',t) INTO n;
  PERFORM pg_temp.check_true(n=0,'unallocated teacher sees no '||t);
 END LOOP;
 PERFORM pg_temp.check_true(public.is_history_teacher(),'unallocated account is genuinely approved');
 PERFORM pg_temp.refuses($q$SELECT * FROM public.get_history_class_results('Fictional Class A',
 '30000000-0000-4000-8000-000000000001')$q$,'P0001','not allocated');
END $$;
SET LOCAL request.jwt.claim.sub='90000000-0000-4000-8000-000000000003';
SELECT pg_temp.check_true(NOT public.is_history_teacher(),'unapproved account denied approval');
SELECT pg_temp.refuses($q$SELECT * FROM public.get_history_class_results('Fictional Class A',
 '30000000-0000-4000-8000-000000000001')$q$,'P0001','Teacher access required');
SET LOCAL request.jwt.claim.sub='90000000-0000-4000-8000-000000000001';
SELECT pg_temp.check_true((SELECT count(*)=1 FROM public.history_classes)
 AND (SELECT count(*)=2 FROM public.history_pupils)
 AND (SELECT count(*)=1 FROM public.history_attempts)
 AND (SELECT count(*)=2 FROM public.get_history_class_results('Fictional Class A',
 '30000000-0000-4000-8000-000000000001')), 'allocated teacher sees own class and complete register');
SELECT pg_temp.refuses($q$SELECT * FROM public.get_history_class_results('Fictional Class B',
 '30000000-0000-4000-8000-000000000001')$q$,'P0001','not allocated');
RESET ROLE;
ROLLBACK;
