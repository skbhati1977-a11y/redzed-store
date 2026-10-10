DO $acl$ DECLARE r record;BEGIN
FOR r IN SELECT p.oid,p.oid::regprocedure signature,has_function_privilege('authenticated',p.oid,'EXECUTE') preserve_authenticated FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND p.proname~'(account|finance|claim|salary|payroll|advance)' LOOP
EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon',r.signature);
IF r.preserve_authenticated THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',r.signature);END IF;
END LOOP;END $acl$;
