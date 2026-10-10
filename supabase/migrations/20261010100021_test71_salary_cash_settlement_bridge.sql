BEGIN;
CREATE TABLE IF NOT EXISTS public.rr_payroll_cash_bank_routes_test71(
 data_mode text NOT NULL CHECK(data_mode IN('TEST','REAL')), payment_mode text NOT NULL,
 cash_bank_ledger_id uuid NOT NULL REFERENCES public.rr_ledgers_v805(id),
 approved_by uuid NOT NULL,approved_at timestamptz NOT NULL DEFAULT now(),reason text NOT NULL,
 PRIMARY KEY(data_mode,payment_mode)
);
ALTER TABLE public.rr_payroll_cash_bank_routes_test71 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rr_payroll_cash_bank_routes_test71 FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.rr_payroll_cash_bank_route_set_test71(p_data_mode text,p_payment_mode text,p_ledger_id uuid,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public AS $f$
DECLARE mode text:=upper(p_data_mode);paymode text:=upper(p_payment_mode);
BEGIN
 IF auth.uid() IS NULL OR NOT public.rr_is_owner_or_admin() THEN RAISE EXCEPTION 'Owner/Admin permission required.' USING ERRCODE='42501';END IF;
 IF mode NOT IN('TEST','REAL') OR paymode NOT IN('CASH','BANK','UPI','CHEQUE','OTHER') THEN RAISE EXCEPTION 'Valid mode/payment method required.';END IF;
 IF nullif(trim(p_reason),'') IS NULL THEN RAISE EXCEPTION 'Route approval reason required.';END IF;
 PERFORM public.rr_app_data_mode_assert_v786(mode);
 IF NOT EXISTS(SELECT 1 FROM public.rr_ledgers_v805 WHERE id=p_ledger_id AND is_active AND upper(ledger_kind) IN('CASH','BANK')
 AND (paymode<>'CASH' OR upper(ledger_kind)='CASH') AND (paymode NOT IN('BANK','UPI','CHEQUE') OR upper(ledger_kind)='BANK')) THEN RAISE EXCEPTION 'Payment method requires a compatible active Cash/Bank ledger.';END IF;
 INSERT INTO public.rr_payroll_cash_bank_routes_test71 VALUES(mode,paymode,p_ledger_id,auth.uid(),now(),trim(p_reason))
 ON CONFLICT(data_mode,payment_mode) DO UPDATE SET cash_bank_ledger_id=excluded.cash_bank_ledger_id,approved_by=excluded.approved_by,approved_at=excluded.approved_at,reason=excluded.reason;
 RETURN jsonb_build_object('ok',true,'data_mode',mode,'payment_mode',paymode,'cash_bank_ledger_id',p_ledger_id);
END;$f$;
REVOKE EXECUTE ON FUNCTION public.rr_payroll_cash_bank_route_set_test71(text,text,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_payroll_cash_bank_route_set_test71(text,text,uuid,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_acct_can_view_v805() RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO public AS $f$
DECLARE identity_json jsonb; effective_role text;
BEGIN
 IF auth.uid() IS NULL THEN RETURN false;END IF;
 IF current_setting('rr.trusted_account_bridge',true)='rci_reversal' THEN RETURN true;END IF;
 IF current_setting('rr.trusted_account_bridge',true)='worker_salary' AND public.rr_worker_salary_can_pay_v781() THEN RETURN true;END IF;
 identity_json:=public.rr_upm_effective_identity_v200();
 effective_role:=upper(coalesce(identity_json->>'resolved_role',identity_json->>'role_code','WORKER'));
 IF effective_role NOT IN('OWNER','SUPER_ADMIN','ADMIN','ACCOUNT','ACCOUNTS') THEN RETURN false;END IF;
 RETURN public.rr_acct_can_view_base_v9762();
END;$f$;
CREATE OR REPLACE FUNCTION public.rr_worker_accounts_ledger_resolve_test71(p_worker_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public AS $f$
DECLARE v_ledger uuid;v_auth uuid;v_count int;
BEGIN
 SELECT salary_ledger_id INTO v_ledger FROM public.rr_worker_accounts_map_v9785 WHERE worker_id=p_worker_id;
 IF v_ledger IS NOT NULL THEN RETURN v_ledger;END IF;
 SELECT linked_auth_user_id INTO v_auth FROM public.rr_worker_directory_unified_v1 WHERE worker_id=p_worker_id;
 IF v_auth IS NULL THEN SELECT linked_auth_user_id INTO v_auth FROM public.rr_worker_directory_v1 WHERE id=p_worker_id;END IF;
 IF v_auth IS NULL THEN RAISE EXCEPTION 'Worker salary Accounts mapping requires exact auth identity.';END IF;
 SELECT count(*),min(salary_ledger_id::text)::uuid INTO v_count,v_ledger FROM public.rr_worker_accounts_map_v9785 WHERE linked_auth_user_id=v_auth;
 IF v_count<>1 THEN RAISE EXCEPTION 'Worker salary Accounts mapping is missing or ambiguous.';END IF;
 RETURN v_ledger;
END;$f$;
REVOKE EXECUTE ON FUNCTION public.rr_worker_accounts_ledger_resolve_test71(uuid) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.rr_worker_salary_cash_event_test71()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public AS $f$
DECLARE worker_ledger uuid;cash_ledger uuid;previous_context text:=current_setting('rr.trusted_account_bridge',true);source text:='WORKER_SALARY_PAYMENT_TEST71';
BEGIN
 IF NEW.status<>'POSTED' OR NEW.amount<=0 THEN RETURN NEW;END IF;
 IF NEW.entry_type NOT IN('PAYMENT','BULK_PAYMENT','PAYMENT_REVERSAL','BULK_PAYMENT_REVERSAL') THEN RETURN NEW;END IF;
 IF auth.uid() IS NULL OR NOT (public.rr_worker_salary_can_pay_v781() OR public.rr_worker_salary_can_reverse_v781()) THEN RAISE EXCEPTION 'Salary settlement permission required.' USING ERRCODE='42501';END IF;
 PERFORM set_config('rr.trusted_account_bridge','worker_salary',true);
 IF NEW.entry_type IN('PAYMENT_REVERSAL','BULK_PAYMENT_REVERSAL') THEN
  -- Legacy settlements have no journal. Do not invent historical cash movements.
  IF EXISTS(SELECT 1 FROM public.rr_account_source_links_v806 WHERE source_module=source AND source_record_id=NEW.related_entry_id::text AND data_mode=NEW.data_mode AND status='ACTIVE') THEN
   PERFORM public.rr_accounts_reverse_source_mirror_v806(source,NEW.related_entry_id::text,NEW.data_mode,coalesce(nullif(NEW.remarks,''),'Salary payment reversal'));
  END IF;
 ELSE
  worker_ledger:=public.rr_worker_accounts_ledger_resolve_test71(NEW.worker_id);
  IF worker_ledger IS NULL THEN RAISE EXCEPTION 'Worker salary Accounts mapping required.';END IF;
  SELECT cash_bank_ledger_id INTO cash_ledger FROM public.rr_payroll_cash_bank_routes_test71 WHERE data_mode=NEW.data_mode AND payment_mode=upper(NEW.payment_mode);
  IF cash_ledger IS NULL AND upper(NEW.payment_mode)='CASH' THEN
   SELECT id INTO cash_ledger FROM public.rr_ledgers_v805 WHERE ledger_code='CASH_MAIN' AND is_active AND ledger_kind='CASH';
  END IF;
  IF cash_ledger IS NULL THEN RAISE EXCEPTION 'Approved Cash/Bank route required for % payment in %.',NEW.payment_mode,NEW.data_mode;END IF;
  PERFORM public.rr_source_data_mode_tag_v806(source,NEW.id::text,NEW.data_mode);
  PERFORM public.rr_accounts_mirror_post_v806('PAYMENT',NEW.amount,jsonb_build_array(
    jsonb_build_object('ledger_id',worker_ledger,'dr',NEW.amount,'cr',0,'narration','Worker salary settlement'),
    jsonb_build_object('ledger_id',cash_ledger,'dr',0,'cr',NEW.amount,'narration','Salary paid from approved Cash/Bank')),
    source,NEW.id::text,worker_ledger,NEW.reference_no,NEW.entry_date,NEW.remarks,NEW.data_mode);
 END IF;
 PERFORM set_config('rr.trusted_account_bridge',coalesce(previous_context,''),true);
 RETURN NEW;
EXCEPTION WHEN others THEN
 PERFORM set_config('rr.trusted_account_bridge',coalesce(previous_context,''),true);
 RAISE;
END;$f$;
REVOKE EXECUTE ON FUNCTION public.rr_worker_salary_cash_event_test71() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS rr_worker_salary_cash_event_test71 ON public.rr_worker_salary_ledger_v781;
CREATE TRIGGER rr_worker_salary_cash_event_test71 AFTER INSERT ON public.rr_worker_salary_ledger_v781
FOR EACH ROW EXECUTE FUNCTION public.rr_worker_salary_cash_event_test71();
COMMIT;

