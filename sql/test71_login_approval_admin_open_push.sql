ALTER TABLE rr_customer_auth_test71.login_approvals ADD COLUMN IF NOT EXISTS last_opened_at timestamptz NOT NULL DEFAULT now(),ADD COLUMN IF NOT EXISTS last_push_at timestamptz;
CREATE OR REPLACE FUNCTION rr_customer_auth_test71.notify_pending_login(p_request_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE a rr_customer_auth_test71.login_approvals%rowtype;cname text;r record;route text;event text;n integer:=0;
BEGIN
 SELECT * INTO a FROM rr_customer_auth_test71.login_approvals WHERE id=p_request_id FOR UPDATE;
 IF a.id IS NULL OR a.status<>'PENDING' OR a.last_push_at>clock_timestamp()-interval '5 seconds' THEN RETURN 0;END IF;
 SELECT customer_name INTO cname FROM public.rr_customers WHERE id=a.customer_id AND is_active;
 IF cname IS NULL THEN RETURN 0;END IF;
 event:='CUSTOMER_LOGIN_APPROVAL:'||a.id::text||':'||gen_random_uuid()::text;
 FOR r IN SELECT DISTINCT coalesce(public.rr_push_worker_id_v712(p.id),p.auth_user_id) worker_id,p.auth_user_id
 FROM public.rr_user_profiles p WHERE p.is_active AND upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE' AND upper(p.role_code) IN('SUPER_ADMIN','OWNER') AND p.auth_user_id IS NOT NULL LOOP
  SELECT s.route_url INTO route FROM public.rr_web_push_subscriptions_v61 s WHERE s.enabled AND s.worker_id=r.worker_id AND s.route_url LIKE 'https://%' ORDER BY s.updated_at DESC LIMIT 1;
  route:=CASE WHEN route IS NOT NULL THEN regexp_replace(regexp_replace(route,'[?#].*$',''),'[^/]*$','') ELSE '' END||'test70-cb-purchase-real-chat-pilot.html?rc_view=chat&rc_kind=group&rc_id=ADMIN&rc_parent=ADMIN&rc_status=OPEN&rc_login_request='||a.id::text||'&source=customer_login_approval&v=TEST71';
  INSERT INTO public.rr_targeted_push_outbox_v708(event_key,recipient_worker_id,title,body,route_url,payload)
  VALUES(event,r.worker_id,'Customer login approval',cname||' · '||a.registered_mobile||' — login approval बाकी है',route,jsonb_build_object('source','CUSTOMER_LOGIN_APPROVAL_TEST71','login_request_id',a.id,'department_code','ADMIN','chat_status','OPEN'));
  n:=n+1;
 END LOOP;
 IF n>0 THEN UPDATE rr_customer_auth_test71.login_approvals SET last_push_at=clock_timestamp() WHERE id=a.id;END IF;
 RETURN n;
END $fn$;
REVOKE ALL ON FUNCTION rr_customer_auth_test71.notify_pending_login(uuid) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION rr_customer_auth_test71.pending_login_push_trigger()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
BEGIN IF NEW.status='PENDING' THEN PERFORM rr_customer_auth_test71.notify_pending_login(NEW.id);END IF;RETURN NEW;END $fn$;
REVOKE ALL ON FUNCTION rr_customer_auth_test71.pending_login_push_trigger() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER test71_pending_login_push AFTER INSERT OR UPDATE OF last_opened_at,status ON rr_customer_auth_test71.login_approvals FOR EACH ROW EXECUTE FUNCTION rr_customer_auth_test71.pending_login_push_trigger();
CREATE OR REPLACE FUNCTION public.rr_customer_login_remind_test71(p_request_id uuid,p_device_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE a rr_customer_auth_test71.login_approvals%rowtype;
BEGIN
 SELECT * INTO a FROM rr_customer_auth_test71.login_approvals WHERE id=p_request_id AND device_id_hash=encode(extensions.digest(trim(coalesce(p_device_id,'')),'sha256'),'hex') FOR UPDATE;
 IF a.id IS NULL THEN RAISE EXCEPTION 'Login request unavailable for this device.';END IF;
 IF a.status='PENDING' THEN UPDATE rr_customer_auth_test71.login_approvals SET last_opened_at=clock_timestamp() WHERE id=a.id;END IF;
 RETURN jsonb_build_object('request_id',a.id,'approval_status',a.status);
END $fn$;
REVOKE ALL ON FUNCTION public.rr_customer_login_remind_test71(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rr_customer_login_remind_test71(uuid,text) TO anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rr_customer_login_request_test71(p_token text,p_customer_name text,p_mobile text,p_device_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
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
 INSERT INTO rr_customer_auth_test71.login_approvals(customer_id,device_id_hash,registered_mobile,requested_name,share_id)
 VALUES(c.id,dh,mobile,left(trim(p_customer_name),120),s.id)
 ON CONFLICT(customer_id,device_id_hash) DO UPDATE SET
  status=CASE WHEN login_approvals.registered_mobile<>excluded.registered_mobile THEN 'PENDING' ELSE login_approvals.status END,
  verified_registered_mobile=CASE WHEN login_approvals.registered_mobile<>excluded.registered_mobile THEN false ELSE login_approvals.verified_registered_mobile END,
  decided_at=CASE WHEN login_approvals.registered_mobile<>excluded.registered_mobile THEN null ELSE login_approvals.decided_at END,
  decided_by=CASE WHEN login_approvals.registered_mobile<>excluded.registered_mobile THEN null ELSE login_approvals.decided_by END,
  requested_at=CASE WHEN login_approvals.registered_mobile<>excluded.registered_mobile THEN now() ELSE login_approvals.requested_at END,
  last_opened_at=CASE WHEN login_approvals.status='PENDING' THEN clock_timestamp() ELSE login_approvals.last_opened_at END,
  registered_mobile=excluded.registered_mobile
 RETURNING * INTO a;
 RETURN jsonb_build_object('approval_status',a.status,'request_id',a.id,'customer_name',c.customer_name,'mobile',mobile,'customer_id',c.id,'share_id',s.id);
END $fn$;


CREATE OR REPLACE FUNCTION public.rr_customer_login_push_pending_test71(p_request_id uuid,p_recipient_worker_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $fn$
 SELECT EXISTS(SELECT 1 FROM rr_customer_auth_test71.login_approvals a WHERE a.id=p_request_id AND a.status='PENDING') AND EXISTS(SELECT 1 FROM public.rr_user_profiles p WHERE p.is_active AND upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE' AND upper(p.role_code) IN('SUPER_ADMIN','OWNER') AND coalesce(public.rr_push_worker_id_v712(p.id),p.auth_user_id)=p_recipient_worker_id);
$fn$;
REVOKE ALL ON FUNCTION public.rr_customer_login_push_pending_test71(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rr_customer_login_push_pending_test71(uuid,uuid) TO service_role;
