CREATE OR REPLACE FUNCTION public.rr_worker_salary_accrual_accounts_test71()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE worker_ledger uuid;expense_ledger uuid;previous_context text:=current_setting('rr.trusted_account_bridge',true);source text:='WORKER_SALARY_ACCRUAL_TEST71';
BEGIN
 IF TG_OP='INSERT' THEN
  IF NEW.data_mode<>'TEST' OR NEW.entry_type NOT IN('MONTHLY_SALARY_DUE','MONTHLY_FINAL_ADJUSTMENT') THEN RETURN NEW;END IF;
 ELSE
  IF OLD.data_mode<>'TEST' OR OLD.entry_type NOT IN('MONTHLY_SALARY_DUE','MONTHLY_FINAL_ADJUSTMENT') THEN RETURN NEW;END IF;
 END IF;
 IF TG_OP='UPDATE' THEN
  IF NOT EXISTS(SELECT 1 FROM public.rr_account_source_links_v806 WHERE source_module=source AND source_record_id=OLD.id::text AND data_mode='TEST' ) THEN RETURN NEW;END IF;
  IF (to_jsonb(NEW)-ARRAY['status','voided_by','voided_by_name','voided_at','void_reason']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','voided_by','voided_by_name','voided_at','void_reason']) THEN RAISE EXCEPTION 'Posted salary accrual financial fields are immutable.';END IF;
  IF OLD.status=NEW.status THEN RETURN NEW;END IF;
  IF OLD.status<>'POSTED' OR NEW.status<>'VOID' THEN RAISE EXCEPTION 'Salary accrual status transition denied.';END IF;
 ELSE
  IF NEW.status<>'POSTED' THEN RETURN NEW;END IF;
 END IF;
 IF auth.uid() IS NULL OR NOT (public.rr_worker_salary_can_pay_v781() OR public.rr_worker_salary_can_reverse_v781() OR public.rr_payroll_can_manage_v779_1()) THEN RAISE EXCEPTION 'Salary accrual permission required.' USING ERRCODE='42501';END IF;
 PERFORM set_config('rr.trusted_account_bridge','worker_salary',true);
 IF TG_OP='UPDATE' THEN
  PERFORM public.rr_accounts_reverse_source_mirror_v806(source,NEW.id::text,'TEST',coalesce(nullif(NEW.void_reason,''),'Salary accrual void'));
 ELSE
  worker_ledger:=public.rr_worker_accounts_ledger_resolve_test71(NEW.worker_id);
  SELECT id INTO expense_ledger FROM public.rr_ledgers_v805 WHERE ledger_code='EXP_MONTHLY_SALARY' AND ledger_kind='EXPENSE' AND is_active;
  IF worker_ledger IS NULL OR expense_ledger IS NULL THEN RAISE EXCEPTION 'Approved worker payable and monthly salary expense Accounts mapping required.';END IF;
  PERFORM public.rr_source_data_mode_tag_v806(source,NEW.id::text,'TEST');
  PERFORM public.rr_accounts_mirror_post_v806('JOURNAL',NEW.amount,jsonb_build_array(
   jsonb_build_object('ledger_id',expense_ledger,'dr',CASE WHEN NEW.balance_effect>0 THEN NEW.amount ELSE 0 END,'cr',CASE WHEN NEW.balance_effect<0 THEN NEW.amount ELSE 0 END,'narration','Monthly salary expense accrual'),
   jsonb_build_object('ledger_id',worker_ledger,'dr',CASE WHEN NEW.balance_effect<0 THEN NEW.amount ELSE 0 END,'cr',CASE WHEN NEW.balance_effect>0 THEN NEW.amount ELSE 0 END,'narration','Worker salary payable accrual')),
   source,NEW.id::text,worker_ledger,NEW.reference_no,NEW.entry_date,NEW.remarks,'TEST');
 END IF;
 PERFORM set_config('rr.trusted_account_bridge',coalesce(previous_context,''),true);
 RETURN NEW;
EXCEPTION WHEN others THEN
 PERFORM set_config('rr.trusted_account_bridge',coalesce(previous_context,''),true);RAISE;
END;$$;
REVOKE ALL ON FUNCTION public.rr_worker_salary_accrual_accounts_test71() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER rr_worker_salary_accrual_accounts_test71 AFTER INSERT OR UPDATE ON public.rr_worker_salary_ledger_v781 FOR EACH ROW EXECUTE FUNCTION public.rr_worker_salary_accrual_accounts_test71();