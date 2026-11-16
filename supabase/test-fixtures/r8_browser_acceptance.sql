-- Reviewed test-only DML. Execute ONLY on ohkpvuhzvshjglbqyepq.
-- Owner authorized fictional records and allocations for local acceptance.
-- Each execution adds one independently generated fictional pupil for a fresh run.
DO $fixture$
DECLARE teacher_id uuid; class_a uuid;
BEGIN
  SELECT id INTO STRICT teacher_id FROM auth.users
    WHERE email = 'r8-test-teacher-a@example.test' AND email_confirmed_at IS NOT NULL;
  SELECT id INTO STRICT class_a FROM public.history_classes
    WHERE class_name = 'R8 Fictional Class A';
  INSERT INTO public.history_teachers(user_id) VALUES(teacher_id) ON CONFLICT DO NOTHING;
  INSERT INTO public.history_teacher_classes(user_id,class_id)
    VALUES(teacher_id,class_a) ON CONFLICT DO NOTHING;
  IF EXISTS (SELECT 1 FROM public.history_teacher_classes
             WHERE user_id=teacher_id AND class_id<>class_a) THEN
    RAISE EXCEPTION 'Expected Class A allocation only';
  END IF;
  INSERT INTO public.history_pupils(class_id,register_number)
    SELECT class_a, greatest(100,coalesce(max(register_number),0)+1)
    FROM public.history_pupils WHERE class_id=class_a;
END;
$fixture$;
