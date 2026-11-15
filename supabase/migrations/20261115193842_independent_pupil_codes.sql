-- R3: independent pupil credentials, preserved register order and bounded failed checks.
-- LOCAL ONLY until explicit owner approval. Rotates every existing pupil code and
-- unfinished-attempt token; no mapping containing old/new credentials is exported.
SET search_path = public, extensions;

ALTER TABLE public.history_pupils ADD COLUMN register_number integer;
UPDATE public.history_pupils
SET register_number = split_part(pupil_code, '-', 2)::integer;
ALTER TABLE public.history_pupils ALTER COLUMN register_number SET NOT NULL;
ALTER TABLE public.history_pupils ADD CONSTRAINT positive_register_number CHECK (register_number > 0);
ALTER TABLE public.history_pupils DROP CONSTRAINT valid_pupil_code;

CREATE FUNCTION homework_private.generate_pupil_code()
RETURNS text LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $code$
DECLARE
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  entropy bytea;
  candidate text;
BEGIN
  LOOP
    entropy := extensions.gen_random_bytes(12);
    candidate := '';
    FOR i IN 0..11 LOOP
      candidate := candidate || substr(alphabet, (get_byte(entropy,i) & 31) + 1, 1);
    END LOOP;
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.history_pupils p WHERE p.pupil_code=candidate);
  END LOOP;
  RETURN candidate;
END;
$code$;
REVOKE ALL ON FUNCTION homework_private.generate_pupil_code() FROM PUBLIC, anon, authenticated, service_role;
ALTER TABLE public.history_pupils ALTER COLUMN pupil_code SET DEFAULT homework_private.generate_pupil_code();
UPDATE public.history_pupils SET pupil_code = homework_private.generate_pupil_code();
ALTER TABLE public.history_pupils ADD CONSTRAINT random_pupil_code CHECK (pupil_code ~ '^[A-HJ-NP-Z2-9]{12}$');
-- Preserve progress and the existing deadline, but revoke any previously leaked session token.
UPDATE public.history_attempts SET attempt_token=gen_random_uuid() WHERE status='in_progress';

CREATE TABLE homework_private.pupil_code_failures (
  bucket_hash text PRIMARY KEY,
  window_started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  failures integer NOT NULL DEFAULT 0 CHECK (failures BETWEEN 0 AND 20),
  blocked_until timestamptz,
  CHECK (length(bucket_hash)=64)
);
CREATE INDEX pupil_code_failures_expiry ON homework_private.pupil_code_failures(window_started_at);
ALTER TABLE homework_private.pupil_code_failures ENABLE ROW LEVEL SECURITY;
CREATE POLICY "No direct rate counter access" ON homework_private.pupil_code_failures
FOR ALL TO PUBLIC USING (false) WITH CHECK (false);
REVOKE ALL ON homework_private.pupil_code_failures FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION homework_private.code_request_bucket()
RETURNS text LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $bucket$
DECLARE
  headers jsonb := coalesce(nullif(current_setting('request.headers',true),''),'{}')::jsonb;
  address text;
  forwarded text[];
BEGIN
  -- Hosted Supabase's Cloudflare edge supplies cf-connecting-ip. This trust boundary
  -- must be verified before deployment. On local Kong, use the LAST forwarded hop:
  -- Kong appends its observed client address, so forged leading XFF values do not win.
  address := headers->>'cf-connecting-ip';
  IF address IS NULL OR address='' THEN
    forwarded := string_to_array(coalesce(headers->>'x-forwarded-for',''),',');
    address := btrim(forwarded[array_length(forwarded,1)]);
  END IF;
  BEGIN
    address := host(address::inet);
  EXCEPTION WHEN invalid_text_representation THEN
    address := NULL;
  END;
  -- Missing trusted metadata fails closed into one shared bucket, not unlimited access.
  RETURN encode(extensions.digest(coalesce(address,'unknown-gateway'),'sha256'),'hex');
END;
$bucket$;
REVOKE ALL ON FUNCTION homework_private.code_request_bucket() FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION homework_private.check_code_budget(entered_code text)
RETURNS TABLE(allowed boolean, valid_code boolean, retry_after integer)
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $budget$
DECLARE
  bucket text := homework_private.code_request_bucket();
  at_time timestamptz := clock_timestamp();
  state homework_private.pupil_code_failures%ROWTYPE;
  found_code boolean;
BEGIN
  -- Prune at most 100 expired buckets; store neither raw addresses nor guessed codes.
  DELETE FROM homework_private.pupil_code_failures WHERE bucket_hash IN (
    SELECT f.bucket_hash FROM homework_private.pupil_code_failures f
    WHERE f.window_started_at < at_time - interval '10 minutes'
      AND coalesce(f.blocked_until,at_time) <= at_time
    ORDER BY f.window_started_at LIMIT 100
  );
  INSERT INTO homework_private.pupil_code_failures(bucket_hash) VALUES(bucket) ON CONFLICT DO NOTHING;
  SELECT f.* INTO state FROM homework_private.pupil_code_failures f WHERE f.bucket_hash=bucket FOR UPDATE;
  IF state.blocked_until IS NOT NULL AND state.blocked_until>at_time THEN
    RETURN QUERY SELECT false,false,GREATEST(1,ceil(extract(epoch FROM state.blocked_until-at_time))::integer);
    RETURN;
  END IF;
  IF state.window_started_at < at_time-interval '10 minutes' OR state.blocked_until IS NOT NULL THEN
    UPDATE homework_private.pupil_code_failures f
    SET window_started_at=at_time,failures=0,blocked_until=NULL WHERE f.bucket_hash=bucket;
    state.failures := 0;
  END IF;
  SELECT EXISTS(SELECT 1 FROM public.history_pupils p
                WHERE p.pupil_code=upper(btrim(entered_code))) INTO found_code;
  IF NOT found_code THEN
    UPDATE homework_private.pupil_code_failures f
    SET failures=state.failures+1,
        blocked_until=CASE WHEN state.failures+1>=20 THEN at_time+interval '10 seconds' ELSE NULL END
    WHERE f.bucket_hash=bucket;
    IF state.failures+1>=20 THEN
      RETURN QUERY SELECT false,false,10;
      RETURN;
    END IF;
  END IF;
  -- Successful codes do not reset the failure budget: an attacker may know their own code.
  RETURN QUERY SELECT true,found_code,0;
END;
$budget$;
REVOKE ALL ON FUNCTION homework_private.check_code_budget(text) FROM PUBLIC, anon, authenticated, service_role;

-- Return controlled HTTP statuses instead of raising after counter writes. Raising
-- would roll back those writes and let repeated failed start calls evade the limit.
ALTER FUNCTION homework_private.get_current_pupil_homework(text) RENAME TO pupil_homework_data;
ALTER FUNCTION homework_private.pupil_homework_data(text) SECURITY INVOKER;
REVOKE ALL ON FUNCTION homework_private.pupil_homework_data(text) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION homework_private.get_current_pupil_homework(entered_code text)
RETURNS TABLE(valid_code boolean, class_name text, year_group integer, quiz_id uuid, quiz_title text, topic text, week_number integer, due_at timestamp with time zone, total_questions integer, pass_mark integer, attempts_taken integer, highest_score integer, passed boolean, unfinished_attempt_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $checked$
DECLARE state record; began timestamptz := clock_timestamp();
BEGIN
  SELECT * INTO state FROM homework_private.check_code_budget(entered_code);
  IF NOT state.allowed THEN
    PERFORM set_config('response.status','429',true);
    PERFORM set_config('response.headers',jsonb_build_array(
      jsonb_build_object('Retry-After',state.retry_after::text),
      jsonb_build_object('Access-Control-Expose-Headers','Retry-After'))::text,true);
    RETURN QUERY SELECT * FROM homework_private.pupil_homework_data(NULL);
  ELSE
    RETURN QUERY SELECT * FROM homework_private.pupil_homework_data(entered_code);
  END IF;
  PERFORM pg_sleep(GREATEST(0,0.05-extract(epoch FROM clock_timestamp()-began))::double precision);
END;
$checked$;
REVOKE ALL ON FUNCTION homework_private.get_current_pupil_homework(text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION homework_private.get_current_pupil_homework(text) TO anon;

ALTER FUNCTION homework_private.start_pupil_quiz(text,uuid) RENAME TO pupil_quiz_start_data;
ALTER FUNCTION homework_private.pupil_quiz_start_data(text,uuid) SECURITY INVOKER;
REVOKE ALL ON FUNCTION homework_private.pupil_quiz_start_data(text,uuid) FROM PUBLIC, anon, authenticated, service_role;
CREATE FUNCTION homework_private.start_pupil_quiz(entered_code text,entered_quiz_id uuid)
RETURNS TABLE(attempt_id uuid,attempt_token uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $checked$
DECLARE state record; began timestamptz := clock_timestamp();
BEGIN
  SELECT * INTO state FROM homework_private.check_code_budget(entered_code);
  IF NOT state.allowed THEN
    PERFORM set_config('response.status','429',true);
    PERFORM set_config('response.headers',jsonb_build_array(
      jsonb_build_object('Retry-After',state.retry_after::text),
      jsonb_build_object('Access-Control-Expose-Headers','Retry-After'))::text,true);
    RETURN QUERY SELECT NULL::uuid,NULL::uuid;
  ELSIF NOT state.valid_code THEN
    PERFORM set_config('response.status','400',true);
    RETURN QUERY SELECT NULL::uuid,NULL::uuid;
  ELSE
    RETURN QUERY SELECT * FROM homework_private.pupil_quiz_start_data(entered_code,entered_quiz_id);
  END IF;
  PERFORM pg_sleep(GREATEST(0,0.05-extract(epoch FROM clock_timestamp()-began))::double precision);
END;
$checked$;
REVOKE ALL ON FUNCTION homework_private.start_pupil_quiz(text,uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION homework_private.start_pupil_quiz(text,uuid) TO anon;

-- Include the separate register number in authorised result rows, without parsing codes.
DROP FUNCTION public.get_history_class_results(text,uuid);
CREATE OR REPLACE FUNCTION public.get_history_class_results(requested_class text, requested_quiz uuid)
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
      AND c.class_name = requested_class
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
  WHERE c.class_name = requested_class
  GROUP BY p.id, p.pupil_code, q.pass_mark
  ORDER BY p.register_number,p.pupil_code;
END;
$function$;
REVOKE ALL ON FUNCTION public.get_history_class_results(text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_history_class_results(text,uuid) TO authenticated;

-- Rebind exposed wrappers after renaming private implementations, invalidating old plans.
CREATE OR REPLACE FUNCTION homework_api.start_pupil_quiz(entered_code text, entered_quiz_id uuid)
RETURNS TABLE(attempt_id uuid,attempt_token uuid)
LANGUAGE sql SECURITY INVOKER SET search_path = ''
AS $wrapper$ SELECT * FROM homework_private.start_pupil_quiz(entered_code,entered_quiz_id); $wrapper$;
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


CREATE INDEX history_pupils_class_register ON public.history_pupils(class_id,register_number);
NOTIFY pgrst, 'reload schema';
