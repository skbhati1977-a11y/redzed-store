
CREATE OR REPLACE FUNCTION public.rr_paid_salaried_profile_rules_test71() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NEW.data_mode='TEST' AND NEW.worker_category='SALARIED' AND NEW.status='ACTIVE' THEN
  NEW.weekly_holiday_isodow:=1;
  UPDATE public.rr_shift_master_v777_2 SET lunch_end=lunch_start+interval '30 minutes',lunch_is_paid=true,updated_at=now()
   WHERE shift_id=NEW.shift_id AND (NOT lunch_is_paid OR lunch_end-lunch_start<>interval '30 minutes');
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.rr_paid_salaried_profile_rules_test71() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER rr_paid_salaried_profile_rules_test71 BEFORE INSERT OR UPDATE OF worker_category,status,shift_id,weekly_holiday_isodow,data_mode ON public.rr_worker_payroll_profile_v777_2 FOR EACH ROW EXECUTE FUNCTION public.rr_paid_salaried_profile_rules_test71();

CREATE OR REPLACE FUNCTION public.rr_paid_holiday_calendar_sync_test71() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_name text;v_date date;v_active boolean;
BEGIN
 IF pg_trigger_depth()>1 THEN RETURN NEW;END IF;
 IF TG_TABLE_NAME='rr_holiday_calendar_v777_2' THEN
  IF NEW.data_mode<>'TEST' THEN RETURN NEW;END IF;
  IF NEW.holiday_name NOT IN ('REPUBLIC_DAY','HOLI','INDEPENDENCE_DAY','RAKSHA_BANDHAN','DIWALI','VISHWAKARMA_DAY','BHAI_DOOJ') THEN RAISE EXCEPTION 'Only the seven approved salaried holidays are enabled in TEST.';END IF;
  IF NOT NEW.is_paid_holiday OR NEW.applies_to NOT IN ('ALL','SALARIED_ONLY') THEN RAISE EXCEPTION 'Approved salaried holidays must remain paid for all salaried workers.';END IF;
  INSERT INTO public.rr_payroll_holidays_v778(holiday_date,holiday_name,extra_pay_factor,is_active,remarks)
   VALUES(NEW.holiday_date,NEW.holiday_name,0,NEW.is_active,'Paid salaried holiday; shared calendar mapping.')
   ON CONFLICT(holiday_date) DO UPDATE SET holiday_name=excluded.holiday_name,is_active=excluded.is_active,updated_at=now();
 ELSE
  v_name:=upper(regexp_replace(trim(NEW.holiday_name),'[ -]+','_','g'));
  v_name:=CASE v_name WHEN '26_JAN' THEN 'REPUBLIC_DAY' WHEN '15_AUG' THEN 'INDEPENDENCE_DAY' WHEN 'RAKSHA_BANDHAN' THEN 'RAKSHA_BANDHAN' WHEN 'BHAIYA_DOOJ' THEN 'BHAI_DOOJ' WHEN 'BHAI_DUJ' THEN 'BHAI_DOOJ' WHEN 'VISHWAKARMA' THEN 'VISHWAKARMA_DAY' ELSE v_name END;
  IF v_name NOT IN ('REPUBLIC_DAY','HOLI','INDEPENDENCE_DAY','RAKSHA_BANDHAN','DIWALI','VISHWAKARMA_DAY','BHAI_DOOJ') THEN RAISE EXCEPTION 'Use one of the seven approved salaried holiday names.';END IF;
  IF EXISTS(SELECT 1 FROM public.rr_holiday_calendar_v777_2 WHERE holiday_date=NEW.holiday_date AND data_mode='TEST' AND payroll_locked) THEN RAISE EXCEPTION 'Payroll locked holiday cannot be changed.';END IF;
  UPDATE public.rr_holiday_calendar_v777_2 SET holiday_name=v_name,is_paid_holiday=true,applies_to='SALARIED_ONLY',selected_departments='[]',is_active=NEW.is_active,updated_at=now()
   WHERE holiday_date=NEW.holiday_date AND data_mode='TEST';
  IF NOT FOUND THEN INSERT INTO public.rr_holiday_calendar_v777_2(holiday_date,holiday_name,applies_to,is_paid_holiday,holiday_multiplier,data_mode,is_active)
   VALUES(NEW.holiday_date,v_name,'SALARIED_ONLY',true,1,'TEST',NEW.is_active);END IF;
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.rr_paid_holiday_calendar_sync_test71() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER rr_paid_holiday_calendar_to_payroll_test71 AFTER INSERT OR UPDATE ON public.rr_holiday_calendar_v777_2 FOR EACH ROW EXECUTE FUNCTION public.rr_paid_holiday_calendar_sync_test71();
CREATE TRIGGER rr_paid_holiday_payroll_to_calendar_test71 AFTER INSERT OR UPDATE ON public.rr_payroll_holidays_v778 FOR EACH ROW EXECUTE FUNCTION public.rr_paid_holiday_calendar_sync_test71();
