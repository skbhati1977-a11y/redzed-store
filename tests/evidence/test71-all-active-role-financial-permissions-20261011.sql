BEGIN;
CREATE TEMP TABLE role_financial_checks(role_code text,effective_role text,expected_allowed boolean,trial_balance_allowed boolean,accounts_home_allowed boolean) ON COMMIT DROP;
DO $test$
DECLARE p record;effective text;expected boolean;report_ok boolean;home_ok boolean;
BEGIN
 FOR p IN SELECT auth_user_id,upper(role_code) role_code FROM public.rr_user_profiles WHERE is_active AND upper(coalesce(access_status,'ACTIVE'))='ACTIVE' AND auth_user_id IS NOT NULL LOOP
  PERFORM set_config('request.jwt.claim.sub',p.auth_user_id::text,true);
  effective:=upper(coalesce(public.rr_upm_effective_identity_v200()->>'resolved_role',public.rr_upm_effective_identity_v200()->>'role_code','WORKER'));
  expected:=effective IN('OWNER','SUPER_ADMIN','ADMIN','ACCOUNT','ACCOUNTS');
  report_ok:=true;home_ok:=true;
  BEGIN PERFORM public.rr_trial_balance_v806('2026-01-01',current_date,'TEST');EXCEPTION WHEN others THEN IF SQLSTATE<>'42501' AND SQLERRM NOT ILIKE '%permission required%' THEN RAISE;END IF;report_ok:=false;END;
  BEGIN PERFORM public.rr_accounts_real_chat_home_v500('OPEN','TEST');EXCEPTION WHEN others THEN IF SQLSTATE<>'42501' AND SQLERRM NOT ILIKE '%permission required%' THEN RAISE;END IF;home_ok:=false;END;
  IF report_ok IS DISTINCT FROM expected OR home_ok IS DISTINCT FROM expected THEN RAISE EXCEPTION 'Financial authority differs for profile role % / effective %',p.role_code,effective;END IF;
  INSERT INTO role_financial_checks VALUES(p.role_code,effective,expected,report_ok,home_ok);
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM role_financial_checks WHERE effective_role='SUPER_ADMIN' AND trial_balance_allowed) THEN RAISE EXCEPTION 'Super Admin role not exercised';END IF;
 IF NOT EXISTS(SELECT 1 FROM role_financial_checks WHERE effective_role='WORKER' AND NOT trial_balance_allowed) THEN RAISE EXCEPTION 'Worker denial not exercised';END IF;
END $test$;
SELECT role_code,effective_role,count(*) profiles_checked,bool_and(trial_balance_allowed=expected_allowed AND accounts_home_allowed=expected_allowed) authority_passed FROM role_financial_checks GROUP BY role_code,effective_role ORDER BY role_code;
ROLLBACK;
