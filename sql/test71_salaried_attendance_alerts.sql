
ALTER TABLE public.rr_worker_attendance_policy_v778_1 ADD COLUMN IF NOT EXISTS checkin_alert_before_minutes integer NOT NULL DEFAULT 10 CHECK(checkin_alert_before_minutes BETWEEN 0 AND 120);
ALTER TABLE public.rr_worker_attendance_policy_v778_1 ADD COLUMN IF NOT EXISTS checkout_alert_after_minutes integer NOT NULL DEFAULT 10 CHECK(checkout_alert_after_minutes BETWEEN 0 AND 120);
CREATE OR REPLACE FUNCTION public.rr_salaried_alert_defaults_test71() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NEW.data_mode='TEST' AND EXISTS(SELECT 1 FROM public.rr_worker_payroll_profile_v777_2 p WHERE public.rr_canonical_worker_id_v264(p.worker_id)=NEW.worker_id AND p.data_mode='TEST' AND p.worker_category='SALARIED' AND p.status='ACTIVE') THEN
  NEW.checkin_alert_before_minutes:=10;NEW.checkout_alert_after_minutes:=10;
 END IF;RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.rr_salaried_alert_defaults_test71() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER rr_salaried_alert_defaults_test71 BEFORE INSERT OR UPDATE ON public.rr_worker_attendance_policy_v778_1 FOR EACH ROW EXECUTE FUNCTION public.rr_salaried_alert_defaults_test71();
UPDATE public.rr_worker_attendance_policy_v778_1 SET checkin_alert_before_minutes=10,checkout_alert_after_minutes=10 WHERE data_mode='TEST' AND status='ACTIVE';
UPDATE public.rr_shift_master_v777_2 SET duty_start='10:00',duty_end='20:00',updated_at=now() WHERE shift_id IN(SELECT shift_id FROM public.rr_worker_payroll_profile_v777_2 WHERE data_mode='TEST' AND worker_category='SALARIED' AND status='ACTIVE');

CREATE OR REPLACE FUNCTION public.rr_attendance_alert_tick_test71(p_now timestamptz DEFAULT now()) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_date date:=(p_now AT TIME ZONE 'Asia/Kolkata')::date; v_rem record;n integer:=0;c integer;v_url text;
BEGIN
 UPDATE public.rr_attendance_reminder_state_v778_2 SET status='EXPIRED' WHERE data_mode='TEST' AND business_date<v_date AND status='DUE';
 UPDATE public.rr_attendance_reminder_state_v778_2 r SET status='RESOLVED',resolved_at=p_now
 WHERE r.data_mode='TEST' AND r.business_date=v_date AND r.status='DUE' AND (
  EXISTS(SELECT 1 FROM public.rr_regular_attendance_sessions_v778_2 s WHERE s.worker_id=r.worker_id AND s.business_date=r.business_date AND s.data_mode='TEST' AND (r.reminder_type='CHECKIN_PENDING' OR s.checkout_at IS NOT NULL))
  OR EXISTS(SELECT 1 FROM public.rr_attendance_day_v778 a WHERE a.worker_id=r.worker_id AND a.attendance_date=r.business_date AND a.data_mode='TEST' AND (r.reminder_type='CHECKIN_PENDING' AND a.check_in_at IS NOT NULL OR r.reminder_type='CHECKOUT_PENDING' AND a.check_out_at IS NOT NULL)));
 INSERT INTO public.rr_attendance_reminder_state_v778_2(worker_id,business_date,reminder_type,first_due_at,next_due_at,repeat_minutes,status,data_mode)
 SELECT DISTINCT ON(ap.worker_id) ap.worker_id,v_date,'CHECKIN_PENDING',
  ((v_date+s.duty_start)-make_interval(mins=>ap.checkin_alert_before_minutes)) AT TIME ZONE 'Asia/Kolkata',
  ((v_date+s.duty_start)-make_interval(mins=>ap.checkin_alert_before_minutes)) AT TIME ZONE 'Asia/Kolkata',ap.reminder_repeat_minutes,'DUE','TEST'
 FROM public.rr_worker_attendance_policy_v778_1 ap
 JOIN public.rr_worker_payroll_profile_v777_2 p ON public.rr_canonical_worker_id_v264(p.worker_id)=ap.worker_id AND p.data_mode='TEST' AND p.status='ACTIVE' AND p.worker_category='SALARIED'
 JOIN public.rr_shift_master_v777_2 s ON s.shift_id=p.shift_id AND s.is_active
 JOIN public.rr_worker_directory_compat_v264 w ON w.worker_id=ap.worker_id AND w.is_active
 WHERE ap.data_mode='TEST' AND ap.status='ACTIVE' AND ap.attendance_type='FACTORY_GEOFENCE'
 AND v_date BETWEEN ap.effective_from AND coalesce(ap.effective_to,'infinity'::date)
 AND v_date BETWEEN p.effective_from AND coalesce(p.effective_to,'infinity'::date)
 AND extract(isodow FROM v_date)<>p.weekly_holiday_isodow
 AND NOT EXISTS(SELECT 1 FROM public.rr_holiday_calendar_v777_2 h WHERE h.data_mode='TEST' AND h.holiday_date=v_date AND h.is_active AND h.is_paid_holiday)
 AND NOT EXISTS(SELECT 1 FROM public.rr_worker_leave_requests_v778_2 l WHERE l.worker_id=ap.worker_id AND l.data_mode='TEST' AND l.status='APPROVED' AND v_date BETWEEN l.leave_from AND l.leave_to)
 AND NOT EXISTS(SELECT 1 FROM public.rr_regular_attendance_sessions_v778_2 x WHERE x.worker_id=ap.worker_id AND x.business_date=v_date AND x.data_mode='TEST')
 AND NOT EXISTS(SELECT 1 FROM public.rr_attendance_day_v778 x WHERE x.worker_id=ap.worker_id AND x.attendance_date=v_date AND x.data_mode='TEST' AND (x.check_in_at IS NOT NULL OR x.status IN('LEAVE_PAID','LEAVE_UNPAID','HOLIDAY','WEEKLY_OFF')))
 AND p_now>=(((v_date+s.duty_start)-make_interval(mins=>ap.checkin_alert_before_minutes)) AT TIME ZONE 'Asia/Kolkata')
 ORDER BY ap.worker_id,p.effective_from DESC,ap.effective_from DESC
 ON CONFLICT(worker_id,business_date,reminder_type,data_mode) DO NOTHING;
 INSERT INTO public.rr_attendance_reminder_state_v778_2(worker_id,business_date,reminder_type,first_due_at,next_due_at,repeat_minutes,status,data_mode)
 SELECT DISTINCT ON(x.worker_id) x.worker_id,v_date,'CHECKOUT_PENDING',
 ((v_date+s.duty_end)+make_interval(mins=>ap.checkout_alert_after_minutes)) AT TIME ZONE 'Asia/Kolkata',
 ((v_date+s.duty_end)+make_interval(mins=>ap.checkout_alert_after_minutes)) AT TIME ZONE 'Asia/Kolkata',ap.reminder_repeat_minutes,'DUE','TEST'
 FROM public.rr_regular_attendance_sessions_v778_2 x
 JOIN public.rr_worker_attendance_policy_v778_1 ap ON ap.worker_id=x.worker_id AND ap.data_mode='TEST' AND ap.status='ACTIVE'
 JOIN public.rr_worker_payroll_profile_v777_2 p ON public.rr_canonical_worker_id_v264(p.worker_id)=x.worker_id AND p.data_mode='TEST' AND p.worker_category='SALARIED' AND p.status='ACTIVE'
 JOIN public.rr_shift_master_v777_2 s ON s.shift_id=p.shift_id
 WHERE x.data_mode='TEST' AND x.business_date=v_date AND x.checkout_at IS NULL
 AND v_date BETWEEN ap.effective_from AND coalesce(ap.effective_to,'infinity'::date)
 AND v_date BETWEEN p.effective_from AND coalesce(p.effective_to,'infinity'::date)
 AND p_now>=(((v_date+s.duty_end)+make_interval(mins=>ap.checkout_alert_after_minutes)) AT TIME ZONE 'Asia/Kolkata')
 ORDER BY x.worker_id,p.effective_from DESC,ap.effective_from DESC
 ON CONFLICT(worker_id,business_date,reminder_type,data_mode) DO NOTHING;
 FOR v_rem IN SELECT * FROM public.rr_attendance_reminder_state_v778_2 WHERE data_mode='TEST' AND business_date=v_date AND status='DUE' AND next_due_at<=p_now AND reminder_type IN('CHECKIN_PENDING','CHECKOUT_PENDING') FOR UPDATE SKIP LOCKED LOOP
  v_url:='https://redzed-test65-git-test71-real-chat-e2e-6adad3-skbhati1977-4414.vercel.app/test70-cb-purchase-real-chat-pilot.html?v=TEST71&rc_view=chat&rc_kind=person&rc_id='||v_rem.worker_id||'&rc_parent=ATTENDANCE&rc_status='||CASE WHEN v_rem.reminder_type='CHECKIN_PENDING' THEN 'OPEN' ELSE 'WORKING' END;
  INSERT INTO public.rr_targeted_push_outbox_v708(event_key,recipient_worker_id,title,body,route_url,payload)
  VALUES('ATTENDANCE_REMINDER_TEST71:'||v_rem.reminder_id||':'||v_rem.delivered_count,v_rem.worker_id,
  CASE WHEN v_rem.reminder_type='CHECKIN_PENDING' THEN 'Check-in reminder · 10:00 AM' ELSE 'Checkout pending · 8:00 PM' END,
  CASE WHEN v_rem.reminder_type='CHECKIN_PENDING' THEN 'सुबह 10 बजे check-in करें। Attendance card खोलें।' ELSE 'रात 8 बजे की shift पूरी है। Checkout बाकी है—Attendance card खोलें।' END,
  v_url,jsonb_build_object('source','ATTENDANCE_REMINDER_TEST71','reminder_id',v_rem.reminder_id,'worker_id',v_rem.worker_id,'business_date',v_date,'reminder_type',v_rem.reminder_type))
  ON CONFLICT(event_key,recipient_worker_id) DO NOTHING;
  GET DIAGNOSTICS c=ROW_COUNT;n:=n+c;
  UPDATE public.rr_attendance_reminder_state_v778_2 SET delivered_count=delivered_count+c,last_delivered_at=CASE WHEN c>0 THEN p_now ELSE last_delivered_at END,next_due_at=p_now+make_interval(mins=>greatest(repeat_minutes,1)) WHERE reminder_id=v_rem.reminder_id;
 END LOOP;
 RETURN jsonb_build_object('ok',true,'queued',n,'business_date',v_date);
END $$;
REVOKE ALL ON FUNCTION public.rr_attendance_alert_tick_test71(timestamptz) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rr_attendance_alert_tick_test71(timestamptz) TO service_role;
SELECT cron.schedule('test71-salaried-attendance-alerts','* * * * *','SELECT public.rr_attendance_alert_tick_test71();');

CREATE OR REPLACE FUNCTION public.rr_paid_salaried_profile_rules_test71() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NEW.data_mode='TEST' AND NEW.worker_category='SALARIED' AND NEW.status='ACTIVE' THEN
 NEW.weekly_holiday_isodow:=1;
 UPDATE public.rr_shift_master_v777_2 SET duty_start='10:00',duty_end='20:00',lunch_end=lunch_start+interval '30 minutes',lunch_is_paid=true,updated_at=now()
 WHERE shift_id=NEW.shift_id AND (duty_start<>time '10:00' OR duty_end<>time '20:00' OR NOT lunch_is_paid OR lunch_end-lunch_start<>interval '30 minutes');
 END IF; RETURN NEW;
END $$;
CREATE OR REPLACE FUNCTION public.rr_generate_attendance_reminders_v778_2(p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_now timestamptz:=now();
  v_local timestamp:=v_now at time zone 'Asia/Kolkata';
  v_date date:=v_local::date;
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_count integer:=0;
begin
  if v_mode='TEST' then return public.rr_attendance_alert_tick_test71(); end if;
  insert into public.rr_attendance_reminder_state_v778_2(
    worker_id,business_date,reminder_type,
    first_due_at,next_due_at,repeat_minutes,status,data_mode
  )
  select
    p.worker_id,v_date,'CHECKIN_PENDING',
    (v_date+time '10:10') at time zone 'Asia/Kolkata',
    (v_date+time '10:10') at time zone 'Asia/Kolkata',
    p.reminder_repeat_minutes,'DUE',v_mode
  from public.rr_worker_attendance_policy_v778_1 p
  join public.rr_worker_payroll_profile_v777_2 pay
    on pay.worker_id=p.worker_id
  where p.status='ACTIVE'
    and p.data_mode=v_mode
    and pay.status='ACTIVE'
    and pay.data_mode=v_mode
    and upper(pay.worker_category)='SALARIED'
    and p.attendance_type='FACTORY_GEOFENCE'
    and v_local::time>=time '10:10'
    and not exists(
      select 1
      from public.rr_regular_attendance_sessions_v778_2 s
      where s.worker_id=p.worker_id
        and s.business_date=v_date
        and s.data_mode=v_mode
    )
    and not exists(
      select 1
      from public.rr_worker_leave_requests_v778_2 l
      where l.worker_id=p.worker_id
        and l.status='APPROVED'
        and v_date between l.leave_from and l.leave_to
        and l.data_mode=v_mode
    )
  on conflict(worker_id,business_date,reminder_type,data_mode) do nothing;

  get diagnostics v_count=row_count;

  insert into public.rr_attendance_reminder_state_v778_2(
    worker_id,business_date,reminder_type,
    first_due_at,next_due_at,repeat_minutes,status,data_mode
  )
  select
    s.worker_id,v_date,'CHECKOUT_PENDING',
    (v_date+time '20:10') at time zone 'Asia/Kolkata',
    (v_date+time '20:10') at time zone 'Asia/Kolkata',
    p.reminder_repeat_minutes,'DUE',v_mode
  from public.rr_regular_attendance_sessions_v778_2 s
  join public.rr_worker_attendance_policy_v778_1 p
    on p.worker_id=s.worker_id
   and p.status='ACTIVE'
   and p.data_mode=s.data_mode
  where s.business_date=v_date
    and s.data_mode=v_mode
    and s.checkout_at is null
    and v_local::time>=time '20:10'
  on conflict(worker_id,business_date,reminder_type,data_mode) do nothing;

  return jsonb_build_object(
    'ok',true,
    'business_date',v_date,
    'reminders_ready',true,
    'delivery_note',
      'Frontend/push worker must deliver DUE reminders every repeat_minutes.'
  );
end $function$;