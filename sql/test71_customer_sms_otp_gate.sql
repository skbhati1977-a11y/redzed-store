-- TEST71: verified SMS ownership before Super Admin approval. No numeric test OTP or client-side bypass.
ALTER TABLE rr_customer_auth_test71.login_approvals ADD COLUMN otp_verified_at timestamptz,ADD COLUMN otp_auth_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;
CREATE TABLE rr_customer_auth_test71.otp_challenges(id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),customer_id uuid NOT NULL REFERENCES public.rr_customers(id),share_id uuid NOT NULL REFERENCES public.rr_market_share_v9420(id),device_id_hash text NOT NULL,registered_mobile text NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),expires_at timestamptz NOT NULL DEFAULT clock_timestamp()+interval '15 minutes',consumed_at timestamptz);
ALTER TABLE rr_customer_auth_test71.otp_challenges ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON rr_customer_auth_test71.otp_challenges FROM PUBLIC,anon,authenticated;
CREATE INDEX otp_challenge_binding_idx ON rr_customer_auth_test71.otp_challenges(customer_id,device_id_hash,created_at DESC);
CREATE FUNCTION rr_customer_auth_test71.otp_owned(p_request_id uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $fn$
 SELECT EXISTS(SELECT 1 FROM rr_customer_auth_test71.login_approvals a JOIN auth.users u ON u.id=a.otp_auth_user_id JOIN public.rr_customers c ON c.id=a.customer_id AND c.is_active WHERE a.id=p_request_id AND a.otp_verified_at IS NOT NULL AND u.phone_confirmed_at IS NOT NULL AND regexp_replace(u.phone,'[^0-9]','','g')='91'||a.registered_mobile AND a.registered_mobile=right(regexp_replace(coalesce(c.mobile,''),'[^0-9]','','g'),10));
$fn$;
REVOKE ALL ON FUNCTION rr_customer_auth_test71.otp_owned(uuid) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.rr_customer_login_otp_prepare_test71(p_token text,p_customer_name text,p_mobile text,p_device_id text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE s public.rr_market_share_v9420%rowtype;c public.rr_customers%rowtype;mob text:=regexp_replace(coalesce(p_mobile,''),'[^0-9]','','g');cid uuid;
BEGIN
 SELECT * INTO s FROM public.rr_market_share_v9420 WHERE (token=p_token OR short_code=upper(trim(p_token))) AND status='ACTIVE' LIMIT 1;
 IF s.id IS NULL OR s.data_mode<>'TEST' OR public.rr_market_share_relation_v81(p_token)='DISTRIBUTOR_CUSTOMER' THEN RAISE EXCEPTION 'Collection phone authority unavailable.';END IF;
 SELECT * INTO c FROM public.rr_customers WHERE id=s.customer_id AND is_active;
 IF c.id IS NULL THEN RAISE EXCEPTION 'Registered customer unavailable.';END IF;
 IF length(mob)=12 AND left(mob,2)='91' THEN mob:=right(mob,10);END IF;
 IF length(mob)<>10 OR mob IS DISTINCT FROM right(regexp_replace(coalesce(c.mobile,''),'[^0-9]','','g'),10) THEN RAISE EXCEPTION 'Mobile does not match this customer. Use the original registered number.';END IF;
 IF length(trim(coalesce(p_device_id,''))) NOT BETWEEN 24 AND 256 THEN RAISE EXCEPTION 'Trusted device binding required.';END IF;
 IF EXISTS(SELECT 1 FROM rr_customer_auth_test71.customer_permissions WHERE customer_id=c.id AND paused) THEN RAISE EXCEPTION 'Customer access paused by Super Admin.';END IF;
 INSERT INTO rr_customer_auth_test71.otp_challenges(customer_id,share_id,device_id_hash,registered_mobile) VALUES(c.id,s.id,encode(extensions.digest(trim(p_device_id),'sha256'),'hex'),mob) RETURNING id INTO cid;
 RETURN jsonb_build_object('challenge_id',cid,'phone','+91'||mob,'customer_name',c.customer_name,'expires_in_seconds',900);
END $fn$;
REVOKE ALL ON FUNCTION public.rr_customer_login_otp_prepare_test71(text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rr_customer_login_otp_prepare_test71(text,text,text,text) TO anon,authenticated;
CREATE FUNCTION public.rr_customer_login_otp_complete_test71(p_challenge_id uuid,p_device_id text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE ch rr_customer_auth_test71.otp_challenges%rowtype;u auth.users%rowtype;c public.rr_customers%rowtype;a rr_customer_auth_test71.login_approvals%rowtype;sid uuid;j jsonb:=auth.jwt();ts numeric;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Verified SMS OTP session required.';END IF;
 SELECT * INTO ch FROM rr_customer_auth_test71.otp_challenges WHERE id=p_challenge_id AND device_id_hash=encode(extensions.digest(trim(coalesce(p_device_id,'')),'sha256'),'hex') AND consumed_at IS NULL AND expires_at>clock_timestamp() FOR UPDATE;
 IF ch.id IS NULL THEN RAISE EXCEPTION 'OTP challenge expired or device does not match.';END IF;
 SELECT * INTO u FROM auth.users WHERE id=auth.uid() AND phone_confirmed_at IS NOT NULL AND NOT is_anonymous;
 SELECT * INTO c FROM public.rr_customers WHERE id=ch.customer_id AND is_active;
 IF u.id IS NULL OR regexp_replace(coalesce(u.phone,''),'[^0-9]','','g') IS DISTINCT FROM '91'||ch.registered_mobile OR c.id IS NULL OR right(regexp_replace(coalesce(c.mobile,''),'[^0-9]','','g'),10) IS DISTINCT FROM ch.registered_mobile THEN RAISE EXCEPTION 'SMS OTP verified phone does not match the original registered number.';END IF;
 sid:=nullif(j->>'session_id','')::uuid;
 IF NOT EXISTS(SELECT 1 FROM auth.sessions se WHERE se.id=sid AND se.user_id=u.id AND (se.not_after IS NULL OR se.not_after>clock_timestamp())) THEN RAISE EXCEPTION 'Verified SMS OTP session unavailable.';END IF;
 SELECT max((v->>'timestamp')::numeric) INTO ts FROM jsonb_array_elements(coalesce(j->'amr','[]'::jsonb)) v WHERE v->>'method'='otp';
 IF ts IS NULL OR to_timestamp(ts)<ch.created_at-interval '30 seconds' OR to_timestamp(ts)<clock_timestamp()-interval '15 minutes' OR to_timestamp(ts)>clock_timestamp()+interval '30 seconds' THEN RAISE EXCEPTION 'Fresh SMS OTP verification required.';END IF;
 IF EXISTS(SELECT 1 FROM rr_customer_auth_test71.customer_permissions WHERE customer_id=c.id AND paused) THEN RAISE EXCEPTION 'Customer access paused by Super Admin.';END IF;
 INSERT INTO rr_customer_auth_test71.login_approvals(customer_id,device_id_hash,registered_mobile,requested_name,share_id,otp_verified_at,otp_auth_user_id) VALUES(c.id,ch.device_id_hash,ch.registered_mobile,c.customer_name,ch.share_id,clock_timestamp(),u.id)
 ON CONFLICT(customer_id,device_id_hash) DO UPDATE SET status=CASE WHEN login_approvals.otp_verified_at IS NULL OR login_approvals.status IN('REJECTED','REVOKED') OR login_approvals.registered_mobile<>excluded.registered_mobile THEN 'PENDING' ELSE login_approvals.status END,verified_registered_mobile=CASE WHEN login_approvals.otp_verified_at IS NULL OR login_approvals.status IN('REJECTED','REVOKED') OR login_approvals.registered_mobile<>excluded.registered_mobile THEN false ELSE login_approvals.verified_registered_mobile END,requested_name=excluded.requested_name,registered_mobile=excluded.registered_mobile,share_id=excluded.share_id,otp_verified_at=excluded.otp_verified_at,otp_auth_user_id=excluded.otp_auth_user_id,last_opened_at=clock_timestamp(),requested_at=clock_timestamp()
 RETURNING * INTO a;
 UPDATE rr_customer_auth_test71.otp_challenges SET consumed_at=clock_timestamp() WHERE id=ch.id;
 RETURN jsonb_build_object('request_id',a.id,'approval_status',a.status,'customer_name',c.customer_name,'mobile',ch.registered_mobile,'otp_verified',true);
END $fn$;
REVOKE ALL ON FUNCTION public.rr_customer_login_otp_complete_test71(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_customer_login_otp_complete_test71(uuid,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_customer_login_request_test71(p_token text, p_customer_name text, p_mobile text, p_device_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE s public.rr_market_share_v9420%rowtype; c public.rr_customers%rowtype;
 a rr_customer_auth_test71.login_approvals%rowtype;
 mobile text:=regexp_replace(coalesce(p_mobile,''),'[^0-9]','','g'); dh text;
BEGIN
 SELECT * INTO s FROM public.rr_market_share_v9420 WHERE (token=p_token OR short_code=upper(trim(p_token))) AND status='ACTIVE' ORDER BY CASE WHEN token=p_token THEN 0 ELSE 1 END LIMIT 1;
 IF s.id IS NULL THEN RAISE EXCEPTION 'Collection link unavailable.'; END IF;
 IF s.data_mode<>'TEST' OR public.rr_market_share_relation_v81(p_token)='DISTRIBUTOR_CUSTOMER' THEN RAISE EXCEPTION 'This login uses a different customer authority.'; END IF;
 SELECT * INTO c FROM public.rr_customers WHERE id=s.customer_id AND is_active;
 IF c.id IS NULL THEN RAISE EXCEPTION 'Super Admin must assign this link to a registered customer first.'; END IF;
 IF length(mobile)=12 AND left(mobile,2)='91' THEN mobile:=right(mobile,10); END IF;
 IF length(mobile)<>10 OR mobile IS DISTINCT FROM right(regexp_replace(coalesce(c.mobile,''),'[^0-9]','','g'),10) THEN
  RAISE EXCEPTION 'Mobile does not match this customer. Use the original registered number.';
 END IF;
 IF length(trim(coalesce(p_device_id,''))) NOT BETWEEN 24 AND 256 THEN RAISE EXCEPTION 'Trusted device binding required.'; END IF;
 IF nullif(trim(coalesce(p_customer_name,'')),'') IS NULL THEN RAISE EXCEPTION 'Customer name required.'; END IF;
 dh:=encode(extensions.digest(trim(p_device_id),'sha256'),'hex');
 SELECT * INTO a FROM rr_customer_auth_test71.login_approvals WHERE customer_id=c.id AND device_id_hash=dh;
 IF a.id IS NULL OR NOT rr_customer_auth_test71.otp_owned(a.id) OR a.registered_mobile<>mobile THEN
 RETURN jsonb_build_object('approval_status','OTP_REQUIRED','request_id',a.id,'customer_name',c.customer_name,'mobile',mobile,'otp_verified',false);
 END IF;
 IF a.status='PENDING' THEN UPDATE rr_customer_auth_test71.login_approvals SET last_opened_at=clock_timestamp() WHERE id=a.id;END IF;
 RETURN jsonb_build_object('approval_status',CASE WHEN EXISTS(SELECT 1 FROM rr_customer_auth_test71.customer_permissions p WHERE p.customer_id=a.customer_id AND p.paused) THEN 'PAUSED' ELSE a.status END,'request_id',a.id,'customer_name',c.customer_name,'mobile',mobile,'customer_id',c.id,'share_id',s.id);
END $function$;
CREATE OR REPLACE FUNCTION public.rr_customer_login_approval_decide_test71(p_request_id uuid, p_decision text, p_mobile_verified boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE a rr_customer_auth_test71.login_approvals%rowtype; actor uuid; decision text:=upper(trim(p_decision)); mobile text;
BEGIN
 PERFORM public.rr_chat_assert_superadmin_v9433();
 SELECT id INTO actor FROM public.rr_user_profiles WHERE auth_user_id=auth.uid() AND is_active AND upper(coalesce(access_status,'ACTIVE'))='ACTIVE' LIMIT 1;
 IF decision NOT IN('APPROVED','REJECTED','REVOKED') THEN RAISE EXCEPTION 'Invalid approval decision.'; END IF;
 SELECT * INTO a FROM rr_customer_auth_test71.login_approvals WHERE id=p_request_id FOR UPDATE;
 IF a.id IS NULL THEN RAISE EXCEPTION 'Login request unavailable.'; END IF;
 SELECT right(regexp_replace(coalesce(c.mobile,''),'[^0-9]','','g'),10) INTO mobile FROM public.rr_customers c WHERE c.id=a.customer_id AND c.is_active;
 IF decision='APPROVED' AND NOT rr_customer_auth_test71.otp_owned(a.id) THEN RAISE EXCEPTION 'Customer must verify the registered number by SMS OTP before approval.';END IF;
 IF decision='APPROVED' AND (NOT coalesce(p_mobile_verified,false) OR mobile IS DISTINCT FROM a.registered_mobile) THEN
  RAISE EXCEPTION 'Verify the original registered mobile before approving this device.';
 END IF;
 UPDATE rr_customer_auth_test71.login_approvals SET status=decision,decided_at=now(),decided_by=actor,verified_registered_mobile=(decision='APPROVED') WHERE id=a.id;
 RETURN jsonb_build_object('request_id',a.id,'approval_status',decision);
END $function$;
CREATE OR REPLACE FUNCTION public.rr_customer_session_validate_v9590(p_session_token text, p_device_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r public.rr_customer_session_v9590%rowtype; h text; dh text;
begin
 if nullif(trim(coalesce(p_session_token,'')),'') is null then raise exception 'Customer session required.'; end if;
 h:=encode(extensions.digest(trim(p_session_token),'sha256'),'hex');
 select * into r from public.rr_customer_session_v9590 where session_token_hash=h and revoked_at is null and expires_at>now() limit 1;
 if r.id is null then raise exception 'Customer session invalid or expired.'; end if;
 if r.device_id_hash is not null then
   if nullif(trim(coalesce(p_device_id,'')),'') is null then raise exception 'Trusted device binding required.'; end if;
   dh:=encode(extensions.digest(trim(p_device_id),'sha256'),'hex');
   if dh<>r.device_id_hash then raise exception 'Trusted device does not match.'; end if;
 end if;
 if r.data_mode='TEST' and exists(select 1 from rr_customer_auth_test71.customer_permissions p where p.customer_id=r.customer_id and p.paused) then raise exception 'Customer access paused by Super Admin.';end if;
 if r.data_mode='TEST' and exists(select 1 from public.rr_market_share_v9420 s where s.id=r.share_id and public.rr_market_share_relation_v81(s.token)<>'DISTRIBUTOR_CUSTOMER') then
   if not exists(select 1 from rr_customer_auth_test71.login_approvals a join public.rr_customers c on c.id=a.customer_id and c.is_active
     where a.customer_id=r.customer_id and a.device_id_hash=r.device_id_hash and a.status='APPROVED' and a.verified_registered_mobile and rr_customer_auth_test71.otp_owned(a.id)
       and a.registered_mobile=right(regexp_replace(coalesce(c.mobile,''),'[^0-9]','','g'),10)) then
     raise exception 'Super Admin approval required for this device.';
   end if;
 end if;
 update public.rr_customer_session_v9590 set last_seen_at=now() where id=r.id;
 return jsonb_build_object('valid',true,'customer_id',r.customer_id,'chat_id',r.chat_id,'share_id',r.share_id,'data_mode',r.data_mode,'expires_at',r.expires_at);
end$function$;
CREATE OR REPLACE FUNCTION public.rr_customer_permission_cards_test71()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE result jsonb;
BEGIN
 PERFORM public.rr_chat_assert_superadmin_v9433();
 SELECT coalesce(jsonb_agg(data ORDER BY customer_name),'[]'::jsonb) INTO result FROM(
 SELECT c.customer_name,jsonb_build_object('customer_id',c.id,'customer_name',c.customer_name,'registered_mobile',right(regexp_replace(coalesce(c.mobile,''),'[^0-9]','','g'),10),'discount_per_piece',coalesce(c.allowed_discount_per_piece,0),'discount_effective_from',(SELECT h.effective_from FROM public.rr_customer_discount_history_v9420 h WHERE h.customer_id=c.id ORDER BY h.effective_from DESC,h.created_at DESC LIMIT 1),'paused',coalesce(p.paused,false),'devices',coalesce((SELECT jsonb_agg(jsonb_build_object('request_id',a.id,'requested_name',a.requested_name,'requested_mobile',a.registered_mobile,'status',a.status,'otp_verified',rr_customer_auth_test71.otp_owned(a.id),'otp_verified_at',a.otp_verified_at,'requested_at',a.requested_at,'device_label',right(a.id::text,6)) ORDER BY a.requested_at DESC) FROM rr_customer_auth_test71.login_approvals a WHERE a.customer_id=c.id),'[]'::jsonb)) data
 FROM public.rr_customers c LEFT JOIN rr_customer_auth_test71.customer_permissions p ON p.customer_id=c.id
 WHERE c.is_active AND (EXISTS(SELECT 1 FROM public.rr_customer_chat_v9433 ch WHERE ch.customer_id=c.id AND ch.data_mode='TEST') OR EXISTS(SELECT 1 FROM public.rr_market_share_v9420 s WHERE s.customer_id=c.id AND s.data_mode='TEST'))
 )q;RETURN result;
END $function$;
CREATE OR REPLACE FUNCTION public.rr_customer_login_status_test71(p_request_id uuid, p_device_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE a rr_customer_auth_test71.login_approvals%rowtype;
BEGIN
 SELECT * INTO a FROM rr_customer_auth_test71.login_approvals WHERE id=p_request_id AND device_id_hash=encode(extensions.digest(trim(coalesce(p_device_id,'')),'sha256'),'hex');
 IF a.id IS NULL THEN RAISE EXCEPTION 'Login request unavailable for this device.'; END IF;
 RETURN jsonb_build_object('approval_status',CASE WHEN NOT rr_customer_auth_test71.otp_owned(a.id) THEN 'OTP_REQUIRED' WHEN EXISTS(SELECT 1 FROM rr_customer_auth_test71.customer_permissions p WHERE p.customer_id=a.customer_id AND p.paused) THEN 'PAUSED' ELSE a.status END,'request_id',a.id);
END $function$;
CREATE OR REPLACE FUNCTION rr_customer_auth_test71.notify_pending_login(p_request_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE a rr_customer_auth_test71.login_approvals%rowtype;cname text;r record;route text;event text;n integer:=0;
BEGIN
 SELECT * INTO a FROM rr_customer_auth_test71.login_approvals WHERE id=p_request_id FOR UPDATE;
 IF a.id IS NULL OR NOT rr_customer_auth_test71.otp_owned(a.id) OR a.status<>'PENDING' OR a.last_push_at>clock_timestamp()-interval '5 seconds' THEN RETURN 0;END IF;
 SELECT customer_name INTO cname FROM public.rr_customers WHERE id=a.customer_id AND is_active;
 IF cname IS NULL OR EXISTS(SELECT 1 FROM rr_customer_auth_test71.customer_permissions p WHERE p.customer_id=a.customer_id AND p.paused) THEN RETURN 0;END IF;
 event:='CUSTOMER_LOGIN_APPROVAL:'||a.id::text||':'||gen_random_uuid()::text;
 FOR r IN SELECT DISTINCT coalesce(public.rr_push_worker_id_v712(p.id),p.auth_user_id) worker_id,p.auth_user_id
 FROM public.rr_user_profiles p WHERE p.is_active AND upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE' AND upper(p.role_code) IN('SUPER_ADMIN','OWNER') AND p.auth_user_id IS NOT NULL LOOP
  SELECT s.route_url INTO route FROM public.rr_web_push_subscriptions_v61 s WHERE s.enabled AND s.worker_id=r.worker_id AND s.route_url LIKE 'https://%' ORDER BY s.updated_at DESC LIMIT 1;
  route:=CASE WHEN route IS NOT NULL THEN regexp_replace(regexp_replace(route,'[?#].*$',''),'[^/]*$','') ELSE '' END||'test70-cb-purchase-real-chat-pilot.html?rc_view=chat&rc_kind=group&rc_id=ADMIN&rc_parent=ADMIN&rc_status=OPEN&rc_login_request='||a.id::text||'&source=customer_login_approval&v=TEST71';
  INSERT INTO public.rr_targeted_push_outbox_v708(event_key,recipient_worker_id,title,body,route_url,payload)
  VALUES(event,r.worker_id,'Customer login approval',cname||' · '||a.registered_mobile||' — SMS OTP verified · login approval बाकी है',route,jsonb_build_object('source','CUSTOMER_LOGIN_APPROVAL_TEST71','login_request_id',a.id,'department_code','ADMIN','chat_status','OPEN'));
  n:=n+1;
 END LOOP;
 IF n>0 THEN UPDATE rr_customer_auth_test71.login_approvals SET last_push_at=clock_timestamp() WHERE id=a.id;END IF;
 RETURN n;
END $function$;
CREATE OR REPLACE FUNCTION public.rr_customer_login_push_pending_test71(p_request_id uuid, p_recipient_worker_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
SELECT EXISTS(SELECT 1 FROM rr_customer_auth_test71.login_approvals a WHERE a.id=p_request_id AND a.status='PENDING' AND rr_customer_auth_test71.otp_owned(a.id) AND NOT EXISTS(SELECT 1 FROM rr_customer_auth_test71.customer_permissions cp WHERE cp.customer_id=a.customer_id AND cp.paused)) AND EXISTS(SELECT 1 FROM public.rr_user_profiles p WHERE p.is_active AND upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE' AND upper(p.role_code) IN('SUPER_ADMIN','OWNER') AND coalesce(public.rr_push_worker_id_v712(p.id),p.auth_user_id)=p_recipient_worker_id);
$function$;
