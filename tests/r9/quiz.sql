BEGIN;
\ir helpers.sql
CREATE TEMP TABLE r9_state (code text, attempt_id text, token text, prior_token text,
 deadline timestamptz, correct_option integer);
INSERT INTO r9_state(code) SELECT pupil_code FROM public.history_pupils
 WHERE id='20000000-0000-4000-8000-000000000001';
GRANT SELECT, UPDATE ON r9_state TO anon;
SET LOCAL ROLE anon;
DO $$ DECLARE s record; a record; BEGIN
 SELECT * INTO s FROM r9_state;
 SELECT * INTO a FROM homework_api.start_pupil_quiz(s.code,'30000000-0000-4000-8000-000000000001');
 UPDATE r9_state SET attempt_id=a.attempt_id::text, token=a.attempt_token::text;
 PERFORM homework_api.open_pupil_question(a.attempt_id::text,a.attempt_token::text);
 PERFORM pg_temp.refuses(format('SELECT * FROM homework_api.submit_pupil_answer(%L,%L,to_jsonb(0))',
 a.attempt_id::text,gen_random_uuid()::text),'P0001','Invalid or inactive');
 PERFORM pg_temp.refuses(format('SELECT * FROM homework_api.complete_pupil_quiz(%L,%L)',
 a.attempt_id::text,a.attempt_token::text),'P0001','Quiz incomplete');
END $$;
SELECT pg_temp.check_true(true,'valid token required and incomplete completion refused');
RESET ROLE;
UPDATE r9_state s SET deadline=a.question_started_at FROM public.history_attempts a WHERE a.id=s.attempt_id::uuid;
SET LOCAL ROLE anon;
DO $$ DECLARE s record; a record; BEGIN
 SELECT * INTO s FROM r9_state;
 SELECT * INTO a FROM homework_api.start_pupil_quiz(s.code,'30000000-0000-4000-8000-000000000001');
 PERFORM pg_temp.check_true(a.attempt_id::text=s.attempt_id AND a.attempt_token::text<>s.token,
 'resume preserves attempt identity and rotates token');
 UPDATE r9_state SET prior_token=token,token=a.attempt_token::text;
 PERFORM pg_temp.refuses(format('SELECT * FROM homework_api.open_pupil_question(%L,%L)',
 s.attempt_id,s.token),'P0001','Invalid or inactive');
END $$;
RESET ROLE;
SELECT pg_temp.check_true((SELECT a.question_started_at=s.deadline AND a.question_position=1
 FROM public.history_attempts a JOIN r9_state s ON a.id=s.attempt_id::uuid),
 'resume preserves original question deadline and progress');
SET LOCAL ROLE anon;
DO $$ DECLARE s record; BEGIN
 SELECT * INTO s FROM r9_state;
 PERFORM homework_api.submit_pupil_answer(s.attempt_id,s.token,'0'::jsonb);
 PERFORM pg_temp.refuses(format('SELECT * FROM homework_api.submit_pupil_answer(%L,%L,to_jsonb(0))',
 s.attempt_id,s.token),'P0001','Open the question first');
 PERFORM homework_api.open_pupil_question(s.attempt_id,s.token);
END $$;
RESET ROLE;
SELECT pg_temp.check_true((SELECT count(*)=1 FROM public.history_answers a JOIN r9_state s
 ON a.attempt_id=s.attempt_id::uuid),'duplicate submission did not add an answer');
-- Age only the disposable fixture's server timestamp; do not wait or mock the SQL clock.
UPDATE public.history_attempts a SET question_started_at=clock_timestamp()-interval '2 hours'
 FROM r9_state s WHERE a.id=s.attempt_id::uuid;
UPDATE r9_state s SET correct_option=(SELECT i::integer-1
 FROM public.history_attempts a,
 LATERAL jsonb_array_elements_text(a.saved_progress->'option_orders'->1) WITH ORDINALITY o(v,i)
 WHERE a.id=s.attempt_id::uuid AND o.v='0');
SET LOCAL ROLE anon;
DO $$ DECLARE s record; answer record; BEGIN
 SELECT * INTO s FROM r9_state;
 SELECT * INTO answer FROM homework_api.submit_pupil_answer(s.attempt_id,s.token,to_jsonb(s.correct_option));
 PERFORM pg_temp.check_true(answer.answer_correct=false,'late correct answer refused credit by server');
END $$;
RESET ROLE;
SELECT pg_temp.check_true((SELECT count(*)=1 FROM public.history_answers a JOIN r9_state s
 ON a.attempt_id=s.attempt_id::uuid WHERE a.question_number=2 AND NOT a.is_correct),
 'late answer persisted exactly once as incorrect');
SET LOCAL ROLE anon;
-- Exercise genuine completion as a positive control, using timeout answers for remaining questions.
DO $$ DECLARE s record; result record; BEGIN
 SELECT * INTO s FROM r9_state;
 FOR i IN 3..25 LOOP
  PERFORM homework_api.open_pupil_question(s.attempt_id,s.token);
  PERFORM homework_api.submit_pupil_answer(s.attempt_id,s.token,'null'::jsonb);
 END LOOP;
 SELECT * INTO result FROM homework_api.complete_pupil_quiz(s.attempt_id,s.token);
 PERFORM pg_temp.check_true(result.total_questions=25 AND result.final_score<=1 AND NOT result.passed,
 'complete quiz uses saved server marks');
 PERFORM pg_temp.refuses(format('SELECT * FROM homework_api.complete_pupil_quiz(%L,%L)',
 s.attempt_id,s.token),'P0001','Invalid or completed');
 PERFORM pg_temp.refuses(format('SELECT * FROM homework_api.submit_pupil_answer(%L,%L,to_jsonb(0))',
 s.attempt_id,s.token),'P0001','Invalid or inactive');
END $$;
RESET ROLE;
SELECT pg_temp.check_true((SELECT count(*)=25 AND count(DISTINCT question_number)=25
 FROM public.history_answers a JOIN r9_state s ON a.attempt_id=s.attempt_id::uuid),
 'full quiz stores exactly one answer per question');
ROLLBACK;
