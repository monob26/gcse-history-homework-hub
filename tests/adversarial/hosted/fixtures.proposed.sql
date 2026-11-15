-- PROPOSAL ONLY. Do not execute without specific owner approval.
-- Three Auth accounts must first be owner-provisioned with confirmed email,
-- no invitation emails, random runtime-only passwords and no admin/service role.
-- Replace :'<teacher>_id' with the three verified Auth UUIDs only after approval.
-- This is fixture DML, not an authorised migration or a CLI deployment command.
BEGIN;
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.history_quizzes WHERE id='cd9fbeb8-e646-4d2f-b662-2b2044d8591c' AND year_group=10 AND is_published) THEN
  RAISE EXCEPTION 'Approved fixture quiz is unavailable';
 END IF;
 IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='history_pupils' AND column_name='register_number') THEN
  RAISE EXCEPTION 'Schema differs from approved R2 fixture plan';
 END IF;
END $$;
-- Validate exact email/UUID matches before touching application rows.
SELECT 1 / CASE WHEN count(*)=3 THEN 1 ELSE 0 END FROM auth.users
WHERE (id=:'teacher_a_id'::uuid AND email='r2-hosted-a-20261115@example.test')
 OR (id=:'teacher_b_id'::uuid AND email='r2-hosted-b-20261115@example.test')
 OR (id=:'teacher_u_id'::uuid AND email='r2-hosted-unallocated-20261115@example.test');
INSERT INTO public.history_teachers(user_id) VALUES (:'teacher_a_id'),(:'teacher_b_id'),(:'teacher_u_id');
INSERT INTO public.history_classes(id,class_name,year_group) VALUES
 ('eab072a6-274e-4fe1-83e8-9bd61fc92501','R2 Fictional A 20261115',10),
 ('eab072a6-274e-4fe1-83e8-9bd61fc92502','R2 Fictional B 20261115',10);
INSERT INTO public.history_teacher_classes(id,user_id,class_id) VALUES
 ('fedf41b8-c1b2-4a6a-b258-11f485faaa01',:'teacher_a_id','eab072a6-274e-4fe1-83e8-9bd61fc92501'),
 ('fedf41b8-c1b2-4a6a-b258-11f485faaa02',:'teacher_b_id','eab072a6-274e-4fe1-83e8-9bd61fc92502');
-- Codes are random credential values generated at execution, never printed or saved.
-- The existing hosted legacy format still applies until separately approved R3 rollout.
INSERT INTO public.history_pupils(id,pupil_code,class_id) VALUES
 ('46ec9d5c-5292-47fb-a238-34d5295cab01',upper(substr(encode(extensions.gen_random_bytes(8),'hex'),1,5))||'-901','eab072a6-274e-4fe1-83e8-9bd61fc92501'),
 ('46ec9d5c-5292-47fb-a238-34d5295cab02',upper(substr(encode(extensions.gen_random_bytes(8),'hex'),1,5))||'-902','eab072a6-274e-4fe1-83e8-9bd61fc92502');
-- Synthetic scores for access-control tests ONLY; no real quiz was completed.
INSERT INTO public.history_attempts(id,pupil_id,quiz_id,attempt_number,status,score,question_position,saved_progress,completed_at) VALUES
 ('71f808f5-8059-47df-88e7-88b68cb0ab01','46ec9d5c-5292-47fb-a238-34d5295cab01','cd9fbeb8-e646-4d2f-b662-2b2044d8591c',1,'completed',21,25,'{"fixture":"R2-HOSTED-20261115","synthetic":true}',clock_timestamp()),
 ('71f808f5-8059-47df-88e7-88b68cb0ab02','46ec9d5c-5292-47fb-a238-34d5295cab02','cd9fbeb8-e646-4d2f-b662-2b2044d8591c',1,'completed',22,25,'{"fixture":"R2-HOSTED-20261115","synthetic":true}',clock_timestamp());
COMMIT;
-- No upsert, update, delete, published quiz, question or answer insertion.
-- A conflict must abort, never overwrite an existing record.
