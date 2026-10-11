CREATE OR REPLACE FUNCTION public.rr_attendance_push_pending_test71(p_reminder_id uuid,p_recipient_worker_id uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
SELECT EXISTS(
 SELECT 1 FROM public.rr_attendance_reminder_state_v778_2 r
 JOIN public.rr_worker_directory_compat_v264 w ON w.worker_id=r.worker_id AND w.is_active AND upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE'
 WHERE r.reminder_id=p_reminder_id AND r.worker_id=p_recipient_worker_id AND r.data_mode='TEST' AND r.status='DUE'
 AND r.business_date=(now() AT TIME ZONE 'Asia/Kolkata')::date AND r.first_due_at<=now()
 AND EXISTS(SELECT 1 FROM public.rr_worker_payroll_profile_v777_2 p WHERE public.rr_canonical_worker_id_v264(p.worker_id)=r.worker_id AND p.data_mode='TEST' AND p.worker_category='SALARIED' AND p.status='ACTIVE' AND r.business_date BETWEEN p.effective_from AND coalesce(p.effective_to,'infinity'::date))
 AND (
  (r.reminder_type='CHECKIN_PENDING'
   AND NOT EXISTS(SELECT 1 FROM public.rr_regular_attendance_sessions_v778_2 s WHERE s.worker_id=r.worker_id AND s.business_date=r.business_date AND s.data_mode='TEST')
   AND NOT EXISTS(SELECT 1 FROM public.rr_attendance_day_v778 a WHERE a.worker_id=r.worker_id AND a.attendance_date=r.business_date AND a.data_mode='TEST' AND (a.check_in_at IS NOT NULL OR a.status IN ('LEAVE_PAID','LEAVE_UNPAID','HOLIDAY','WEEKLY_OFF')))
   AND NOT EXISTS(SELECT 1 FROM public.rr_holiday_calendar_v777_2 h WHERE h.holiday_date=r.business_date AND h.data_mode='TEST' AND h.is_active AND h.is_paid_holiday)
   AND NOT EXISTS(SELECT 1 FROM public.rr_worker_payroll_profile_v777_2 p WHERE public.rr_canonical_worker_id_v264(p.worker_id)=r.worker_id AND p.data_mode='TEST' AND p.status='ACTIVE' AND extract(isodow FROM r.business_date)=p.weekly_holiday_isodow)
   AND NOT EXISTS(SELECT 1 FROM public.rr_worker_leave_requests_v778_2 l WHERE l.worker_id=r.worker_id AND l.data_mode='TEST' AND l.status='APPROVED' AND r.business_date BETWEEN l.leave_from AND l.leave_to))
  OR (r.reminder_type='CHECKOUT_PENDING' AND EXISTS(SELECT 1 FROM public.rr_regular_attendance_sessions_v778_2 s WHERE s.worker_id=r.worker_id AND s.business_date=r.business_date AND s.data_mode='TEST' AND s.checkout_at IS NULL)
   AND NOT EXISTS(SELECT 1 FROM public.rr_attendance_day_v778 a WHERE a.worker_id=r.worker_id AND a.attendance_date=r.business_date AND a.data_mode='TEST' AND a.check_out_at IS NOT NULL))
 )
);
$$;
REVOKE ALL ON FUNCTION public.rr_attendance_push_pending_test71(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rr_attendance_push_pending_test71(uuid,uuid) TO service_role;