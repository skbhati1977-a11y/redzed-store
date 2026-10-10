BEGIN;
CREATE TEMP TABLE audit_permission_result(label text,result jsonb);
SET LOCAL ROLE anon;
DO $test$ DECLARE denied bool:=false;BEGIN
 BEGIN PERFORM public.rr_trial_balance_v806('2026-01-01','2026-10-10','TEST'); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Anonymous report leak remains';END IF;
END $test$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','af915a18-3823-48df-b039-1e4c7a88479b',true);
SET LOCAL ROLE authenticated;
SELECT count(*) owner_trial_balance_rows FROM public.rr_trial_balance_v806('2026-01-01','2026-10-10','TEST');
SELECT public.rr_report_ui_bootstrap_v807('TEST')->>'ok' bootstrap_ok;
RESET ROLE;
DO $test$ DECLARE r record;err text;rows int;res jsonb:='[]';BEGIN
PERFORM set_config('request.jwt.claim.sub','893c58dd-420b-4dfa-aff7-844e20e634c5',true);
FOR r IN SELECT worker_id,worker_name FROM public.rr_worker_directory_compat_v264 WHERE is_active AND lower(worker_name) IN('imamul','ali','nasim','shailender','lukman') LOOP
 PERFORM public.rr_test_set_on_behalf_context_v176(r.worker_id);err:=null;rows:=null;
 BEGIN SELECT count(*) INTO rows FROM public.rr_trial_balance_v806('2026-01-01','2026-10-10','TEST');EXCEPTION WHEN insufficient_privilege THEN err:=sqlerrm;END;
 IF public.rr_acct_can_view_v805() <> (err IS NULL) THEN RAISE EXCEPTION 'Role mismatch %',r.worker_name;END IF;
 res:=res||jsonb_build_array(jsonb_build_object('person',r.worker_name,'expected_allowed',public.rr_acct_can_view_v805(),'rows',rows,'error',err));
END LOOP;
INSERT INTO audit_permission_result VALUES('role_matrix',res);
END $test$;
SELECT jsonb_build_object('role_matrix',(SELECT result FROM audit_permission_result),'anonymous_execute_count',(SELECT count(*) FROM pg_proc WHERE proname = ANY(ARRAY['rr_trial_balance_v806','rr_day_book_v806','rr_day_book_v807','rr_ledger_statement_v806','rr_ledger_statement_v807','rr_material_opening_balance_v664']) AND has_function_privilege('anon',oid,'EXECUTE'))) result;
ROLLBACK;
