BEGIN;
SET LOCAL ROLE anon;
SET LOCAL request.headers='{"cf-connecting-ip":"192.0.2.235"}';
SELECT 1 / CASE WHEN homework_api.quiz_session('list','{"code":"invalid-fictional-code"}')
  ->>'valid_code' = 'false' THEN 1 ELSE 0 END;
COMMIT;
