-- TEST71 presence verification: only explicit Admin/Super Admin run sends pushes.
-- Individual switch defaults ON for existing/future salaried workers; no automatic job.
-- No salary calculation or deduction writes.

CREATE TABLE public.rr_attendance_presence_checks_test71(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),worker_id uuid NOT NULL,business_date date NOT NULL,run_id uuid NOT NULL,
 scheduled_at timestamptz NOT NULL,deadline_at timestamptz NOT NULL,status text NOT NULL DEFAULT 'SCHEDULED' CHECK(status IN('SCHEDULED','PENDING','VERIFIED','REVIEW_REQUIRED','CANCELLED','REVIEWED')),
 requested_at timestamptz,responded_at timestamptz,review_reason text,latitude numeric,longitude numeric,accuracy_meters numeric,premise_id uuid,inside_geofence boolean,
 verified_late boolean NOT NULL DEFAULT false,reviewed_by uuid,reviewed_at timestamptz,review_note text,created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(worker_id,run_id),CHECK(deadline_at>scheduled_at));
ALTER TABLE public.rr_attendance_presence_checks_test71 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rr_attendance_presence_checks_test71 FROM anon,authenticated;
GRANT ALL ON public.rr_attendance_presence_checks_test71 TO service_role;

CREATE OR REPLACE FUNCTION public.rr_attendance_presence_list_test71(p_month date DEFAULT NULL,p_worker_id uuid DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE q jsonb;
BEGIN
 q:=public.rr_chat_attendance_queue_test71(p_month,p_worker_id);
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id',r.id,'worker_id',r.worker_id,'business_date',r.business_date,'status',CASE WHEN r.status='PENDING' AND r.deadline_at<now() THEN 'REVIEW_REQUIRED' ELSE r.status END,'scheduled_at',CASE WHEN r.status<>'SCHEDULED' THEN r.scheduled_at ELSE NULL END,'deadline_at',CASE WHEN r.status<>'SCHEDULED' THEN r.deadline_at ELSE NULL END,'responded_at',r.responded_at,'review_reason',CASE WHEN r.status='PENDING' AND r.deadline_at<now() THEN 'NO_RESPONSE' ELSE r.review_reason END,'inside_geofence',r.inside_geofence,'verified_late',r.verified_late,'review_note',r.review_note,
 'can_verify',w.linked_auth_user_id=auth.uid() AND r.status IN('PENDING','REVIEW_REQUIRED') AND r.business_date=(now() AT TIME ZONE 'Asia/Kolkata')::date,
 'can_review',coalesce((c->>'can_manage')::boolean,false) AND (r.status='REVIEW_REQUIRED' OR r.status='PENDING' AND r.deadline_at<now())) ORDER BY r.scheduled_at)
 FROM public.rr_attendance_presence_checks_test71 r
 JOIN public.rr_worker_directory_compat_v264 w ON w.worker_id=r.worker_id
 JOIN LATERAL (SELECT x c FROM jsonb_array_elements(q->'cards') x WHERE (x->>'worker_id')::uuid=r.worker_id AND (x->>'attendance_date')::date=r.business_date LIMIT 1) a ON true
 WHERE r.status<>'SCHEDULED'), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.rr_attendance_presence_list_test71(date,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_attendance_presence_list_test71(date,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.rr_attendance_presence_respond_test71(p_request_id uuid,p_latitude numeric DEFAULT NULL,p_longitude numeric DEFAULT NULL,p_accuracy_meters numeric DEFAULT NULL,p_gps_error text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.rr_attendance_presence_checks_test71%rowtype;g jsonb;pol public.rr_worker_attendance_policy_v778_1%rowtype;v_reason text;v_ok boolean;
BEGIN
 SELECT * INTO r FROM public.rr_attendance_presence_checks_test71 WHERE id=p_request_id FOR UPDATE;
 IF r.id IS NULL OR NOT EXISTS(SELECT 1 FROM public.rr_user_profiles WHERE auth_user_id=auth.uid() AND is_active AND upper(coalesce(access_status,'ACTIVE'))='ACTIVE')
 OR NOT EXISTS(SELECT 1 FROM public.rr_worker_directory_compat_v264 WHERE worker_id=r.worker_id AND linked_auth_user_id=auth.uid() AND is_active) THEN RAISE EXCEPTION 'Own active login required for live presence verification.';END IF;
 IF r.status='VERIFIED' THEN RETURN jsonb_build_object('ok',true,'duplicate',true,'status',r.status);END IF;
 IF r.status NOT IN('PENDING','REVIEW_REQUIRED') OR r.business_date<>(now() AT TIME ZONE 'Asia/Kolkata')::date THEN RAISE EXCEPTION 'No current pending presence request.';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.rr_regular_attendance_sessions_v778_2 WHERE worker_id=r.worker_id AND business_date=r.business_date AND data_mode='TEST' AND checkout_at IS NULL) THEN RAISE EXCEPTION 'Worker is no longer checked in.';END IF;
 SELECT * INTO pol FROM public.rr_current_attendance_policy_v778_2(r.worker_id,r.business_date,'TEST');
 IF p_gps_error IS NOT NULL THEN
  IF p_gps_error NOT IN('PERMISSION_DENIED','POSITION_UNAVAILABLE','TIMEOUT','GPS_UNAVAILABLE') THEN RAISE EXCEPTION 'Invalid GPS error';END IF;v_reason:=p_gps_error;
 ELSE
  IF p_latitude IS NULL OR p_latitude NOT BETWEEN -90 AND 90 OR p_longitude IS NULL OR p_longitude NOT BETWEEN -180 AND 180 OR p_accuracy_meters IS NULL OR p_accuracy_meters<0 THEN RAISE EXCEPTION 'Valid live GPS required';END IF;
  g:=public.rr_nearest_attendance_premise_v778_2(r.worker_id,p_latitude,p_longitude,r.business_date,'TEST');
  v_reason:=CASE WHEN pol.policy_id IS NULL THEN 'POLICY_MISSING' WHEN p_accuracy_meters>pol.gps_accuracy_limit_meters THEN 'LOW_ACCURACY' WHEN NOT coalesce((g->>'ok')::boolean,false) THEN 'PREMISE_UNAVAILABLE' WHEN NOT coalesce((g->>'inside_geofence')::boolean,false) THEN 'OUTSIDE_GEOFENCE' END;
 END IF;
 v_ok:=v_reason IS NULL;
 UPDATE public.rr_attendance_presence_checks_test71 SET status=CASE WHEN v_ok THEN 'VERIFIED' ELSE 'REVIEW_REQUIRED' END,responded_at=now(),review_reason=v_reason,
 latitude=p_latitude,longitude=p_longitude,accuracy_meters=p_accuracy_meters,premise_id=nullif(g->>'premise_id','')::uuid,inside_geofence=(g->>'inside_geofence')::boolean,verified_late=now()>deadline_at WHERE id=r.id;
 RETURN jsonb_build_object('ok',true,'verified',v_ok,'status',CASE WHEN v_ok THEN 'VERIFIED' ELSE 'REVIEW_REQUIRED' END,'reason',v_reason,'late',now()>r.deadline_at);
END $$;
REVOKE ALL ON FUNCTION public.rr_attendance_presence_respond_test71(uuid,numeric,numeric,numeric,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_attendance_presence_respond_test71(uuid,numeric,numeric,numeric,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.rr_attendance_presence_review_test71(p_request_id uuid,p_note text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.rr_attendance_presence_checks_test71%rowtype;items jsonb;
BEGIN
 SELECT * INTO r FROM public.rr_attendance_presence_checks_test71 WHERE id=p_request_id FOR UPDATE;
 IF r.id IS NULL THEN RAISE EXCEPTION 'Presence request not found';END IF;
 items:=public.rr_attendance_presence_list_test71(date_trunc('month',r.business_date)::date,r.worker_id);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(items) x WHERE (x->>'id')::uuid=r.id AND (x->>'can_review')::boolean) THEN RAISE EXCEPTION 'Relevant staff review permission required';END IF;
 IF length(trim(coalesce(p_note,'')))<5 THEN RAISE EXCEPTION 'Review note required';END IF;
 UPDATE public.rr_attendance_presence_checks_test71 SET status='REVIEWED',review_note=trim(p_note),reviewed_by=auth.uid(),reviewed_at=now() WHERE id=r.id;
 RETURN jsonb_build_object('ok',true,'salary_deduction_applied',false);
END $$;
REVOKE ALL ON FUNCTION public.rr_attendance_presence_review_test71(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_attendance_presence_review_test71(uuid,text) TO authenticated;


CREATE OR REPLACE FUNCTION public.rr_attendance_presence_run_test71(p_run_id uuid,p_worker_id uuid DEFAULT NULL,p_review_only boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE d date:=(now() AT TIME ZONE 'Asia/Kolkata')::date;r record;n integer:=0;v_url text;
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.rr_user_profiles WHERE auth_user_id=auth.uid() AND is_active AND upper(coalesce(access_status,'ACTIVE'))='ACTIVE' AND upper(role_code) IN('OWNER','SUPER_ADMIN','ADMIN')) THEN RAISE EXCEPTION 'Admin/Super Admin login required to run presence checks.';END IF;
 IF p_run_id IS NULL THEN RAISE EXCEPTION 'Run ID required';END IF;
 UPDATE public.rr_attendance_presence_checks_test71 c SET status='CANCELLED' WHERE c.status IN('SCHEDULED','PENDING') AND (c.business_date<d OR EXISTS(SELECT 1 FROM public.rr_regular_attendance_sessions_v778_2 x WHERE x.worker_id=c.worker_id AND x.business_date=c.business_date AND x.data_mode='TEST' AND x.checkout_at IS NOT NULL));
 UPDATE public.rr_attendance_presence_checks_test71 SET status='REVIEW_REQUIRED',review_reason='NO_RESPONSE' WHERE business_date=d AND status='PENDING' AND deadline_at<now();
 IF p_review_only THEN
 FOR r IN SELECT c.*,w.worker_name,w.department_code FROM public.rr_attendance_presence_checks_test71 c JOIN public.rr_worker_directory_compat_v264 w ON w.worker_id=c.worker_id WHERE c.status='REVIEW_REQUIRED' AND (p_worker_id IS NULL OR c.worker_id=p_worker_id) LOOP
  INSERT INTO public.rr_targeted_push_outbox_v708(event_key,recipient_worker_id,title,body,route_url,payload)
  SELECT 'PRESENCE_REVIEW_TEST71:'||r.id,w.worker_id,'Presence review · '||r.worker_name,'Presence verify नहीं हुई: '||coalesce(r.review_reason,'PENDING')||'. Staff review करें; automatic salary deduction नहीं।',
   'test70-cb-purchase-real-chat-pilot.html?v=TEST71&rc_view=chat&rc_kind=person&rc_id='||r.worker_id||'&rc_parent=ATTENDANCE&rc_status=OPEN&rc_presence='||r.id,
   jsonb_build_object('source','PRESENCE_REVIEW_TEST71','request_id',r.id,'worker_id',r.worker_id)
  FROM public.rr_worker_directory_compat_v264 w WHERE w.is_active AND upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE'
   AND (upper(w.role_code) IN('OWNER','SUPER_ADMIN','ADMIN','MANAGER') OR upper(w.role_code) IN('DEPARTMENT_HEAD','CUTTING_MASTER','LINE_MANAGER','LINE_MAN') AND upper(w.department_code)=upper(r.department_code))
  ON CONFLICT(event_key,recipient_worker_id) DO NOTHING;
  n:=n+1;
 END LOOP;
 ELSE
 FOR r IN
 INSERT INTO public.rr_attendance_presence_checks_test71(worker_id,business_date,run_id,scheduled_at,deadline_at,status,requested_at)
 SELECT DISTINCT ON(x.worker_id) x.worker_id,d,p_run_id,now(),now()+interval '10 minutes','PENDING',now()
 FROM public.rr_regular_attendance_sessions_v778_2 x
 JOIN public.rr_worker_payroll_profile_v777_2 p ON public.rr_canonical_worker_id_v264(p.worker_id)=x.worker_id AND p.data_mode='TEST' AND p.worker_category='SALARIED' AND p.status='ACTIVE'
 JOIN public.rr_worker_attendance_policy_v778_1 a ON a.worker_id=x.worker_id AND a.data_mode='TEST' AND a.status='ACTIVE'
 JOIN public.rr_worker_directory_compat_v264 w ON w.worker_id=x.worker_id AND w.is_active AND upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE'
 WHERE x.business_date=d AND x.data_mode='TEST' AND x.checkout_at IS NULL AND (p_worker_id IS NULL OR x.worker_id=p_worker_id)
 AND d BETWEEN p.effective_from AND coalesce(p.effective_to,'infinity'::date) AND d BETWEEN a.effective_from AND coalesce(a.effective_to,'infinity'::date)
 AND NOT EXISTS(SELECT 1 FROM public.rr_attendance_presence_checks_test71 c WHERE c.worker_id=x.worker_id AND c.business_date=d AND c.status='PENDING' AND c.deadline_at>=now())
 ORDER BY x.worker_id,p.effective_from DESC,a.effective_from DESC
 ON CONFLICT(worker_id,run_id) DO NOTHING RETURNING * LOOP
  v_url:='test70-cb-purchase-real-chat-pilot.html?v=TEST71&rc_view=chat&rc_kind=person&rc_id='||r.worker_id||'&rc_parent=ATTENDANCE&rc_status=WORKING&rc_presence='||r.id;
  INSERT INTO public.rr_targeted_push_outbox_v708(event_key,recipient_worker_id,title,body,route_url,payload)
  VALUES('PRESENCE_CHECK_TEST71:'||r.id,r.worker_id,'Presence verification','Admin ने presence check भेजा है। 10 मिनट में Attendance card से live GPS verify करें।',v_url,jsonb_build_object('source','PRESENCE_CHECK_TEST71','request_id',r.id,'worker_id',r.worker_id))
  ON CONFLICT(event_key,recipient_worker_id) DO NOTHING;n:=n+1;
 END LOOP;
 END IF;
 RETURN jsonb_build_object('ok',true,'requests',n,'manual_run',true);
END $$;
REVOKE ALL ON FUNCTION public.rr_attendance_presence_run_test71(uuid,uuid,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_attendance_presence_run_test71(uuid,uuid,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.rr_presence_push_pending_test71(p_request_id uuid,p_recipient_worker_id uuid,p_review boolean DEFAULT false) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM public.rr_attendance_presence_checks_test71 c JOIN public.rr_worker_directory_compat_v264 owner ON owner.worker_id=c.worker_id
 WHERE c.id=p_request_id AND (
  NOT p_review AND c.worker_id=p_recipient_worker_id AND c.status='PENDING' AND c.deadline_at>=now() AND c.business_date=(now() AT TIME ZONE 'Asia/Kolkata')::date
   AND EXISTS(SELECT 1 FROM public.rr_regular_attendance_sessions_v778_2 s WHERE s.worker_id=c.worker_id AND s.business_date=c.business_date AND s.data_mode='TEST' AND s.checkout_at IS NULL)
  OR p_review AND c.status='REVIEW_REQUIRED' AND EXISTS(SELECT 1 FROM public.rr_worker_directory_compat_v264 w WHERE w.worker_id=p_recipient_worker_id AND w.is_active AND upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE'
   AND (upper(w.role_code) IN('OWNER','SUPER_ADMIN','ADMIN','MANAGER') OR upper(w.role_code) IN('DEPARTMENT_HEAD','CUTTING_MASTER','LINE_MANAGER','LINE_MAN') AND upper(w.department_code)=upper(owner.department_code)))
 ));
$$;
REVOKE ALL ON FUNCTION public.rr_presence_push_pending_test71(uuid,uuid,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rr_presence_push_pending_test71(uuid,uuid,boolean) TO service_role;

CREATE TABLE public.rr_presence_worker_control_test71(worker_id uuid PRIMARY KEY,enabled boolean NOT NULL DEFAULT true,updated_by uuid,updated_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE public.rr_presence_worker_control_test71 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rr_presence_worker_control_test71 FROM anon,authenticated;
GRANT ALL ON public.rr_presence_worker_control_test71 TO service_role;
CREATE OR REPLACE FUNCTION public.rr_presence_worker_switch_test71(p_worker_id uuid,p_enabled boolean) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.rr_user_profiles WHERE auth_user_id=auth.uid() AND is_active AND upper(coalesce(access_status,'ACTIVE'))='ACTIVE' AND upper(role_code) IN('OWNER','SUPER_ADMIN','ADMIN')) THEN RAISE EXCEPTION 'Admin/Super Admin required';END IF;
 IF p_enabled IS NULL OR NOT EXISTS(SELECT 1 FROM public.rr_active_payroll_profile_v778_2(p_worker_id,(now() AT TIME ZONE 'Asia/Kolkata')::date,'TEST') p WHERE p.worker_category='SALARIED') THEN RAISE EXCEPTION 'Active salaried worker required';END IF;
 INSERT INTO public.rr_presence_worker_control_test71(worker_id,enabled,updated_by) VALUES(p_worker_id,p_enabled,auth.uid()) ON CONFLICT(worker_id) DO UPDATE SET enabled=excluded.enabled,updated_by=excluded.updated_by,updated_at=now();
 IF NOT p_enabled THEN UPDATE public.rr_attendance_presence_checks_test71 SET status='CANCELLED' WHERE worker_id=p_worker_id AND status IN('SCHEDULED','PENDING');END IF;
 RETURN jsonb_build_object('ok',true,'enabled',p_enabled);
END $$;
REVOKE ALL ON FUNCTION public.rr_presence_worker_switch_test71(uuid,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_presence_worker_switch_test71(uuid,boolean) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_presence_worker_controls_test71(p_month date DEFAULT NULL,p_worker_id uuid DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE q jsonb;
BEGIN
 q:=public.rr_chat_attendance_queue_test71(p_month,p_worker_id);
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('worker_id',w.worker_id,'enabled',coalesce(c.enabled,true))) FROM (SELECT DISTINCT (x->>'worker_id')::uuid worker_id FROM jsonb_array_elements(q->'cards') x) w LEFT JOIN public.rr_presence_worker_control_test71 c USING(worker_id)),'[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.rr_presence_worker_controls_test71(date,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_presence_worker_controls_test71(date,uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_attendance_presence_run_test71(p_run_id uuid, p_worker_id uuid DEFAULT NULL::uuid, p_review_only boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE d date:=(now() AT TIME ZONE 'Asia/Kolkata')::date;r record;n integer:=0;v_url text;
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.rr_user_profiles WHERE auth_user_id=auth.uid() AND is_active AND upper(coalesce(access_status,'ACTIVE'))='ACTIVE' AND upper(role_code) IN('OWNER','SUPER_ADMIN','ADMIN')) THEN RAISE EXCEPTION 'Admin/Super Admin login required to run presence checks.';END IF;
 IF p_run_id IS NULL THEN RAISE EXCEPTION 'Run ID required';END IF;
 UPDATE public.rr_attendance_presence_checks_test71 c SET status='CANCELLED' WHERE c.status IN('SCHEDULED','PENDING') AND (c.business_date<d OR EXISTS(SELECT 1 FROM public.rr_regular_attendance_sessions_v778_2 x WHERE x.worker_id=c.worker_id AND x.business_date=c.business_date AND x.data_mode='TEST' AND x.checkout_at IS NOT NULL));
 UPDATE public.rr_attendance_presence_checks_test71 SET status='REVIEW_REQUIRED',review_reason='NO_RESPONSE' WHERE business_date=d AND status='PENDING' AND deadline_at<now();
 IF p_review_only THEN
 FOR r IN SELECT c.*,w.worker_name,w.department_code FROM public.rr_attendance_presence_checks_test71 c JOIN public.rr_worker_directory_compat_v264 w ON w.worker_id=c.worker_id WHERE c.status='REVIEW_REQUIRED' AND (p_worker_id IS NULL OR c.worker_id=p_worker_id) LOOP
  INSERT INTO public.rr_targeted_push_outbox_v708(event_key,recipient_worker_id,title,body,route_url,payload)
  SELECT 'PRESENCE_REVIEW_TEST71:'||r.id,w.worker_id,'Presence review · '||r.worker_name,'Presence verify नहीं हुई: '||coalesce(r.review_reason,'PENDING')||'. Staff review करें; automatic salary deduction नहीं।',
   'test70-cb-purchase-real-chat-pilot.html?v=TEST71&rc_view=chat&rc_kind=person&rc_id='||r.worker_id||'&rc_parent=ATTENDANCE&rc_status=OPEN&rc_presence='||r.id,
   jsonb_build_object('source','PRESENCE_REVIEW_TEST71','request_id',r.id,'worker_id',r.worker_id)
  FROM public.rr_worker_directory_compat_v264 w WHERE w.is_active AND upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE'
   AND (upper(w.role_code) IN('OWNER','SUPER_ADMIN','ADMIN','MANAGER') OR upper(w.role_code) IN('DEPARTMENT_HEAD','CUTTING_MASTER','LINE_MANAGER','LINE_MAN') AND upper(w.department_code)=upper(r.department_code))
  ON CONFLICT(event_key,recipient_worker_id) DO NOTHING;
  n:=n+1;
 END LOOP;
 ELSE
 FOR r IN
 INSERT INTO public.rr_attendance_presence_checks_test71(worker_id,business_date,run_id,scheduled_at,deadline_at,status,requested_at)
 SELECT DISTINCT ON(x.worker_id) x.worker_id,d,p_run_id,now(),now()+interval '10 minutes','PENDING',now()
 FROM public.rr_regular_attendance_sessions_v778_2 x
 JOIN public.rr_worker_payroll_profile_v777_2 p ON public.rr_canonical_worker_id_v264(p.worker_id)=x.worker_id AND p.data_mode='TEST' AND p.worker_category='SALARIED' AND p.status='ACTIVE'
 JOIN public.rr_worker_attendance_policy_v778_1 a ON a.worker_id=x.worker_id AND a.data_mode='TEST' AND a.status='ACTIVE'
 JOIN public.rr_worker_directory_compat_v264 w ON w.worker_id=x.worker_id AND w.is_active AND upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE'
 WHERE x.business_date=d AND x.data_mode='TEST' AND x.checkout_at IS NULL AND (p_worker_id IS NULL OR x.worker_id=p_worker_id)
 AND d BETWEEN p.effective_from AND coalesce(p.effective_to,'infinity'::date) AND d BETWEEN a.effective_from AND coalesce(a.effective_to,'infinity'::date)
 AND NOT EXISTS(SELECT 1 FROM public.rr_presence_worker_control_test71 ctrl WHERE ctrl.worker_id=x.worker_id AND NOT ctrl.enabled)
 AND NOT EXISTS(SELECT 1 FROM public.rr_attendance_presence_checks_test71 c WHERE c.worker_id=x.worker_id AND c.business_date=d AND c.status='PENDING' AND c.deadline_at>=now())
 ORDER BY x.worker_id,p.effective_from DESC,a.effective_from DESC
 ON CONFLICT(worker_id,run_id) DO NOTHING RETURNING * LOOP
  v_url:='test70-cb-purchase-real-chat-pilot.html?v=TEST71&rc_view=chat&rc_kind=person&rc_id='||r.worker_id||'&rc_parent=ATTENDANCE&rc_status=WORKING&rc_presence='||r.id;
  INSERT INTO public.rr_targeted_push_outbox_v708(event_key,recipient_worker_id,title,body,route_url,payload)
  VALUES('PRESENCE_CHECK_TEST71:'||r.id,r.worker_id,'Presence verification','Admin ने presence check भेजा है। 10 मिनट में Attendance card से live GPS verify करें।',v_url,jsonb_build_object('source','PRESENCE_CHECK_TEST71','request_id',r.id,'worker_id',r.worker_id))
  ON CONFLICT(event_key,recipient_worker_id) DO NOTHING;n:=n+1;
 END LOOP;
 END IF;
 RETURN jsonb_build_object('ok',true,'requests',n,'manual_run',true);
END $function$;
CREATE OR REPLACE FUNCTION public.rr_presence_cancel_checkout_test71() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NEW.data_mode='TEST' AND NEW.checkout_at IS NOT NULL THEN
 UPDATE public.rr_attendance_presence_checks_test71 SET status='CANCELLED' WHERE worker_id=NEW.worker_id AND business_date=NEW.business_date AND status IN('SCHEDULED','PENDING');
 END IF;RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.rr_presence_cancel_checkout_test71() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER rr_presence_cancel_checkout_test71 AFTER UPDATE OF checkout_at ON public.rr_regular_attendance_sessions_v778_2 FOR EACH ROW EXECUTE FUNCTION public.rr_presence_cancel_checkout_test71();