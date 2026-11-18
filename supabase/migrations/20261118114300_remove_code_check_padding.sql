-- Release same-address budget row locks without an artificial transaction delay.
BEGIN;

CREATE OR REPLACE FUNCTION homework_private.get_current_pupil_homework(entered_code text)
RETURNS TABLE(valid_code boolean, class_name text, year_group integer, quiz_id uuid, quiz_title text, topic text, week_number integer, due_at timestamp with time zone, total_questions integer, pass_mark integer, attempts_taken integer, highest_score integer, passed boolean, unfinished_attempt_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $checked$
DECLARE state record;
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
END;
$checked$;

CREATE OR REPLACE FUNCTION homework_private.start_pupil_quiz(entered_code text,entered_quiz_id uuid)
RETURNS TABLE(attempt_id uuid,attempt_token uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $checked$
DECLARE state record;
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
END;
$checked$;

CREATE OR REPLACE FUNCTION homework_private.qm_home_list(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE budget record; pupil public.history_pupils; class public.history_classes;
 quizzes jsonb;
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
 RETURN jsonb_build_object('valid_code',true,'class_name',class.class_name,'year_group',class.year_group,'quizzes',quizzes);
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
 allowed text[]; first_pass timestamptz; BEGIN
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

COMMIT;
