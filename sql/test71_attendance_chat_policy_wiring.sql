-- TEST71 read-only Attendance projection. Existing records remain authoritative.
CREATE OR REPLACE FUNCTION public.rr_chat_attendance_queue_test71(p_month date DEFAULT NULL, p_worker_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
 v_uid uuid:=auth.uid(); v_identity jsonb; v_role text; v_self uuid;
 v_today date:=(now() AT TIME ZONE 'Asia/Kolkata')::date;
 v_from date; v_to date; v_cards jsonb; v_all boolean; v_depts text[]; v_head boolean;
BEGIN
 IF v_uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.rr_user_profiles WHERE auth_user_id=v_uid AND is_active AND upper(coalesce(access_status,'ACTIVE'))='ACTIVE') THEN RAISE EXCEPTION 'Active login required.'; END IF;
 v_identity:=public.rr_upm_effective_identity_v200(); v_role:=upper(coalesce(v_identity->>'resolved_role',v_identity->>'role_code','WORKER')); v_self:=nullif(v_identity->>'worker_id','')::uuid;
 v_all:=v_role IN ('OWNER','SUPER_ADMIN','ADMIN','MANAGER','ACCOUNT','ACCOUNTS','PAYROLL','HR');
 v_head:=v_role IN ('DEPARTMENT_HEAD','CUTTING_MASTER','LINE_MANAGER','LINE_MAN');
 SELECT array_agg(upper(x)) INTO v_depts FROM jsonb_array_elements_text(coalesce(v_identity->'department_codes','[]'::jsonb)) x;
 v_depts:=coalesce(v_depts,'{}'::text[])||upper(coalesce(v_identity->>'department_code',''));
 IF NOT v_all AND NOT v_head AND p_worker_id IS NOT NULL AND p_worker_id IS DISTINCT FROM v_self THEN RAISE EXCEPTION 'Own attendance only.'; END IF;
 v_from:=date_trunc('month',coalesce(p_month,v_today))::date; v_to:=least((v_from+interval '1 month - 1 day')::date,v_today);
 WITH profiles AS MATERIALIZED (
  SELECT DISTINCT ON (p.worker_id) p.worker_id,p.effective_from,p.effective_to,p.attendance_required,p.weekly_holiday_isodow,
   w.worker_name,w.worker_code,w.department_code,w.linked_auth_user_id
  FROM public.rr_worker_payroll_profile_v777_2 p JOIN public.rr_worker_directory_compat_v264 w ON w.worker_id=p.worker_id
  WHERE p.data_mode='TEST' AND p.status='ACTIVE' AND p.worker_category='SALARIED' AND w.is_active AND upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE'
    AND p.effective_from<=v_to AND (p.effective_to IS NULL OR p.effective_to>=v_from)
    AND (v_all OR p.worker_id=v_self OR v_head AND upper(w.department_code)=ANY(v_depts)) AND (p_worker_id IS NULL OR p.worker_id=p_worker_id)
  ORDER BY p.worker_id,p.effective_from DESC,p.configured_at DESC
 ), sources AS (
  SELECT a.worker_id,a.attendance_date,a.id::text source_id,'MANUAL'::text source_kind,a.check_in_at,a.check_out_at,a.status,a.updated_at source_at,
    NULL::boolean inside_geofence,NULL::text premise, a.locked_payroll_run_id IS NOT NULL locked,1 priority
  FROM public.rr_attendance_day_v778 a JOIN profiles p USING(worker_id)
  WHERE a.data_mode='TEST' AND a.attendance_date BETWEEN greatest(v_from,p.effective_from) AND least(v_to,coalesce(p.effective_to,v_to))
  UNION ALL
  SELECT a.worker_id,a.business_date,a.session_id::text,'GEOFENCE',a.checkin_at,a.checkout_at,
    CASE WHEN a.checkout_at IS NULL THEN 'CHECKED_IN' ELSE 'PRESENT' END,a.updated_at,
    CASE WHEN a.checkout_at IS NULL THEN a.checkin_inside_geofence ELSE a.checkout_inside_geofence END,
    coalesce(a.checkout_premise_name,a.checkin_premise_name),false,1
  FROM public.rr_regular_attendance_sessions_v778_2 a JOIN profiles p USING(worker_id)
  WHERE a.data_mode='TEST' AND a.business_date BETWEEN greatest(v_from,p.effective_from) AND least(v_to,coalesce(p.effective_to,v_to))
  UNION ALL
  SELECT a.worker_id,a.attendance_date,a.attendance_day_id::text,'DAY',a.first_check_in,a.last_check_out,a.attendance_status,a.updated_at,NULL,NULL,false,2
  FROM public.rr_attendance_day_v777_2 a JOIN profiles p USING(worker_id)
  WHERE a.data_mode='TEST' AND a.attendance_date BETWEEN greatest(v_from,p.effective_from) AND least(v_to,coalesce(p.effective_to,v_to))
 ), actual AS (
  SELECT DISTINCT ON(worker_id,attendance_date) * FROM sources ORDER BY worker_id,attendance_date,priority,source_at DESC
 ), daily AS (
  SELECT a.*,p.worker_name,p.worker_code,p.department_code,p.linked_auth_user_id FROM actual a JOIN profiles p USING(worker_id)
  UNION ALL
  SELECT p.worker_id,v_today,NULL,'PENDING',NULL,NULL,'PENDING',NULL,NULL,NULL,false,0,p.worker_name,p.worker_code,p.department_code,p.linked_auth_user_id
  FROM profiles p WHERE v_today BETWEEN v_from AND v_to AND v_today>=p.effective_from AND (p.effective_to IS NULL OR v_today<=p.effective_to)
   AND p.attendance_required AND extract(isodow FROM v_today)<>coalesce(p.weekly_holiday_isodow,1)
   AND NOT EXISTS(SELECT 1 FROM public.rr_payroll_holidays_v778 h WHERE h.holiday_date=v_today AND h.is_active)
   AND NOT EXISTS(SELECT 1 FROM actual a WHERE a.worker_id=p.worker_id AND a.attendance_date=v_today)
 ), classified AS (
  SELECT d.*,pol.attendance_type,pol.policy_id,
   CASE WHEN d.check_in_at IS NULL AND d.status IN ('PENDING','INCOMPLETE','REVIEW_REQUIRED')
      OR d.attendance_date<v_today AND d.status IN ('INCOMPLETE','REVIEW_REQUIRED','CHECKED_IN') AND d.check_out_at IS NULL THEN 'OPEN' ELSE 'WORKING' END chat_status,
   (v_role IN ('OWNER','SUPER_ADMIN','ADMIN') OR d.worker_id=v_self) can_punch
  FROM daily d LEFT JOIN LATERAL (SELECT policy_id,attendance_type FROM public.rr_worker_attendance_policy_v778_1 pol
   WHERE pol.worker_id=d.worker_id AND pol.data_mode='TEST' AND pol.status='ACTIVE' AND pol.effective_from<=d.attendance_date
    AND (pol.effective_to IS NULL OR pol.effective_to>=d.attendance_date)
   ORDER BY pol.effective_from DESC,pol.configured_at DESC LIMIT 1) pol ON true
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'event_key','ATTENDANCE:'||worker_id||':'||attendance_date,'worker_id',worker_id,'worker_name',worker_name,'worker_code',worker_code,
  'department_code',department_code,'attendance_date',attendance_date,'source_id',source_id,'source_kind',source_kind,
  'check_in_at',check_in_at,'check_out_at',check_out_at,'status',status,'chat_status',chat_status,'inside_geofence',inside_geofence,'premise',premise,
  'raw_late_minutes',coalesce((SELECT m.late_checkin_minutes FROM public.rr_attendance_daily_minutes_v778_2 m WHERE m.worker_id=classified.worker_id AND m.business_date=classified.attendance_date AND m.data_mode='TEST'),0),
 'early_minutes',coalesce((SELECT m.early_checkin_minutes FROM public.rr_attendance_daily_minutes_v778_2 m WHERE m.worker_id=classified.worker_id AND m.business_date=classified.attendance_date AND m.data_mode='TEST'),0),
 'after_shift_minutes',coalesce((SELECT m.verified_ot_minutes FROM public.rr_attendance_daily_minutes_v778_2 m WHERE m.worker_id=classified.worker_id AND m.business_date=classified.attendance_date AND m.data_mode='TEST'),0),
 'locked',locked,'policy_ready',policy_id IS NOT NULL,'attendance_type',attendance_type,
  'can_manage',v_all,
  'action',CASE WHEN can_punch AND attendance_date=v_today AND attendance_type='FACTORY_GEOFENCE' AND NOT locked
     AND check_out_at IS NULL AND source_kind IN ('PENDING','GEOFENCE')
    THEN CASE WHEN check_in_at IS NULL THEN 'CHECK_IN' ELSE 'CHECK_OUT' END ELSE NULL END
 ) ORDER BY attendance_date DESC,worker_name),'[]'::jsonb) INTO v_cards FROM classified;
 RETURN jsonb_build_object('cards',v_cards,'OPEN',(SELECT count(*) FROM jsonb_array_elements(v_cards)c WHERE c->>'chat_status'='OPEN'),
 'WORKING',(SELECT count(*) FROM jsonb_array_elements(v_cards)c WHERE c->>'chat_status'='WORKING'),'month',v_from,'today',v_today,'can_manage',v_all);
END $$;
REVOKE ALL ON FUNCTION public.rr_chat_attendance_queue_test71(date,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_chat_attendance_queue_test71(date,uuid) TO authenticated;

-- Serialise duplicate taps; canonical check-in/out uses server time and existing geofence policy.
CREATE OR REPLACE FUNCTION public.rr_chat_attendance_action_test71(p_worker_id uuid,p_action text,p_latitude numeric,p_longitude numeric,p_accuracy_meters numeric,p_source_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_uid uuid:=auth.uid();v_identity jsonb;v_role text;v_self uuid;v_today date:=(now() AT TIME ZONE 'Asia/Kolkata')::date;
 v_session public.rr_regular_attendance_sessions_v778_2%rowtype;v_result jsonb;v_profile public.rr_worker_payroll_profile_v777_2%rowtype;
BEGIN
 IF v_uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.rr_user_profiles WHERE auth_user_id=v_uid AND is_active AND upper(coalesce(access_status,'ACTIVE'))='ACTIVE') THEN RAISE EXCEPTION 'Active login required.'; END IF;
 v_identity:=public.rr_upm_effective_identity_v200();v_role:=upper(coalesce(v_identity->>'resolved_role',v_identity->>'role_code','WORKER'));v_self:=nullif(v_identity->>'worker_id','')::uuid;
 IF v_role NOT IN ('OWNER','SUPER_ADMIN','ADMIN') AND p_worker_id IS DISTINCT FROM v_self THEN RAISE EXCEPTION 'Own attendance or Owner/Admin required.'; END IF;
 IF p_action NOT IN ('CHECK_IN','CHECK_OUT') THEN RAISE EXCEPTION 'CHECK_IN or CHECK_OUT required.'; END IF;
 IF p_latitude IS NULL OR p_latitude NOT BETWEEN -90 AND 90 OR p_longitude IS NULL OR p_longitude NOT BETWEEN -180 AND 180 OR p_accuracy_meters IS NULL OR p_accuracy_meters<0 THEN RAISE EXCEPTION 'Valid live GPS required.'; END IF;
 IF nullif(trim(p_source_id),'') IS NULL THEN RAISE EXCEPTION 'Source action ID required.'; END IF;
 SELECT * INTO v_profile FROM public.rr_active_payroll_profile_v778_2(p_worker_id,v_today,'TEST');
 IF v_profile.profile_id IS NULL OR v_profile.worker_category<>'SALARIED' THEN RAISE EXCEPTION 'Active salaried payroll profile required.'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('TEST71_ATTENDANCE:'||p_worker_id||':'||v_today,0));
 IF EXISTS(SELECT 1 FROM public.rr_attendance_day_v778 WHERE worker_id=p_worker_id AND attendance_date=v_today AND data_mode='TEST')
 OR EXISTS(SELECT 1 FROM public.rr_payroll_runs_v778 r JOIN public.rr_payroll_run_lines_v778 l ON l.payroll_run_id=r.id WHERE l.worker_id=p_worker_id AND r.data_mode='TEST' AND v_today BETWEEN r.period_month AND r.period_end AND r.status IN ('APPROVED','PAID')) THEN
 RAISE EXCEPTION 'Attendance already marked or payroll locked; use existing Attendance module.'; END IF;
 SELECT * INTO v_session FROM public.rr_regular_attendance_sessions_v778_2 WHERE worker_id=p_worker_id AND business_date=v_today AND data_mode='TEST';
 IF p_action='CHECK_IN' AND v_session.session_id IS NOT NULL THEN RETURN jsonb_build_object('ok',true,'duplicate',true,'event','CHECK_IN','session_id',v_session.session_id); END IF;
 IF p_action='CHECK_OUT' AND v_session.checkout_at IS NOT NULL THEN RETURN jsonb_build_object('ok',true,'duplicate',true,'event','CHECK_OUT','session_id',v_session.session_id); END IF;
 IF p_action='CHECK_IN' THEN v_result:=public.rr_regular_checkin_v778_2(p_worker_id,p_latitude,p_longitude,p_accuracy_meters,p_source_id,'TEST');
 ELSE v_result:=public.rr_regular_checkout_v778_2(p_worker_id,p_latitude,p_longitude,p_accuracy_meters,p_source_id,'TEST'); END IF;
 IF coalesce((v_result->>'ok')::boolean,false) THEN PERFORM public.rr_calculate_attendance_day_v778_2(p_worker_id,v_today,'TEST'); END IF;
 RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.rr_chat_attendance_action_test71(uuid,text,numeric,numeric,numeric,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_chat_attendance_action_test71(uuid,text,numeric,numeric,numeric,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.rr_attendance_actor_v778_2(p_worker_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_actor public.rr_user_profiles%rowtype;v_worker record;v_admin boolean;v_self boolean;v_id uuid;
begin
 select * into v_actor from public.rr_user_profiles where auth_user_id=auth.uid() and coalesce(is_active,false) and upper(coalesce(access_status,'ACTIVE'))='ACTIVE' limit 1;
 if not found then raise exception 'Active ERP profile required.';end if;
 v_id:=public.rr_canonical_worker_id_v264(p_worker_id);
 select worker_id,worker_name,worker_code,department_code,role_code,linked_auth_user_id,is_active,access_status into v_worker from public.rr_worker_directory_compat_v264 where worker_id=v_id limit 1;
 if not found then raise exception 'Worker not found.';end if;
 v_admin:=lower(coalesce(v_actor.role_code,'')) in('owner','super_admin','admin');v_self:=v_worker.linked_auth_user_id=auth.uid();
 if not v_admin and not v_self then raise exception 'Self-login or Owner/Admin required.';end if;
 return jsonb_build_object('actor_auth_user_id',auth.uid(),'actor_name',v_actor.full_name,'actor_role',v_actor.role_code,'owner_admin',v_admin,'self_login',v_self,'worker_id',v_worker.worker_id,'worker_name',v_worker.worker_name,'department_code',v_worker.department_code,'worker_role_code',v_worker.role_code,'worker_is_active',v_worker.is_active,'worker_access_status',v_worker.access_status);
end$function$


-- Configure all canonical TEST salaried workers using the existing V778.2 policy.
-- Forward effective date; no fabricated punches, salary runs, payments or historical deductions.
CREATE OR REPLACE FUNCTION public.rr_ensure_salaried_attendance_policy_test71(p_worker_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_worker uuid:=public.rr_canonical_worker_id_v264(p_worker_id);v_from date;v_to date;v_today date:=(now() AT TIME ZONE 'Asia/Kolkata')::date;
BEGIN
 SELECT greatest(p.effective_from,v_today),p.effective_to INTO v_from,v_to
 FROM public.rr_worker_payroll_profile_v777_2 p JOIN public.rr_worker_directory_compat_v264 w ON w.worker_id=v_worker
 WHERE public.rr_canonical_worker_id_v264(p.worker_id)=v_worker AND p.data_mode='TEST' AND p.status='ACTIVE' AND p.worker_category='SALARIED'
  AND (p.effective_to IS NULL OR p.effective_to>=v_today) AND w.is_active AND upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE'
 ORDER BY p.effective_from DESC,p.configured_at DESC LIMIT 1;
 IF v_from IS NULL THEN RETURN; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('TEST71_ATTENDANCE_POLICY:'||v_worker,0));
 IF NOT EXISTS(SELECT 1 FROM public.rr_worker_attendance_policy_v778_1 WHERE worker_id=v_worker AND data_mode='TEST' AND status='ACTIVE' AND effective_from<=v_from AND (effective_to IS NULL OR effective_to>=v_from)) THEN
  INSERT INTO public.rr_worker_attendance_policy_v778_1(worker_id,workforce_type,attendance_type,start_day_required,end_day_required,
   auto_start_from_first_business_event,auto_end_at_business_day_close,continuous_location_required,location_required_on_start,location_required_on_end,
   location_required_on_business_event,minimum_verified_business_events,gps_accuracy_limit_meters,premise_access_mode,data_mode,effective_from,effective_to,configured_by,reason)
  VALUES(v_worker,'FACTORY_WORKER','FACTORY_GEOFENCE',true,true,false,false,false,true,true,false,0,100,'SELECTED_ONLY','TEST',v_from,v_to,auth.uid(),'TEST71 all salaried attendance wiring; existing V778.2 rules; L1/L2 100m');
 END IF;
 INSERT INTO public.rr_worker_attendance_premises_v778_1(worker_id,premise_id,is_primary,is_active,effective_from,effective_to,assigned_by,reason)
 SELECT v_worker,p.premise_id,p.premise_code='L1',true,v_from,v_to,auth.uid(),'TEST71 salaried L1/L2 existing Geo Fence'
 FROM public.rr_attendance_premises_v778_1 p WHERE p.data_mode='TEST' AND p.premise_code IN ('L1','L2') AND p.is_active
 AND p.effective_from<=v_from AND (p.effective_to IS NULL OR p.effective_to>=v_from)
 AND NOT EXISTS(SELECT 1 FROM public.rr_worker_attendance_premises_v778_1 x WHERE x.worker_id=v_worker AND x.premise_id=p.premise_id AND x.is_active AND x.effective_from<=v_from AND (x.effective_to IS NULL OR x.effective_to>=v_from))
 ON CONFLICT(worker_id,premise_id,effective_from) DO NOTHING;
END $$;
REVOKE ALL ON FUNCTION public.rr_ensure_salaried_attendance_policy_test71(uuid) FROM PUBLIC,anon,authenticated;
DO $$ DECLARE w record; BEGIN
 FOR w IN SELECT DISTINCT public.rr_canonical_worker_id_v264(worker_id) id FROM public.rr_worker_payroll_profile_v777_2 WHERE data_mode='TEST' AND status='ACTIVE' AND worker_category='SALARIED'
 LOOP PERFORM public.rr_ensure_salaried_attendance_policy_test71(w.id); END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.rr_salaried_attendance_policy_trigger_test71()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN IF NEW.data_mode='TEST' AND NEW.status='ACTIVE' AND NEW.worker_category='SALARIED' THEN PERFORM public.rr_ensure_salaried_attendance_policy_test71(NEW.worker_id); END IF;RETURN NEW;END $$;
REVOKE ALL ON FUNCTION public.rr_salaried_attendance_policy_trigger_test71() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS rr_salaried_attendance_policy_test71 ON public.rr_worker_payroll_profile_v777_2;
CREATE TRIGGER rr_salaried_attendance_policy_test71 AFTER INSERT OR UPDATE OF worker_category,status,effective_from,effective_to ON public.rr_worker_payroll_profile_v777_2 FOR EACH ROW EXECUTE FUNCTION public.rr_salaried_attendance_policy_trigger_test71();


-- Project existing verified daily minutes into the existing canonical payroll-day row.
-- No salary calculation, ledger posting or duplicate payroll record.
CREATE OR REPLACE FUNCTION public.rr_attendance_minutes_payroll_sync_test71()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE p public.rr_worker_payroll_profile_v777_2%rowtype;s public.rr_shift_master_v777_2%rowtype;
 n_ded integer:=0;n_extra integer:=0;v_complete boolean;v_status text;
BEGIN
 IF NEW.data_mode<>'TEST' THEN RETURN NEW;END IF;
 SELECT * INTO p FROM public.rr_active_payroll_profile_v778_2(NEW.worker_id,NEW.business_date,'TEST');
 IF p.profile_id IS NULL OR p.worker_category<>'SALARIED' THEN RETURN NEW;END IF;
 IF NEW.business_date>(now() AT TIME ZONE 'Asia/Kolkata')::date THEN RAISE EXCEPTION 'Future attendance blocked.';END IF;
 IF EXISTS(SELECT 1 FROM public.rr_payroll_runs_v778 r JOIN public.rr_payroll_run_lines_v778 l ON l.payroll_run_id=r.id
  WHERE l.worker_id=NEW.worker_id AND r.data_mode='TEST' AND NEW.business_date BETWEEN r.period_month AND r.period_end AND r.status IN ('APPROVED','PAID')) THEN RAISE EXCEPTION 'Approved payroll attendance is locked.';END IF;
 SELECT * INTO s FROM public.rr_shift_master_v777_2 WHERE shift_id=p.shift_id;
 v_complete:=NEW.regular_checkin_at IS NOT NULL AND NEW.regular_checkout_at IS NOT NULL AND NOT NEW.forgot_checkout;
 v_status:=CASE WHEN NEW.forgot_checkout OR NOT v_complete THEN 'REVIEW_REQUIRED' ELSE NEW.attendance_status END;
 IF v_complete THEN
 n_ded:=(CASE WHEN p.late_deduction_applicable THEN NEW.late_checkin_minutes ELSE 0 END)+NEW.early_checkout_minutes;
 n_extra:=NEW.early_checkin_minutes+(CASE WHEN p.overtime_applicable AND NOT NEW.forgot_checkout AND NOT NEW.outside_checkout THEN NEW.verified_ot_minutes ELSE 0 END)
   +(CASE WHEN p.holiday_extra_applicable THEN NEW.verified_holiday_minutes ELSE 0 END);
 END IF;
 INSERT INTO public.rr_attendance_day_v777_2(worker_id,profile_id,attendance_date,first_check_in,last_check_out,
 gross_presence_minutes,grace_used_minutes,late_deduction_minutes,early_exit_deduction_minutes,normal_payable_minutes,gross_overtime_minutes,
 payable_overtime_minutes,holiday_work_minutes,attendance_status,is_holiday,calculation_snapshot,approval_status,data_mode,
 scheduled_payable_minutes,net_deduction_minutes,net_extra_work_minutes,net_working_minutes,paid_leave_minutes,unpaid_leave_minutes)
 VALUES(NEW.worker_id,p.profile_id,NEW.business_date,NEW.regular_checkin_at,NEW.regular_checkout_at,
 greatest(coalesce(floor(extract(epoch FROM NEW.regular_checkout_at-NEW.regular_checkin_at)/60)::integer,0),0),0,
 CASE WHEN v_complete AND p.late_deduction_applicable THEN NEW.late_checkin_minutes ELSE 0 END,
 CASE WHEN v_complete THEN NEW.early_checkout_minutes ELSE 0 END,
 CASE WHEN v_complete THEN greatest(s.normal_payable_minutes-n_ded,0) ELSE 0 END,n_extra,
 CASE WHEN v_complete AND p.overtime_applicable AND NOT NEW.outside_checkout THEN NEW.verified_ot_minutes ELSE 0 END,
 CASE WHEN v_complete AND p.holiday_extra_applicable THEN NEW.verified_holiday_minutes ELSE 0 END,
 v_status,extract(isodow FROM NEW.business_date)=p.weekly_holiday_isodow,
 jsonb_build_object('source','V778_2_VERIFIED_DAILY_MINUTES','daily_minutes_id',NEW.daily_minutes_id,'money_calculation_included',false,'review_required',NOT v_complete),
 CASE WHEN v_complete THEN 'APPROVED' ELSE 'PENDING' END,'TEST',s.normal_payable_minutes,n_ded,n_extra,
 CASE WHEN v_complete THEN greatest(s.normal_payable_minutes-n_ded+n_extra,0) ELSE 0 END,0,0)
 ON CONFLICT(worker_id,attendance_date,data_mode) DO UPDATE SET
 profile_id=excluded.profile_id,first_check_in=excluded.first_check_in,last_check_out=excluded.last_check_out,gross_presence_minutes=excluded.gross_presence_minutes,
 late_deduction_minutes=excluded.late_deduction_minutes,early_exit_deduction_minutes=excluded.early_exit_deduction_minutes,normal_payable_minutes=excluded.normal_payable_minutes,
 gross_overtime_minutes=excluded.gross_overtime_minutes,payable_overtime_minutes=excluded.payable_overtime_minutes,holiday_work_minutes=excluded.holiday_work_minutes,
 attendance_status=excluded.attendance_status,is_holiday=excluded.is_holiday,calculation_snapshot=excluded.calculation_snapshot,approval_status=excluded.approval_status,
 scheduled_payable_minutes=excluded.scheduled_payable_minutes,net_deduction_minutes=excluded.net_deduction_minutes,net_extra_work_minutes=excluded.net_extra_work_minutes,
 net_working_minutes=excluded.net_working_minutes,updated_at=now();
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.rr_attendance_minutes_payroll_sync_test71() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS rr_attendance_minutes_payroll_test71 ON public.rr_attendance_daily_minutes_v778_2;
CREATE TRIGGER rr_attendance_minutes_payroll_test71 AFTER INSERT OR UPDATE ON public.rr_attendance_daily_minutes_v778_2
 FOR EACH ROW EXECUTE FUNCTION public.rr_attendance_minutes_payroll_sync_test71();
