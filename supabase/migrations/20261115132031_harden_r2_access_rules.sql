-- R2: tighten API privileges without changing quiz behaviour.

-- Apply only after review/approval on hosted Supabase. Test locally first.

SET search_path = public, extensions;

DROP FUNCTION homework_api.check_pupil_code(text);

CREATE SCHEMA homework_private AUTHORIZATION postgres;

REVOKE ALL ON SCHEMA homework_private FROM PUBLIC, anon, authenticated, service_role;

GRANT USAGE ON SCHEMA homework_private TO anon;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA homework_private REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role;

ALTER FUNCTION homework_api._ensure_attempt_shuffle(v_attempt_id uuid) SET SCHEMA homework_private;

CREATE OR REPLACE FUNCTION homework_private._ensure_attempt_shuffle(v_attempt_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  a record;
  q record;
  ids jsonb := '[]'::jsonb;
  orders jsonb := '[]'::jsonb;
  perm jsonb;
  n integer := 0;
  has_existing_answers boolean;
BEGIN
  SELECT at.quiz_id, at.saved_progress INTO a
  FROM public.history_attempts at WHERE at.id = v_attempt_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Attempt not found'; END IF;
  IF a.saved_progress ? 'question_ids' THEN RETURN; END IF;
  SELECT EXISTS (SELECT 1 FROM public.history_answers x WHERE x.attempt_id=v_attempt_id)
    INTO has_existing_answers;

  FOR q IN SELECT h.id, h.answer_options, h.question_type
           FROM public.history_questions h
           WHERE h.quiz_id = a.quiz_id
           ORDER BY CASE WHEN has_existing_answers THEN h.question_number::double precision
                         ELSE pg_catalog.random() END
  LOOP
    IF q.question_type <> 'multiple_choice'
       OR pg_catalog.jsonb_typeof(q.answer_options) <> 'array'
       OR pg_catalog.jsonb_array_length(q.answer_options) <> 4 THEN
      RAISE EXCEPTION 'This quiz contains an unsupported question format';
    END IF;
    IF has_existing_answers THEN
      perm := '[0,1,2,3]'::jsonb;
    ELSE
      SELECT pg_catalog.to_jsonb(pg_catalog.array_agg(s.i ORDER BY s.r))
        INTO perm
      FROM (SELECT i, pg_catalog.random() AS r FROM pg_catalog.generate_series(0,3) i) s;
    END IF;
    ids := ids || pg_catalog.to_jsonb(q.id::text);
    orders := orders || pg_catalog.jsonb_build_array(perm);
    n := n + 1;
  END LOOP;
  IF n <> (SELECT z.total_questions FROM public.history_quizzes z WHERE z.id = a.quiz_id) THEN
    RAISE EXCEPTION 'Quiz question count does not match quiz settings';
  END IF;
  UPDATE public.history_attempts at
  SET saved_progress = pg_catalog.jsonb_set(
      pg_catalog.jsonb_set(at.saved_progress, '{question_ids}', ids, true),
      '{option_orders}', orders, true)
  WHERE at.id = v_attempt_id;
END;
$function$;

REVOKE ALL ON FUNCTION homework_private._ensure_attempt_shuffle(v_attempt_id uuid) FROM PUBLIC, anon, authenticated, service_role;

ALTER FUNCTION homework_api.check_published_attempt(entered_attempt_id uuid, entered_attempt_token uuid) SET SCHEMA homework_private;

CREATE OR REPLACE FUNCTION homework_private.check_published_attempt(entered_attempt_id uuid, entered_attempt_token uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.history_attempts a
    JOIN public.history_quizzes q
      ON q.id = a.quiz_id
    WHERE a.id = entered_attempt_id
      AND a.attempt_token = entered_attempt_token
      AND a.status = 'in_progress'
      AND q.is_published = true
  );
$function$;

REVOKE ALL ON FUNCTION homework_private.check_published_attempt(entered_attempt_id uuid, entered_attempt_token uuid) FROM PUBLIC, anon, authenticated, service_role;

ALTER FUNCTION homework_api.complete_pupil_quiz(entered_attempt_id uuid, entered_attempt_token uuid) SET SCHEMA homework_private;

CREATE OR REPLACE FUNCTION homework_private.complete_pupil_quiz(entered_attempt_id uuid, entered_attempt_token uuid)
 RETURNS TABLE(final_score integer, total_questions integer, passed boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  a record;
  q record;
  saved_count integer;
  distinct_count integer;
  calculated_score integer;
BEGIN
  SELECT *
  INTO a
  FROM public.history_attempts
  WHERE id = entered_attempt_id
    AND attempt_token = entered_attempt_token
  FOR UPDATE;

  IF NOT FOUND OR a.status <> 'in_progress' THEN
    RAISE EXCEPTION 'Invalid or completed attempt';
  END IF;

  IF NOT homework_private.check_published_attempt(
    entered_attempt_id,
    entered_attempt_token
  ) THEN
    RAISE EXCEPTION 'Quiz is not available';
  END IF;

  SELECT *
  INTO q
  FROM public.history_quizzes
  WHERE id = a.quiz_id;

  SELECT
    COUNT(*)::integer,
    COUNT(DISTINCT ans.question_number)::integer,
    COUNT(*) FILTER (
      WHERE ans.is_correct = true
    )::integer
  INTO saved_count, distinct_count, calculated_score
  FROM public.history_answers ans
  WHERE ans.attempt_id = a.id;

  IF saved_count <> q.total_questions
     OR distinct_count <> q.total_questions THEN
    RAISE EXCEPTION
      'Quiz incomplete or duplicate answers: % answers, % distinct questions, expected %',
      saved_count, distinct_count, q.total_questions;
  END IF;

  UPDATE public.history_attempts
  SET
    status = 'completed',
    score = calculated_score,
    completed_at = now(),
    question_position = q.total_questions
  WHERE id = a.id;

  RETURN QUERY SELECT
    calculated_score,
    q.total_questions,
    calculated_score >= q.pass_mark;
END;
$function$;

REVOKE ALL ON FUNCTION homework_private.complete_pupil_quiz(entered_attempt_id uuid, entered_attempt_token uuid) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION homework_api.complete_pupil_quiz(entered_attempt_id uuid, entered_attempt_token uuid)
RETURNS TABLE(final_score integer, total_questions integer, passed boolean)
LANGUAGE sql SECURITY INVOKER SET search_path = ''
AS $wrapper$ SELECT * FROM homework_private.complete_pupil_quiz($1, $2); $wrapper$;

REVOKE ALL ON FUNCTION homework_api.complete_pupil_quiz(entered_attempt_id uuid, entered_attempt_token uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION homework_api.complete_pupil_quiz(entered_attempt_id uuid, entered_attempt_token uuid) TO anon;

GRANT EXECUTE ON FUNCTION homework_private.complete_pupil_quiz(entered_attempt_id uuid, entered_attempt_token uuid) TO anon;

ALTER FUNCTION homework_api.complete_quiz_test(entered_attempt_id uuid) SET SCHEMA homework_private;

CREATE OR REPLACE FUNCTION homework_private.complete_quiz_test(entered_attempt_id uuid)
 RETURNS TABLE(final_score integer, total_questions integer, passed boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  a record;
  q record;
  saved_count integer;
  calculated_score integer;
BEGIN
  SELECT *
  INTO a
  FROM public.history_attempts
  WHERE id = entered_attempt_id
  FOR UPDATE;

  IF NOT FOUND OR a.status <> 'in_progress' THEN
    RAISE EXCEPTION 'No active quiz attempt found';
  END IF;

  SELECT *
  INTO q
  FROM public.history_quizzes
  WHERE id = a.quiz_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Quiz not found';
  END IF;

  SELECT
    COUNT(*)::integer,
    COUNT(*) FILTER (WHERE ans.is_correct)::integer
  INTO saved_count, calculated_score
  FROM public.history_answers ans
  WHERE ans.attempt_id = a.id;

  IF saved_count <> q.total_questions THEN
    RAISE EXCEPTION
      'Quiz incomplete: % of % answers saved',
      saved_count, q.total_questions;
  END IF;

  UPDATE public.history_attempts
  SET
    status = 'completed',
    score = calculated_score,
    completed_at = now(),
    question_position = q.total_questions
  WHERE id = a.id;

  RETURN QUERY SELECT
    calculated_score,
    q.total_questions,
    calculated_score >= q.pass_mark;
END;
$function$;

REVOKE ALL ON FUNCTION homework_private.complete_quiz_test(entered_attempt_id uuid) FROM PUBLIC, anon, authenticated, service_role;

ALTER FUNCTION homework_api.get_current_pupil_homework(entered_code text) SET SCHEMA homework_private;

CREATE OR REPLACE FUNCTION homework_private.get_current_pupil_homework(entered_code text)
 RETURNS TABLE(valid_code boolean, class_name text, year_group integer, quiz_id uuid, quiz_title text, topic text, week_number integer, due_at timestamp with time zone, total_questions integer, pass_mark integer, attempts_taken integer, highest_score integer, passed boolean, unfinished_attempt_id uuid)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  WITH pupil AS (
    SELECT p.id AS pupil_id, c.class_name, c.year_group
    FROM public.history_pupils p
    JOIN public.history_classes c ON c.id = p.class_id
    WHERE p.pupil_code = pg_catalog.upper(pg_catalog.btrim(entered_code))
    LIMIT 1
  ),
  current_quiz AS (
    SELECT q.id, q.quiz_title, q.topic, q.week_number, q.due_at,
           q.total_questions, q.pass_mark
    FROM public.history_quizzes q
    JOIN pupil p ON p.year_group = q.year_group
    WHERE q.is_published IS TRUE
    ORDER BY q.created_at DESC NULLS LAST, q.id DESC
    LIMIT 1
  )
  SELECT
    (p.pupil_id IS NOT NULL) AS valid_code,
    p.class_name,
    p.year_group,
    q.id AS quiz_id,
    q.quiz_title,
    q.topic,
    q.week_number,
    q.due_at,
    q.total_questions,
    q.pass_mark,
    COALESCE(s.attempts_taken, 0)::integer AS attempts_taken,
    s.highest_score,
    COALESCE(s.passed, FALSE) AS passed,
    CASE WHEN COALESCE(s.passed, FALSE) THEN NULL::uuid
         ELSE unfinished.id END AS unfinished_attempt_id
  FROM (SELECT 1) seed
  LEFT JOIN pupil p ON TRUE
  LEFT JOIN current_quiz q ON TRUE
  LEFT JOIN LATERAL (
    SELECT COUNT(*) FILTER (WHERE a.status = 'completed')::integer AS attempts_taken,
           MAX(a.score) FILTER (WHERE a.status = 'completed')::integer AS highest_score,
           COALESCE(BOOL_OR(a.status = 'completed' AND a.score >= q.pass_mark), FALSE) AS passed
    FROM public.history_attempts a
    WHERE a.pupil_id = p.pupil_id AND a.quiz_id = q.id
  ) s ON TRUE
  LEFT JOIN LATERAL (
    SELECT a.id
    FROM public.history_attempts a
    WHERE a.pupil_id = p.pupil_id AND a.quiz_id = q.id
      AND a.status = 'in_progress'
    ORDER BY a.started_at DESC NULLS LAST, a.id DESC
    LIMIT 1
  ) unfinished ON TRUE;
$function$;

REVOKE ALL ON FUNCTION homework_private.get_current_pupil_homework(entered_code text) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION homework_api.get_current_pupil_homework(entered_code text)
RETURNS TABLE(valid_code boolean, class_name text, year_group integer, quiz_id uuid, quiz_title text, topic text, week_number integer, due_at timestamp with time zone, total_questions integer, pass_mark integer, attempts_taken integer, highest_score integer, passed boolean, unfinished_attempt_id uuid)
LANGUAGE sql SECURITY INVOKER SET search_path = ''
AS $wrapper$ SELECT * FROM homework_private.get_current_pupil_homework($1); $wrapper$;

REVOKE ALL ON FUNCTION homework_api.get_current_pupil_homework(entered_code text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION homework_api.get_current_pupil_homework(entered_code text) TO anon;

GRANT EXECUTE ON FUNCTION homework_private.get_current_pupil_homework(entered_code text) TO anon;

ALTER FUNCTION homework_api.get_pupil_attempt_status(entered_code text, entered_quiz_id uuid) SET SCHEMA homework_private;

CREATE OR REPLACE FUNCTION homework_private.get_pupil_attempt_status(entered_code text, entered_quiz_id uuid)
 RETURNS TABLE(quiz_id uuid, attempts integer, highest_score integer, passed boolean, unfinished_attempt_id uuid, unfinished_attempt_token uuid, next_question integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_pupil uuid;
BEGIN
  SELECT p.id INTO v_pupil
  FROM public.history_pupils p
  WHERE p.pupil_code = pg_catalog.upper(pg_catalog.btrim(entered_code));
  IF v_pupil IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.history_quizzes q
    WHERE q.id = entered_quiz_id AND q.is_published = true
  ) THEN
    RAISE EXCEPTION 'Pupil or published quiz not found';
  END IF;
  RETURN QUERY
  SELECT entered_quiz_id,
    (SELECT count(*)::integer FROM public.history_attempts a
      WHERE a.pupil_id = v_pupil AND a.quiz_id = entered_quiz_id AND a.status = 'completed'),
    (SELECT max(a.score) FROM public.history_attempts a
      WHERE a.pupil_id = v_pupil AND a.quiz_id = entered_quiz_id AND a.status = 'completed'),
    EXISTS (SELECT 1 FROM public.history_attempts a
      JOIN public.history_quizzes q ON q.id = a.quiz_id
      WHERE a.pupil_id = v_pupil AND a.quiz_id = entered_quiz_id
        AND a.status = 'completed' AND a.score >= q.pass_mark),
    (SELECT a.id FROM public.history_attempts a
      WHERE a.pupil_id = v_pupil AND a.quiz_id = entered_quiz_id AND a.status = 'in_progress'
      ORDER BY a.started_at DESC, a.id DESC LIMIT 1),
    (SELECT a.attempt_token FROM public.history_attempts a
      WHERE a.pupil_id = v_pupil AND a.quiz_id = entered_quiz_id AND a.status = 'in_progress'
      ORDER BY a.started_at DESC, a.id DESC LIMIT 1),
    (SELECT a.question_position FROM public.history_attempts a
      WHERE a.pupil_id = v_pupil AND a.quiz_id = entered_quiz_id AND a.status = 'in_progress'
      ORDER BY a.started_at DESC, a.id DESC LIMIT 1);
END;
$function$;

REVOKE ALL ON FUNCTION homework_private.get_pupil_attempt_status(entered_code text, entered_quiz_id uuid) FROM PUBLIC, anon, authenticated, service_role;

ALTER FUNCTION homework_api.get_pupil_questions(entered_attempt_id uuid, entered_attempt_token uuid) SET SCHEMA homework_private;

CREATE OR REPLACE FUNCTION homework_private.get_pupil_questions(entered_attempt_id uuid, entered_attempt_token uuid)
 RETURNS TABLE(question_number integer, question_text text, answer_options jsonb, time_allowed_seconds integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF NOT homework_private.check_published_attempt(
    entered_attempt_id,
    entered_attempt_token
  ) THEN
    RAISE EXCEPTION 'Quiz is not available';
  END IF;

  RETURN QUERY
  SELECT
    q.question_number,
    q.question_text,
    q.answer_options,
    q.time_allowed_seconds
  FROM public.history_questions q
  JOIN public.history_attempts a
    ON a.quiz_id = q.quiz_id
  WHERE a.id = entered_attempt_id
    AND a.attempt_token = entered_attempt_token
  ORDER BY q.question_number;
END;
$function$;

REVOKE ALL ON FUNCTION homework_private.get_pupil_questions(entered_attempt_id uuid, entered_attempt_token uuid) FROM PUBLIC, anon, authenticated, service_role;

ALTER FUNCTION homework_api.mark_quiz_test(entered_quiz_id uuid, submitted_answers jsonb) SET SCHEMA homework_private;

CREATE OR REPLACE FUNCTION homework_private.mark_quiz_test(entered_quiz_id uuid, submitted_answers jsonb)
 RETURNS TABLE(score integer, total_questions integer, passed boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    expected_count integer;
    calculated_score integer;
    required_mark integer;
BEGIN
    IF jsonb_typeof(submitted_answers) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'Answers must be an array';
    END IF;

    SELECT q.total_questions, q.pass_mark
    INTO expected_count, required_mark
    FROM public.history_quizzes q
    WHERE q.id = entered_quiz_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Quiz not found';
    END IF;

    IF jsonb_array_length(submitted_answers) <> expected_count THEN
        RAISE EXCEPTION 'Incorrect number of answers';
    END IF;

    SELECT COUNT(*)::integer
    INTO calculated_score
    FROM public.history_questions q
    WHERE q.quiz_id = entered_quiz_id
      AND EXISTS (
          SELECT 1
          FROM jsonb_array_elements(submitted_answers) WITH ORDINALITY AS a(answer, position)
          WHERE a.position = q.question_number
            AND a.answer = q.correct_answer
      );

    RETURN QUERY
    SELECT calculated_score, expected_count,
           calculated_score >= required_mark;
END;
$function$;

REVOKE ALL ON FUNCTION homework_private.mark_quiz_test(entered_quiz_id uuid, submitted_answers jsonb) FROM PUBLIC, anon, authenticated, service_role;

ALTER FUNCTION homework_api.mark_test_answer(entered_question_id uuid, entered_answer integer) SET SCHEMA homework_private;

CREATE OR REPLACE FUNCTION homework_private.mark_test_answer(entered_question_id uuid, entered_answer integer)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM public.history_questions
        WHERE id = entered_question_id
          AND correct_answer = to_jsonb(entered_answer)
    );
$function$;

REVOKE ALL ON FUNCTION homework_private.mark_test_answer(entered_question_id uuid, entered_answer integer) FROM PUBLIC, anon, authenticated, service_role;

ALTER FUNCTION homework_api.open_pupil_question(entered_attempt_id uuid, entered_attempt_token uuid) SET SCHEMA homework_private;

CREATE OR REPLACE FUNCTION homework_private.open_pupil_question(entered_attempt_id uuid, entered_attempt_token uuid)
 RETURNS TABLE(question_number integer, question_text text, answer_options jsonb, time_allowed_seconds integer, seconds_remaining integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  a record;
  q record;
  question_uuid uuid;
  order_json jsonb;
  shuffled_options jsonb;
  remaining integer;
BEGIN
  SELECT at.* INTO a FROM public.history_attempts at
  JOIN public.history_quizzes z ON z.id = at.quiz_id
  WHERE at.id = entered_attempt_id AND at.attempt_token = entered_attempt_token
    AND at.status = 'in_progress' AND z.is_published IS TRUE
  FOR UPDATE OF at;
  IF NOT FOUND THEN RAISE EXCEPTION 'Invalid or inactive quiz session'; END IF;
  PERFORM homework_private._ensure_attempt_shuffle(a.id);
  SELECT at.* INTO a FROM public.history_attempts at WHERE at.id = a.id;
  IF a.question_position > (SELECT z.total_questions FROM public.history_quizzes z WHERE z.id=a.quiz_id) THEN
    RAISE EXCEPTION 'All questions answered; complete the quiz';
  END IF;
  question_uuid := (a.saved_progress->'question_ids'->>(a.question_position - 1))::uuid;
  order_json := a.saved_progress->'option_orders'->(a.question_position - 1);
  SELECT h.* INTO q FROM public.history_questions h
  WHERE h.id = question_uuid AND h.quiz_id = a.quiz_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Question not found'; END IF;
  IF a.question_started_at IS NULL THEN
    UPDATE public.history_attempts at SET question_started_at = pg_catalog.clock_timestamp()
    WHERE at.id = a.id RETURNING at.question_started_at INTO a.question_started_at;
  END IF;
  SELECT pg_catalog.jsonb_agg(q.answer_options->((v.i)::integer) ORDER BY v.pos)
  INTO shuffled_options
  FROM pg_catalog.jsonb_array_elements_text(order_json) WITH ORDINALITY AS v(i,pos);
  remaining := GREATEST(0, pg_catalog.ceil(
    EXTRACT(EPOCH FROM (a.question_started_at +
      pg_catalog.make_interval(secs => q.time_allowed_seconds) - pg_catalog.clock_timestamp()))
  )::integer);
  RETURN QUERY SELECT a.question_position, q.question_text, shuffled_options,
                      q.time_allowed_seconds, remaining;
END;
$function$;

REVOKE ALL ON FUNCTION homework_private.open_pupil_question(entered_attempt_id uuid, entered_attempt_token uuid) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION homework_api.open_pupil_question(entered_attempt_id uuid, entered_attempt_token uuid)
RETURNS TABLE(question_number integer, question_text text, answer_options jsonb, time_allowed_seconds integer, seconds_remaining integer)
LANGUAGE sql SECURITY INVOKER SET search_path = ''
AS $wrapper$ SELECT * FROM homework_private.open_pupil_question($1, $2); $wrapper$;

REVOKE ALL ON FUNCTION homework_api.open_pupil_question(entered_attempt_id uuid, entered_attempt_token uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION homework_api.open_pupil_question(entered_attempt_id uuid, entered_attempt_token uuid) TO anon;

GRANT EXECUTE ON FUNCTION homework_private.open_pupil_question(entered_attempt_id uuid, entered_attempt_token uuid) TO anon;

ALTER FUNCTION homework_api.save_marked_test_attempt(entered_pupil_code text, entered_quiz_id uuid, submitted_answers jsonb) SET SCHEMA homework_private;

CREATE OR REPLACE FUNCTION homework_private.save_marked_test_attempt(entered_pupil_code text, entered_quiz_id uuid, submitted_answers jsonb)
 RETURNS TABLE(attempt_number integer, score integer, total_questions integer, passed boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_pupil_id uuid;
    v_pupil_year integer;
    v_quiz_year integer;
    v_expected integer;
    v_pass_mark integer;
    v_question_count integer;
    v_score integer;
    v_attempt_number integer;
    v_attempt_id uuid;
BEGIN
    IF jsonb_typeof(submitted_answers) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'Answers must be a JSON array';
    END IF;

    SELECT p.id, c.year_group
    INTO v_pupil_id, v_pupil_year
    FROM public.history_pupils AS p
    JOIN public.history_classes AS c ON c.id = p.class_id
    WHERE p.pupil_code = entered_pupil_code;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Fictional pupil code not found';
    END IF;

    SELECT q.year_group, q.total_questions, q.pass_mark
    INTO v_quiz_year, v_expected, v_pass_mark
    FROM public.history_quizzes AS q
    WHERE q.id = entered_quiz_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Quiz not found';
    END IF;
    IF v_pupil_year <> v_quiz_year THEN
        RAISE EXCEPTION 'Pupil and quiz year groups do not match';
    END IF;
    IF v_expected <> 25 OR jsonb_array_length(submitted_answers) <> v_expected THEN
        RAISE EXCEPTION 'Exactly 25 answers are required for this test';
    END IF;

    SELECT count(*)::integer INTO v_question_count
    FROM public.history_questions AS q
    WHERE q.quiz_id = entered_quiz_id;
    IF v_question_count <> v_expected THEN
        RAISE EXCEPTION 'Quiz question count does not match its settings';
    END IF;

    -- This test version handles the current multiple-choice quiz only.
    -- Validate each answer as an integer from 0 to 3 before saving anything.
    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(submitted_answers) AS a(answer)
        WHERE jsonb_typeof(a.answer) <> 'number'
           OR a.answer::text NOT IN ('0', '1', '2', '3')
    ) THEN
        RAISE EXCEPTION 'Every answer must be an option number from 0 to 3';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.history_questions AS q
        WHERE q.quiz_id = entered_quiz_id AND q.question_type <> 'multiple_choice'
    ) THEN
        RAISE EXCEPTION 'This test function only supports multiple-choice questions';
    END IF;

    SELECT count(*)::integer INTO v_score
    FROM public.history_questions AS q
    JOIN LATERAL (
        SELECT a.answer
        FROM jsonb_array_elements(submitted_answers) WITH ORDINALITY AS a(answer, position)
        WHERE a.position = q.question_number
    ) AS response ON true
    WHERE q.quiz_id = entered_quiz_id
      AND response.answer = q.correct_answer;

    -- Serialize attempts for this pupil/quiz so numbering cannot race.
    PERFORM 1 FROM public.history_pupils WHERE id = v_pupil_id FOR UPDATE;
    SELECT coalesce(max(a.attempt_number), 0) + 1
    INTO v_attempt_number
    FROM public.history_attempts AS a
    WHERE a.pupil_id = v_pupil_id AND a.quiz_id = entered_quiz_id;

    INSERT INTO public.history_attempts
      (pupil_id, quiz_id, attempt_number, status, score, question_position, completed_at)
    VALUES
      (v_pupil_id, entered_quiz_id, v_attempt_number, 'completed', v_score, 25, now())
    RETURNING id INTO v_attempt_id;

    INSERT INTO public.history_answers
      (attempt_id, question_number, question_id, pupil_answer, is_correct, time_allowed_seconds)
    SELECT
      v_attempt_id, q.question_number, q.id::text, response.answer,
      response.answer = q.correct_answer, q.time_allowed_seconds
    FROM public.history_questions AS q
    JOIN LATERAL (
        SELECT a.answer
        FROM jsonb_array_elements(submitted_answers) WITH ORDINALITY AS a(answer, position)
        WHERE a.position = q.question_number
    ) AS response ON true
    WHERE q.quiz_id = entered_quiz_id;

    RETURN QUERY SELECT v_attempt_number, v_score, v_expected, (v_score >= v_pass_mark);
END;
$function$;

REVOKE ALL ON FUNCTION homework_private.save_marked_test_attempt(entered_pupil_code text, entered_quiz_id uuid, submitted_answers jsonb) FROM PUBLIC, anon, authenticated, service_role;

ALTER FUNCTION homework_api.save_quiz_result(entered_code text, entered_quiz_id uuid, entered_score integer) SET SCHEMA homework_private;

CREATE OR REPLACE FUNCTION homework_private.save_quiz_result(entered_code text, entered_quiz_id uuid, entered_score integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  found_pupil_id uuid;
  next_attempt integer;
  new_attempt_id uuid;
BEGIN

  -- Only accept a valid score out of 25.
  IF entered_score IS NULL
     OR entered_score < 0
     OR entered_score > 25 THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Invalid score'
    );
  END IF;

  -- Check the fictional pupil code.
  SELECT id INTO found_pupil_id
  FROM public.history_pupils
  WHERE pupil_code = upper(trim(entered_code));

  IF found_pupil_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Invalid pupil code'
    );
  END IF;

  -- Check the quiz exists and belongs to the pupil's year.
  IF NOT EXISTS (
    SELECT 1
    FROM public.history_quizzes q
    JOIN public.history_pupils p
      ON p.id = found_pupil_id
    JOIN public.history_classes c
      ON c.id = p.class_id
    WHERE q.id = entered_quiz_id
      AND q.year_group = c.year_group
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Quiz not available for this pupil'
    );
  END IF;

  -- Find the next completed attempt number.
  SELECT COALESCE(MAX(attempt_number), 0) + 1
  INTO next_attempt
  FROM public.history_attempts
  WHERE pupil_id = found_pupil_id
    AND quiz_id = entered_quiz_id;

  -- Save the completed result.
  INSERT INTO public.history_attempts (
    pupil_id,
    quiz_id,
    attempt_number,
    status,
    score,
    completed_at
  )
  VALUES (
    found_pupil_id,
    entered_quiz_id,
    next_attempt,
    'completed',
    entered_score,
    now()
  )
  RETURNING id INTO new_attempt_id;

  RETURN jsonb_build_object(
    'success', true,
    'attempt_id', new_attempt_id,
    'attempt_number', next_attempt,
    'score', entered_score,
    'passed', entered_score >= 20
  );

END;
$function$;

REVOKE ALL ON FUNCTION homework_private.save_quiz_result(entered_code text, entered_quiz_id uuid, entered_score integer) FROM PUBLIC, anon, authenticated, service_role;

ALTER FUNCTION homework_api.set_question_start_time() SET SCHEMA homework_private;

CREATE OR REPLACE FUNCTION homework_private.set_question_start_time()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.question_started_at := NULL;

  ELSIF NEW.question_position
        IS DISTINCT FROM OLD.question_position THEN
    NEW.question_started_at := NULL;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION homework_private.set_question_start_time() FROM PUBLIC, anon, authenticated, service_role;

ALTER FUNCTION homework_api.start_pupil_quiz(entered_code text, entered_quiz_id uuid) SET SCHEMA homework_private;

CREATE OR REPLACE FUNCTION homework_private.start_pupil_quiz(entered_code text, entered_quiz_id uuid)
 RETURNS TABLE(attempt_id uuid, attempt_token uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  found_pupil_id uuid;
  pupil_year integer;
  current_quiz_id uuid;
  next_attempt_number integer;
  existing_attempt_id uuid;
  fresh_token uuid;
BEGIN
  SELECT p.id, c.year_group
    INTO found_pupil_id, pupil_year
  FROM public.history_pupils p
  JOIN public.history_classes c ON c.id = p.class_id
  WHERE p.pupil_code = pg_catalog.upper(pg_catalog.btrim(entered_code));

  IF found_pupil_id IS NULL THEN
    RAISE EXCEPTION 'Pupil code not found';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(found_pupil_id::text),
    pg_catalog.hashtext(entered_quiz_id::text)
  );

  -- Match the published, most recently created quiz for this pupil's year.
  SELECT q.id INTO current_quiz_id
  FROM public.history_quizzes q
  WHERE q.year_group = pupil_year AND q.is_published IS TRUE
  ORDER BY q.created_at DESC NULLS LAST, q.id DESC
  LIMIT 1;

  IF current_quiz_id IS NULL OR current_quiz_id <> entered_quiz_id THEN
    RAISE EXCEPTION 'Quiz is not available for this pupil';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.history_attempts a
    JOIN public.history_quizzes q ON q.id = a.quiz_id
    WHERE a.pupil_id = found_pupil_id
      AND a.quiz_id = entered_quiz_id
      AND a.status = 'completed'
      AND a.score >= q.pass_mark
  ) THEN
    RAISE EXCEPTION 'Homework already passed';
  END IF;

  SELECT a.id INTO existing_attempt_id
  FROM public.history_attempts a
  WHERE a.pupil_id = found_pupil_id
    AND a.quiz_id = entered_quiz_id
    AND a.status = 'in_progress'
  ORDER BY a.started_at DESC NULLS LAST, a.id DESC
  LIMIT 1
  FOR UPDATE;

  IF existing_attempt_id IS NOT NULL THEN
    -- Rotate token: a second device taking over invalidates the first.
    -- No questions or answers are deleted; progress is retained.
    fresh_token := pg_catalog.gen_random_uuid();
    UPDATE public.history_attempts a
    SET attempt_token = fresh_token,
        question_started_at = NULL
    WHERE a.id = existing_attempt_id;
    RETURN QUERY SELECT existing_attempt_id, fresh_token;
    RETURN;
  END IF;

  SELECT COALESCE(MAX(a.attempt_number), 0) + 1
  INTO next_attempt_number
  FROM public.history_attempts a
  WHERE a.pupil_id = found_pupil_id AND a.quiz_id = entered_quiz_id;

  RETURN QUERY
  INSERT INTO public.history_attempts (
    pupil_id, quiz_id, attempt_number, status, score, question_position
  ) VALUES (
    found_pupil_id, entered_quiz_id, next_attempt_number,
    'in_progress', NULL, 1
  )
  RETURNING history_attempts.id, history_attempts.attempt_token;
END;
$function$;

REVOKE ALL ON FUNCTION homework_private.start_pupil_quiz(entered_code text, entered_quiz_id uuid) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION homework_api.start_pupil_quiz(entered_code text, entered_quiz_id uuid)
RETURNS TABLE(attempt_id uuid, attempt_token uuid)
LANGUAGE sql SECURITY INVOKER SET search_path = ''
AS $wrapper$ SELECT * FROM homework_private.start_pupil_quiz($1, $2); $wrapper$;

REVOKE ALL ON FUNCTION homework_api.start_pupil_quiz(entered_code text, entered_quiz_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION homework_api.start_pupil_quiz(entered_code text, entered_quiz_id uuid) TO anon;

GRANT EXECUTE ON FUNCTION homework_private.start_pupil_quiz(entered_code text, entered_quiz_id uuid) TO anon;

ALTER FUNCTION homework_api.start_quiz_test(entered_code text, entered_quiz_id uuid) SET SCHEMA homework_private;

CREATE OR REPLACE FUNCTION homework_private.start_quiz_test(entered_code text, entered_quiz_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  found_pupil_id uuid;
  new_attempt_id uuid;
  next_attempt_number integer;
BEGIN
  SELECT p.id
  INTO found_pupil_id
  FROM public.history_pupils p
  WHERE p.pupil_code = upper(trim(entered_code));

  IF found_pupil_id IS NULL THEN
    RAISE EXCEPTION 'Pupil code not found';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.history_quizzes q
    WHERE q.id = entered_quiz_id
  ) THEN
    RAISE EXCEPTION 'Quiz not found';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(found_pupil_id::text),
    pg_catalog.hashtext(entered_quiz_id::text)
  );

  SELECT COALESCE(MAX(a.attempt_number), 0) + 1
  INTO next_attempt_number
  FROM public.history_attempts a
  WHERE a.pupil_id = found_pupil_id
    AND a.quiz_id = entered_quiz_id;

  INSERT INTO public.history_attempts (
    pupil_id,
    quiz_id,
    attempt_number,
    status,
    score,
    question_position
  )
  VALUES (
    found_pupil_id,
    entered_quiz_id,
    next_attempt_number,
    'in_progress',
    NULL,
    1
  )
  RETURNING id INTO new_attempt_id;

  RETURN new_attempt_id;
END;
$function$;

REVOKE ALL ON FUNCTION homework_private.start_quiz_test(entered_code text, entered_quiz_id uuid) FROM PUBLIC, anon, authenticated, service_role;

ALTER FUNCTION homework_api.submit_answer_test(entered_attempt_id uuid, entered_answer integer) SET SCHEMA homework_private;

CREATE OR REPLACE FUNCTION homework_private.submit_answer_test(entered_attempt_id uuid, entered_answer integer)
 RETURNS TABLE(answer_correct boolean, correct_option integer, feedback text, next_question integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  a record;
  q record;
  marked_correct boolean;
  correct_index integer;
  next_position integer;
BEGIN
  SELECT *
  INTO a
  FROM public.history_attempts
  WHERE id = entered_attempt_id
  FOR UPDATE;

  IF NOT FOUND OR a.status <> 'in_progress' THEN
    RAISE EXCEPTION 'No active quiz attempt found';
  END IF;

  IF a.question_position NOT BETWEEN 1 AND 25 THEN
    RAISE EXCEPTION 'Invalid question position';
  END IF;

  SELECT *
  INTO q
  FROM public.history_questions
  WHERE quiz_id = a.quiz_id
    AND question_number = a.question_position;

  IF NOT FOUND OR q.question_type <> 'multiple_choice' THEN
    RAISE EXCEPTION 'Supported question not found';
  END IF;

  IF jsonb_typeof(q.correct_answer) <> 'number' THEN
    RAISE EXCEPTION 'Unsupported answer format';
  END IF;

  correct_index := (q.correct_answer #>> '{}')::integer;

  IF entered_answer IS NOT NULL
     AND entered_answer NOT BETWEEN 0 AND 3 THEN
    RAISE EXCEPTION 'Invalid answer option';
  END IF;

  marked_correct :=
    COALESCE(entered_answer = correct_index, false);

  INSERT INTO public.history_answers (
    attempt_id,
    question_number,
    question_id,
    pupil_answer,
    is_correct,
    time_allowed_seconds
  )
  VALUES (
    a.id,
    a.question_position,
    q.id::text,
    COALESCE(to_jsonb(entered_answer), 'null'::jsonb),
    marked_correct,
    q.time_allowed_seconds
  );

  next_position := LEAST(a.question_position + 1, 25);

  UPDATE public.history_attempts
  SET question_position = next_position
  WHERE id = a.id;

  RETURN QUERY SELECT
    marked_correct,
    correct_index,
    q.explanation,
    next_position;
END;
$function$;

REVOKE ALL ON FUNCTION homework_private.submit_answer_test(entered_attempt_id uuid, entered_answer integer) FROM PUBLIC, anon, authenticated, service_role;

ALTER FUNCTION homework_api.submit_pupil_answer(entered_attempt_id uuid, entered_attempt_token uuid, entered_answer integer) SET SCHEMA homework_private;

CREATE OR REPLACE FUNCTION homework_private.submit_pupil_answer(entered_attempt_id uuid, entered_attempt_token uuid, entered_answer integer)
 RETURNS TABLE(answer_correct boolean, correct_option integer, feedback text, next_question integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  a record;
  q record;
  order_json jsonb;
  question_uuid uuid;
  original_answer integer;
  original_correct integer;
  display_correct integer;
  expired boolean;
  marked_correct boolean;
  total integer;
BEGIN
  SELECT at.* INTO a FROM public.history_attempts at
  JOIN public.history_quizzes z ON z.id = at.quiz_id
  WHERE at.id = entered_attempt_id AND at.attempt_token = entered_attempt_token
    AND at.status = 'in_progress' AND z.is_published IS TRUE
  FOR UPDATE OF at;
  IF NOT FOUND THEN RAISE EXCEPTION 'Invalid or inactive quiz session'; END IF;
  IF a.question_started_at IS NULL THEN RAISE EXCEPTION 'Open the question first'; END IF;
  SELECT z.total_questions INTO total FROM public.history_quizzes z WHERE z.id=a.quiz_id;
  IF a.question_position > total THEN RAISE EXCEPTION 'All questions answered'; END IF;
  IF entered_answer IS NOT NULL AND (entered_answer < 0 OR entered_answer > 3) THEN
    RAISE EXCEPTION 'Answer must be 0 to 3';
  END IF;
  question_uuid := (a.saved_progress->'question_ids'->>(a.question_position - 1))::uuid;
  order_json := a.saved_progress->'option_orders'->(a.question_position - 1);
  SELECT h.* INTO q FROM public.history_questions h
  WHERE h.id = question_uuid AND h.quiz_id=a.quiz_id;
  IF NOT FOUND OR q.question_type <> 'multiple_choice' THEN
    RAISE EXCEPTION 'Question unavailable';
  END IF;
  original_correct := (q.correct_answer #>> '{}')::integer;
  SELECT (v.i)::integer - 1 INTO display_correct
  FROM pg_catalog.jsonb_array_elements_text(order_json) WITH ORDINALITY AS v(val,i)
  WHERE (v.val)::integer = original_correct;
  IF display_correct IS NULL THEN RAISE EXCEPTION 'Invalid answer configuration'; END IF;
  original_answer := CASE WHEN entered_answer IS NULL THEN NULL
                          ELSE (order_json->>entered_answer)::integer END;
  expired := pg_catalog.clock_timestamp() >
    a.question_started_at + pg_catalog.make_interval(secs => q.time_allowed_seconds + 5);
  marked_correct := NOT expired AND original_answer IS NOT NULL
                    AND original_answer = original_correct;
  INSERT INTO public.history_answers
    (attempt_id, question_number, question_id, pupil_answer, is_correct, time_allowed_seconds)
  VALUES (a.id, a.question_position, q.id::text,
          CASE WHEN entered_answer IS NULL THEN 'null'::jsonb
               ELSE pg_catalog.to_jsonb(entered_answer) END,
          marked_correct, q.time_allowed_seconds);
  -- Critical: each question must get its OWN timer.
  UPDATE public.history_attempts at
  SET question_position = LEAST(a.question_position + 1, total),
      question_started_at = NULL
  WHERE at.id = a.id;
  RETURN QUERY SELECT marked_correct, display_correct, q.explanation,
                      LEAST(a.question_position + 1, total);
END;
$function$;

REVOKE ALL ON FUNCTION homework_private.submit_pupil_answer(entered_attempt_id uuid, entered_attempt_token uuid, entered_answer integer) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION homework_api.submit_pupil_answer(entered_attempt_id uuid, entered_attempt_token uuid, entered_answer integer)
RETURNS TABLE(answer_correct boolean, correct_option integer, feedback text, next_question integer)
LANGUAGE sql SECURITY INVOKER SET search_path = ''
AS $wrapper$ SELECT * FROM homework_private.submit_pupil_answer($1, $2, $3); $wrapper$;

REVOKE ALL ON FUNCTION homework_api.submit_pupil_answer(entered_attempt_id uuid, entered_attempt_token uuid, entered_answer integer) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION homework_api.submit_pupil_answer(entered_attempt_id uuid, entered_attempt_token uuid, entered_answer integer) TO anon;

GRANT EXECUTE ON FUNCTION homework_private.submit_pupil_answer(entered_attempt_id uuid, entered_attempt_token uuid, entered_answer integer) TO anon;

-- Teacher reads run under RLS instead of owner privileges.

ALTER FUNCTION public.is_history_teacher() SECURITY INVOKER;

ALTER FUNCTION public.get_history_class_results(text, uuid) SECURITY INVOKER;

REVOKE ALL ON FUNCTION public.is_history_teacher() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_history_class_results(text, uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.is_history_teacher() TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_history_class_results(text, uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.rls_auto_enable() FROM PUBLIC, anon, authenticated, service_role;

-- RLS does not govern TRUNCATE. Remove unused DML/maintenance grants as well.

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, authenticated;

GRANT SELECT ON public.history_classes, public.history_pupils, public.history_quizzes, public.history_attempts, public.history_teacher_classes, public.history_teachers TO authenticated;

CREATE POLICY "Approved teachers can read their own approval" ON public.history_teachers
FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));

CREATE POLICY "Legacy attempts are not an API" ON public.history_quiz_attempts
FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);

-- Future objects need deliberate grants, not factory grants to public callers.

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES FROM anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA homework_api REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
