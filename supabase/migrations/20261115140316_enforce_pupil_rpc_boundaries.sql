-- New local security fixes from the required adversarial tests (T7/T8/T10/T11).

-- Hosted application still requires explicit owner approval.

-- Preserve the active question deadline when rotating a resumed attempt token.

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
    SET attempt_token = fresh_token
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

-- Reject a correct answer immediately after the displayed server deadline.

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
    a.question_started_at + pg_catalog.make_interval(secs => q.time_allowed_seconds);
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

-- Text/JSON boundary inputs let us reject malformed values without PostgreSQL type errors.

-- Successful JSON requests and response fields keep their existing page-facing contract.

DROP FUNCTION homework_api.open_pupil_question(entered_attempt_id uuid, entered_attempt_token uuid);

CREATE FUNCTION homework_api.open_pupil_question(entered_attempt_id text DEFAULT NULL, entered_attempt_token text DEFAULT NULL)
RETURNS TABLE(question_number integer, question_text text, answer_options jsonb, time_allowed_seconds integer, seconds_remaining integer)
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $boundary$
DECLARE v_id uuid; v_token uuid;
BEGIN
  IF entered_attempt_id IS NULL OR entered_attempt_token IS NULL
     OR length(entered_attempt_id) > 36 OR length(entered_attempt_token) > 36 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'Invalid or inactive quiz session';
  END IF;
  BEGIN
    v_id := entered_attempt_id::uuid;
    v_token := entered_attempt_token::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'Invalid or inactive quiz session';
  END;

  RETURN QUERY SELECT * FROM homework_private.open_pupil_question(v_id, v_token);
END;
$boundary$;

REVOKE ALL ON FUNCTION homework_api.open_pupil_question(text, text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION homework_api.open_pupil_question(text, text) TO anon;

DROP FUNCTION homework_api.submit_pupil_answer(entered_attempt_id uuid, entered_attempt_token uuid, entered_answer integer);

CREATE FUNCTION homework_api.submit_pupil_answer(entered_attempt_id text DEFAULT NULL, entered_attempt_token text DEFAULT NULL, entered_answer jsonb DEFAULT NULL)
RETURNS TABLE(answer_correct boolean, correct_option integer, feedback text, next_question integer)
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $boundary$
DECLARE v_id uuid; v_token uuid; v_answer integer;
BEGIN
  IF entered_attempt_id IS NULL OR entered_attempt_token IS NULL
     OR length(entered_attempt_id) > 36 OR length(entered_attempt_token) > 36 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'Invalid or inactive quiz session';
  END IF;
  BEGIN
    v_id := entered_attempt_id::uuid;
    v_token := entered_attempt_token::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'Invalid or inactive quiz session';
  END;
  IF entered_answer IS NULL OR entered_answer = 'null'::jsonb THEN
    v_answer := NULL;
  ELSIF jsonb_typeof(entered_answer) = 'number'
        AND entered_answer::text IN ('0','1','2','3') THEN
    v_answer := entered_answer::text::integer;
  ELSE
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'Answer must be 0 to 3';
  END IF;

  RETURN QUERY SELECT * FROM homework_private.submit_pupil_answer(v_id, v_token, v_answer);
END;
$boundary$;

REVOKE ALL ON FUNCTION homework_api.submit_pupil_answer(text, text, jsonb) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION homework_api.submit_pupil_answer(text, text, jsonb) TO anon;

DROP FUNCTION homework_api.complete_pupil_quiz(entered_attempt_id uuid, entered_attempt_token uuid);

CREATE FUNCTION homework_api.complete_pupil_quiz(entered_attempt_id text DEFAULT NULL, entered_attempt_token text DEFAULT NULL)
RETURNS TABLE(final_score integer, total_questions integer, passed boolean)
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $boundary$
DECLARE v_id uuid; v_token uuid;
BEGIN
  IF entered_attempt_id IS NULL OR entered_attempt_token IS NULL
     OR length(entered_attempt_id) > 36 OR length(entered_attempt_token) > 36 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'Invalid or inactive quiz session';
  END IF;
  BEGIN
    v_id := entered_attempt_id::uuid;
    v_token := entered_attempt_token::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'Invalid or inactive quiz session';
  END;

  RETURN QUERY SELECT * FROM homework_private.complete_pupil_quiz(v_id, v_token);
END;
$boundary$;

REVOKE ALL ON FUNCTION homework_api.complete_pupil_quiz(text, text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION homework_api.complete_pupil_quiz(text, text) TO anon;

CREATE OR REPLACE FUNCTION homework_api.get_current_pupil_homework(entered_code text)
RETURNS TABLE(valid_code boolean, class_name text, year_group integer, quiz_id uuid, quiz_title text, topic text, week_number integer, due_at timestamp with time zone, total_questions integer, pass_mark integer, attempts_taken integer, highest_score integer, passed boolean, unfinished_attempt_id uuid)
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $boundary$
BEGIN
  IF entered_code IS NULL OR length(entered_code) > 256 OR btrim(entered_code) = '' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'Invalid pupil code';
  END IF;
  RETURN QUERY SELECT * FROM homework_private.get_current_pupil_homework(entered_code);
END;
$boundary$;

NOTIFY pgrst, 'reload schema';
