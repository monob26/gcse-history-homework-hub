-- R10: additive class-ID results API; preserve the old API for existing deployments.
CREATE OR REPLACE FUNCTION public.get_history_class_results_by_id(requested_class_id uuid, requested_quiz uuid)
 RETURNS TABLE(pupil_code text, register_number integer, attempts bigint, highest_score integer, homework_status text)
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
BEGIN
  IF NOT public.is_history_teacher() THEN
    RAISE EXCEPTION 'Teacher access required';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.history_teacher_classes tc
    JOIN public.history_classes c
      ON c.id = tc.class_id
    WHERE tc.user_id = (SELECT auth.uid())
      AND c.id = requested_class_id
  ) THEN
    RAISE EXCEPTION 'You are not allocated to this class';
  END IF;

  RETURN QUERY
  SELECT
    p.pupil_code,
    p.register_number,
    COUNT(a.id) FILTER (
      WHERE a.status = 'completed'
    ) AS attempts,
    MAX(a.score) FILTER (
      WHERE a.status = 'completed'
    ) AS highest_score,
    CASE
      WHEN MAX(a.score) FILTER (
        WHERE a.status = 'completed'
      ) >= q.pass_mark THEN 'Passed'
      WHEN COUNT(a.id) FILTER (
        WHERE a.status = 'completed'
      ) > 0 THEN 'Not passed'
      ELSE 'Not completed'
    END AS homework_status
  FROM public.history_pupils p
  JOIN public.history_classes c
    ON c.id = p.class_id
  JOIN public.history_quizzes q
    ON q.id = requested_quiz
    AND q.year_group = c.year_group
    AND q.is_published = true
  LEFT JOIN public.history_attempts a
    ON a.pupil_id = p.id
    AND a.quiz_id = q.id
  WHERE c.id = requested_class_id
  GROUP BY p.id, p.pupil_code, q.pass_mark
  ORDER BY p.register_number,p.pupil_code;
END;
$function$;
REVOKE ALL ON FUNCTION public.get_history_class_results_by_id(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_history_class_results_by_id(uuid,uuid) TO authenticated;


-- A saved final answer must lead to completion, never reopen that answered question.
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
  IF a.question_position > (SELECT z.total_questions FROM public.history_quizzes z WHERE z.id=a.quiz_id)
     OR EXISTS (SELECT 1 FROM public.history_answers ans
                WHERE ans.attempt_id=a.id AND ans.question_number=a.question_position) THEN
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


NOTIFY pgrst, 'reload schema';

-- Read-only question timing metadata, behind the same code validation/rate budget as home.
CREATE FUNCTION homework_private.get_pupil_quiz_timing(entered_code text, entered_quiz_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $timing$
DECLARE h record; timings jsonb;
BEGIN
  SELECT * INTO h FROM homework_private.get_current_pupil_homework(entered_code);
  IF h.valid_code IS DISTINCT FROM true OR h.quiz_id IS DISTINCT FROM entered_quiz_id THEN
    RETURN NULL;
  END IF;
  SELECT jsonb_agg(jsonb_build_object('seconds',x.seconds,'questions',x.questions) ORDER BY x.seconds)
  INTO timings FROM (
    SELECT q.time_allowed_seconds AS seconds,count(*) AS questions
    FROM public.history_questions q WHERE q.quiz_id=entered_quiz_id
    GROUP BY q.time_allowed_seconds
  ) x;
  RETURN jsonb_build_object('time_limits',timings);
END;
$timing$;
REVOKE ALL ON FUNCTION homework_private.get_pupil_quiz_timing(text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION homework_private.get_pupil_quiz_timing(text,uuid) TO anon;
CREATE FUNCTION homework_api.get_pupil_quiz_timing(entered_code text,entered_quiz_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $timing$
BEGIN
 IF entered_code IS NULL OR length(entered_code)>256 OR btrim(entered_code)='' THEN
   RAISE EXCEPTION 'Invalid pupil code';
 END IF;
 RETURN homework_private.get_pupil_quiz_timing(entered_code,entered_quiz_id);
END;
$timing$;
REVOKE ALL ON FUNCTION homework_api.get_pupil_quiz_timing(text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION homework_api.get_pupil_quiz_timing(text,uuid) TO anon;
NOTIFY pgrst, 'reload schema';
