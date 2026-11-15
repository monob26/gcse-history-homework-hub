-- Owner approved only these 11 fictional application records on 2026-11-15.
-- Hosted fixture migration, NOT a general schema migration or local seed.
-- No Auth account creation, invitations, logins, signup or test execution.
-- Resolve generated Auth UUIDs by the exact approved emails.
-- One DO statement makes all fixture writes atomic; conflicts must abort.
DO $r2_fixture$
DECLARE
 teacher_a uuid;
 teacher_b uuid;
 teacher_u uuid;
BEGIN
 SELECT id INTO STRICT teacher_a FROM auth.users WHERE email='r2-hosted-a-20261115@example.test' AND email_confirmed_at IS NOT NULL AND role='authenticated';
 SELECT id INTO STRICT teacher_b FROM auth.users WHERE email='r2-hosted-b-20261115@example.test' AND email_confirmed_at IS NOT NULL AND role='authenticated';
 SELECT id INTO STRICT teacher_u FROM auth.users WHERE email='r2-hosted-unallocated-20261115@example.test' AND email_confirmed_at IS NOT NULL AND role='authenticated';
 IF EXISTS(SELECT 1 FROM public.history_teachers WHERE user_id IN (teacher_a,teacher_b,teacher_u)) OR EXISTS(SELECT 1 FROM public.history_teacher_classes WHERE user_id IN (teacher_a,teacher_b,teacher_u)) THEN
  RAISE EXCEPTION 'Fixture accounts already approved or allocated; stop';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.history_quizzes WHERE id='cd9fbeb8-e646-4d2f-b662-2b2044d8591c' AND year_group=10 AND is_published) THEN
  RAISE EXCEPTION 'Approved fixture quiz is unavailable';
 END IF;
 IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='history_pupils' AND column_name='register_number') THEN
  RAISE EXCEPTION 'Schema differs from approved R2 fixture plan';
 END IF;
INSERT INTO public.history_teachers(user_id) VALUES (teacher_a),(teacher_b),(teacher_u);

INSERT INTO public.history_classes(id,class_name,year_group) VALUES
 ('eab072a6-274e-4fe1-83e8-9bd61fc92501','R2 Fictional A 20261115',10),
 ('eab072a6-274e-4fe1-83e8-9bd61fc92502','R2 Fictional B 20261115',10);

INSERT INTO public.history_teacher_classes(id,user_id,class_id) VALUES
 ('fedf41b8-c1b2-4a6a-b258-11f485faaa01',teacher_a,'eab072a6-274e-4fe1-83e8-9bd61fc92501'),
 ('fedf41b8-c1b2-4a6a-b258-11f485faaa02',teacher_b,'eab072a6-274e-4fe1-83e8-9bd61fc92502');

INSERT INTO public.history_pupils(id,pupil_code,class_id) VALUES
 ('46ec9d5c-5292-47fb-a238-34d5295cab01',upper(substr(encode(extensions.gen_random_bytes(8),'hex'),1,5))||'-901','eab072a6-274e-4fe1-83e8-9bd61fc92501'),
 ('46ec9d5c-5292-47fb-a238-34d5295cab02',upper(substr(encode(extensions.gen_random_bytes(8),'hex'),1,5))||'-902','eab072a6-274e-4fe1-83e8-9bd61fc92502');

INSERT INTO public.history_attempts(id,pupil_id,quiz_id,attempt_number,status,score,question_position,saved_progress,completed_at) VALUES
 ('71f808f5-8059-47df-88e7-88b68cb0ab01','46ec9d5c-5292-47fb-a238-34d5295cab01','cd9fbeb8-e646-4d2f-b662-2b2044d8591c',1,'completed',21,25,'{"fixture":"R2-HOSTED-20261115","synthetic":true}',clock_timestamp()),
 ('71f808f5-8059-47df-88e7-88b68cb0ab02','46ec9d5c-5292-47fb-a238-34d5295cab02','cd9fbeb8-e646-4d2f-b662-2b2044d8591c',1,'completed',22,25,'{"fixture":"R2-HOSTED-20261115","synthetic":true}',clock_timestamp());
END;
$r2_fixture$;
