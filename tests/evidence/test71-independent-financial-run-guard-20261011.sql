-- Run after guard migration inside BEGIN/ROLLBACK; no Auth actor or business fixture writes.
BEGIN;
DO $test$
DECLARE a jsonb;b jsonb;run uuid;proof jsonb;blocked boolean:=false;n integer:=0;
BEGIN
 PERFORM set_config('request.jwt.claim.sub','',true);
 BEGIN PERFORM public.rr_test71_independent_financial_claim();EXCEPTION WHEN SQLSTATE '42501' THEN blocked:=true;END;
 IF NOT blocked THEN RAISE EXCEPTION 'Anonymous claim must fail';END IF;n:=n+1;
 PERFORM set_config('request.jwt.claim.sub','893c58dd-420b-4dfa-aff7-844e20e634c5',true);
 a:=public.rr_test71_independent_financial_claim();IF NOT (a->>'claimed')::boolean THEN RAISE EXCEPTION 'Fresh run must claim';END IF;run:=(a->>'run_id')::uuid;n:=n+1;
 b:=public.rr_test71_independent_financial_claim();IF (b->>'claimed')::boolean OR b->>'status'<>'RUNNING' OR b->>'run_id'<>run::text THEN RAISE EXCEPTION 'Repeated claim must not provision';END IF;n:=n+1;
 blocked:=false;BEGIN PERFORM public.rr_test71_independent_financial_finish(run,NULL,jsonb_build_object('run_id',run,'roles','[]'::jsonb));EXCEPTION WHEN others THEN blocked:=true;END;
 IF NOT blocked THEN RAISE EXCEPTION 'NULL blocked state must fail';END IF;n:=n+1;
 proof:=jsonb_build_object('run_id',run,'roles','[]'::jsonb,'complete',false);
 PERFORM public.rr_test71_independent_financial_finish(run,false,proof);
 b:=public.rr_test71_independent_financial_claim();IF b->>'status'<>'CACHED' OR b->'proof'<>proof THEN RAISE EXCEPTION 'Completed retry must reuse proof';END IF;n:=n+1;
 UPDATE test71_security.independent_financial_runs SET created_at=now()-interval '11 minutes' WHERE id=run;
 a:=public.rr_test71_independent_financial_claim();IF NOT (a->>'claimed')::boolean THEN RAISE EXCEPTION 'Cooldown expiry must claim';END IF;run:=(a->>'run_id')::uuid;
 proof:=jsonb_build_object('run_id',run,'roles','[]'::jsonb,'complete',false);PERFORM public.rr_test71_independent_financial_finish(run,true,proof);
 b:=public.rr_test71_independent_financial_claim();IF b->>'status'<>'BLOCKED' OR (b->>'claimed')::boolean THEN RAISE EXCEPTION 'Unreconciled run must remain blocked';END IF;n:=n+1;
 PERFORM set_config('test71.run_guard_checks',n::text,true);
END $test$;
SELECT current_setting('test71.run_guard_checks')::int AS passed_checks;
ROLLBACK;
