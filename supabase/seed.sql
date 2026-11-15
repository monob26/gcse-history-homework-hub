-- Handwritten fictional fixtures for disposable LOCAL development only.
-- Never export hosted rows and never apply this seed to the hosted project.
INSERT INTO public.history_classes (id, class_name, year_group) VALUES
  ('10000000-0000-4000-8000-000000000001', 'Fictional Class A', 10),
  ('10000000-0000-4000-8000-000000000002', 'Fictional Class B', 10);

INSERT INTO public.history_pupils (id, pupil_code, class_id) VALUES
  ('20000000-0000-4000-8000-000000000001', 'TESTA-01', '10000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-000000000002', 'TESTA-02', '10000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-000000000003', 'TESTB-01', '10000000-0000-4000-8000-000000000002');

INSERT INTO public.history_quizzes
  (id, quiz_title, year_group, topic, week_number, total_questions, pass_mark, is_published)
VALUES
  ('30000000-0000-4000-8000-000000000001', 'Fictional R1 Practice Quiz', 10,
   'Fictional local verification fixture', 1, 25, 20, true);

INSERT INTO public.history_questions
  (quiz_id, question_number, question_type, question_text, answer_options,
   correct_answer, explanation, time_allowed_seconds)
SELECT '30000000-0000-4000-8000-000000000001', n, 'multiple_choice',
       'Fictional practice question ' || n || ': choose Option A.',
       '["Option A", "Option B", "Option C", "Option D"]'::jsonb,
       '0'::jsonb, 'Option A is the answer in this fictional test fixture.',
       CASE WHEN n <= 20 THEN 45 ELSE 60 END
FROM generate_series(1, 25) n;
