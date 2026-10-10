BEGIN;
SET LOCAL ROLE anon;
DO $t$ DECLARE denied bool:=false;BEGIN
 BEGIN PERFORM 1 FROM public.rr_account_reporting_base_v806 LIMIT 1;EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'Anonymous financial view still readable';END IF;
END;$t$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','af915a18-3823-48df-b039-1e4c7a88479b',true);
SET LOCAL ROLE authenticated;
DO $t$ DECLARE n int;BEGIN SELECT count(*) INTO n FROM public.rr_account_reporting_base_v806;IF n<>764 THEN RAISE EXCEPTION 'Owner financial view changed %',n;END IF;END;$t$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','893c58dd-420b-4dfa-aff7-844e20e634c5',true);
SELECT rr_test_set_on_behalf_context_v176((SELECT worker_id FROM rr_worker_directory_compat_v264 WHERE lower(worker_name)='imamul' AND is_active LIMIT 1));
SET LOCAL ROLE authenticated;
DO $t$ DECLARE n int;BEGIN
 SELECT count(*) INTO n FROM public.rr_account_reporting_base_v806;IF n<>0 THEN RAISE EXCEPTION 'Worker financial view leaked';END IF;
 SELECT count(*) INTO n FROM public.rr_worker_salary_ledger_board_v781;IF n<>0 THEN RAISE EXCEPTION 'Worker all-salary view leaked';END IF;
 IF public.rr_worker_salary_can_pay_v781() OR public.rr_payroll_can_manage_v778() THEN RAISE EXCEPTION 'On-behalf Worker inherited operator pay permissions';END IF;
END;$t$;
SELECT jsonb_build_object('anonymous_view_denied',true,'owner_financial_rows',764,'worker_global_financial_rows',0,'worker_payroll_management_denied',true) result;
ROLLBACK;
