BEGIN;
\ir ../r9/helpers.sql
INSERT INTO auth.users(id) VALUES
 ('90000000-0000-4000-8000-000000000001'),('90000000-0000-4000-8000-000000000002');
INSERT INTO public.history_teachers(user_id) SELECT id FROM auth.users;
INSERT INTO public.history_teacher_classes(user_id,class_id) VALUES
 ('90000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001');
-- Rename the class; ID-based access must not depend on the old display name.
UPDATE public.history_classes SET class_name='Renamed Fictional Class A'
 WHERE id='10000000-0000-4000-8000-000000000001';
SET LOCAL ROLE anon;
SELECT pg_temp.refuses($q$SELECT * FROM public.get_history_class_results_by_id(
 '10000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001')$q$,
 '42501','permission denied');
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='90000000-0000-4000-8000-000000000001';
SELECT pg_temp.check_true((SELECT count(*)=2 AND bool_and(attempts=0 AND homework_status='Not completed')
 FROM public.get_history_class_results_by_id('10000000-0000-4000-8000-000000000001',
 '30000000-0000-4000-8000-000000000001')), 'class-ID results include every allocated pupil without attempts');
SELECT pg_temp.refuses($q$SELECT * FROM public.get_history_class_results_by_id(
 '10000000-0000-4000-8000-000000000002','30000000-0000-4000-8000-000000000001')$q$,
 'P0001','not allocated');
SELECT pg_temp.check_true(true,'unallocated class ID refused even after a display-name change');
SET LOCAL request.jwt.claim.sub='90000000-0000-4000-8000-000000000002';
SELECT pg_temp.refuses($q$SELECT * FROM public.get_history_class_results_by_id(
 '10000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001')$q$,
 'P0001','not allocated');
RESET ROLE;
ROLLBACK;
