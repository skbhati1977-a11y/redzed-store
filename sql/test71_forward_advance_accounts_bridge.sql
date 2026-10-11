-- TEST71 only. Forward events; historical opening advances are not backfilled.
CREATE OR REPLACE FUNCTION public.rr_worker_advance_accounts_event_test71()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE asset uuid;cat uuid;cash uuid;salary uuid;src text:='WORKER_ADVANCE_TEST71';
prev text:=current_setting('rr.trusted_account_bridge',true);linked public.rr_worker_advance_ledger_v785%rowtype;
BEGIN
 IF NEW.data_mode<>'TEST' THEN RETURN NEW; END IF;
 IF TG_OP='UPDATE' THEN
  IF (to_jsonb(NEW)-ARRAY['status','voided_by','voided_by_name','voided_at','void_reason']) IS DISTINCT FROM
     (to_jsonb(OLD)-ARRAY['status','voided_by','voided_by_name','voided_at','void_reason']) THEN
   RAISE EXCEPTION 'Advance financial fields are immutable; use an audited reversal.';
  END IF;
  IF NEW.status=OLD.status THEN RETURN NEW;END IF;
  IF OLD.status<>'POSTED' OR NEW.status<>'VOID' THEN RAISE EXCEPTION 'Advance status transition is not allowed.';END IF;
 END IF;
 IF auth.uid() IS NULL OR NOT(public.rr_worker_salary_can_pay_v781() OR public.rr_worker_salary_can_reverse_v781()) THEN
  RAISE EXCEPTION 'Advance settlement permission required.' USING ERRCODE='42501';
 END IF;
 PERFORM set_config('rr.trusted_account_bridge','worker_salary',true);
 IF TG_OP='UPDATE' THEN
  IF EXISTS(SELECT 1 FROM public.rr_account_source_links_v806 WHERE source_module=src AND source_record_id=NEW.id::text AND data_mode=NEW.data_mode AND status='ACTIVE') THEN
   PERFORM public.rr_accounts_reverse_source_mirror_v806(src,NEW.id::text,NEW.data_mode,coalesce(nullif(NEW.void_reason,''),'Advance void'));
  END IF;
 ELSIF NEW.status='POSTED' AND NEW.entry_type<>'OPENING_ADVANCE' THEN
  IF NEW.entry_type='ADVANCE_REVERSAL' THEN
   SELECT * INTO linked FROM public.rr_worker_advance_ledger_v785 WHERE id=NEW.related_entry_id FOR UPDATE;
   IF NOT FOUND OR linked.worker_id<>NEW.worker_id OR linked.data_mode<>NEW.data_mode OR linked.entry_type<>'ADVANCE_RECOVERY' OR linked.amount<>NEW.amount THEN
    RAISE EXCEPTION 'Advance reversal must match the original worker recovery.';
   END IF;
   IF EXISTS(SELECT 1 FROM public.rr_account_source_links_v806 WHERE source_module=src AND source_record_id=linked.id::text AND data_mode=NEW.data_mode AND status='ACTIVE') THEN
    PERFORM public.rr_accounts_reverse_source_mirror_v806(src,linked.id::text,NEW.data_mode,coalesce(nullif(NEW.remarks,''),'Advance recovery reversal'));
   END IF;
  ELSE
   salary:=public.rr_worker_accounts_ledger_resolve_test71(NEW.worker_id);
   IF salary IS NULL OR NOT EXISTS(SELECT 1 FROM public.rr_ledgers_v805 WHERE id=salary AND is_active) THEN RAISE EXCEPTION 'Active worker Accounts mapping required.';END IF;
   PERFORM pg_advisory_xact_lock(hashtextextended('ADVANCE_ASSET_TEST71|'||NEW.worker_id::text,0));
   SELECT id INTO asset FROM public.rr_ledgers_v805 WHERE ledger_code='ADV_TEST_'||NEW.worker_id::text AND is_active AND ledger_kind='ASSET';
   IF asset IS NULL AND NEW.entry_type='ADVANCE_PAYMENT' THEN
    SELECT id INTO cat FROM public.rr_account_categories_v805 WHERE category_code='STAFF_ADVANCE' AND is_active;
    IF cat IS NULL THEN RAISE EXCEPTION 'Staff advance asset category required.';END IF;
    INSERT INTO public.rr_ledgers_v805(ledger_code,ledger_name,normalized_name,category_id,ledger_kind,linked_entity_type,linked_entity_id,created_by)
    VALUES('ADV_TEST_'||NEW.worker_id::text,'TEST Advance · '||coalesce(NEW.worker_name,NEW.worker_id::text),
     'test advance '||NEW.worker_id::text,cat,'ASSET','WORKER_ADVANCE_TEST',NEW.worker_id::text,auth.uid()) RETURNING id INTO asset;
   END IF;
   IF asset IS NULL THEN RAISE EXCEPTION 'Approved advance opening Accounts mapping required before recovery.';END IF;
   IF NEW.entry_type='ADVANCE_PAYMENT' THEN
    SELECT cash_bank_ledger_id INTO cash FROM public.rr_payroll_cash_bank_routes_test71 WHERE data_mode=NEW.data_mode AND payment_mode=upper(NEW.payment_mode);
    IF cash IS NULL AND upper(NEW.payment_mode)='CASH' THEN SELECT id INTO cash FROM public.rr_ledgers_v805 WHERE ledger_code='CASH_MAIN' AND is_active AND ledger_kind='CASH';END IF;
    IF cash IS NULL OR NOT EXISTS(SELECT 1 FROM public.rr_ledgers_v805 WHERE id=cash AND is_active AND ledger_kind IN('CASH','BANK')) THEN RAISE EXCEPTION 'Approved active Cash/Bank route required for advance payment.';END IF;
    PERFORM public.rr_source_data_mode_tag_v806(src,NEW.id::text,NEW.data_mode);
    PERFORM public.rr_accounts_mirror_post_v806('PAYMENT',NEW.amount,jsonb_build_array(
     jsonb_build_object('ledger_id',asset,'dr',NEW.amount,'cr',0,'narration','Worker advance asset'),
     jsonb_build_object('ledger_id',cash,'dr',0,'cr',NEW.amount,'narration','Advance paid')),src,NEW.id::text,asset,NEW.reference_no,NEW.entry_date,NEW.remarks,NEW.data_mode);
   ELSIF NEW.entry_type='ADVANCE_RECOVERY' THEN
    PERFORM public.rr_source_data_mode_tag_v806(src,NEW.id::text,NEW.data_mode);
    PERFORM public.rr_accounts_mirror_post_v806('JOURNAL',NEW.amount,jsonb_build_array(
     jsonb_build_object('ledger_id',salary,'dr',NEW.amount,'cr',0,'narration','Advance recovered from salary payable'),
     jsonb_build_object('ledger_id',asset,'dr',0,'cr',NEW.amount,'narration','Advance asset recovered')),src,NEW.id::text,salary,NEW.reference_no,NEW.entry_date,NEW.remarks,NEW.data_mode);
   END IF;
  END IF;
 END IF;
 PERFORM set_config('rr.trusted_account_bridge',coalesce(prev,''),true);RETURN NEW;
EXCEPTION WHEN others THEN PERFORM set_config('rr.trusted_account_bridge',coalesce(prev,''),true);RAISE;
END;$$;
REVOKE ALL ON FUNCTION public.rr_worker_advance_accounts_event_test71() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER rr_worker_advance_accounts_event_test71 AFTER INSERT OR UPDATE ON public.rr_worker_advance_ledger_v785 FOR EACH ROW EXECUTE FUNCTION public.rr_worker_advance_accounts_event_test71();
