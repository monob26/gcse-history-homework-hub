-- Fictional fixtures only. The transaction also permits a rollback-only run on TEST.
BEGIN;
\ir helpers.sql

INSERT INTO auth.users(id) VALUES
 ('92000000-0000-4000-8000-000000000001'),
 ('92000000-0000-4000-8000-000000000002'),
 ('92000000-0000-4000-8000-000000000003');
INSERT INTO public.history_teachers(user_id) VALUES
 ('92000000-0000-4000-8000-000000000001'), ('92000000-0000-4000-8000-000000000002');
INSERT INTO public.history_classes(id, class_name, year_group) VALUES
 ('92100000-0000-4000-8000-000000000001', 'Review 2 fictional A', 10),
 ('92100000-0000-4000-8000-000000000002', 'Review 2 fictional B', 10);
INSERT INTO public.history_teacher_classes(user_id, class_id) VALUES
 ('92000000-0000-4000-8000-000000000001', '92100000-0000-4000-8000-000000000001'),
 ('92000000-0000-4000-8000-000000000002', '92100000-0000-4000-8000-000000000002');
INSERT INTO public.history_pupils(id, class_id, register_number) VALUES
 ('92200000-0000-4000-8000-000000000001', '92100000-0000-4000-8000-000000000001', 1),
 ('92200000-0000-4000-8000-000000000002', '92100000-0000-4000-8000-000000000002', 1);
DO $$ BEGIN
 PERFORM set_config('review2.code_a', pupil_code, true)
 FROM public.history_pupils WHERE id='92200000-0000-4000-8000-000000000001';
 PERFORM set_config('review2.code_b', pupil_code, true)
 FROM public.history_pupils WHERE id='92200000-0000-4000-8000-000000000002';
END $$;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='92000000-0000-4000-8000-000000000001';
DO $$
DECLARE document jsonb; metadata jsonb; result jsonb;
BEGIN
 SELECT jsonb_build_object('schema_version', 1, 'questions', jsonb_agg(jsonb_build_object(
   'id', 'question-'||n, 'type', 'missing_word', 'prompt', 'Fictional question '||n,
   'explanation', 'Fictional explanation', 'seconds', 45, 'answers', jsonb_build_object(
     'canonical','fictional','aliases','[]'::jsonb,'surname_aliases','[]'::jsonb,
     'confusable','[]'::jsonb,'allow_minor_typos',false)
 ) ORDER BY n)) INTO document FROM generate_series(1, 25) n;
 metadata := jsonb_build_object('title','Review 2 fictional quiz','year_group',10,
   'topic','Fictional topic','week_number',987654321,'content',document);
 result := public.quiz_manager_import(jsonb_set(metadata, '{content,questions,0,seconds}', '60'));
 PERFORM pg_temp.check_true(result->>'error'='validation_failed'
   AND jsonb_array_length(result->'errors')>0, 'database import rejects invalid question timers');
 PERFORM pg_temp.check_true(NOT EXISTS (
   SELECT FROM public.quiz_manager_quizzes WHERE title=metadata->>'title'
 ), 'failed import leaves no quiz');
 result := public.quiz_manager_import(metadata);
 PERFORM pg_temp.check_true(result->>'ok'='true', 'approved teacher imports a valid fictional quiz');
 PERFORM set_config('review2.quiz',result->>'id',true);
 PERFORM set_config('review2.content',document::text,true);
END $$;
SET LOCAL request.jwt.claim.sub='92000000-0000-4000-8000-000000000003';
DO $$
DECLARE quiz uuid := current_setting('review2.quiz')::uuid;
BEGIN
 PERFORM pg_temp.check_true(NOT EXISTS (SELECT FROM public.quiz_manager_quizzes WHERE id=quiz)
   AND NOT EXISTS (SELECT FROM public.quiz_manager_allocations WHERE quiz_id=quiz),
   'authenticated account without teacher approval cannot read Quiz Manager tables');
 PERFORM pg_temp.check_true(
   public.quiz_manager_write('save',quiz,2,'{}')->>'error'='teacher_required'
   AND public.quiz_manager_import('{}')->>'error'='teacher_required'
   AND public.quiz_manager_release('approve',quiz,2,'{"confirmed":true}')->>'error'='teacher_required',
   'authenticated account without teacher approval cannot edit, import or approve');
END $$;

SET LOCAL request.jwt.claim.sub='92000000-0000-4000-8000-000000000002';
DO $$
DECLARE quiz uuid := current_setting('review2.quiz')::uuid; result jsonb;
BEGIN
 result := public.quiz_manager_write('save',quiz,2,jsonb_build_object(
   'title','Review 2 fictional shared quiz','year_group',10,'topic','Fictional topic',
   'week_number',987654321,'content',current_setting('review2.content')::jsonb));
 PERFORM pg_temp.check_true(result->>'ok'='true','approved colleague can edit the shared quiz');
 result := public.quiz_manager_release('publish_now',quiz,3,'{"confirmed":true}');
 PERFORM pg_temp.check_true(result->>'error'='approval_required','publication still requires approval');
 result := public.quiz_manager_release('approve',quiz,3,'{"confirmed":true}');
 PERFORM pg_temp.check_true(result->>'ok'='true','approved colleague can approve the shared quiz');
 PERFORM set_config('review2.runtime',result#>>'{quiz,runtime_quiz_id}',true);
END $$;

RESET ROLE;
SET LOCAL ROLE anon;
SET LOCAL request.headers='{"cf-connecting-ip":"192.0.2.230"}';
DO $$
DECLARE request jsonb := jsonb_build_object('code',current_setting('review2.code_a'),
 'quiz_id',current_setting('review2.runtime'));
BEGIN
 PERFORM pg_temp.refuses('SELECT * FROM public.quiz_manager_quizzes','42501','permission denied');
 PERFORM pg_temp.refuses('SELECT * FROM public.quiz_manager_allocations','42501','permission denied');
 PERFORM pg_temp.check_true(homework_api.quiz_session('home',request)->>'quiz_id' IS NULL,
   'an approved but unreleased deep link returns no quiz');
 PERFORM pg_temp.refuses(format('SELECT homework_api.quiz_session(%L,%L)','start',request),
   '22023','quiz_not_available');
END $$;

RESET ROLE;
SET LOCAL ROLE authenticated;
DO $$
DECLARE quiz uuid := current_setting('review2.quiz')::uuid; runtime uuid := current_setting('review2.runtime')::uuid;
 class_a uuid := '92100000-0000-4000-8000-000000000001';
BEGIN
 PERFORM pg_temp.check_true(public.quiz_manager_release('publish_now',quiz,3,jsonb_build_object(
   'confirmed',true,'classes',jsonb_build_array(class_a),
   'due_local',to_char((clock_timestamp() + interval '7 days') AT TIME ZONE 'Europe/London',
     'YYYY-MM-DD"T"HH24:MI')))->>'ok'='true', 'approved colleague can publish the shared quiz');
 PERFORM pg_temp.refuses(format('SELECT public.quiz_manager_class_results(%L,%L)',class_a,runtime),
   '42501','Teacher allocation required');
 PERFORM set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000001',true);
 PERFORM pg_temp.check_true(jsonb_array_length(public.quiz_manager_class_results(class_a,runtime))=1,
   'results include the allocated register and exclude the other class');
 PERFORM set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000003',true);
 PERFORM pg_temp.check_true(NOT EXISTS (SELECT FROM public.quiz_manager_allocations WHERE quiz_id=quiz),
   'unapproved account cannot read a real Quiz Manager allocation');
END $$;

RESET ROLE;
SET LOCAL ROLE anon;
DO $$
DECLARE request jsonb := jsonb_build_object('code',current_setting('review2.code_b'),
 'quiz_id',current_setting('review2.runtime')); result jsonb; credentials jsonb;
BEGIN
 PERFORM pg_temp.check_true(homework_api.quiz_session('home',request)->>'quiz_id' IS NULL,
   'a different class cannot access the published deep link');
 PERFORM pg_temp.refuses(format('SELECT homework_api.quiz_session(%L,%L)','start',request),
   '22023','quiz_not_available');
 PERFORM pg_temp.check_true(NOT EXISTS (
   SELECT FROM jsonb_array_elements(homework_api.quiz_session('list',request - 'quiz_id')->'quizzes') q
   WHERE q->>'quiz_id'=current_setting('review2.runtime')
 ), 'a different class cannot list the published quiz');
 request := jsonb_set(request,'{code}',to_jsonb(current_setting('review2.code_a')));
 result := homework_api.quiz_session('start',request);
 credentials := jsonb_build_object('attempt_id',result->'attempt_id','token',result->'attempt_token');
 PERFORM pg_temp.check_true(result->>'attempt_id' IS NOT NULL,'allocated pupil starts the managed quiz');
 PERFORM pg_temp.refuses(format('SELECT homework_api.quiz_session(%L,%L)','review',credentials),
   '22023','complete_before_review');
 result := homework_api.quiz_session('open',credentials);
 PERFORM pg_temp.check_true(result->>'question_type'='missing_word'
   AND NOT (result->'payload' ? 'answers'), 'open returns a question with no accepted answers');
 PERFORM set_config('review2.attempt',credentials::text,true);
END $$;

RESET ROLE;
UPDATE public.history_attempts SET question_started_at=clock_timestamp()-interval '46 seconds'
WHERE id=(current_setting('review2.attempt')::jsonb->>'attempt_id')::uuid;

SET LOCAL ROLE anon;
DO $$
DECLARE credentials jsonb := current_setting('review2.attempt')::jsonb; result jsonb;
BEGIN
 result := homework_api.quiz_session('answer',credentials||'{"answer":"fictional"}');
 PERFORM pg_temp.check_true(result->>'answer_correct'='false' AND result->>'timed_out'='true',
   'late correct answer earns no credit through the managed quiz API');
 FOR n IN 2..25 LOOP
   PERFORM homework_api.quiz_session('open',credentials);
   result := homework_api.quiz_session('answer',credentials||'{"answer":"fictional"}');
   IF result->>'answer_correct' IS DISTINCT FROM 'true' THEN
     RAISE EXCEPTION 'An on-time managed answer did not earn credit';
   END IF;
 END LOOP;
 result := homework_api.quiz_session('finish',credentials);
 PERFORM pg_temp.check_true(result->>'final_score'='24','completion uses server marks');
 result := homework_api.quiz_session('review',credentials);
 PERFORM pg_temp.check_true(jsonb_array_length(result->'answers')=25 AND result->>'score'='24',
   'completed attempt returns the managed quiz review');
END $$;

-- Use a unique fictional bucket so each lookup action sees its own 20th failure.
DO $$
DECLARE action text; response jsonb; bucket integer := 230;
BEGIN
 FOREACH action IN ARRAY ARRAY['list','home','start'] LOOP
   bucket := bucket + 1;
   PERFORM set_config('request.headers',jsonb_build_object('cf-connecting-ip','192.0.2.'||bucket)::text,true);
   FOR n IN 1..20 LOOP
     PERFORM set_config('response.status','',true);
     response := homework_api.quiz_session(action,'{"code":"invalid-fictional-code"}');
     IF response->>'valid_code' IS DISTINCT FROM 'false'
       OR (current_setting('response.status')='429') IS DISTINCT FROM (n=20) THEN
       RAISE EXCEPTION 'Unexpected budget result for % on request %',action,n;
     END IF;
   END LOOP;
   PERFORM pg_temp.check_true(current_setting('response.headers')::jsonb->0 ? 'Retry-After',
     action||' shares the failure budget and returns a retry interval');
 END LOOP;
END $$;

ROLLBACK;
