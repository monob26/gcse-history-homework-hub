BEGIN;
SELECT set_config('review2.observer_code',pupil_code,true)
FROM public.history_pupils WHERE id='20000000-0000-4000-8000-000000000001';
SET LOCAL ROLE anon;
SET LOCAL request.headers='{"cf-connecting-ip":"192.0.2.236"}';
SELECT 1 / CASE WHEN homework_api.quiz_session('list',
  jsonb_build_object('code',current_setting('review2.observer_code')))
  ->>'valid_code' = 'true' THEN 1 ELSE 0 END;
COMMIT;
