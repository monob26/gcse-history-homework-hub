-- Quiz Manager schema recovered from hosted TEST and matched against LIVE catalogs.
-- Schema only. Existing hosted installations already contain these objects.
BEGIN;
SET LOCAL check_function_bodies = off;
GRANT USAGE ON SCHEMA homework_private TO authenticated;

CREATE TABLE public.quiz_manager_allocations (
  quiz_id uuid NOT NULL,
  class_id uuid NOT NULL
);

CREATE TABLE public.quiz_manager_audit (
  id bigint GENERATED ALWAYS AS IDENTITY,
  quiz_id uuid,
  actor_id uuid,
  action text NOT NULL,
  outcome text NOT NULL,
  reason text,
  revision bigint,
  recorded_at timestamp with time zone DEFAULT clock_timestamp() NOT NULL
);

CREATE TABLE public.quiz_manager_quizzes (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  title text NOT NULL,
  year_group integer NOT NULL,
  topic text,
  week_number integer,
  content jsonb DEFAULT '{"questions": [], "schema_version": 1}'::jsonb NOT NULL,
  revision bigint DEFAULT 1 NOT NULL,
  state text DEFAULT 'draft'::text NOT NULL,
  approved_revision bigint,
  approved_by uuid,
  approved_at timestamp with time zone,
  release_at timestamp with time zone,
  due_at timestamp with time zone,
  total_questions integer DEFAULT 25 NOT NULL,
  pass_mark integer DEFAULT 20 NOT NULL,
  runtime_quiz_id uuid,
  first_started_at timestamp with time zone,
  created_by uuid NOT NULL,
  updated_by uuid NOT NULL,
  created_at timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
  updated_at timestamp with time zone DEFAULT clock_timestamp() NOT NULL
);

CREATE TABLE public.quiz_manager_revisions (
  quiz_id uuid NOT NULL,
  revision bigint NOT NULL,
  snapshot jsonb NOT NULL,
  actor_id uuid NOT NULL,
  recorded_at timestamp with time zone DEFAULT clock_timestamp() NOT NULL
);

CREATE OR REPLACE FUNCTION homework_api.quiz_session(action text, payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$
 SELECT CASE WHEN $1='list' THEN homework_private.qm_home_list($2)
 ELSE homework_private.qm3_session($1,$2) END
$function$;

CREATE OR REPLACE FUNCTION homework_private.qm_attempt_identity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF ROW(OLD.quiz_id,OLD.pupil_id) IS DISTINCT FROM ROW(NEW.quiz_id,NEW.pupil_id)
    AND EXISTS (SELECT FROM public.quiz_manager_quizzes WHERE runtime_quiz_id IN (OLD.quiz_id,NEW.quiz_id)) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='immutable_attempt_identity';
  END IF;
  RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION homework_private.qm_classes()
 RETURNS TABLE(id uuid, class_name text, year_group integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (SELECT FROM public.history_teachers WHERE user_id=auth.uid()) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='teacher_required';
  END IF;
  RETURN QUERY SELECT c.id,c.class_name,c.year_group FROM public.history_classes c
    WHERE c.year_group IN (9,10,11) ORDER BY c.year_group,c.class_name,c.id;
END $function$;

CREATE OR REPLACE FUNCTION homework_private.qm_content_errors(document jsonb, topic text, complete boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
DECLARE out jsonb := '[]'; q jsonb; v jsonb; a jsonb; c jsonb; entries jsonb;
 qi integer := -1; vi integer; p text; ep text; f text; k text; field_name text;
 allowed text[]; ids text[]; seen text[] := '{}'; labels text[]; right_labels text[];
 accepted text[]; label text; correct_ids text[]; typed boolean; choices boolean;
BEGIN
 IF document IS NULL OR jsonb_typeof(document)<>'object' THEN
   RETURN homework_private.qm_issue('content','Expected an object'); END IF;
 FOR k IN SELECT jsonb_object_keys(document) LOOP
   IF k NOT IN ('schema_version','questions') THEN out:=out||homework_private.qm_issue('content.'||k,'Unsupported field'); END IF;
 END LOOP;
 IF document->'schema_version' IS DISTINCT FROM '1'::jsonb THEN out:=out||homework_private.qm_issue('schema_version','Use schema_version 1'); END IF;
 IF octet_length(document::text)>1048576 THEN out:=out||homework_private.qm_issue('content','Maximum content size is 1 MiB'); END IF;
 IF jsonb_typeof(document->'questions') IS DISTINCT FROM 'array' THEN RETURN out||homework_private.qm_issue('questions','Expected a question array'); END IF;
 IF jsonb_array_length(document->'questions')>25 OR (complete AND jsonb_array_length(document->'questions')<>25) THEN
   out:=out||homework_private.qm_issue('questions','Exactly 25 valid questions are required for approval'); END IF;
 FOR q IN SELECT value FROM jsonb_array_elements(document->'questions') LOOP
   qi:=qi+1;p:='questions['||qi||']';
   IF jsonb_typeof(q)<>'object' THEN out:=out||homework_private.qm_issue(p,'Expected a question object',qi); CONTINUE; END IF;
   IF jsonb_typeof(q->'id') IS DISTINCT FROM 'string' OR homework_private.qm4_trim(q->>'id')='' OR length(q->>'id')>100 OR q->>'id'=ANY(seen) THEN
     out:=out||homework_private.qm_issue(p||'.id','Use a unique non-empty ID (maximum 100 characters)',qi); END IF;
   seen:=array_append(seen,q->>'id');
   IF q->>'type' IS NULL OR q->>'type' NOT IN ('multiple_choice','missing_word','matching','chronology','select_all','spot_the_mistake','cause_consequence','who_am_i') THEN
     out:=out||homework_private.qm_issue(p||'.type','Unsupported question type',qi); CONTINUE; END IF;
   choices:=q->>'type' IN ('multiple_choice','select_all','spot_the_mistake','cause_consequence');
   typed:=q->>'type' IN ('missing_word','who_am_i');
   allowed:=ARRAY['id','type','prompt','explanation','seconds']||CASE WHEN choices THEN ARRAY['options','correct']
     WHEN typed AND q->>'type'='who_am_i' THEN ARRAY['answers','clues'] WHEN typed THEN ARRAY['answers']
     WHEN q->>'type'='matching' THEN ARRAY['pairs'] ELSE ARRAY['events','correct'] END;
   FOR k IN SELECT jsonb_object_keys(q) LOOP
     IF NOT k=ANY(allowed) THEN out:=out||homework_private.qm_issue(p||'.'||k,'Unsupported field',qi); END IF;
   END LOOP;
   FOREACH f IN ARRAY ARRAY['prompt','explanation'] LOOP
     IF (complete OR q ? f) AND (jsonb_typeof(q->f) IS DISTINCT FROM 'string' OR length(q->>f)>4000 OR (complete AND homework_private.qm4_trim(q->>f)='')) THEN
       out:=out||homework_private.qm_issue(p||'.'||f,'Enter '||f||' (maximum 4000 characters)',qi); END IF;
   END LOOP;
   IF (complete OR q ? 'seconds') AND q->'seconds' IS DISTINCT FROM
     to_jsonb(CASE WHEN q->>'type' IN ('matching','chronology','select_all') THEN 60 ELSE 45 END) THEN
     out:=out||homework_private.qm_issue(p||'.seconds','Incorrect timer for question type',qi); END IF;
   IF complete AND q->>'type'='cause_consequence' AND coalesce(topic,'') !~* 'cold[[:space:]_-]*war' THEN
     out:=out||homework_private.qm_issue(p||'.type','Cause / Consequence is Cold War only',qi); END IF;
   IF NOT typed THEN
     field_name:=CASE WHEN choices THEN 'options' WHEN q->>'type'='matching' THEN 'pairs' ELSE 'events' END;
     entries:=q->field_name;ids:='{}';labels:='{}';right_labels:='{}';
     IF complete OR q ? field_name THEN
       IF jsonb_typeof(entries) IS DISTINCT FROM 'array' THEN
         out:=out||homework_private.qm_issue(p||'.'||field_name,'Expected an array',qi);
       ELSE
         IF (complete AND NOT(jsonb_array_length(entries)=CASE WHEN choices THEN 4 ELSE 3 END OR (q->>'type'='select_all' AND jsonb_array_length(entries)=5)))
           OR jsonb_array_length(entries)>(CASE WHEN q->>'type'='select_all' THEN 5 WHEN choices THEN 4 ELSE 3 END) THEN
           out:=out||homework_private.qm_issue(p||'.'||field_name,'Incorrect number of entries',qi); END IF;
         vi:=-1;
         FOR v IN SELECT value FROM jsonb_array_elements(entries) LOOP
           vi:=vi+1;ep:=p||'.'||field_name||'['||vi||']';
           IF jsonb_typeof(v)<>'object' THEN out:=out||homework_private.qm_issue(ep,'Expected an entry object',qi); CONTINUE; END IF;
           FOR k IN SELECT jsonb_object_keys(v) LOOP
             IF k<> 'id' AND NOT (field_name='pairs' AND k IN ('left','right')) AND NOT (field_name<>'pairs' AND k='text') THEN
               out:=out||homework_private.qm_issue(ep||'.'||k,'Unsupported field',qi); END IF;
           END LOOP;
           IF jsonb_typeof(v->'id') IS DISTINCT FROM 'string' OR homework_private.qm4_trim(v->>'id')='' OR length(v->>'id')>100 OR v->>'id'=ANY(ids) THEN
             out:=out||homework_private.qm_issue(ep||'.id','Entry IDs must be unique',qi); END IF;
           ids:=array_append(ids,v->>'id');
           FOREACH f IN ARRAY (CASE WHEN field_name='pairs' THEN ARRAY['left','right'] ELSE ARRAY['text'] END) LOOP
             IF (complete OR v ? f) AND (jsonb_typeof(v->f) IS DISTINCT FROM 'string' OR length(v->>f)>4000 OR (complete AND homework_private.qm4_trim(v->>f)='')) THEN
               out:=out||homework_private.qm_issue(ep||'.'||f,'Enter a non-empty label',qi); END IF;
             label:=homework_private.qm_normalize(coalesce(v->>f,''));
             IF label<>'' AND label=ANY(CASE WHEN f='right' THEN right_labels ELSE labels END) THEN
               out:=out||homework_private.qm_issue(ep||'.'||f,'Labels must be distinguishable',qi); END IF;
             IF f='right' THEN right_labels:=array_append(right_labels,label); ELSE labels:=array_append(labels,label); END IF;
             IF field_name='events' AND pg_catalog.normalize(coalesce(v->>f,''),'NFKC') ~* '\m[0-9]{3,4}\M|\m[0-9]{1,2}[/.\-][0-9]{1,2}([/.\-][0-9]{2,4})?\M|\m[0-9]{1,2}(st|nd|rd|th)?[[:space:]]+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\M|\m(january|february|march|april|may|june|july|august|september|october|november|december)[[:space:]]+[0-9]' THEN
               out:=out||homework_private.qm_issue(ep||'.text','Remove dates and years from event labels',qi); END IF;
           END LOOP;
         END LOOP;
       END IF;
     END IF;
     IF field_name<>'pairs' AND (complete OR q ? 'correct') THEN
       c:=q->'correct';correct_ids:='{}';
       IF jsonb_typeof(c) IS DISTINCT FROM 'array' THEN out:=out||homework_private.qm_issue(p||'.correct','Expected correct entry IDs',qi);
       ELSE
         FOR v IN SELECT value FROM jsonb_array_elements(c) LOOP
           label:=v#>>'{}';
           IF jsonb_typeof(v)<>'string' OR NOT label=ANY(ids) OR label=ANY(correct_ids) THEN
             out:=out||homework_private.qm_issue(p||'.correct','Correct answers must reference distinct entry IDs',qi); END IF;
           correct_ids:=array_append(correct_ids,label);
         END LOOP;
         IF (complete AND NOT(CASE WHEN q->>'type'='chronology' THEN jsonb_array_length(c)=3 WHEN q->>'type'='select_all' THEN jsonb_array_length(c) IN (2,3) ELSE jsonb_array_length(c)=1 END))
           OR jsonb_array_length(c)>(CASE WHEN q->>'type' IN ('chronology','select_all') THEN 3 ELSE 1 END) THEN
           out:=out||homework_private.qm_issue(p||'.correct','Incorrect number of correct answers',qi); END IF;
       END IF;
     END IF;
   ELSE
     a:=q->'answers';accepted:='{}';
     IF complete OR q ? 'answers' THEN
       IF jsonb_typeof(a) IS DISTINCT FROM 'object' THEN out:=out||homework_private.qm_issue(p||'.answers','Provide typed-answer settings',qi);
       ELSE
         FOR k IN SELECT jsonb_object_keys(a) LOOP
           IF k NOT IN ('canonical','aliases','surname_aliases','confusable','allow_minor_typos') THEN out:=out||homework_private.qm_issue(p||'.answers.'||k,'Unsupported field',qi); END IF;
         END LOOP;
         IF (complete OR a ? 'canonical') AND (jsonb_typeof(a->'canonical') IS DISTINCT FROM 'string' OR length(a->>'canonical')>4000 OR (complete AND homework_private.qm4_trim(a->>'canonical')='')) THEN
           out:=out||homework_private.qm_issue(p||'.answers.canonical','Enter the canonical answer',qi); END IF;
         accepted:=array_append(accepted,homework_private.qm_normalize(a->>'canonical'));
         FOREACH f IN ARRAY ARRAY['aliases','surname_aliases','confusable'] LOOP
           IF complete OR a ? f THEN
             IF jsonb_typeof(a->f) IS DISTINCT FROM 'array' THEN out:=out||homework_private.qm_issue(p||'.answers.'||f,'Use an array of up to 50 non-empty strings',qi);
             ELSE
               IF jsonb_array_length(a->f)>50 THEN out:=out||homework_private.qm_issue(p||'.answers.'||f,'Use at most 50 strings',qi); END IF;
               FOR v IN SELECT value FROM jsonb_array_elements(a->f) LOOP
                 IF jsonb_typeof(v)<>'string' OR homework_private.qm4_trim(v#>>'{}')='' OR length(v#>>'{}')>4000 THEN
                   out:=out||homework_private.qm_issue(p||'.answers.'||f,'Use non-empty strings',qi); END IF;
                 IF f<>'confusable' THEN accepted:=array_append(accepted,homework_private.qm_normalize(v#>>'{}')); END IF;
               END LOOP;
               IF f='surname_aliases' AND q->>'type'='missing_word' AND jsonb_array_length(a->f)>0 THEN out:=out||homework_private.qm_issue(p||'.answers.surname_aliases','Surname aliases apply only to Who Am I?',qi); END IF;
             END IF;
           END IF;
         END LOOP;
         IF (complete OR a ? 'allow_minor_typos') AND jsonb_typeof(a->'allow_minor_typos') IS DISTINCT FROM 'boolean' THEN out:=out||homework_private.qm_issue(p||'.answers.allow_minor_typos','Choose whether guarded minor typos are allowed',qi); END IF;
         IF jsonb_typeof(a->'confusable')='array' THEN
           FOR v IN SELECT value FROM jsonb_array_elements(a->'confusable') LOOP
             IF homework_private.qm_normalize(v#>>'{}')=ANY(accepted) THEN out:=out||homework_private.qm_issue(p||'.answers.confusable','An answer cannot be both accepted and excluded',qi); END IF;
           END LOOP;
         END IF;
       END IF;
     END IF;
     IF q->>'type'='who_am_i' AND (complete OR q ? 'clues') THEN
       IF jsonb_typeof(q->'clues') IS DISTINCT FROM 'array' THEN out:=out||homework_private.qm_issue(p||'.clues','Provide exactly three non-empty clues',qi);
       ELSE
         IF jsonb_array_length(q->'clues')<>3 OR EXISTS(SELECT FROM jsonb_array_elements(q->'clues') x WHERE jsonb_typeof(x)<>'string' OR length(x#>>'{}')>4000 OR (complete AND homework_private.qm4_trim(x#>>'{}')='')) THEN
           out:=out||homework_private.qm_issue(p||'.clues','Provide exactly three non-empty clues',qi); END IF;
       END IF;
     END IF;
   END IF;
 END LOOP;
 RETURN out;
END $function$;

CREATE OR REPLACE FUNCTION homework_private.qm_draft_shape()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 IF jsonb_array_length(homework_private.qm_content_errors(NEW.content,coalesce(NEW.topic,''),false))>0 THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='invalid_draft'; END IF;
 RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION homework_private.qm_guard_quiz()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.state <> 'draft' OR OLD.runtime_quiz_id IS NOT NULL OR OLD.first_started_at IS NOT NULL
      OR EXISTS (SELECT FROM public.quiz_manager_allocations WHERE quiz_id = OLD.id) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='draft_has_references';
    END IF;
    RETURN OLD;
  END IF;
  IF NEW.id <> OLD.id OR NEW.created_by <> OLD.created_by OR NEW.created_at <> OLD.created_at
    OR (OLD.runtime_quiz_id IS NOT NULL AND NEW.runtime_quiz_id IS DISTINCT FROM OLD.runtime_quiz_id)
    OR (OLD.first_started_at IS NOT NULL AND NEW.first_started_at IS DISTINCT FROM OLD.first_started_at) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='immutable_identity_or_lock';
  END IF;
  IF ROW(NEW.content,NEW.title,NEW.year_group,NEW.topic,NEW.week_number,NEW.total_questions,NEW.pass_mark)
    IS DISTINCT FROM ROW(OLD.content,OLD.title,OLD.year_group,OLD.topic,OLD.week_number,OLD.total_questions,OLD.pass_mark) THEN
    IF OLD.first_started_at IS NOT NULL OR EXISTS (
      SELECT FROM public.history_attempts WHERE quiz_id=OLD.runtime_quiz_id) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='quiz_locked';
    END IF;
    IF OLD.state <> 'draft' OR NEW.state <> 'draft' THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='take_offline_first';
    END IF;
  END IF;
  RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION homework_private.qm_guard_runtime()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE target_id uuid; q public.quiz_manager_quizzes; old_id uuid;
BEGIN
  -- Lock both owners in a deterministic order if a question is moved.
  IF TG_TABLE_NAME = 'history_questions' THEN
    IF TG_OP <> 'INSERT' THEN old_id := OLD.quiz_id; END IF;
    IF TG_OP <> 'DELETE' THEN target_id := NEW.quiz_id; END IF;
  ELSE
    old_id := OLD.id;
    IF TG_OP = 'UPDATE' AND ROW(NEW.quiz_title,NEW.year_group,NEW.topic,NEW.week_number,
      NEW.total_questions,NEW.pass_mark,NEW.version_number) IS NOT DISTINCT FROM
      ROW(OLD.quiz_title,OLD.year_group,OLD.topic,OLD.week_number,
      OLD.total_questions,OLD.pass_mark,OLD.version_number) THEN RETURN NEW; END IF;
  END IF;
  FOR q IN SELECT * FROM public.quiz_manager_quizzes
    WHERE runtime_quiz_id IN (old_id,target_id) ORDER BY id FOR UPDATE LOOP
    IF q.first_started_at IS NOT NULL OR EXISTS (SELECT FROM public.history_attempts WHERE quiz_id=q.runtime_quiz_id) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='quiz_locked';
    END IF;
    IF q.state <> 'draft' THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='take_offline_first';
    END IF;
  END LOOP;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION homework_private.qm_home_list(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE budget record; pupil public.history_pupils; class public.history_classes;
 quizzes jsonb; began timestamptz:=clock_timestamp();
BEGIN
 IF jsonb_typeof(payload) IS DISTINCT FROM 'object' OR octet_length(payload::text)>32000
 OR jsonb_typeof(payload->'code') IS DISTINCT FROM 'string'
 OR EXISTS(SELECT FROM jsonb_object_keys(payload) k WHERE k<>'code') THEN
   RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_request'; END IF;
 SELECT * INTO budget FROM homework_private.check_code_budget(payload->>'code');
 IF NOT budget.allowed THEN
   PERFORM set_config('response.status','429',true);
   PERFORM set_config('response.headers',jsonb_build_array(jsonb_build_object('Retry-After',budget.retry_after::text),jsonb_build_object('Access-Control-Expose-Headers','Retry-After'))::text,true);
   RETURN jsonb_build_object('valid_code',false);
 END IF;
 IF NOT budget.valid_code THEN RETURN jsonb_build_object('valid_code',false); END IF;
 SELECT * INTO pupil FROM public.history_pupils WHERE pupil_code=upper(btrim(payload->>'code'));
 SELECT * INTO class FROM public.history_classes WHERE id=pupil.class_id;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'valid_code',true,'class_name',class.class_name,'year_group',class.year_group,
   'quiz_id',h.id,'quiz_title',h.quiz_title,'topic',h.topic,'week_number',h.week_number,
   'due_at',h.due_at,'total_questions',h.total_questions,'pass_mark',h.pass_mark,
   'attempts_taken',a.attempts,'highest_score',a.highest,
   'passed',coalesce(a.highest>=h.pass_mark,false),'first_passed_at',a.first_pass,
   'deadline_status',CASE WHEN a.first_pass IS NULL THEN NULL WHEN h.due_at IS NULL OR a.first_pass<=h.due_at THEN 'On time' ELSE 'Late' END,
   'unfinished_attempt_id',a.unfinished,
   'time_limits',(SELECT jsonb_agg(jsonb_build_object('seconds',s,'questions',n) ORDER BY s)
     FROM (SELECT time_allowed_seconds s,count(*) n FROM public.history_questions WHERE quiz_id=h.id GROUP BY 1) t)
 ) ORDER BY coalesce(m.release_at,h.created_at) DESC,h.id DESC),'[]') INTO quizzes
 FROM public.history_quizzes h
 LEFT JOIN public.quiz_manager_quizzes m ON m.runtime_quiz_id=h.id
 CROSS JOIN LATERAL (
   SELECT count(*) FILTER(WHERE status='completed') attempts,
     max(score) FILTER(WHERE status='completed') highest,
     min(completed_at) FILTER(WHERE status='completed' AND score>=h.pass_mark) first_pass,
     (array_agg(id ORDER BY started_at DESC,id DESC) FILTER(WHERE status='in_progress'))[1] unfinished
   FROM public.history_attempts WHERE pupil_id=pupil.id AND quiz_id=h.id
 ) a
 WHERE homework_private.qm3_available(pupil.id,h.id);
 PERFORM pg_sleep(greatest(0,0.05-extract(epoch FROM clock_timestamp()-began))::double precision);
 RETURN jsonb_build_object('valid_code',true,'class_name',class.class_name,'year_group',class.year_group,'quizzes',quizzes);
END $function$;

CREATE OR REPLACE FUNCTION homework_private.qm_import(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE result jsonb; errors jsonb; failure text;
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS(SELECT FROM public.history_teachers WHERE user_id=auth.uid()) THEN
   INSERT INTO public.quiz_manager_audit(actor_id,action,outcome,reason)
     VALUES(auth.uid(),'import','denied','teacher_required');
   RETURN jsonb_build_object('ok',false,'error','teacher_required'); END IF;
 IF payload IS NULL OR jsonb_typeof(payload)<>'object' THEN
   failure:='invalid_metadata';
 ELSIF EXISTS(SELECT FROM jsonb_object_keys(payload) k WHERE k NOT IN ('title','year_group','topic','week_number','content')) THEN
   failure:='invalid_metadata';
 ELSE
   errors:=homework_private.qm_content_errors(payload->'content',payload->>'topic',true);
   IF jsonb_array_length(errors)>0 THEN failure:='validation_failed';
   ELSIF jsonb_typeof(payload->'topic') IS DISTINCT FROM 'string' OR homework_private.qm4_trim(payload->>'topic')='' OR length(payload->>'topic')>200
     OR jsonb_typeof(payload->'week_number') IS DISTINCT FROM 'number' OR payload->>'week_number' !~ '^[1-9][0-9]{0,8}$' THEN failure:='invalid_metadata'; END IF;
 END IF;
 IF failure IS NULL THEN
   BEGIN
     result:=homework_private.qm_write('create',NULL,NULL,jsonb_build_object('title',payload->'title','year_group',payload->'year_group'));
     IF result->>'ok' <> 'true' THEN failure:=result->>'error';RAISE EXCEPTION 'import_refused'; END IF;
     result:=homework_private.qm_write('save',(result->>'id')::uuid,1,payload);
     IF result->>'ok' <> 'true' THEN failure:=result->>'error';RAISE EXCEPTION 'import_refused'; END IF;
   EXCEPTION WHEN raise_exception THEN
     IF failure IS NULL THEN RAISE; END IF;
   END;
 END IF;
 INSERT INTO public.quiz_manager_audit(quiz_id,actor_id,action,outcome,reason,revision)
   VALUES(CASE WHEN failure IS NULL THEN (result->>'id')::uuid ELSE NULL END,auth.uid(),'import',
     CASE WHEN failure IS NULL THEN 'success' ELSE 'denied' END,failure,
     CASE WHEN failure IS NULL THEN (result#>>'{quiz,revision}')::bigint ELSE NULL END);
 IF failure IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'error',failure,'errors',coalesce(errors,'[]')); END IF;
 RETURN result;
END $function$;

CREATE OR REPLACE FUNCTION homework_private.qm_issue(path text, message text, question integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 SELECT jsonb_build_array(jsonb_build_object('path',$1,'message',$2,'question',$3))
$function$;

CREATE OR REPLACE FUNCTION homework_private.qm_normalize(value text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 SELECT regexp_replace(lower(pg_catalog.normalize($1,'NFKC')),'\s','','g')
$function$;

CREATE OR REPLACE FUNCTION homework_private.qm_start_lock()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE q public.quiz_manager_quizzes; pupil_class uuid;
BEGIN
  SELECT * INTO q FROM public.quiz_manager_quizzes WHERE runtime_quiz_id=NEW.quiz_id FOR UPDATE;
  IF NOT FOUND THEN RETURN NEW; END IF;
  SELECT class_id INTO pupil_class FROM public.history_pupils WHERE id=NEW.pupil_id;
  IF q.state NOT IN ('published','scheduled') OR q.approved_revision IS DISTINCT FROM q.revision
    OR q.release_at IS NULL OR q.release_at > clock_timestamp()
    OR NOT EXISTS (SELECT FROM public.quiz_manager_allocations
      WHERE quiz_id=q.id AND class_id=pupil_class) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='quiz_not_available';
  END IF;
  IF q.first_started_at IS NULL THEN
    UPDATE public.quiz_manager_quizzes SET first_started_at=clock_timestamp() WHERE id=q.id;
    INSERT INTO public.quiz_manager_audit(quiz_id,action,outcome,revision)
      VALUES(q.id,'first_start','success',q.revision);
  END IF;
  RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION homework_private.qm_valid_draft(document jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
DECLARE q jsonb; seen text[] := '{}';
BEGIN
  IF document IS NULL OR jsonb_typeof(document) <> 'object'
    OR document->'schema_version' IS DISTINCT FROM '1'::jsonb
    OR jsonb_typeof(document->'questions') IS DISTINCT FROM 'array'
    OR octet_length(document::text) > 1048576 THEN RETURN false; END IF;
  IF EXISTS (SELECT FROM jsonb_object_keys(document) k WHERE k NOT IN ('schema_version','questions'))
    OR jsonb_array_length(document->'questions') > 25 THEN RETURN false; END IF;
  FOR q IN SELECT value FROM jsonb_array_elements(document->'questions') LOOP
    IF jsonb_typeof(q) <> 'object' OR jsonb_typeof(q->'id') IS DISTINCT FROM 'string'
      OR length(q->>'id') NOT BETWEEN 1 AND 100 OR q->>'id' = ANY(seen)
      OR jsonb_typeof(q->'type') IS DISTINCT FROM 'string'
      OR q->>'type' NOT IN ('multiple_choice','missing_word','matching','chronology',
        'select_all','spot_the_mistake','cause_consequence','who_am_i') THEN RETURN false; END IF;
    seen := array_append(seen,q->>'id');
  END LOOP;
  RETURN true;
END $function$;

CREATE OR REPLACE FUNCTION homework_private.qm_validate(content jsonb, topic text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS(SELECT FROM public.history_teachers WHERE user_id=auth.uid()) THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='teacher_required'; END IF;
 RETURN homework_private.qm_content_errors(content,topic,true);
END $function$;

CREATE OR REPLACE FUNCTION homework_private.qm_write(action text, quiz_id uuid, expected_revision bigint, payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE q public.quiz_manager_quizzes; source public.quiz_manager_quizzes;
  actor uuid := auth.uid(); failure text; event_action text;
BEGIN
  event_action := CASE WHEN action IN ('create','save','duplicate','delete','take_offline') THEN action ELSE 'invalid_action' END;
  IF actor IS NULL OR NOT EXISTS (SELECT FROM public.history_teachers WHERE user_id=actor) THEN
    failure := 'teacher_required';
  ELSE
    BEGIN
      IF action IS NULL OR action NOT IN ('create','save','duplicate','delete','take_offline') THEN
        RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_action';
      END IF;
      IF payload IS NULL OR jsonb_typeof(payload) <> 'object' OR octet_length(payload::text)>1100000 THEN
        RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_payload';
      END IF;
      IF EXISTS (SELECT FROM jsonb_object_keys(payload) k WHERE NOT (
        (action='create' AND k IN ('title','year_group')) OR
        (action='save' AND k IN ('title','year_group','topic','week_number','content')) OR
        (action='duplicate' AND k='title') OR
        (action IN ('delete','take_offline') AND k='confirmed'))) THEN
        RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='unexpected_field';
      END IF;
      IF action='create' THEN
        IF quiz_id IS NOT NULL OR expected_revision IS NOT NULL THEN
          RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_create';
        END IF;
      ELSE
        SELECT * INTO q FROM public.quiz_manager_quizzes m WHERE m.id=quiz_id FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='quiz_not_found'; END IF;
        IF expected_revision IS NULL OR expected_revision <> q.revision THEN
          RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='revision_conflict';
        END IF;
      END IF;
      IF action IN ('create','save') OR (action='duplicate' AND payload ? 'title') THEN
        IF jsonb_typeof(payload->'title') IS DISTINCT FROM 'string'
          OR length(homework_private.qm4_trim(payload->>'title')) NOT BETWEEN 1 AND 200 THEN
          RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_title';
        END IF;
      END IF;
      IF action IN ('create','save') AND (payload->'year_group' IS NULL
        OR payload->'year_group' NOT IN ('9'::jsonb,'10'::jsonb,'11'::jsonb)) THEN
        RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_year';
      END IF;
      IF action='create' THEN
        INSERT INTO public.quiz_manager_quizzes(title,year_group,created_by,updated_by)
          VALUES(homework_private.qm4_trim(payload->>'title'),(payload->>'year_group')::integer,actor,actor) RETURNING * INTO q;
      ELSIF action='duplicate' THEN
        source := q;
        INSERT INTO public.quiz_manager_quizzes(title,year_group,topic,week_number,content,created_by,updated_by)
          VALUES(coalesce(payload->>'title',left(source.title,193)||' (copy)'),source.year_group,
          source.topic,source.week_number,source.content,actor,actor) RETURNING * INTO q;
      ELSE
        IF q.first_started_at IS NOT NULL OR EXISTS (SELECT FROM public.history_attempts WHERE history_attempts.quiz_id=q.runtime_quiz_id) THEN
          RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='quiz_locked';
        END IF;
        IF action='save' THEN
          IF q.state <> 'draft' THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='take_offline_first'; END IF;
          IF NOT homework_private.qm_valid_draft(payload->'content') THEN
            RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_draft';
          END IF;
          IF payload ? 'topic' AND payload->'topic' <> 'null'::jsonb AND (
            jsonb_typeof(payload->'topic') <> 'string' OR length(payload->>'topic')>200) THEN
            RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_topic';
          END IF;
          IF payload ? 'week_number' AND payload->'week_number' <> 'null'::jsonb AND (
            jsonb_typeof(payload->'week_number') <> 'number' OR payload->>'week_number' !~ '^[1-9][0-9]{0,8}$') THEN
            RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_week';
          END IF;
          UPDATE public.quiz_manager_quizzes m SET title=homework_private.qm4_trim(payload->>'title'),
            year_group=(payload->>'year_group')::integer,topic=nullif(homework_private.qm4_trim(payload->>'topic'),''),
            week_number=(payload->>'week_number')::integer,content=payload->'content',
            revision=m.revision+1,updated_by=actor,updated_at=clock_timestamp()
            WHERE m.id=q.id RETURNING * INTO q;
        ELSIF action='take_offline' THEN
          IF payload->'confirmed' IS DISTINCT FROM 'true'::jsonb THEN
            RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='confirmation_required';
          END IF;
          -- Manager availability is withdrawn first under the same row lock.
          UPDATE public.quiz_manager_quizzes m SET state='draft',approved_revision=NULL,
            approved_by=NULL,approved_at=NULL,release_at=NULL,revision=m.revision+1,
            updated_by=actor,updated_at=clock_timestamp() WHERE m.id=q.id RETURNING * INTO q;
          UPDATE public.history_quizzes SET is_published=false WHERE id=q.runtime_quiz_id;
        ELSIF action='delete' THEN
          IF payload->'confirmed' IS DISTINCT FROM 'true'::jsonb THEN
            RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='confirmation_required';
          END IF;
          DELETE FROM public.quiz_manager_quizzes WHERE id=q.id;
        END IF;
      END IF;
      IF action <> 'delete' THEN
        INSERT INTO public.quiz_manager_revisions(quiz_id,revision,snapshot,actor_id)
          VALUES(q.id,q.revision,to_jsonb(q),actor);
      END IF;
    EXCEPTION
      WHEN SQLSTATE '22023' THEN failure := SQLERRM;
      WHEN SQLSTATE '23514' THEN failure := CASE WHEN SQLERRM IN
        ('quiz_locked','take_offline_first','draft_has_references','immutable_identity_or_lock')
        THEN SQLERRM ELSE 'invalid_draft' END;
      WHEN foreign_key_violation THEN failure := 'draft_has_references';
    END;
  END IF;
  INSERT INTO public.quiz_manager_audit(quiz_id,actor_id,action,outcome,reason,revision)
    VALUES(CASE WHEN failure IS NULL THEN q.id ELSE quiz_id END,actor,event_action,
      CASE WHEN failure IS NULL THEN 'success' ELSE 'denied' END,failure,
      CASE WHEN failure IS NULL THEN q.revision ELSE NULL END);
  IF failure IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'error',failure); END IF;
  RETURN jsonb_build_object('ok',true,'quiz',CASE WHEN action='delete' THEN NULL ELSE to_jsonb(q) END,'id',q.id);
END $function$;

CREATE OR REPLACE FUNCTION public.quiz_manager_class_results(class_id uuid, quiz_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ SELECT homework_private.qm3_results($1,$2) $function$;

CREATE OR REPLACE FUNCTION public.quiz_manager_classes()
 RETURNS TABLE(id uuid, class_name text, year_group integer)
 LANGUAGE sql
 SET search_path TO ''
AS $function$ SELECT * FROM homework_private.qm_classes() $function$;

CREATE OR REPLACE FUNCTION public.quiz_manager_import(payload jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ SELECT homework_private.qm_import($1) $function$;

CREATE OR REPLACE FUNCTION public.quiz_manager_release(action text, quiz_id uuid, expected_revision bigint, payload jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ SELECT homework_private.qm3_release($1,$2,$3,$4) $function$;

CREATE OR REPLACE FUNCTION public.quiz_manager_validate(content jsonb, topic text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ SELECT homework_private.qm_validate($1,$2) $function$;

CREATE OR REPLACE FUNCTION public.quiz_manager_write(action text, quiz_id uuid DEFAULT NULL::uuid, expected_revision bigint DEFAULT NULL::bigint, payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  SELECT homework_private.qm_write($1,$2,$3,$4)
$function$;

CREATE OR REPLACE FUNCTION homework_private.qm3_available(pupil uuid, quiz uuid)
 RETURNS boolean
 LANGUAGE sql
 SET search_path TO ''
AS $function$
 SELECT EXISTS(SELECT FROM public.history_quizzes h JOIN public.history_pupils p ON p.id=$1
 JOIN public.history_classes c ON c.id=p.class_id WHERE h.id=$2 AND h.year_group=c.year_group AND h.is_published
 AND (NOT EXISTS(SELECT FROM public.quiz_manager_quizzes m WHERE m.runtime_quiz_id=h.id)
 OR EXISTS(SELECT FROM public.quiz_manager_quizzes m JOIN public.quiz_manager_allocations a ON a.quiz_id=m.id
 WHERE m.runtime_quiz_id=h.id AND a.class_id=p.class_id AND m.state IN ('published','scheduled')
 AND m.approved_revision=m.revision AND m.release_at<=clock_timestamp())))
$function$;

CREATE OR REPLACE FUNCTION homework_private.qm3_distance(a text, b text)
 RETURNS integer
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
DECLARE i integer:=1; j integer:=1; n integer:=0; tmp text; BEGIN
 IF abs(length(a)-length(b))>1 THEN RETURN 2; END IF;
 IF length(a)=length(b) THEN
   FOR i IN 1..length(a) LOOP IF substr(a,i,1)<>substr(b,i,1) THEN n:=n+1; END IF; END LOOP; RETURN n;
 END IF;
 IF length(a)>length(b) THEN tmp:=a;a:=b;b:=tmp; END IF;
 WHILE i<=length(a) AND j<=length(b) LOOP
   IF substr(a,i,1)=substr(b,j,1) THEN i:=i+1;j:=j+1; ELSE j:=j+1;n:=n+1; END IF;
 END LOOP;
 RETURN n+length(b)-j+1;
END $function$;

CREATE OR REPLACE FUNCTION homework_private.qm3_feedback_question(q jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 SELECT ($1-ARRAY['id','prompt','explanation','answers']) || CASE WHEN $1 ? 'answers'
   THEN jsonb_build_object('answers',jsonb_build_object('canonical',$1#>>'{answers,canonical}')) ELSE '{}'::jsonb END
$function$;

CREATE OR REPLACE FUNCTION homework_private.qm3_legacy_start(entered_code text, entered_quiz_id uuid)
 RETURNS TABLE(attempt_id uuid, attempt_token uuid)
 LANGUAGE plpgsql
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
    AND NOT EXISTS (SELECT FROM public.quiz_manager_quizzes m WHERE m.runtime_quiz_id=q.id)
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

CREATE OR REPLACE FUNCTION homework_private.qm3_mark(q jsonb, answer jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
DECLARE settings jsonb; entered_value text; v jsonb; accepted text[]:='{}'; excluded text[]:='{}'; canonical text;
BEGIN
 IF answer IS NULL OR answer='null'::jsonb THEN RETURN false; END IF;
 IF q->>'type' IN ('missing_word','who_am_i') THEN
   IF jsonb_typeof(answer)<>'string' OR length(answer#>>'{}')>4000 THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_typed_answer'; END IF;
   settings:=q->'answers';entered_value:=homework_private.qm_normalize(answer#>>'{}');
   FOR v IN SELECT x FROM jsonb_array_elements(settings->'confusable') x LOOP excluded:=array_append(excluded,homework_private.qm_normalize(v#>>'{}')); END LOOP;
   IF entered_value='' OR entered_value=ANY(excluded) THEN RETURN false; END IF;
   accepted:=array_append(accepted,homework_private.qm_normalize(settings->>'canonical'));
   FOR v IN SELECT x FROM jsonb_array_elements(settings->'aliases') x LOOP accepted:=array_append(accepted,homework_private.qm_normalize(v#>>'{}')); END LOOP;
   IF entered_value=ANY(accepted) THEN RETURN true; END IF;
   IF EXISTS(SELECT FROM jsonb_array_elements_text(settings->'surname_aliases') x WHERE homework_private.qm_normalize(x)=entered_value) THEN RETURN true; END IF;
   IF (settings->>'allow_minor_typos')::boolean AND length(entered_value)>=6
     AND NOT EXISTS(SELECT FROM unnest(excluded) x WHERE homework_private.qm3_distance(entered_value,x)<=1) THEN
     FOREACH canonical IN ARRAY accepted LOOP
       IF length(canonical)>=6 AND homework_private.qm3_distance(entered_value,canonical)=1 THEN RETURN true; END IF;
     END LOOP;
   END IF;
   RETURN false;
 ELSIF q->>'type'='matching' THEN
   IF jsonb_typeof(answer)<>'object' THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_matching_answer'; END IF;
   RETURN (SELECT count(*)=3 FROM jsonb_object_keys(answer)) AND NOT EXISTS(SELECT FROM jsonb_array_elements(q->'pairs') p WHERE answer->>(p->>'id') IS DISTINCT FROM p->>'id');
 ELSE
   IF jsonb_typeof(answer)<>'array' THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_choice_answer'; END IF;
   IF q->>'type'='chronology' THEN RETURN answer=q->'correct'; END IF;
   RETURN jsonb_array_length(answer)=jsonb_array_length(q->'correct') AND answer @> (q->'correct') AND (q->'correct') @> answer;
 END IF;
END $function$;

CREATE OR REPLACE FUNCTION homework_private.qm3_presentation(q jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE clean jsonb:=jsonb_build_object('type',q->>'type','prompt',q->>'prompt'); mapping jsonb:='{}';
 entries jsonb:='[]'; lefts jsonb:='[]'; rights jsonb:='[]'; v jsonb; opaque text; other text;
BEGIN
 IF q->>'type' IN ('multiple_choice','spot_the_mistake','cause_consequence','select_all','chronology') THEN
   FOR v IN SELECT value FROM jsonb_array_elements(CASE WHEN q->>'type'='chronology' THEN q->'events' ELSE q->'options' END) ORDER BY random() LOOP
     opaque:=gen_random_uuid()::text;mapping:=mapping||jsonb_build_object(opaque,v->>'id');
     entries:=entries||jsonb_build_array(jsonb_build_object('id',opaque,'text',v->>'text'));
   END LOOP;
   clean:=clean||jsonb_build_object(CASE WHEN q->>'type'='chronology' THEN 'events' ELSE 'options' END,entries);
   IF q->>'type'='select_all' THEN clean:=clean||jsonb_build_object('selection_limit',jsonb_array_length(q->'correct')); END IF;
 ELSIF q->>'type'='matching' THEN
   FOR v IN SELECT value FROM jsonb_array_elements(q->'pairs') ORDER BY random() LOOP
     opaque:=gen_random_uuid()::text;other:=gen_random_uuid()::text;
     mapping:=mapping||jsonb_build_object(opaque,v->>'id',other,v->>'id');
     lefts:=lefts||jsonb_build_array(jsonb_build_object('id',opaque,'text',v->>'left'));
     rights:=rights||jsonb_build_array(jsonb_build_object('id',other,'text',v->>'right'));
   END LOOP;
   SELECT jsonb_agg(ent.value ORDER BY random()) INTO rights FROM jsonb_array_elements(rights) ent(value);
   clean:=clean||jsonb_build_object('left',lefts,'right',rights);
 ELSIF q->>'type'='who_am_i' THEN clean:=clean||jsonb_build_object('clues',q->'clues'); END IF;
 RETURN jsonb_build_object('public',clean,'map',mapping);
END $function$;

CREATE OR REPLACE FUNCTION homework_private.qm3_session(action text, payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE pupil public.history_pupils; class public.history_classes; h public.history_quizzes;
 manager public.quiz_manager_quizzes; a public.history_attempts; row public.history_questions;
 budget record; quiz uuid; aid uuid; token uuid; qid uuid; progress jsonb; presentation jsonb;
 ids jsonb; maps jsonb:='{}'; q jsonb; response jsonb; submitted jsonb; canonical_answer jsonb; v jsonb;
 pair record; raw text; mapped text; score integer; remaining integer; expired boolean; correct boolean;
 allowed text[]; first_pass timestamptz; began timestamptz:=clock_timestamp(); BEGIN
 IF jsonb_typeof(payload) IS DISTINCT FROM 'object' OR octet_length(payload::text)>32000 THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_request'; END IF;
 IF action IN ('home','start') THEN allowed:=ARRAY['code','quiz_id'];
 ELSIF action IN ('open','finish','review') THEN allowed:=ARRAY['attempt_id','token'];
 ELSIF action='answer' THEN allowed:=ARRAY['attempt_id','token','answer'];
 ELSE RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_action'; END IF;
 IF EXISTS(SELECT FROM jsonb_object_keys(payload) k WHERE NOT k=ANY(allowed)) THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='unexpected_field'; END IF;
 IF action IN ('home','start') THEN
   SELECT * INTO budget FROM homework_private.check_code_budget(payload->>'code');
   IF NOT budget.allowed THEN
     PERFORM set_config('response.status','429',true);PERFORM set_config('response.headers',jsonb_build_array(jsonb_build_object('Retry-After',budget.retry_after::text),jsonb_build_object('Access-Control-Expose-Headers','Retry-After'))::text,true);
     RETURN jsonb_build_object('valid_code',false);
   END IF;
   IF NOT budget.valid_code THEN RETURN jsonb_build_object('valid_code',false); END IF;
   SELECT * INTO pupil FROM public.history_pupils p WHERE p.pupil_code=upper(btrim(payload->>'code'));
   SELECT * INTO class FROM public.history_classes c WHERE c.id=pupil.class_id;
   BEGIN quiz:=nullif(payload->>'quiz_id','')::uuid; EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_quiz_link'; END;
   IF action='home' THEN
     SELECT * INTO h FROM public.history_quizzes z WHERE (quiz IS NULL OR z.id=quiz)
       AND homework_private.qm3_available(pupil.id,z.id) ORDER BY z.created_at DESC,z.id DESC LIMIT 1;
     SELECT min(completed_at) INTO first_pass FROM public.history_attempts WHERE pupil_id=pupil.id AND quiz_id=h.id AND status='completed' AND history_attempts.score>=h.pass_mark;
     SELECT jsonb_build_object('valid_code',true,'class_name',class.class_name,'year_group',class.year_group,'quiz_id',h.id,'quiz_title',h.quiz_title,'topic',h.topic,'week_number',h.week_number,'due_at',h.due_at,'total_questions',h.total_questions,'pass_mark',h.pass_mark,
       'attempts_taken',count(*) FILTER(WHERE status='completed'),'highest_score',max(history_attempts.score) FILTER(WHERE status='completed'),
       'passed',coalesce(max(history_attempts.score) FILTER(WHERE status='completed')>=h.pass_mark,false),'first_passed_at',first_pass,'deadline_status',CASE WHEN first_pass IS NULL THEN NULL WHEN h.due_at IS NULL OR first_pass<=h.due_at THEN 'On time' ELSE 'Late' END,
       'unfinished_attempt_id',(SELECT id FROM public.history_attempts WHERE pupil_id=pupil.id AND quiz_id=h.id AND status='in_progress' ORDER BY started_at DESC LIMIT 1),
       'time_limits',(SELECT jsonb_agg(jsonb_build_object('seconds',s,'questions',n) ORDER BY s) FROM (SELECT time_allowed_seconds s,count(*) n FROM public.history_questions WHERE quiz_id=h.id GROUP BY 1) x)) INTO response
       FROM public.history_attempts WHERE pupil_id=pupil.id AND quiz_id=h.id;
     PERFORM pg_sleep(greatest(0,0.05-extract(epoch FROM clock_timestamp()-began))::double precision);
     RETURN response;
   END IF;
   IF quiz IS NULL OR NOT homework_private.qm3_available(pupil.id,quiz) THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='quiz_not_available'; END IF;
   -- Same lock order as edits: manager first, then per-pupil/quiz advisory lock.
   PERFORM 1 FROM public.quiz_manager_quizzes WHERE runtime_quiz_id=quiz FOR UPDATE;
   PERFORM pg_advisory_xact_lock(hashtext(pupil.id::text),hashtext(quiz::text));
   IF NOT homework_private.qm3_available(pupil.id,quiz) THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='quiz_not_available'; END IF;
   SELECT * INTO a FROM public.history_attempts WHERE pupil_id=pupil.id AND quiz_id=quiz AND status='in_progress' ORDER BY started_at DESC LIMIT 1 FOR UPDATE;
   IF FOUND THEN UPDATE public.history_attempts SET attempt_token=gen_random_uuid() WHERE id=a.id RETURNING * INTO a;
   ELSE INSERT INTO public.history_attempts(pupil_id,quiz_id,attempt_number)
     SELECT pupil.id,quiz,coalesce(max(attempt_number),0)+1 FROM public.history_attempts WHERE pupil_id=pupil.id AND quiz_id=quiz RETURNING * INTO a; END IF;
   PERFORM pg_sleep(greatest(0,0.05-extract(epoch FROM clock_timestamp()-began))::double precision);
   RETURN jsonb_build_object('attempt_id',a.id,'attempt_token',a.attempt_token);
 END IF;
 BEGIN aid:=(payload->>'attempt_id')::uuid;token:=(payload->>'token')::uuid;
 EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_quiz_session'; END;
 SELECT * INTO a FROM public.history_attempts WHERE id=aid AND attempt_token=token FOR UPDATE;
 IF NOT FOUND OR NOT homework_private.qm3_available(a.pupil_id,a.quiz_id) THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_quiz_session'; END IF;
 SELECT * INTO h FROM public.history_quizzes WHERE id=a.quiz_id;
 SELECT * INTO manager FROM public.quiz_manager_quizzes WHERE runtime_quiz_id=a.quiz_id;
 IF action='review' THEN
   IF a.status<>'completed' THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='complete_before_review'; END IF;
   SELECT jsonb_agg(jsonb_build_object('number',ans.question_number,'prompt',z.question_text,'type',z.question_type,
     'your_answer',ans.pupil_answer,'correct',ans.is_correct,'explanation',z.explanation,
     'timed_out',coalesce((a.saved_progress->'timeouts'->>ans.question_number::text)::boolean,ans.pupil_answer='null'::jsonb),
     'your_answer_text',CASE WHEN manager.id IS NULL AND ans.pupil_answer<>'null'::jsonb THEN z.answer_options->>(coalesce((a.saved_progress->'option_orders'->(ans.question_number-1)->>((ans.pupil_answer#>>'{}')::integer))::integer,(ans.pupil_answer#>>'{}')::integer)) ELSE NULL END,
     'question',CASE WHEN manager.id IS NOT NULL THEN homework_private.qm3_feedback_question(z.correct_answer) ELSE jsonb_build_object('options',z.answer_options,'correct',z.correct_answer) END,
     'presentation',a.saved_progress->'presentations'->z.id::text->'public',
     'correct_answer',CASE WHEN manager.id IS NOT NULL THEN homework_private.qm3_feedback_question(z.correct_answer) ELSE z.answer_options->((z.correct_answer#>>'{}')::integer) END) ORDER BY ans.question_number)
   INTO response FROM public.history_answers ans JOIN public.history_questions z ON z.id::text=ans.question_id AND z.quiz_id=a.quiz_id WHERE ans.attempt_id=a.id;
   RETURN jsonb_build_object('answers',response,'score',a.score,'total_questions',h.total_questions);
 END IF;
 IF action='finish' THEN
   IF a.status='completed' THEN RETURN jsonb_build_object('final_score',a.score,'total_questions',h.total_questions,'passed',a.score>=h.pass_mark); END IF;
   IF (SELECT count(*) FROM public.history_answers WHERE attempt_id=a.id)<>h.total_questions THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='quiz_incomplete'; END IF;
   SELECT count(*) FILTER(WHERE is_correct) INTO remaining FROM public.history_answers WHERE attempt_id=a.id;
   UPDATE public.history_attempts SET status='completed',score=remaining,completed_at=clock_timestamp(),question_position=h.total_questions WHERE id=a.id;
   RETURN jsonb_build_object('final_score',remaining,'total_questions',h.total_questions,'passed',remaining>=h.pass_mark);
 END IF;
 IF a.status<>'in_progress' THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_quiz_session'; END IF;
 IF manager.id IS NULL THEN
   IF action='open' THEN SELECT to_jsonb(x) INTO response FROM homework_private.open_pupil_question(a.id,a.attempt_token) x;RETURN response;
   ELSE
     IF payload->'answer' IS NULL OR payload->'answer'='null'::jsonb THEN score:=NULL;
     ELSIF payload->'answer' IN ('0'::jsonb,'1'::jsonb,'2'::jsonb,'3'::jsonb) THEN score:=(payload->>'answer')::integer;
     ELSE RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_choice_answer'; END IF;
     SELECT to_jsonb(x) INTO response FROM homework_private.submit_pupil_answer(a.id,a.attempt_token,score) x;RETURN response;
   END IF;
 END IF;
 IF NOT a.saved_progress ? 'presentations' THEN
   ids:='[]';
   FOR row IN SELECT * FROM public.history_questions WHERE quiz_id=a.quiz_id ORDER BY random() LOOP
     ids:=ids||to_jsonb(row.id::text);maps:=maps||jsonb_build_object(row.id::text,homework_private.qm3_presentation(row.correct_answer));
   END LOOP;
   UPDATE public.history_attempts SET saved_progress=jsonb_build_object('question_ids',ids,'presentations',maps) WHERE id=a.id RETURNING * INTO a;
 END IF;
 IF EXISTS(SELECT FROM public.history_answers WHERE attempt_id=a.id AND question_number=a.question_position) THEN RAISE EXCEPTION 'All questions answered; complete the quiz'; END IF;
 qid:=(a.saved_progress->'question_ids'->>(a.question_position-1))::uuid;
 SELECT * INTO row FROM public.history_questions WHERE id=qid AND quiz_id=a.quiz_id;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='question_unavailable'; END IF;
 q:=row.correct_answer;presentation:=a.saved_progress->'presentations'->qid::text;
 IF action='open' THEN
   IF a.question_started_at IS NULL THEN UPDATE public.history_attempts SET question_started_at=clock_timestamp() WHERE id=a.id RETURNING * INTO a; END IF;
   remaining:=greatest(0,ceil(extract(epoch FROM (a.question_started_at+make_interval(secs=>row.time_allowed_seconds)-clock_timestamp())))::integer);
   RETURN jsonb_build_object('question_number',a.question_position,'question_text',row.question_text,'question_type',row.question_type,'payload',presentation->'public','time_allowed_seconds',row.time_allowed_seconds,'seconds_remaining',remaining);
 END IF;
 IF a.question_started_at IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='open_question_first'; END IF;
 submitted:=coalesce(payload->'answer','null'::jsonb);canonical_answer:=submitted;
 IF submitted<>'null'::jsonb THEN
   IF q->>'type'='matching' THEN
     IF jsonb_typeof(submitted)<>'object' OR (SELECT count(*) FROM jsonb_object_keys(submitted))<>3 THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_matching_answer'; END IF;
     canonical_answer:='{}';
     FOR pair IN SELECT * FROM jsonb_each_text(submitted) LOOP
       IF NOT EXISTS(SELECT FROM jsonb_array_elements(presentation->'public'->'left') x WHERE x->>'id'=pair.key)
         OR NOT EXISTS(SELECT FROM jsonb_array_elements(presentation->'public'->'right') x WHERE x->>'id'=pair.value) THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_matching_answer'; END IF;
       canonical_answer:=canonical_answer||jsonb_build_object(presentation->'map'->>pair.key,presentation->'map'->>pair.value);
     END LOOP;
   ELSIF q->>'type' NOT IN ('missing_word','who_am_i') THEN
     IF jsonb_typeof(submitted)<>'array' THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_choice_answer'; END IF;
     IF jsonb_array_length(submitted)>(CASE WHEN q->>'type'='select_all' THEN jsonb_array_length(q->'correct') WHEN q->>'type'='chronology' THEN 3 ELSE 1 END) THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='selection_limit'; END IF;
     canonical_answer:='[]';
     FOR v IN SELECT value FROM jsonb_array_elements(submitted) LOOP
       raw:=v#>>'{}';mapped:=presentation->'map'->>raw;
       IF jsonb_typeof(v)<>'string' OR mapped IS NULL OR canonical_answer @> jsonb_build_array(mapped) THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_choice_answer'; END IF;
       canonical_answer:=canonical_answer||jsonb_build_array(mapped);
     END LOOP;
   END IF;
 END IF;
 expired:=clock_timestamp()>=a.question_started_at+make_interval(secs=>row.time_allowed_seconds);
 correct:=homework_private.qm3_mark(q,canonical_answer);
 correct:=NOT expired AND correct;
 INSERT INTO public.history_answers(attempt_id,question_number,question_id,pupil_answer,is_correct,time_allowed_seconds)
 VALUES(a.id,a.question_position,qid::text,canonical_answer,correct,row.time_allowed_seconds);
 UPDATE public.history_attempts SET question_position=least(a.question_position+1,h.total_questions),question_started_at=NULL,
   saved_progress=jsonb_set(a.saved_progress,'{timeouts}',coalesce(a.saved_progress->'timeouts','{}')||jsonb_build_object(a.question_position::text,expired OR submitted='null'::jsonb)) WHERE id=a.id;
 RETURN jsonb_build_object('answer_correct',correct,'timed_out',expired,'feedback',row.explanation,'correct_answer',homework_private.qm3_feedback_question(q),'next_question',least(a.question_position+1,h.total_questions));
END $function$;

CREATE OR REPLACE FUNCTION homework_private.qm3_uk_time(value text, fold text DEFAULT NULL::text)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
DECLARE local_value timestamp; options timestamptz[]; BEGIN
 IF value IS NULL OR value !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}$' THEN
   RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_uk_time'; END IF;
 local_value:=value::timestamp;
 SELECT array_agg(t ORDER BY t) INTO options FROM (
   SELECT (local_value AT TIME ZONE 'Europe/London')+n*interval '1 hour' AS t FROM generate_series(-1,1) n
 ) x WHERE t AT TIME ZONE 'Europe/London'=local_value;
 IF coalesce(array_length(options,1),0)=0 THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='nonexistent_uk_time'; END IF;
 IF array_length(options,1)=2 AND coalesce(fold,'') NOT IN ('earlier','later') THEN
   RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='ambiguous_uk_time_choose_earlier_or_later'; END IF;
 RETURN options[CASE WHEN fold='later' THEN array_length(options,1) ELSE 1 END];
END $function$;

CREATE OR REPLACE FUNCTION homework_private.qm3_release(action text, quiz_id uuid, expected_revision bigint, payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE q public.quiz_manager_quizzes; item jsonb; runtime uuid; release_time timestamptz; due_time timestamptz;
 actor uuid:=auth.uid(); failure text; errors jsonb; class_ids uuid[]; BEGIN
 IF actor IS NULL OR NOT EXISTS(SELECT FROM public.history_teachers WHERE user_id=actor) THEN failure:='teacher_required';
 ELSE BEGIN
   IF action IS NULL OR action NOT IN ('approve','publish_now','schedule') OR jsonb_typeof(payload) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_action'; END IF;
   IF EXISTS(SELECT FROM jsonb_object_keys(payload) k WHERE NOT(k='confirmed' OR (action<>'approve' AND k IN ('classes','due_local','due_fold','release_local','release_fold')))) THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='unexpected_field'; END IF;
   IF payload->'confirmed' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='confirmation_required'; END IF;
   SELECT * INTO q FROM public.quiz_manager_quizzes m WHERE m.id=quiz_id FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='quiz_not_found'; END IF;
   IF expected_revision IS DISTINCT FROM q.revision THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='revision_conflict'; END IF;
   IF q.first_started_at IS NOT NULL OR EXISTS(SELECT FROM public.history_attempts WHERE history_attempts.quiz_id=q.runtime_quiz_id) THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='quiz_locked'; END IF;
   errors:=homework_private.qm_content_errors(q.content,q.topic,true);
   IF jsonb_array_length(errors)>0 OR length(homework_private.qm4_trim(q.title))=0 OR q.topic IS NULL OR homework_private.qm4_trim(q.topic)='' OR q.week_number IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='validation_failed'; END IF;
   IF q.year_group=9 AND q.topic !~* '^medicine\M' THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='year9_medicine_only'; END IF;
   IF action='approve' THEN
     IF q.state<>'draft' THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='take_offline_first'; END IF;
     runtime:=q.runtime_quiz_id;
     IF runtime IS NULL THEN
       INSERT INTO public.history_quizzes(quiz_title,year_group,topic,week_number,due_at,is_published)
         VALUES(q.title,q.year_group,q.topic,q.week_number,NULL,false) RETURNING id INTO runtime;
     ELSE
       UPDATE public.history_quizzes SET quiz_title=q.title,year_group=q.year_group,topic=q.topic,week_number=q.week_number,is_published=false WHERE id=runtime;
       DELETE FROM public.history_questions WHERE history_questions.quiz_id=runtime;
     END IF;
     INSERT INTO public.history_questions(quiz_id,question_number,question_type,question_text,answer_options,correct_answer,explanation,time_allowed_seconds)
       SELECT runtime,n::integer,v->>'type',v->>'prompt','[]'::jsonb,v,v->>'explanation',(v->>'seconds')::integer
       FROM jsonb_array_elements(q.content->'questions') WITH ORDINALITY x(v,n);
     UPDATE public.quiz_manager_quizzes m SET state='approved',approved_revision=m.revision,approved_by=actor,approved_at=clock_timestamp(),runtime_quiz_id=runtime WHERE m.id=q.id RETURNING * INTO q;
   ELSE
     IF q.state<>'approved' OR q.approved_revision IS DISTINCT FROM q.revision THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='approval_required'; END IF;
     IF jsonb_typeof(payload->'classes') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_classes'; END IF;
     SELECT array_agg(v::uuid) INTO class_ids FROM jsonb_array_elements_text(payload->'classes') v;
     IF coalesce(array_length(class_ids,1),0)=0 OR (SELECT count(DISTINCT x) FROM unnest(class_ids) x)<>array_length(class_ids,1)
       OR (SELECT count(*) FROM public.history_classes c WHERE c.id=ANY(class_ids) AND c.year_group=q.year_group)<>array_length(class_ids,1) THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_classes'; END IF;
     release_time:=CASE WHEN action='publish_now' THEN clock_timestamp() ELSE homework_private.qm3_uk_time(payload->>'release_local',payload->>'release_fold') END;
     due_time:=homework_private.qm3_uk_time(payload->>'due_local',payload->>'due_fold');
     IF (action='schedule' AND release_time<=clock_timestamp()) OR due_time<release_time THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_release_or_deadline'; END IF;
     DELETE FROM public.quiz_manager_allocations a WHERE a.quiz_id=q.id;
     INSERT INTO public.quiz_manager_allocations SELECT q.id,x FROM unnest(class_ids) x;
     UPDATE public.history_quizzes SET due_at=due_time,is_published=true WHERE id=q.runtime_quiz_id;
     UPDATE public.quiz_manager_quizzes m SET state=CASE WHEN action='schedule' THEN 'scheduled' ELSE 'published' END,
       release_at=release_time,due_at=due_time WHERE m.id=q.id RETURNING * INTO q;
   END IF;
 EXCEPTION WHEN SQLSTATE '22023' THEN failure:=SQLERRM;
   WHEN OTHERS THEN failure:='invalid_release_settings';
 END; END IF;
 INSERT INTO public.quiz_manager_audit(quiz_id,actor_id,action,outcome,reason,revision)
 VALUES(quiz_id,actor,CASE WHEN action IN ('approve','publish_now','schedule') THEN action ELSE 'invalid_release_action' END,
 CASE WHEN failure IS NULL THEN 'success' ELSE 'denied' END,failure,CASE WHEN failure IS NULL THEN q.revision ELSE NULL END);
 IF failure IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'error',failure,'errors',coalesce(errors,'[]')); END IF;
 RETURN jsonb_build_object('ok',true,'quiz',to_jsonb(q));
END $function$;

CREATE OR REPLACE FUNCTION homework_private.qm3_results(class_id uuid, quiz_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ DECLARE result jsonb; BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS(SELECT FROM public.history_teachers WHERE user_id=auth.uid())
 OR NOT EXISTS(SELECT FROM public.history_teacher_classes t WHERE t.user_id=auth.uid() AND t.class_id=qm3_results.class_id) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Teacher allocation required'; END IF;
 IF EXISTS(SELECT FROM public.quiz_manager_quizzes m WHERE m.runtime_quiz_id=qm3_results.quiz_id)
 AND NOT EXISTS(SELECT FROM public.quiz_manager_quizzes m JOIN public.quiz_manager_allocations a ON a.quiz_id=m.id WHERE m.runtime_quiz_id=qm3_results.quiz_id AND a.class_id=qm3_results.class_id) THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Quiz is not assigned to this class'; END IF;
 SELECT jsonb_agg(to_jsonb(x) ORDER BY x.register_number) INTO result FROM (
 SELECT p.pupil_code,p.register_number,count(a.id) FILTER(WHERE a.status='completed') attempts,max(a.score) FILTER(WHERE a.status='completed') highest_score,
 CASE WHEN max(a.score) FILTER(WHERE a.status='completed')>=h.pass_mark THEN 'Passed' WHEN count(a.id) FILTER(WHERE a.status='completed')>0 THEN 'Not passed' ELSE 'Not completed' END homework_status,
 min(a.completed_at) FILTER(WHERE a.status='completed' AND a.score>=h.pass_mark) first_passed_at,
 CASE WHEN min(a.completed_at) FILTER(WHERE a.status='completed' AND a.score>=h.pass_mark) IS NULL THEN NULL
 WHEN h.due_at IS NULL OR min(a.completed_at) FILTER(WHERE a.status='completed' AND a.score>=h.pass_mark)<=h.due_at THEN 'On time' ELSE 'Late' END deadline_status
 FROM public.history_pupils p JOIN public.history_classes c ON c.id=p.class_id
 JOIN public.history_quizzes h ON h.id=qm3_results.quiz_id AND h.year_group=c.year_group AND h.is_published
 LEFT JOIN public.history_attempts a ON a.pupil_id=p.id AND a.quiz_id=h.id
 WHERE p.class_id=qm3_results.class_id GROUP BY p.id,p.pupil_code,p.register_number,h.pass_mark,h.due_at
 ) x;RETURN coalesce(result,'[]'); END $function$;

CREATE OR REPLACE FUNCTION homework_private.qm4_trim(value text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE STRICT
 SET search_path TO ''
AS $function$
 SELECT btrim($1,chr(9)||chr(10)||chr(11)||chr(12)||chr(13)||chr(32)||chr(160)||chr(5760)||chr(8192)||chr(8193)||chr(8194)||chr(8195)||chr(8196)||chr(8197)||chr(8198)||chr(8199)||chr(8200)||chr(8201)||chr(8202)||chr(8232)||chr(8233)||chr(8239)||chr(8287)||chr(12288)||chr(65279) )
$function$;

CREATE OR REPLACE FUNCTION homework_private.pupil_homework_data(entered_code text)
 RETURNS TABLE(valid_code boolean, class_name text, year_group integer, quiz_id uuid, quiz_title text, topic text, week_number integer, due_at timestamp with time zone, total_questions integer, pass_mark integer, attempts_taken integer, highest_score integer, passed boolean, unfinished_attempt_id uuid)
 LANGUAGE sql
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
    WHERE q.is_published IS TRUE AND NOT EXISTS (SELECT FROM public.quiz_manager_quizzes m WHERE m.runtime_quiz_id=q.id)
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

CREATE OR REPLACE FUNCTION homework_private.pupil_quiz_start_data(entered_code text, entered_quiz_id uuid)
 RETURNS TABLE(attempt_id uuid, attempt_token uuid)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE r jsonb; BEGIN
 IF EXISTS(SELECT FROM public.quiz_manager_quizzes WHERE runtime_quiz_id=entered_quiz_id) THEN
   r:=homework_private.qm3_session('start',jsonb_build_object('code',entered_code,'quiz_id',entered_quiz_id));
   RETURN QUERY SELECT (r->>'attempt_id')::uuid,(r->>'attempt_token')::uuid;
 ELSE RETURN QUERY SELECT * FROM homework_private.qm3_legacy_start(entered_code,entered_quiz_id); END IF;
END $function$;

ALTER TABLE public.quiz_manager_quizzes ADD CONSTRAINT qm_draft_envelope CHECK (homework_private.qm_valid_draft(content));

ALTER TABLE public.quiz_manager_allocations ADD CONSTRAINT quiz_manager_allocations_pkey PRIMARY KEY (quiz_id, class_id);

ALTER TABLE public.quiz_manager_audit ADD CONSTRAINT quiz_manager_audit_outcome_check CHECK ((outcome = ANY (ARRAY['success'::text, 'denied'::text])));

ALTER TABLE public.quiz_manager_audit ADD CONSTRAINT quiz_manager_audit_pkey PRIMARY KEY (id);

ALTER TABLE public.quiz_manager_quizzes ADD CONSTRAINT quiz_manager_quizzes_check CHECK ((((state = 'draft'::text) AND (approved_revision IS NULL) AND (approved_by IS NULL) AND (approved_at IS NULL)) OR ((state <> 'draft'::text) AND (approved_revision IS NOT NULL) AND (approved_revision = revision) AND (approved_by IS NOT NULL) AND (approved_at IS NOT NULL) AND (topic IS NOT NULL) AND (btrim(topic) <> ''::text) AND (week_number IS NOT NULL))));

ALTER TABLE public.quiz_manager_quizzes ADD CONSTRAINT quiz_manager_quizzes_check1 CHECK (((state <> ALL (ARRAY['scheduled'::text, 'published'::text])) OR ((release_at IS NOT NULL) AND (due_at IS NOT NULL) AND (due_at >= release_at) AND (runtime_quiz_id IS NOT NULL))));

ALTER TABLE public.quiz_manager_quizzes ADD CONSTRAINT quiz_manager_quizzes_pass_mark_check CHECK ((pass_mark = 20));

ALTER TABLE public.quiz_manager_quizzes ADD CONSTRAINT quiz_manager_quizzes_pkey PRIMARY KEY (id);

ALTER TABLE public.quiz_manager_quizzes ADD CONSTRAINT quiz_manager_quizzes_revision_check CHECK ((revision > 0));

ALTER TABLE public.quiz_manager_quizzes ADD CONSTRAINT quiz_manager_quizzes_runtime_quiz_id_key UNIQUE (runtime_quiz_id);

ALTER TABLE public.quiz_manager_quizzes ADD CONSTRAINT quiz_manager_quizzes_state_check CHECK ((state = ANY (ARRAY['draft'::text, 'approved'::text, 'scheduled'::text, 'published'::text])));

ALTER TABLE public.quiz_manager_quizzes ADD CONSTRAINT quiz_manager_quizzes_title_check CHECK (((length(btrim(title)) >= 1) AND (length(btrim(title)) <= 200)));

ALTER TABLE public.quiz_manager_quizzes ADD CONSTRAINT quiz_manager_quizzes_topic_check CHECK ((length(topic) <= 200));

ALTER TABLE public.quiz_manager_quizzes ADD CONSTRAINT quiz_manager_quizzes_total_questions_check CHECK ((total_questions = 25));

ALTER TABLE public.quiz_manager_quizzes ADD CONSTRAINT quiz_manager_quizzes_week_number_check CHECK ((week_number > 0));

ALTER TABLE public.quiz_manager_quizzes ADD CONSTRAINT quiz_manager_quizzes_year_group_check CHECK ((year_group = ANY (ARRAY[9, 10, 11])));

ALTER TABLE public.quiz_manager_revisions ADD CONSTRAINT quiz_manager_revisions_pkey PRIMARY KEY (quiz_id, revision);

ALTER TABLE public.quiz_manager_allocations ADD CONSTRAINT quiz_manager_allocations_class_id_fkey FOREIGN KEY (class_id) REFERENCES public.history_classes(id) ON DELETE RESTRICT;

ALTER TABLE public.quiz_manager_allocations ADD CONSTRAINT quiz_manager_allocations_quiz_id_fkey FOREIGN KEY (quiz_id) REFERENCES public.quiz_manager_quizzes(id) ON DELETE RESTRICT;

ALTER TABLE public.quiz_manager_quizzes ADD CONSTRAINT quiz_manager_quizzes_runtime_quiz_id_fkey FOREIGN KEY (runtime_quiz_id) REFERENCES public.history_quizzes(id) ON DELETE RESTRICT;

ALTER TABLE public.quiz_manager_revisions ADD CONSTRAINT quiz_manager_revisions_quiz_id_fkey FOREIGN KEY (quiz_id) REFERENCES public.quiz_manager_quizzes(id) ON DELETE CASCADE;

CREATE INDEX quiz_manager_allocations_class_idx ON public.quiz_manager_allocations USING btree (class_id);

CREATE INDEX quiz_manager_audit_quiz_idx ON public.quiz_manager_audit USING btree (quiz_id, recorded_at DESC);

CREATE INDEX quiz_manager_quizzes_year_idx ON public.quiz_manager_quizzes USING btree (year_group, updated_at DESC);

ALTER TABLE public.quiz_manager_allocations ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.quiz_manager_audit ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.quiz_manager_quizzes ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.quiz_manager_revisions ENABLE ROW LEVEL SECURITY;

CREATE POLICY qm_teacher_read ON public.quiz_manager_allocations AS PERMISSIVE FOR SELECT TO authenticated USING (( SELECT public.is_history_teacher() AS is_history_teacher));

CREATE POLICY qm_teacher_read ON public.quiz_manager_audit AS PERMISSIVE FOR SELECT TO authenticated USING (( SELECT public.is_history_teacher() AS is_history_teacher));

CREATE POLICY qm_teacher_read ON public.quiz_manager_quizzes AS PERMISSIVE FOR SELECT TO authenticated USING (( SELECT public.is_history_teacher() AS is_history_teacher));

CREATE POLICY qm_teacher_read ON public.quiz_manager_revisions AS PERMISSIVE FOR SELECT TO authenticated USING (( SELECT public.is_history_teacher() AS is_history_teacher));

CREATE TRIGGER qm_draft_shape BEFORE INSERT OR UPDATE OF content ON public.quiz_manager_quizzes FOR EACH ROW EXECUTE FUNCTION homework_private.qm_draft_shape();

CREATE TRIGGER qm_guard_quiz BEFORE DELETE OR UPDATE ON public.quiz_manager_quizzes FOR EACH ROW EXECUTE FUNCTION homework_private.qm_guard_quiz();

CREATE TRIGGER qm_attempt_identity BEFORE UPDATE OF quiz_id, pupil_id ON public.history_attempts FOR EACH ROW EXECUTE FUNCTION homework_private.qm_attempt_identity();

CREATE TRIGGER qm_guard_questions BEFORE INSERT OR DELETE OR UPDATE ON public.history_questions FOR EACH ROW EXECUTE FUNCTION homework_private.qm_guard_runtime();

CREATE TRIGGER qm_guard_runtime BEFORE DELETE OR UPDATE ON public.history_quizzes FOR EACH ROW EXECUTE FUNCTION homework_private.qm_guard_runtime();

CREATE TRIGGER qm_start_lock BEFORE INSERT ON public.history_attempts FOR EACH ROW EXECUTE FUNCTION homework_private.qm_start_lock();

REVOKE ALL ON TABLE public.quiz_manager_allocations FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT ON TABLE public.quiz_manager_allocations TO authenticated;

REVOKE ALL ON TABLE public.quiz_manager_audit FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT ON TABLE public.quiz_manager_audit TO authenticated;

REVOKE ALL ON SEQUENCE public.quiz_manager_audit_id_seq FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TABLE public.quiz_manager_quizzes FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT ON TABLE public.quiz_manager_quizzes TO authenticated;

REVOKE ALL ON TABLE public.quiz_manager_revisions FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT ON TABLE public.quiz_manager_revisions TO authenticated;

REVOKE ALL ON FUNCTION homework_api.quiz_session(action text, payload jsonb) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION homework_api.quiz_session(action text, payload jsonb) TO anon;

REVOKE ALL ON FUNCTION homework_private.qm3_available(pupil uuid, quiz uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION homework_private.qm3_distance(a text, b text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION homework_private.qm3_feedback_question(q jsonb) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION homework_private.qm3_legacy_start(entered_code text, entered_quiz_id uuid) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION homework_private.qm3_mark(q jsonb, answer jsonb) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION homework_private.qm3_presentation(q jsonb) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION homework_private.qm3_release(action text, quiz_id uuid, expected_revision bigint, payload jsonb) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION homework_private.qm3_release(action text, quiz_id uuid, expected_revision bigint, payload jsonb) TO authenticated;

REVOKE ALL ON FUNCTION homework_private.qm3_results(class_id uuid, quiz_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION homework_private.qm3_results(class_id uuid, quiz_id uuid) TO authenticated;

REVOKE ALL ON FUNCTION homework_private.qm3_session(action text, payload jsonb) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION homework_private.qm3_session(action text, payload jsonb) TO anon;

REVOKE ALL ON FUNCTION homework_private.qm3_uk_time(value text, fold text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION homework_private.qm4_trim(value text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION homework_private.qm_attempt_identity() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION homework_private.qm_classes() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION homework_private.qm_classes() TO authenticated;

REVOKE ALL ON FUNCTION homework_private.qm_content_errors(document jsonb, topic text, complete boolean) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION homework_private.qm_draft_shape() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION homework_private.qm_guard_quiz() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION homework_private.qm_guard_runtime() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION homework_private.qm_home_list(payload jsonb) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION homework_private.qm_home_list(payload jsonb) TO anon;

REVOKE ALL ON FUNCTION homework_private.qm_import(payload jsonb) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION homework_private.qm_import(payload jsonb) TO authenticated;

REVOKE ALL ON FUNCTION homework_private.qm_issue(path text, message text, question integer) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION homework_private.qm_normalize(value text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION homework_private.qm_start_lock() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION homework_private.qm_valid_draft(document jsonb) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION homework_private.qm_validate(content jsonb, topic text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION homework_private.qm_validate(content jsonb, topic text) TO authenticated;

REVOKE ALL ON FUNCTION homework_private.qm_write(action text, quiz_id uuid, expected_revision bigint, payload jsonb) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION homework_private.qm_write(action text, quiz_id uuid, expected_revision bigint, payload jsonb) TO authenticated;

REVOKE ALL ON FUNCTION public.quiz_manager_class_results(class_id uuid, quiz_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.quiz_manager_class_results(class_id uuid, quiz_id uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.quiz_manager_classes() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.quiz_manager_classes() TO authenticated;

REVOKE ALL ON FUNCTION public.quiz_manager_import(payload jsonb) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.quiz_manager_import(payload jsonb) TO authenticated;

REVOKE ALL ON FUNCTION public.quiz_manager_release(action text, quiz_id uuid, expected_revision bigint, payload jsonb) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.quiz_manager_release(action text, quiz_id uuid, expected_revision bigint, payload jsonb) TO authenticated;

REVOKE ALL ON FUNCTION public.quiz_manager_validate(content jsonb, topic text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.quiz_manager_validate(content jsonb, topic text) TO authenticated;

REVOKE ALL ON FUNCTION public.quiz_manager_write(action text, quiz_id uuid, expected_revision bigint, payload jsonb) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.quiz_manager_write(action text, quiz_id uuid, expected_revision bigint, payload jsonb) TO authenticated;

COMMIT;
