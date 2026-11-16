-- NEW isolated R8 test project only: ohkpvuhzvshjglbqyepq.
-- Fresh fictional records; never run on live or replay after insertion.
-- No Auth accounts, passwords, existing codes, tokens or hosted rows are copied.
DO $fixtures$
DECLARE class_a uuid; class_b uuid; quiz uuid;
BEGIN
  IF EXISTS (SELECT 1 FROM public.history_classes)
     OR EXISTS (SELECT 1 FROM public.history_quizzes)
     OR EXISTS (SELECT 1 FROM public.history_pupils) THEN
    RAISE EXCEPTION 'Expected an empty R8 test dataset; do not replay';
  END IF;
  INSERT INTO public.history_classes(class_name,year_group)
  VALUES('R8 Fictional Class A',10) RETURNING id INTO class_a;
  INSERT INTO public.history_classes(class_name,year_group)
  VALUES('R8 Fictional Class B',10) RETURNING id INTO class_b;
  INSERT INTO public.history_pupils(class_id,register_number)
  VALUES(class_a,1),(class_a,2),(class_b,1);
  INSERT INTO public.history_quizzes
    (quiz_title,year_group,topic,week_number,total_questions,pass_mark,is_published)
  VALUES('R8 Fictional Practice Quiz',10,'Synthetic test questions only',1,25,20,true)
  RETURNING id INTO quiz;
  INSERT INTO public.history_questions
    (quiz_id,question_number,question_type,question_text,answer_options,
     correct_answer,explanation,time_allowed_seconds)
  SELECT quiz,n,'multiple_choice','Fictional practice question ' || n || ': choose Option A.',
    '["Option A","Option B","Option C","Option D"]'::jsonb,
    '0'::jsonb,'Option A is correct in this fictional test fixture.',
    CASE WHEN n<=20 THEN 45 ELSE 60 END
  FROM generate_series(1,25) n;
END;
$fixtures$;
