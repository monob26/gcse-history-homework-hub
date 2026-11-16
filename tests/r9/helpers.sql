CREATE FUNCTION pg_temp.check_true(ok boolean, label text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $$
BEGIN
  IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION USING ERRCODE='23514', MESSAGE=label; END IF;
  RAISE NOTICE 'PASS: %', label;
END $$;
CREATE FUNCTION pg_temp.refuses(statement text, expected_state text, expected_message text)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER AS $$
BEGIN
  BEGIN
    EXECUTE statement;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = expected_state AND SQLERRM ~ expected_message THEN RETURN; END IF;
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Unexpected refusal category: '||SQLSTATE||' expected '||expected_state||' matching '||expected_message;
  END;
  RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Expected refusal did not occur';
END $$;
