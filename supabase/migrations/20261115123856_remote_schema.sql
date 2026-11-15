-- Schema-only baseline from read-only Supabase MCP catalog queries.

-- Source: inxsjdogxvqbvxydxmym; source commits: 3e3d852 / 6741666.

-- No application rows, Auth rows, passwords, keys, or sequence current values.

-- Baseline preserves the source; it is not a security remediation.

SET check_function_bodies = false;

SET search_path = public, extensions;

CREATE SCHEMA IF NOT EXISTS "public";

ALTER SCHEMA "public" OWNER TO "pg_database_owner";

CREATE SCHEMA IF NOT EXISTS "homework_api";

ALTER SCHEMA "homework_api" OWNER TO "postgres";

CREATE TABLE "public"."history_answers" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "attempt_id" uuid NOT NULL,
  "question_number" integer NOT NULL,
  "question_id" text NOT NULL,
  "pupil_answer" jsonb NOT NULL,
  "is_correct" boolean NOT NULL,
  "time_allowed_seconds" integer NOT NULL,
  "answered_at" timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE "public"."history_answers" OWNER TO "postgres";

CREATE TABLE "public"."history_attempts" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "pupil_id" uuid NOT NULL,
  "quiz_id" uuid NOT NULL,
  "attempt_number" integer NOT NULL,
  "status" text DEFAULT 'in_progress'::text NOT NULL,
  "score" integer,
  "question_position" integer DEFAULT 1 NOT NULL,
  "saved_progress" jsonb DEFAULT '{}'::jsonb NOT NULL,
  "started_at" timestamp with time zone DEFAULT now() NOT NULL,
  "completed_at" timestamp with time zone,
  "attempt_token" uuid DEFAULT gen_random_uuid() NOT NULL,
  "question_started_at" timestamp with time zone
);

ALTER TABLE "public"."history_attempts" OWNER TO "postgres";

CREATE TABLE "public"."history_classes" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "class_name" text NOT NULL,
  "year_group" integer NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE "public"."history_classes" OWNER TO "postgres";

CREATE TABLE "public"."history_pupils" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "pupil_code" text NOT NULL,
  "class_id" uuid NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE "public"."history_pupils" OWNER TO "postgres";

CREATE TABLE "public"."history_questions" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "quiz_id" uuid NOT NULL,
  "question_number" integer NOT NULL,
  "question_type" text NOT NULL,
  "question_text" text NOT NULL,
  "answer_options" jsonb DEFAULT '[]'::jsonb NOT NULL,
  "correct_answer" jsonb NOT NULL,
  "explanation" text NOT NULL,
  "time_allowed_seconds" integer DEFAULT 45 NOT NULL
);

ALTER TABLE "public"."history_questions" OWNER TO "postgres";

CREATE TABLE "public"."history_quiz_attempts" (
  "id" bigint GENERATED ALWAYS AS IDENTITY (SEQUENCE NAME "public"."history_quiz_attempts_id_seq" START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 NO CYCLE) NOT NULL,
  "pupil_code" text NOT NULL,
  "quiz_id" bigint NOT NULL,
  "attempt_number" integer NOT NULL,
  "score" integer NOT NULL,
  "total_questions" integer DEFAULT 25 NOT NULL,
  "passed" boolean NOT NULL,
  "completed_at" timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE "public"."history_quiz_attempts" OWNER TO "postgres";

CREATE TABLE "public"."history_quizzes" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "quiz_title" text NOT NULL,
  "year_group" integer NOT NULL,
  "topic" text NOT NULL,
  "week_number" integer NOT NULL,
  "due_at" timestamp with time zone,
  "total_questions" integer DEFAULT 25 NOT NULL,
  "pass_mark" integer DEFAULT 20 NOT NULL,
  "version_number" integer DEFAULT 1 NOT NULL,
  "is_published" boolean DEFAULT false NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE "public"."history_quizzes" OWNER TO "postgres";

CREATE TABLE "public"."history_teacher_classes" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "user_id" uuid NOT NULL,
  "class_id" uuid NOT NULL,
  "assigned_at" timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE "public"."history_teacher_classes" OWNER TO "postgres";

CREATE TABLE "public"."history_teachers" (
  "user_id" uuid NOT NULL,
  "approved_at" timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE "public"."history_teachers" OWNER TO "postgres";

ALTER TABLE "public"."history_answers" ADD CONSTRAINT "history_answers_attempt_id_question_number_key" UNIQUE (attempt_id, question_number);

ALTER TABLE "public"."history_answers" ADD CONSTRAINT "history_answers_pkey" PRIMARY KEY (id);

ALTER TABLE "public"."history_answers" ADD CONSTRAINT "history_answers_question_number_check" CHECK (question_number >= 1 AND question_number <= 25);

ALTER TABLE "public"."history_answers" ADD CONSTRAINT "history_answers_time_allowed_seconds_check" CHECK (time_allowed_seconds = ANY (ARRAY[45, 60]));

ALTER TABLE "public"."history_quiz_attempts" ADD CONSTRAINT "history_attempt_number_valid" CHECK (attempt_number >= 1);

ALTER TABLE "public"."history_quiz_attempts" ADD CONSTRAINT "history_attempt_pass_valid" CHECK (passed = (score >= 20));

ALTER TABLE "public"."history_quiz_attempts" ADD CONSTRAINT "history_attempt_score_valid" CHECK (score >= 0 AND score <= total_questions AND total_questions = 25);

ALTER TABLE "public"."history_attempts" ADD CONSTRAINT "history_attempts_attempt_number_check" CHECK (attempt_number > 0);

ALTER TABLE "public"."history_attempts" ADD CONSTRAINT "history_attempts_pkey" PRIMARY KEY (id);

ALTER TABLE "public"."history_attempts" ADD CONSTRAINT "history_attempts_pupil_id_quiz_id_attempt_number_key" UNIQUE (pupil_id, quiz_id, attempt_number);

ALTER TABLE "public"."history_attempts" ADD CONSTRAINT "history_attempts_question_position_check" CHECK (question_position >= 1 AND question_position <= 25);

ALTER TABLE "public"."history_attempts" ADD CONSTRAINT "history_attempts_score_check" CHECK (score >= 0 AND score <= 25);

ALTER TABLE "public"."history_attempts" ADD CONSTRAINT "history_attempts_status_check" CHECK (status = ANY (ARRAY['in_progress'::text, 'completed'::text]));

ALTER TABLE "public"."history_classes" ADD CONSTRAINT "history_classes_class_name_key" UNIQUE (class_name);

ALTER TABLE "public"."history_classes" ADD CONSTRAINT "history_classes_pkey" PRIMARY KEY (id);

ALTER TABLE "public"."history_classes" ADD CONSTRAINT "history_classes_year_group_check" CHECK (year_group = ANY (ARRAY[9, 10, 11]));

ALTER TABLE "public"."history_pupils" ADD CONSTRAINT "history_pupils_pkey" PRIMARY KEY (id);

ALTER TABLE "public"."history_pupils" ADD CONSTRAINT "history_pupils_pupil_code_key" UNIQUE (pupil_code);

ALTER TABLE "public"."history_questions" ADD CONSTRAINT "history_questions_pkey" PRIMARY KEY (id);

ALTER TABLE "public"."history_questions" ADD CONSTRAINT "history_questions_question_number_check" CHECK (question_number >= 1 AND question_number <= 25);

ALTER TABLE "public"."history_questions" ADD CONSTRAINT "history_questions_quiz_id_question_number_key" UNIQUE (quiz_id, question_number);

ALTER TABLE "public"."history_questions" ADD CONSTRAINT "history_questions_time_allowed_seconds_check" CHECK (time_allowed_seconds = ANY (ARRAY[45, 60]));

ALTER TABLE "public"."history_quiz_attempts" ADD CONSTRAINT "history_quiz_attempts_pkey" PRIMARY KEY (id);

ALTER TABLE "public"."history_quizzes" ADD CONSTRAINT "history_quizzes_pass_mark_check" CHECK (pass_mark = 20);

ALTER TABLE "public"."history_quizzes" ADD CONSTRAINT "history_quizzes_pkey" PRIMARY KEY (id);

ALTER TABLE "public"."history_quizzes" ADD CONSTRAINT "history_quizzes_total_questions_check" CHECK (total_questions = 25);

ALTER TABLE "public"."history_quizzes" ADD CONSTRAINT "history_quizzes_version_number_check" CHECK (version_number > 0);

ALTER TABLE "public"."history_quizzes" ADD CONSTRAINT "history_quizzes_week_number_check" CHECK (week_number > 0);

ALTER TABLE "public"."history_quizzes" ADD CONSTRAINT "history_quizzes_year_group_check" CHECK (year_group = ANY (ARRAY[9, 10, 11]));

ALTER TABLE "public"."history_teacher_classes" ADD CONSTRAINT "history_teacher_classes_pkey" PRIMARY KEY (id);

ALTER TABLE "public"."history_teacher_classes" ADD CONSTRAINT "history_teacher_classes_user_id_class_id_key" UNIQUE (user_id, class_id);

ALTER TABLE "public"."history_teachers" ADD CONSTRAINT "history_teachers_pkey" PRIMARY KEY (user_id);

ALTER TABLE "public"."history_attempts" ADD CONSTRAINT "valid_completion" CHECK (status = 'in_progress'::text AND score IS NULL AND completed_at IS NULL OR status = 'completed'::text AND score IS NOT NULL AND completed_at IS NOT NULL);

ALTER TABLE "public"."history_pupils" ADD CONSTRAINT "valid_pupil_code" CHECK (pupil_code ~ '^[A-Z0-9]{4,5}-[0-9]{2,3}$'::text);

ALTER TABLE "public"."history_answers" ADD CONSTRAINT "history_answers_attempt_id_fkey" FOREIGN KEY (attempt_id) REFERENCES history_attempts(id) ON DELETE CASCADE;

ALTER TABLE "public"."history_attempts" ADD CONSTRAINT "history_attempts_pupil_id_fkey" FOREIGN KEY (pupil_id) REFERENCES history_pupils(id);

ALTER TABLE "public"."history_attempts" ADD CONSTRAINT "history_attempts_quiz_id_fkey" FOREIGN KEY (quiz_id) REFERENCES history_quizzes(id);

ALTER TABLE "public"."history_pupils" ADD CONSTRAINT "history_pupils_class_id_fkey" FOREIGN KEY (class_id) REFERENCES history_classes(id);

ALTER TABLE "public"."history_questions" ADD CONSTRAINT "history_questions_quiz_id_fkey" FOREIGN KEY (quiz_id) REFERENCES history_quizzes(id) ON DELETE CASCADE;

ALTER TABLE "public"."history_teacher_classes" ADD CONSTRAINT "history_teacher_classes_class_id_fkey" FOREIGN KEY (class_id) REFERENCES history_classes(id) ON DELETE CASCADE;

ALTER TABLE "public"."history_teacher_classes" ADD CONSTRAINT "history_teacher_classes_user_id_fkey" FOREIGN KEY (user_id) REFERENCES history_teachers(user_id) ON DELETE CASCADE;

ALTER TABLE "public"."history_teachers" ADD CONSTRAINT "history_teachers_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE INDEX history_answers_attempt_idx ON public.history_answers USING btree (attempt_id);

CREATE INDEX history_attempts_pupil_idx ON public.history_attempts USING btree (pupil_id);

CREATE INDEX history_attempts_quiz_idx ON public.history_attempts USING btree (quiz_id);

CREATE UNIQUE INDEX history_attempts_attempt_token_unique ON public.history_attempts USING btree (attempt_token);

CREATE OR REPLACE FUNCTION homework_api._ensure_attempt_shuffle(v_attempt_id uuid)
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

ALTER FUNCTION "homework_api"."_ensure_attempt_shuffle"(v_attempt_id uuid) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION homework_api.check_published_attempt(entered_attempt_id uuid, entered_attempt_token uuid)
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

ALTER FUNCTION "homework_api"."check_published_attempt"(entered_attempt_id uuid, entered_attempt_token uuid) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION homework_api.check_pupil_code(entered_code text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.history_pupils
    WHERE pupil_code = upper(trim(entered_code))
  );
END;
$function$;

ALTER FUNCTION "homework_api"."check_pupil_code"(entered_code text) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION homework_api.complete_pupil_quiz(entered_attempt_id uuid, entered_attempt_token uuid)
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

  IF NOT homework_api.check_published_attempt(
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

ALTER FUNCTION "homework_api"."complete_pupil_quiz"(entered_attempt_id uuid, entered_attempt_token uuid) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION homework_api.complete_quiz_test(entered_attempt_id uuid)
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

ALTER FUNCTION "homework_api"."complete_quiz_test"(entered_attempt_id uuid) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION homework_api.get_current_pupil_homework(entered_code text)
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

ALTER FUNCTION "homework_api"."get_current_pupil_homework"(entered_code text) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION homework_api.get_pupil_attempt_status(entered_code text, entered_quiz_id uuid)
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

ALTER FUNCTION "homework_api"."get_pupil_attempt_status"(entered_code text, entered_quiz_id uuid) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION homework_api.get_pupil_questions(entered_attempt_id uuid, entered_attempt_token uuid)
 RETURNS TABLE(question_number integer, question_text text, answer_options jsonb, time_allowed_seconds integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF NOT homework_api.check_published_attempt(
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

ALTER FUNCTION "homework_api"."get_pupil_questions"(entered_attempt_id uuid, entered_attempt_token uuid) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION homework_api.mark_quiz_test(entered_quiz_id uuid, submitted_answers jsonb)
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

ALTER FUNCTION "homework_api"."mark_quiz_test"(entered_quiz_id uuid, submitted_answers jsonb) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION homework_api.mark_test_answer(entered_question_id uuid, entered_answer integer)
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

ALTER FUNCTION "homework_api"."mark_test_answer"(entered_question_id uuid, entered_answer integer) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION homework_api.open_pupil_question(entered_attempt_id uuid, entered_attempt_token uuid)
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
  PERFORM homework_api._ensure_attempt_shuffle(a.id);
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

ALTER FUNCTION "homework_api"."open_pupil_question"(entered_attempt_id uuid, entered_attempt_token uuid) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION homework_api.save_marked_test_attempt(entered_pupil_code text, entered_quiz_id uuid, submitted_answers jsonb)
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

ALTER FUNCTION "homework_api"."save_marked_test_attempt"(entered_pupil_code text, entered_quiz_id uuid, submitted_answers jsonb) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION homework_api.save_quiz_result(entered_code text, entered_quiz_id uuid, entered_score integer)
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

ALTER FUNCTION "homework_api"."save_quiz_result"(entered_code text, entered_quiz_id uuid, entered_score integer) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION homework_api.set_question_start_time()
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

ALTER FUNCTION "homework_api"."set_question_start_time"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION homework_api.start_pupil_quiz(entered_code text, entered_quiz_id uuid)
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

ALTER FUNCTION "homework_api"."start_pupil_quiz"(entered_code text, entered_quiz_id uuid) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION homework_api.start_quiz_test(entered_code text, entered_quiz_id uuid)
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

ALTER FUNCTION "homework_api"."start_quiz_test"(entered_code text, entered_quiz_id uuid) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION homework_api.submit_answer_test(entered_attempt_id uuid, entered_answer integer)
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

ALTER FUNCTION "homework_api"."submit_answer_test"(entered_attempt_id uuid, entered_answer integer) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION homework_api.submit_pupil_answer(entered_attempt_id uuid, entered_attempt_token uuid, entered_answer integer)
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

ALTER FUNCTION "homework_api"."submit_pupil_answer"(entered_attempt_id uuid, entered_attempt_token uuid, entered_answer integer) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION public.get_history_class_results(requested_class text, requested_quiz uuid)
 RETURNS TABLE(pupil_code text, attempts bigint, highest_score integer, homework_status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
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
      AND c.class_name = requested_class
  ) THEN
    RAISE EXCEPTION 'You are not allocated to this class';
  END IF;

  RETURN QUERY
  SELECT
    p.pupil_code,
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
  WHERE c.class_name = requested_class
  GROUP BY p.id, p.pupil_code, q.pass_mark
  ORDER BY p.pupil_code;
END;
$function$;

ALTER FUNCTION "public"."get_history_class_results"(requested_class text, requested_quiz uuid) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION public.is_history_teacher()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.history_teachers
    WHERE user_id = (SELECT auth.uid())
  );
$function$;

ALTER FUNCTION "public"."is_history_teacher"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
  tbl name;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        SELECT c.relname INTO tbl FROM pg_catalog.pg_class c WHERE c.oid = cmd.objid;
        EXECUTE format('alter table if exists %I.%I enable row level security', cmd.schema_name, tbl);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;

ALTER FUNCTION "public"."rls_auto_enable"() OWNER TO "postgres";

CREATE TRIGGER history_attempt_question_timer BEFORE INSERT OR UPDATE OF question_position ON history_attempts FOR EACH ROW EXECUTE FUNCTION homework_api.set_question_start_time();

ALTER TABLE "public"."history_pupils" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."history_pupils" NO FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."history_attempts" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."history_attempts" NO FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."history_answers" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."history_answers" NO FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."history_classes" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."history_classes" NO FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."history_quiz_attempts" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."history_quiz_attempts" NO FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."history_quizzes" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."history_quizzes" NO FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."history_teachers" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."history_teachers" NO FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."history_teacher_classes" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."history_teacher_classes" NO FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."history_questions" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."history_questions" NO FORCE ROW LEVEL SECURITY;

CREATE POLICY "Teachers can view pupils in allocated classes" ON "public"."history_pupils" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM history_teacher_classes tc
  WHERE ((tc.class_id = history_pupils.class_id) AND (tc.user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "Teachers can view allocated pupil results" ON "public"."history_attempts" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM (history_pupils p
     JOIN history_teacher_classes tc ON ((tc.class_id = p.class_id)))
  WHERE ((p.id = history_attempts.pupil_id) AND (tc.user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "Teachers can view answers for allocated pupils" ON "public"."history_answers" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ((history_attempts a
     JOIN history_pupils p ON ((p.id = a.pupil_id)))
     JOIN history_teacher_classes tc ON ((tc.class_id = p.class_id)))
  WHERE ((a.id = history_answers.attempt_id) AND (tc.user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "Teachers can view their allocated classes" ON "public"."history_classes" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM history_teacher_classes tc
  WHERE ((tc.class_id = history_classes.id) AND (tc.user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "Teachers can view quizzes for allocated year groups" ON "public"."history_quizzes" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((is_published = true) AND (EXISTS ( SELECT 1
   FROM (history_teacher_classes tc
     JOIN history_classes c ON ((c.id = tc.class_id)))
  WHERE ((tc.user_id = ( SELECT auth.uid() AS uid)) AND (c.year_group = history_quizzes.year_group))))));

CREATE POLICY "Teachers can view their own class allocations" ON "public"."history_teacher_classes" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "Teachers can view questions for allocated classes" ON "public"."history_questions" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ((history_quizzes q
     JOIN history_classes c ON ((c.year_group = q.year_group)))
     JOIN history_teacher_classes tc ON ((tc.class_id = c.id)))
  WHERE ((q.id = history_questions.quiz_id) AND (tc.user_id = ( SELECT auth.uid() AS uid)) AND (q.is_published = true)))));

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON SEQUENCES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON SEQUENCES FROM "anon";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON SEQUENCES FROM "authenticated";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON SEQUENCES FROM "pg_database_owner";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON SEQUENCES FROM "postgres";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON SEQUENCES FROM "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT SELECT ON SEQUENCES TO "postgres";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT UPDATE ON SEQUENCES TO "postgres";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT USAGE ON SEQUENCES TO "postgres";

DO $baseline$ BEGIN
  IF (SELECT jsonb_agg(jsonb_build_array(grantee, privilege_type, is_grantable)
                      ORDER BY grantee COLLATE "C", privilege_type COLLATE "C", is_grantable)
      FROM (SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee)::text END AS grantee,
                   a.privilege_type, a.is_grantable
            FROM pg_default_acl d
            LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace
            CROSS JOIN LATERAL aclexplode(d.defaclacl) a
            WHERE pg_get_userbyid(d.defaclrole) = 'supabase_admin'
              AND coalesce(n.nspname, '') = 'public'
              AND d.defaclobjtype = 'S') actual)
     IS DISTINCT FROM '[["anon", "SELECT", false], ["anon", "UPDATE", false], ["anon", "USAGE", false], ["authenticated", "SELECT", false], ["authenticated", "UPDATE", false], ["authenticated", "USAGE", false], ["postgres", "SELECT", false], ["postgres", "UPDATE", false], ["postgres", "USAGE", false], ["service_role", "SELECT", false], ["service_role", "UPDATE", false], ["service_role", "USAGE", false]]'::jsonb THEN
    RAISE EXCEPTION 'Supabase-managed default privileges differ from exported baseline (SEQUENCES)';
  END IF;
END $baseline$;

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON FUNCTIONS FROM PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON FUNCTIONS FROM "anon";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON FUNCTIONS FROM "authenticated";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON FUNCTIONS FROM "pg_database_owner";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON FUNCTIONS FROM "postgres";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON FUNCTIONS FROM "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT EXECUTE ON FUNCTIONS TO "postgres";

DO $baseline$ BEGIN
  IF (SELECT jsonb_agg(jsonb_build_array(grantee, privilege_type, is_grantable)
                      ORDER BY grantee COLLATE "C", privilege_type COLLATE "C", is_grantable)
      FROM (SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee)::text END AS grantee,
                   a.privilege_type, a.is_grantable
            FROM pg_default_acl d
            LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace
            CROSS JOIN LATERAL aclexplode(d.defaclacl) a
            WHERE pg_get_userbyid(d.defaclrole) = 'supabase_admin'
              AND coalesce(n.nspname, '') = 'public'
              AND d.defaclobjtype = 'f') actual)
     IS DISTINCT FROM '[["anon", "EXECUTE", false], ["authenticated", "EXECUTE", false], ["postgres", "EXECUTE", false], ["service_role", "EXECUTE", false]]'::jsonb THEN
    RAISE EXCEPTION 'Supabase-managed default privileges differ from exported baseline (FUNCTIONS)';
  END IF;
END $baseline$;

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON TABLES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON TABLES FROM "anon";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON TABLES FROM "authenticated";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON TABLES FROM "pg_database_owner";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON TABLES FROM "postgres";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON TABLES FROM "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT INSERT ON TABLES TO "postgres";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT SELECT ON TABLES TO "postgres";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT UPDATE ON TABLES TO "postgres";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT DELETE ON TABLES TO "postgres";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT TRUNCATE ON TABLES TO "postgres";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES ON TABLES TO "postgres";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT TRIGGER ON TABLES TO "postgres";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT MAINTAIN ON TABLES TO "postgres";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT TRUNCATE ON TABLES TO "anon";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES ON TABLES TO "anon";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT TRIGGER ON TABLES TO "anon";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT MAINTAIN ON TABLES TO "anon";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT TRUNCATE ON TABLES TO "authenticated";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES ON TABLES TO "authenticated";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT TRIGGER ON TABLES TO "authenticated";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT MAINTAIN ON TABLES TO "authenticated";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT TRUNCATE ON TABLES TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES ON TABLES TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT TRIGGER ON TABLES TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT MAINTAIN ON TABLES TO "service_role";

DO $baseline$ BEGIN
  IF (SELECT jsonb_agg(jsonb_build_array(grantee, privilege_type, is_grantable)
                      ORDER BY grantee COLLATE "C", privilege_type COLLATE "C", is_grantable)
      FROM (SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee)::text END AS grantee,
                   a.privilege_type, a.is_grantable
            FROM pg_default_acl d
            LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace
            CROSS JOIN LATERAL aclexplode(d.defaclacl) a
            WHERE pg_get_userbyid(d.defaclrole) = 'supabase_admin'
              AND coalesce(n.nspname, '') = 'public'
              AND d.defaclobjtype = 'r') actual)
     IS DISTINCT FROM '[["anon", "DELETE", false], ["anon", "INSERT", false], ["anon", "MAINTAIN", false], ["anon", "REFERENCES", false], ["anon", "SELECT", false], ["anon", "TRIGGER", false], ["anon", "TRUNCATE", false], ["anon", "UPDATE", false], ["authenticated", "DELETE", false], ["authenticated", "INSERT", false], ["authenticated", "MAINTAIN", false], ["authenticated", "REFERENCES", false], ["authenticated", "SELECT", false], ["authenticated", "TRIGGER", false], ["authenticated", "TRUNCATE", false], ["authenticated", "UPDATE", false], ["postgres", "DELETE", false], ["postgres", "INSERT", false], ["postgres", "MAINTAIN", false], ["postgres", "REFERENCES", false], ["postgres", "SELECT", false], ["postgres", "TRIGGER", false], ["postgres", "TRUNCATE", false], ["postgres", "UPDATE", false], ["service_role", "DELETE", false], ["service_role", "INSERT", false], ["service_role", "MAINTAIN", false], ["service_role", "REFERENCES", false], ["service_role", "SELECT", false], ["service_role", "TRIGGER", false], ["service_role", "TRUNCATE", false], ["service_role", "UPDATE", false]]'::jsonb THEN
    RAISE EXCEPTION 'Supabase-managed default privileges differ from exported baseline (TABLES)';
  END IF;
END $baseline$;

REVOKE ALL ON FUNCTION "homework_api"."_ensure_attempt_shuffle"(v_attempt_id uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION "homework_api"."_ensure_attempt_shuffle"(v_attempt_id uuid) FROM "anon";

REVOKE ALL ON FUNCTION "homework_api"."_ensure_attempt_shuffle"(v_attempt_id uuid) FROM "authenticated";

REVOKE ALL ON FUNCTION "homework_api"."_ensure_attempt_shuffle"(v_attempt_id uuid) FROM "pg_database_owner";

REVOKE ALL ON FUNCTION "homework_api"."_ensure_attempt_shuffle"(v_attempt_id uuid) FROM "postgres";

REVOKE ALL ON FUNCTION "homework_api"."_ensure_attempt_shuffle"(v_attempt_id uuid) FROM "service_role";

GRANT EXECUTE ON FUNCTION "homework_api"."_ensure_attempt_shuffle"(v_attempt_id uuid) TO "postgres";

REVOKE ALL ON FUNCTION "homework_api"."check_published_attempt"(entered_attempt_id uuid, entered_attempt_token uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION "homework_api"."check_published_attempt"(entered_attempt_id uuid, entered_attempt_token uuid) FROM "anon";

REVOKE ALL ON FUNCTION "homework_api"."check_published_attempt"(entered_attempt_id uuid, entered_attempt_token uuid) FROM "authenticated";

REVOKE ALL ON FUNCTION "homework_api"."check_published_attempt"(entered_attempt_id uuid, entered_attempt_token uuid) FROM "pg_database_owner";

REVOKE ALL ON FUNCTION "homework_api"."check_published_attempt"(entered_attempt_id uuid, entered_attempt_token uuid) FROM "postgres";

REVOKE ALL ON FUNCTION "homework_api"."check_published_attempt"(entered_attempt_id uuid, entered_attempt_token uuid) FROM "service_role";

GRANT EXECUTE ON FUNCTION "homework_api"."check_published_attempt"(entered_attempt_id uuid, entered_attempt_token uuid) TO "postgres";

REVOKE ALL ON FUNCTION "homework_api"."check_pupil_code"(entered_code text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "homework_api"."check_pupil_code"(entered_code text) FROM "anon";

REVOKE ALL ON FUNCTION "homework_api"."check_pupil_code"(entered_code text) FROM "authenticated";

REVOKE ALL ON FUNCTION "homework_api"."check_pupil_code"(entered_code text) FROM "pg_database_owner";

REVOKE ALL ON FUNCTION "homework_api"."check_pupil_code"(entered_code text) FROM "postgres";

REVOKE ALL ON FUNCTION "homework_api"."check_pupil_code"(entered_code text) FROM "service_role";

GRANT EXECUTE ON FUNCTION "homework_api"."check_pupil_code"(entered_code text) TO "postgres";

GRANT EXECUTE ON FUNCTION "homework_api"."check_pupil_code"(entered_code text) TO "anon";

GRANT EXECUTE ON FUNCTION "homework_api"."check_pupil_code"(entered_code text) TO "authenticated";

GRANT EXECUTE ON FUNCTION "homework_api"."check_pupil_code"(entered_code text) TO "service_role";

REVOKE ALL ON FUNCTION "homework_api"."complete_pupil_quiz"(entered_attempt_id uuid, entered_attempt_token uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION "homework_api"."complete_pupil_quiz"(entered_attempt_id uuid, entered_attempt_token uuid) FROM "anon";

REVOKE ALL ON FUNCTION "homework_api"."complete_pupil_quiz"(entered_attempt_id uuid, entered_attempt_token uuid) FROM "authenticated";

REVOKE ALL ON FUNCTION "homework_api"."complete_pupil_quiz"(entered_attempt_id uuid, entered_attempt_token uuid) FROM "pg_database_owner";

REVOKE ALL ON FUNCTION "homework_api"."complete_pupil_quiz"(entered_attempt_id uuid, entered_attempt_token uuid) FROM "postgres";

REVOKE ALL ON FUNCTION "homework_api"."complete_pupil_quiz"(entered_attempt_id uuid, entered_attempt_token uuid) FROM "service_role";

GRANT EXECUTE ON FUNCTION "homework_api"."complete_pupil_quiz"(entered_attempt_id uuid, entered_attempt_token uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "homework_api"."complete_pupil_quiz"(entered_attempt_id uuid, entered_attempt_token uuid) TO "anon";

REVOKE ALL ON FUNCTION "homework_api"."complete_quiz_test"(entered_attempt_id uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION "homework_api"."complete_quiz_test"(entered_attempt_id uuid) FROM "anon";

REVOKE ALL ON FUNCTION "homework_api"."complete_quiz_test"(entered_attempt_id uuid) FROM "authenticated";

REVOKE ALL ON FUNCTION "homework_api"."complete_quiz_test"(entered_attempt_id uuid) FROM "pg_database_owner";

REVOKE ALL ON FUNCTION "homework_api"."complete_quiz_test"(entered_attempt_id uuid) FROM "postgres";

REVOKE ALL ON FUNCTION "homework_api"."complete_quiz_test"(entered_attempt_id uuid) FROM "service_role";

GRANT EXECUTE ON FUNCTION "homework_api"."complete_quiz_test"(entered_attempt_id uuid) TO "postgres";

REVOKE ALL ON FUNCTION "homework_api"."get_current_pupil_homework"(entered_code text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "homework_api"."get_current_pupil_homework"(entered_code text) FROM "anon";

REVOKE ALL ON FUNCTION "homework_api"."get_current_pupil_homework"(entered_code text) FROM "authenticated";

REVOKE ALL ON FUNCTION "homework_api"."get_current_pupil_homework"(entered_code text) FROM "pg_database_owner";

REVOKE ALL ON FUNCTION "homework_api"."get_current_pupil_homework"(entered_code text) FROM "postgres";

REVOKE ALL ON FUNCTION "homework_api"."get_current_pupil_homework"(entered_code text) FROM "service_role";

GRANT EXECUTE ON FUNCTION "homework_api"."get_current_pupil_homework"(entered_code text) TO "postgres";

GRANT EXECUTE ON FUNCTION "homework_api"."get_current_pupil_homework"(entered_code text) TO "anon";

GRANT EXECUTE ON FUNCTION "homework_api"."get_current_pupil_homework"(entered_code text) TO "authenticated";

REVOKE ALL ON FUNCTION "homework_api"."get_pupil_attempt_status"(entered_code text, entered_quiz_id uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION "homework_api"."get_pupil_attempt_status"(entered_code text, entered_quiz_id uuid) FROM "anon";

REVOKE ALL ON FUNCTION "homework_api"."get_pupil_attempt_status"(entered_code text, entered_quiz_id uuid) FROM "authenticated";

REVOKE ALL ON FUNCTION "homework_api"."get_pupil_attempt_status"(entered_code text, entered_quiz_id uuid) FROM "pg_database_owner";

REVOKE ALL ON FUNCTION "homework_api"."get_pupil_attempt_status"(entered_code text, entered_quiz_id uuid) FROM "postgres";

REVOKE ALL ON FUNCTION "homework_api"."get_pupil_attempt_status"(entered_code text, entered_quiz_id uuid) FROM "service_role";

GRANT EXECUTE ON FUNCTION "homework_api"."get_pupil_attempt_status"(entered_code text, entered_quiz_id uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "homework_api"."get_pupil_attempt_status"(entered_code text, entered_quiz_id uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "homework_api"."get_pupil_questions"(entered_attempt_id uuid, entered_attempt_token uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION "homework_api"."get_pupil_questions"(entered_attempt_id uuid, entered_attempt_token uuid) FROM "anon";

REVOKE ALL ON FUNCTION "homework_api"."get_pupil_questions"(entered_attempt_id uuid, entered_attempt_token uuid) FROM "authenticated";

REVOKE ALL ON FUNCTION "homework_api"."get_pupil_questions"(entered_attempt_id uuid, entered_attempt_token uuid) FROM "pg_database_owner";

REVOKE ALL ON FUNCTION "homework_api"."get_pupil_questions"(entered_attempt_id uuid, entered_attempt_token uuid) FROM "postgres";

REVOKE ALL ON FUNCTION "homework_api"."get_pupil_questions"(entered_attempt_id uuid, entered_attempt_token uuid) FROM "service_role";

GRANT EXECUTE ON FUNCTION "homework_api"."get_pupil_questions"(entered_attempt_id uuid, entered_attempt_token uuid) TO "postgres";

REVOKE ALL ON FUNCTION "homework_api"."mark_quiz_test"(entered_quiz_id uuid, submitted_answers jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION "homework_api"."mark_quiz_test"(entered_quiz_id uuid, submitted_answers jsonb) FROM "anon";

REVOKE ALL ON FUNCTION "homework_api"."mark_quiz_test"(entered_quiz_id uuid, submitted_answers jsonb) FROM "authenticated";

REVOKE ALL ON FUNCTION "homework_api"."mark_quiz_test"(entered_quiz_id uuid, submitted_answers jsonb) FROM "pg_database_owner";

REVOKE ALL ON FUNCTION "homework_api"."mark_quiz_test"(entered_quiz_id uuid, submitted_answers jsonb) FROM "postgres";

REVOKE ALL ON FUNCTION "homework_api"."mark_quiz_test"(entered_quiz_id uuid, submitted_answers jsonb) FROM "service_role";

GRANT EXECUTE ON FUNCTION "homework_api"."mark_quiz_test"(entered_quiz_id uuid, submitted_answers jsonb) TO "postgres";

REVOKE ALL ON FUNCTION "homework_api"."mark_test_answer"(entered_question_id uuid, entered_answer integer) FROM PUBLIC;

REVOKE ALL ON FUNCTION "homework_api"."mark_test_answer"(entered_question_id uuid, entered_answer integer) FROM "anon";

REVOKE ALL ON FUNCTION "homework_api"."mark_test_answer"(entered_question_id uuid, entered_answer integer) FROM "authenticated";

REVOKE ALL ON FUNCTION "homework_api"."mark_test_answer"(entered_question_id uuid, entered_answer integer) FROM "pg_database_owner";

REVOKE ALL ON FUNCTION "homework_api"."mark_test_answer"(entered_question_id uuid, entered_answer integer) FROM "postgres";

REVOKE ALL ON FUNCTION "homework_api"."mark_test_answer"(entered_question_id uuid, entered_answer integer) FROM "service_role";

GRANT EXECUTE ON FUNCTION "homework_api"."mark_test_answer"(entered_question_id uuid, entered_answer integer) TO "postgres";

REVOKE ALL ON FUNCTION "homework_api"."open_pupil_question"(entered_attempt_id uuid, entered_attempt_token uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION "homework_api"."open_pupil_question"(entered_attempt_id uuid, entered_attempt_token uuid) FROM "anon";

REVOKE ALL ON FUNCTION "homework_api"."open_pupil_question"(entered_attempt_id uuid, entered_attempt_token uuid) FROM "authenticated";

REVOKE ALL ON FUNCTION "homework_api"."open_pupil_question"(entered_attempt_id uuid, entered_attempt_token uuid) FROM "pg_database_owner";

REVOKE ALL ON FUNCTION "homework_api"."open_pupil_question"(entered_attempt_id uuid, entered_attempt_token uuid) FROM "postgres";

REVOKE ALL ON FUNCTION "homework_api"."open_pupil_question"(entered_attempt_id uuid, entered_attempt_token uuid) FROM "service_role";

GRANT EXECUTE ON FUNCTION "homework_api"."open_pupil_question"(entered_attempt_id uuid, entered_attempt_token uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "homework_api"."open_pupil_question"(entered_attempt_id uuid, entered_attempt_token uuid) TO "anon";

REVOKE ALL ON FUNCTION "homework_api"."save_marked_test_attempt"(entered_pupil_code text, entered_quiz_id uuid, submitted_answers jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION "homework_api"."save_marked_test_attempt"(entered_pupil_code text, entered_quiz_id uuid, submitted_answers jsonb) FROM "anon";

REVOKE ALL ON FUNCTION "homework_api"."save_marked_test_attempt"(entered_pupil_code text, entered_quiz_id uuid, submitted_answers jsonb) FROM "authenticated";

REVOKE ALL ON FUNCTION "homework_api"."save_marked_test_attempt"(entered_pupil_code text, entered_quiz_id uuid, submitted_answers jsonb) FROM "pg_database_owner";

REVOKE ALL ON FUNCTION "homework_api"."save_marked_test_attempt"(entered_pupil_code text, entered_quiz_id uuid, submitted_answers jsonb) FROM "postgres";

REVOKE ALL ON FUNCTION "homework_api"."save_marked_test_attempt"(entered_pupil_code text, entered_quiz_id uuid, submitted_answers jsonb) FROM "service_role";

GRANT EXECUTE ON FUNCTION "homework_api"."save_marked_test_attempt"(entered_pupil_code text, entered_quiz_id uuid, submitted_answers jsonb) TO "postgres";

REVOKE ALL ON FUNCTION "homework_api"."save_quiz_result"(entered_code text, entered_quiz_id uuid, entered_score integer) FROM PUBLIC;

REVOKE ALL ON FUNCTION "homework_api"."save_quiz_result"(entered_code text, entered_quiz_id uuid, entered_score integer) FROM "anon";

REVOKE ALL ON FUNCTION "homework_api"."save_quiz_result"(entered_code text, entered_quiz_id uuid, entered_score integer) FROM "authenticated";

REVOKE ALL ON FUNCTION "homework_api"."save_quiz_result"(entered_code text, entered_quiz_id uuid, entered_score integer) FROM "pg_database_owner";

REVOKE ALL ON FUNCTION "homework_api"."save_quiz_result"(entered_code text, entered_quiz_id uuid, entered_score integer) FROM "postgres";

REVOKE ALL ON FUNCTION "homework_api"."save_quiz_result"(entered_code text, entered_quiz_id uuid, entered_score integer) FROM "service_role";

GRANT EXECUTE ON FUNCTION "homework_api"."save_quiz_result"(entered_code text, entered_quiz_id uuid, entered_score integer) TO "postgres";

REVOKE ALL ON FUNCTION "homework_api"."set_question_start_time"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "homework_api"."set_question_start_time"() FROM "anon";

REVOKE ALL ON FUNCTION "homework_api"."set_question_start_time"() FROM "authenticated";

REVOKE ALL ON FUNCTION "homework_api"."set_question_start_time"() FROM "pg_database_owner";

REVOKE ALL ON FUNCTION "homework_api"."set_question_start_time"() FROM "postgres";

REVOKE ALL ON FUNCTION "homework_api"."set_question_start_time"() FROM "service_role";

GRANT EXECUTE ON FUNCTION "homework_api"."set_question_start_time"() TO PUBLIC;

GRANT EXECUTE ON FUNCTION "homework_api"."set_question_start_time"() TO "postgres";

REVOKE ALL ON FUNCTION "homework_api"."start_pupil_quiz"(entered_code text, entered_quiz_id uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION "homework_api"."start_pupil_quiz"(entered_code text, entered_quiz_id uuid) FROM "anon";

REVOKE ALL ON FUNCTION "homework_api"."start_pupil_quiz"(entered_code text, entered_quiz_id uuid) FROM "authenticated";

REVOKE ALL ON FUNCTION "homework_api"."start_pupil_quiz"(entered_code text, entered_quiz_id uuid) FROM "pg_database_owner";

REVOKE ALL ON FUNCTION "homework_api"."start_pupil_quiz"(entered_code text, entered_quiz_id uuid) FROM "postgres";

REVOKE ALL ON FUNCTION "homework_api"."start_pupil_quiz"(entered_code text, entered_quiz_id uuid) FROM "service_role";

GRANT EXECUTE ON FUNCTION "homework_api"."start_pupil_quiz"(entered_code text, entered_quiz_id uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "homework_api"."start_pupil_quiz"(entered_code text, entered_quiz_id uuid) TO "anon";

REVOKE ALL ON FUNCTION "homework_api"."start_quiz_test"(entered_code text, entered_quiz_id uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION "homework_api"."start_quiz_test"(entered_code text, entered_quiz_id uuid) FROM "anon";

REVOKE ALL ON FUNCTION "homework_api"."start_quiz_test"(entered_code text, entered_quiz_id uuid) FROM "authenticated";

REVOKE ALL ON FUNCTION "homework_api"."start_quiz_test"(entered_code text, entered_quiz_id uuid) FROM "pg_database_owner";

REVOKE ALL ON FUNCTION "homework_api"."start_quiz_test"(entered_code text, entered_quiz_id uuid) FROM "postgres";

REVOKE ALL ON FUNCTION "homework_api"."start_quiz_test"(entered_code text, entered_quiz_id uuid) FROM "service_role";

GRANT EXECUTE ON FUNCTION "homework_api"."start_quiz_test"(entered_code text, entered_quiz_id uuid) TO "postgres";

REVOKE ALL ON FUNCTION "homework_api"."submit_answer_test"(entered_attempt_id uuid, entered_answer integer) FROM PUBLIC;

REVOKE ALL ON FUNCTION "homework_api"."submit_answer_test"(entered_attempt_id uuid, entered_answer integer) FROM "anon";

REVOKE ALL ON FUNCTION "homework_api"."submit_answer_test"(entered_attempt_id uuid, entered_answer integer) FROM "authenticated";

REVOKE ALL ON FUNCTION "homework_api"."submit_answer_test"(entered_attempt_id uuid, entered_answer integer) FROM "pg_database_owner";

REVOKE ALL ON FUNCTION "homework_api"."submit_answer_test"(entered_attempt_id uuid, entered_answer integer) FROM "postgres";

REVOKE ALL ON FUNCTION "homework_api"."submit_answer_test"(entered_attempt_id uuid, entered_answer integer) FROM "service_role";

GRANT EXECUTE ON FUNCTION "homework_api"."submit_answer_test"(entered_attempt_id uuid, entered_answer integer) TO "postgres";

REVOKE ALL ON FUNCTION "homework_api"."submit_pupil_answer"(entered_attempt_id uuid, entered_attempt_token uuid, entered_answer integer) FROM PUBLIC;

REVOKE ALL ON FUNCTION "homework_api"."submit_pupil_answer"(entered_attempt_id uuid, entered_attempt_token uuid, entered_answer integer) FROM "anon";

REVOKE ALL ON FUNCTION "homework_api"."submit_pupil_answer"(entered_attempt_id uuid, entered_attempt_token uuid, entered_answer integer) FROM "authenticated";

REVOKE ALL ON FUNCTION "homework_api"."submit_pupil_answer"(entered_attempt_id uuid, entered_attempt_token uuid, entered_answer integer) FROM "pg_database_owner";

REVOKE ALL ON FUNCTION "homework_api"."submit_pupil_answer"(entered_attempt_id uuid, entered_attempt_token uuid, entered_answer integer) FROM "postgres";

REVOKE ALL ON FUNCTION "homework_api"."submit_pupil_answer"(entered_attempt_id uuid, entered_attempt_token uuid, entered_answer integer) FROM "service_role";

GRANT EXECUTE ON FUNCTION "homework_api"."submit_pupil_answer"(entered_attempt_id uuid, entered_attempt_token uuid, entered_answer integer) TO "postgres";

GRANT EXECUTE ON FUNCTION "homework_api"."submit_pupil_answer"(entered_attempt_id uuid, entered_attempt_token uuid, entered_answer integer) TO "anon";

REVOKE ALL ON FUNCTION "public"."get_history_class_results"(requested_class text, requested_quiz uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION "public"."get_history_class_results"(requested_class text, requested_quiz uuid) FROM "anon";

REVOKE ALL ON FUNCTION "public"."get_history_class_results"(requested_class text, requested_quiz uuid) FROM "authenticated";

REVOKE ALL ON FUNCTION "public"."get_history_class_results"(requested_class text, requested_quiz uuid) FROM "pg_database_owner";

REVOKE ALL ON FUNCTION "public"."get_history_class_results"(requested_class text, requested_quiz uuid) FROM "postgres";

REVOKE ALL ON FUNCTION "public"."get_history_class_results"(requested_class text, requested_quiz uuid) FROM "service_role";

GRANT EXECUTE ON FUNCTION "public"."get_history_class_results"(requested_class text, requested_quiz uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."get_history_class_results"(requested_class text, requested_quiz uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."get_history_class_results"(requested_class text, requested_quiz uuid) TO "service_role";

REVOKE ALL ON FUNCTION "public"."is_history_teacher"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "public"."is_history_teacher"() FROM "anon";

REVOKE ALL ON FUNCTION "public"."is_history_teacher"() FROM "authenticated";

REVOKE ALL ON FUNCTION "public"."is_history_teacher"() FROM "pg_database_owner";

REVOKE ALL ON FUNCTION "public"."is_history_teacher"() FROM "postgres";

REVOKE ALL ON FUNCTION "public"."is_history_teacher"() FROM "service_role";

GRANT EXECUTE ON FUNCTION "public"."is_history_teacher"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."is_history_teacher"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."rls_auto_enable"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "public"."rls_auto_enable"() FROM "anon";

REVOKE ALL ON FUNCTION "public"."rls_auto_enable"() FROM "authenticated";

REVOKE ALL ON FUNCTION "public"."rls_auto_enable"() FROM "pg_database_owner";

REVOKE ALL ON FUNCTION "public"."rls_auto_enable"() FROM "postgres";

REVOKE ALL ON FUNCTION "public"."rls_auto_enable"() FROM "service_role";

GRANT EXECUTE ON FUNCTION "public"."rls_auto_enable"() TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."rls_auto_enable"() TO "postgres";

REVOKE ALL ON SCHEMA "homework_api" FROM PUBLIC;

REVOKE ALL ON SCHEMA "homework_api" FROM "anon";

REVOKE ALL ON SCHEMA "homework_api" FROM "authenticated";

REVOKE ALL ON SCHEMA "homework_api" FROM "pg_database_owner";

REVOKE ALL ON SCHEMA "homework_api" FROM "postgres";

REVOKE ALL ON SCHEMA "homework_api" FROM "service_role";

GRANT USAGE ON SCHEMA "homework_api" TO "postgres";

GRANT CREATE ON SCHEMA "homework_api" TO "postgres";

GRANT USAGE ON SCHEMA "homework_api" TO "anon";

GRANT USAGE ON SCHEMA "homework_api" TO "authenticated";

REVOKE ALL ON SCHEMA "public" FROM PUBLIC;

REVOKE ALL ON SCHEMA "public" FROM "anon";

REVOKE ALL ON SCHEMA "public" FROM "authenticated";

REVOKE ALL ON SCHEMA "public" FROM "pg_database_owner";

REVOKE ALL ON SCHEMA "public" FROM "postgres";

REVOKE ALL ON SCHEMA "public" FROM "service_role";

GRANT USAGE ON SCHEMA "public" TO "pg_database_owner";

GRANT CREATE ON SCHEMA "public" TO "pg_database_owner";

GRANT USAGE ON SCHEMA "public" TO PUBLIC;

GRANT USAGE ON SCHEMA "public" TO "postgres";

GRANT USAGE ON SCHEMA "public" TO "anon";

GRANT USAGE ON SCHEMA "public" TO "authenticated";

GRANT USAGE ON SCHEMA "public" TO "service_role";

REVOKE ALL ON SEQUENCE "public"."history_quiz_attempts_id_seq" FROM PUBLIC;

REVOKE ALL ON SEQUENCE "public"."history_quiz_attempts_id_seq" FROM "anon";

REVOKE ALL ON SEQUENCE "public"."history_quiz_attempts_id_seq" FROM "authenticated";

REVOKE ALL ON SEQUENCE "public"."history_quiz_attempts_id_seq" FROM "pg_database_owner";

REVOKE ALL ON SEQUENCE "public"."history_quiz_attempts_id_seq" FROM "postgres";

REVOKE ALL ON SEQUENCE "public"."history_quiz_attempts_id_seq" FROM "service_role";

GRANT SELECT ON SEQUENCE "public"."history_quiz_attempts_id_seq" TO "postgres";

GRANT UPDATE ON SEQUENCE "public"."history_quiz_attempts_id_seq" TO "postgres";

GRANT USAGE ON SEQUENCE "public"."history_quiz_attempts_id_seq" TO "postgres";

REVOKE ALL ON TABLE "public"."history_answers" FROM PUBLIC;

REVOKE ALL ON TABLE "public"."history_answers" FROM "anon";

REVOKE ALL ON TABLE "public"."history_answers" FROM "authenticated";

REVOKE ALL ON TABLE "public"."history_answers" FROM "pg_database_owner";

REVOKE ALL ON TABLE "public"."history_answers" FROM "postgres";

REVOKE ALL ON TABLE "public"."history_answers" FROM "service_role";

GRANT INSERT ON TABLE "public"."history_answers" TO "postgres";

GRANT SELECT ON TABLE "public"."history_answers" TO "postgres";

GRANT UPDATE ON TABLE "public"."history_answers" TO "postgres";

GRANT DELETE ON TABLE "public"."history_answers" TO "postgres";

GRANT TRUNCATE ON TABLE "public"."history_answers" TO "postgres";

GRANT REFERENCES ON TABLE "public"."history_answers" TO "postgres";

GRANT TRIGGER ON TABLE "public"."history_answers" TO "postgres";

GRANT MAINTAIN ON TABLE "public"."history_answers" TO "postgres";

GRANT TRUNCATE ON TABLE "public"."history_answers" TO "service_role";

GRANT REFERENCES ON TABLE "public"."history_answers" TO "service_role";

GRANT TRIGGER ON TABLE "public"."history_answers" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."history_answers" TO "service_role";

GRANT SELECT ON TABLE "public"."history_answers" TO "authenticated";

REVOKE ALL ON TABLE "public"."history_attempts" FROM PUBLIC;

REVOKE ALL ON TABLE "public"."history_attempts" FROM "anon";

REVOKE ALL ON TABLE "public"."history_attempts" FROM "authenticated";

REVOKE ALL ON TABLE "public"."history_attempts" FROM "pg_database_owner";

REVOKE ALL ON TABLE "public"."history_attempts" FROM "postgres";

REVOKE ALL ON TABLE "public"."history_attempts" FROM "service_role";

GRANT INSERT ON TABLE "public"."history_attempts" TO "postgres";

GRANT SELECT ON TABLE "public"."history_attempts" TO "postgres";

GRANT UPDATE ON TABLE "public"."history_attempts" TO "postgres";

GRANT DELETE ON TABLE "public"."history_attempts" TO "postgres";

GRANT TRUNCATE ON TABLE "public"."history_attempts" TO "postgres";

GRANT REFERENCES ON TABLE "public"."history_attempts" TO "postgres";

GRANT TRIGGER ON TABLE "public"."history_attempts" TO "postgres";

GRANT MAINTAIN ON TABLE "public"."history_attempts" TO "postgres";

GRANT TRUNCATE ON TABLE "public"."history_attempts" TO "service_role";

GRANT REFERENCES ON TABLE "public"."history_attempts" TO "service_role";

GRANT TRIGGER ON TABLE "public"."history_attempts" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."history_attempts" TO "service_role";

GRANT SELECT ON TABLE "public"."history_attempts" TO "authenticated";

REVOKE ALL ON TABLE "public"."history_classes" FROM PUBLIC;

REVOKE ALL ON TABLE "public"."history_classes" FROM "anon";

REVOKE ALL ON TABLE "public"."history_classes" FROM "authenticated";

REVOKE ALL ON TABLE "public"."history_classes" FROM "pg_database_owner";

REVOKE ALL ON TABLE "public"."history_classes" FROM "postgres";

REVOKE ALL ON TABLE "public"."history_classes" FROM "service_role";

GRANT INSERT ON TABLE "public"."history_classes" TO "postgres";

GRANT SELECT ON TABLE "public"."history_classes" TO "postgres";

GRANT UPDATE ON TABLE "public"."history_classes" TO "postgres";

GRANT DELETE ON TABLE "public"."history_classes" TO "postgres";

GRANT TRUNCATE ON TABLE "public"."history_classes" TO "postgres";

GRANT REFERENCES ON TABLE "public"."history_classes" TO "postgres";

GRANT TRIGGER ON TABLE "public"."history_classes" TO "postgres";

GRANT MAINTAIN ON TABLE "public"."history_classes" TO "postgres";

GRANT TRUNCATE ON TABLE "public"."history_classes" TO "service_role";

GRANT REFERENCES ON TABLE "public"."history_classes" TO "service_role";

GRANT TRIGGER ON TABLE "public"."history_classes" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."history_classes" TO "service_role";

GRANT SELECT ON TABLE "public"."history_classes" TO "authenticated";

REVOKE ALL ON TABLE "public"."history_pupils" FROM PUBLIC;

REVOKE ALL ON TABLE "public"."history_pupils" FROM "anon";

REVOKE ALL ON TABLE "public"."history_pupils" FROM "authenticated";

REVOKE ALL ON TABLE "public"."history_pupils" FROM "pg_database_owner";

REVOKE ALL ON TABLE "public"."history_pupils" FROM "postgres";

REVOKE ALL ON TABLE "public"."history_pupils" FROM "service_role";

GRANT INSERT ON TABLE "public"."history_pupils" TO "postgres";

GRANT SELECT ON TABLE "public"."history_pupils" TO "postgres";

GRANT UPDATE ON TABLE "public"."history_pupils" TO "postgres";

GRANT DELETE ON TABLE "public"."history_pupils" TO "postgres";

GRANT TRUNCATE ON TABLE "public"."history_pupils" TO "postgres";

GRANT REFERENCES ON TABLE "public"."history_pupils" TO "postgres";

GRANT TRIGGER ON TABLE "public"."history_pupils" TO "postgres";

GRANT MAINTAIN ON TABLE "public"."history_pupils" TO "postgres";

GRANT TRUNCATE ON TABLE "public"."history_pupils" TO "service_role";

GRANT REFERENCES ON TABLE "public"."history_pupils" TO "service_role";

GRANT TRIGGER ON TABLE "public"."history_pupils" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."history_pupils" TO "service_role";

GRANT SELECT ON TABLE "public"."history_pupils" TO "authenticated";

REVOKE ALL ON TABLE "public"."history_questions" FROM PUBLIC;

REVOKE ALL ON TABLE "public"."history_questions" FROM "anon";

REVOKE ALL ON TABLE "public"."history_questions" FROM "authenticated";

REVOKE ALL ON TABLE "public"."history_questions" FROM "pg_database_owner";

REVOKE ALL ON TABLE "public"."history_questions" FROM "postgres";

REVOKE ALL ON TABLE "public"."history_questions" FROM "service_role";

GRANT INSERT ON TABLE "public"."history_questions" TO "postgres";

GRANT SELECT ON TABLE "public"."history_questions" TO "postgres";

GRANT UPDATE ON TABLE "public"."history_questions" TO "postgres";

GRANT DELETE ON TABLE "public"."history_questions" TO "postgres";

GRANT TRUNCATE ON TABLE "public"."history_questions" TO "postgres";

GRANT REFERENCES ON TABLE "public"."history_questions" TO "postgres";

GRANT TRIGGER ON TABLE "public"."history_questions" TO "postgres";

GRANT MAINTAIN ON TABLE "public"."history_questions" TO "postgres";

GRANT TRUNCATE ON TABLE "public"."history_questions" TO "service_role";

GRANT REFERENCES ON TABLE "public"."history_questions" TO "service_role";

GRANT TRIGGER ON TABLE "public"."history_questions" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."history_questions" TO "service_role";

GRANT SELECT ON TABLE "public"."history_questions" TO "authenticated";

REVOKE ALL ON TABLE "public"."history_quiz_attempts" FROM PUBLIC;

REVOKE ALL ON TABLE "public"."history_quiz_attempts" FROM "anon";

REVOKE ALL ON TABLE "public"."history_quiz_attempts" FROM "authenticated";

REVOKE ALL ON TABLE "public"."history_quiz_attempts" FROM "pg_database_owner";

REVOKE ALL ON TABLE "public"."history_quiz_attempts" FROM "postgres";

REVOKE ALL ON TABLE "public"."history_quiz_attempts" FROM "service_role";

GRANT INSERT ON TABLE "public"."history_quiz_attempts" TO "postgres";

GRANT SELECT ON TABLE "public"."history_quiz_attempts" TO "postgres";

GRANT UPDATE ON TABLE "public"."history_quiz_attempts" TO "postgres";

GRANT DELETE ON TABLE "public"."history_quiz_attempts" TO "postgres";

GRANT TRUNCATE ON TABLE "public"."history_quiz_attempts" TO "postgres";

GRANT REFERENCES ON TABLE "public"."history_quiz_attempts" TO "postgres";

GRANT TRIGGER ON TABLE "public"."history_quiz_attempts" TO "postgres";

GRANT MAINTAIN ON TABLE "public"."history_quiz_attempts" TO "postgres";

GRANT TRUNCATE ON TABLE "public"."history_quiz_attempts" TO "service_role";

GRANT REFERENCES ON TABLE "public"."history_quiz_attempts" TO "service_role";

GRANT TRIGGER ON TABLE "public"."history_quiz_attempts" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."history_quiz_attempts" TO "service_role";

REVOKE ALL ON TABLE "public"."history_quizzes" FROM PUBLIC;

REVOKE ALL ON TABLE "public"."history_quizzes" FROM "anon";

REVOKE ALL ON TABLE "public"."history_quizzes" FROM "authenticated";

REVOKE ALL ON TABLE "public"."history_quizzes" FROM "pg_database_owner";

REVOKE ALL ON TABLE "public"."history_quizzes" FROM "postgres";

REVOKE ALL ON TABLE "public"."history_quizzes" FROM "service_role";

GRANT INSERT ON TABLE "public"."history_quizzes" TO "postgres";

GRANT SELECT ON TABLE "public"."history_quizzes" TO "postgres";

GRANT UPDATE ON TABLE "public"."history_quizzes" TO "postgres";

GRANT DELETE ON TABLE "public"."history_quizzes" TO "postgres";

GRANT TRUNCATE ON TABLE "public"."history_quizzes" TO "postgres";

GRANT REFERENCES ON TABLE "public"."history_quizzes" TO "postgres";

GRANT TRIGGER ON TABLE "public"."history_quizzes" TO "postgres";

GRANT MAINTAIN ON TABLE "public"."history_quizzes" TO "postgres";

GRANT TRUNCATE ON TABLE "public"."history_quizzes" TO "service_role";

GRANT REFERENCES ON TABLE "public"."history_quizzes" TO "service_role";

GRANT TRIGGER ON TABLE "public"."history_quizzes" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."history_quizzes" TO "service_role";

GRANT SELECT ON TABLE "public"."history_quizzes" TO "authenticated";

REVOKE ALL ON TABLE "public"."history_teacher_classes" FROM PUBLIC;

REVOKE ALL ON TABLE "public"."history_teacher_classes" FROM "anon";

REVOKE ALL ON TABLE "public"."history_teacher_classes" FROM "authenticated";

REVOKE ALL ON TABLE "public"."history_teacher_classes" FROM "pg_database_owner";

REVOKE ALL ON TABLE "public"."history_teacher_classes" FROM "postgres";

REVOKE ALL ON TABLE "public"."history_teacher_classes" FROM "service_role";

GRANT INSERT ON TABLE "public"."history_teacher_classes" TO "postgres";

GRANT SELECT ON TABLE "public"."history_teacher_classes" TO "postgres";

GRANT UPDATE ON TABLE "public"."history_teacher_classes" TO "postgres";

GRANT DELETE ON TABLE "public"."history_teacher_classes" TO "postgres";

GRANT TRUNCATE ON TABLE "public"."history_teacher_classes" TO "postgres";

GRANT REFERENCES ON TABLE "public"."history_teacher_classes" TO "postgres";

GRANT TRIGGER ON TABLE "public"."history_teacher_classes" TO "postgres";

GRANT MAINTAIN ON TABLE "public"."history_teacher_classes" TO "postgres";

GRANT TRUNCATE ON TABLE "public"."history_teacher_classes" TO "anon";

GRANT REFERENCES ON TABLE "public"."history_teacher_classes" TO "anon";

GRANT TRIGGER ON TABLE "public"."history_teacher_classes" TO "anon";

GRANT MAINTAIN ON TABLE "public"."history_teacher_classes" TO "anon";

GRANT SELECT ON TABLE "public"."history_teacher_classes" TO "authenticated";

GRANT TRUNCATE ON TABLE "public"."history_teacher_classes" TO "authenticated";

GRANT REFERENCES ON TABLE "public"."history_teacher_classes" TO "authenticated";

GRANT TRIGGER ON TABLE "public"."history_teacher_classes" TO "authenticated";

GRANT MAINTAIN ON TABLE "public"."history_teacher_classes" TO "authenticated";

GRANT TRUNCATE ON TABLE "public"."history_teacher_classes" TO "service_role";

GRANT REFERENCES ON TABLE "public"."history_teacher_classes" TO "service_role";

GRANT TRIGGER ON TABLE "public"."history_teacher_classes" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."history_teacher_classes" TO "service_role";

REVOKE ALL ON TABLE "public"."history_teachers" FROM PUBLIC;

REVOKE ALL ON TABLE "public"."history_teachers" FROM "anon";

REVOKE ALL ON TABLE "public"."history_teachers" FROM "authenticated";

REVOKE ALL ON TABLE "public"."history_teachers" FROM "pg_database_owner";

REVOKE ALL ON TABLE "public"."history_teachers" FROM "postgres";

REVOKE ALL ON TABLE "public"."history_teachers" FROM "service_role";

GRANT INSERT ON TABLE "public"."history_teachers" TO "postgres";

GRANT SELECT ON TABLE "public"."history_teachers" TO "postgres";

GRANT UPDATE ON TABLE "public"."history_teachers" TO "postgres";

GRANT DELETE ON TABLE "public"."history_teachers" TO "postgres";

GRANT TRUNCATE ON TABLE "public"."history_teachers" TO "postgres";

GRANT REFERENCES ON TABLE "public"."history_teachers" TO "postgres";

GRANT TRIGGER ON TABLE "public"."history_teachers" TO "postgres";

GRANT MAINTAIN ON TABLE "public"."history_teachers" TO "postgres";

GRANT TRUNCATE ON TABLE "public"."history_teachers" TO "service_role";

GRANT REFERENCES ON TABLE "public"."history_teachers" TO "service_role";

GRANT TRIGGER ON TABLE "public"."history_teachers" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."history_teachers" TO "service_role";

DO $baseline$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_event_trigger WHERE evtname = 'ensure_rls') THEN CREATE EVENT TRIGGER "ensure_rls" ON ddl_command_end WHEN TAG IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO') EXECUTE FUNCTION public.rls_auto_enable(); END IF; END $baseline$;
