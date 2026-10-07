-- TEST71 only. Personal WhatsApp evidence is checked by Super Admin, never by the client.
CREATE TABLE rr_customer_auth_test71.whatsapp_challenges (
 request_id uuid PRIMARY KEY REFERENCES rr_customer_auth_test71.login_approvals(id),
 code text NOT NULL, requested_at timestamptz NOT NULL,
 expires_at timestamptz NOT NULL, consumed_at timestamptz
);
CREATE TABLE rr_customer_auth_test71.whatsapp_verifications (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
 request_id uuid NOT NULL REFERENCES rr_customer_auth_test71.login_approvals(id),
 requested_at timestamptz NOT NULL, registered_mobile text NOT NULL,
 observed_sender_mobile text NOT NULL, verified_at timestamptz NOT NULL,
 verified_by uuid NOT NULL REFERENCES public.rr_user_profiles(id),
 method text NOT NULL DEFAULT 'WHATSAPP_MANUAL' CHECK(method='WHATSAPP_MANUAL')
);
ALTER TABLE rr_customer_auth_test71.whatsapp_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE rr_customer_auth_test71.whatsapp_verifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON rr_customer_auth_test71.whatsapp_challenges,rr_customer_auth_test71.whatsapp_verifications FROM PUBLIC,anon,authenticated;
CREATE FUNCTION rr_customer_auth_test71.whatsapp_pending(p_id uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM rr_customer_auth_test71.whatsapp_challenges w JOIN rr_customer_auth_test71.login_approvals a ON a.id=w.request_id JOIN public.rr_customers c ON c.id=a.customer_id AND c.is_active WHERE a.id=p_id AND a.status='PENDING' AND w.requested_at=a.requested_at AND w.consumed_at IS NULL AND w.expires_at>clock_timestamp() AND a.registered_mobile=right(regexp_replace(coalesce(c.mobile,''),'[^0-9]','','g'),10));
$$;
CREATE FUNCTION rr_customer_auth_test71.number_verified(p_id uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT rr_customer_auth_test71.otp_owned(p_id) OR EXISTS(SELECT 1 FROM rr_customer_auth_test71.whatsapp_verifications v JOIN rr_customer_auth_test71.login_approvals a ON a.id=v.request_id JOIN public.rr_customers c ON c.id=a.customer_id AND c.is_active WHERE a.id=p_id AND a.status='APPROVED' AND a.verified_registered_mobile AND v.requested_at=a.requested_at AND v.verified_at=a.decided_at AND v.verified_by=a.decided_by AND v.registered_mobile=a.registered_mobile AND v.observed_sender_mobile=a.registered_mobile AND a.registered_mobile=right(regexp_replace(coalesce(c.mobile,''),'[^0-9]','','g'),10));
$$;
REVOKE ALL ON FUNCTION rr_customer_auth_test71.whatsapp_pending(uuid),rr_customer_auth_test71.number_verified(uuid) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.rr_customer_whatsapp_request_test71(p_token text,p_customer_name text,p_mobile text,p_device_id text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s public.rr_market_share_v9420%rowtype;c public.rr_customers%rowtype;a rr_customer_auth_test71.login_approvals%rowtype;w rr_customer_auth_test71.whatsapp_challenges%rowtype;mob text:=regexp_replace(coalesce(p_mobile,''),'[^0-9]','','g');dh text;destination text;owners integer;
BEGIN
 SELECT * INTO s FROM public.rr_market_share_v9420 WHERE (token=p_token OR short_code=upper(trim(p_token))) AND status='ACTIVE' ORDER BY (token=p_token) DESC LIMIT 1;
 IF s.id IS NULL OR s.data_mode<>'TEST' OR public.rr_market_share_relation_v81(p_token)='DISTRIBUTOR_CUSTOMER' THEN RAISE EXCEPTION 'WhatsApp verification is available only for TEST71 collection customers.';END IF;
 SELECT * INTO c FROM public.rr_customers WHERE id=s.customer_id AND is_active;
 IF length(mob)=12 AND left(mob,2)='91' THEN mob:=right(mob,10);END IF;
 IF c.id IS NULL OR length(mob)<>10 OR mob IS DISTINCT FROM right(regexp_replace(coalesce(c.mobile,''),'[^0-9]','','g'),10) THEN RAISE EXCEPTION 'Use the original registered customer number.';END IF;
 IF length(trim(coalesce(p_device_id,''))) NOT BETWEEN 24 AND 256 THEN RAISE EXCEPTION 'Trusted device binding required.';END IF;
 IF EXISTS(SELECT 1 FROM rr_customer_auth_test71.customer_permissions WHERE customer_id=c.id AND paused) THEN RAISE EXCEPTION 'Customer access paused by Super Admin.';END IF;
 -- User selected the existing Owner number. Fail closed if there is no unique active Owner.
 SELECT count(*),min(regexp_replace(coalesce(mobile,''),'[^0-9]','','g')) INTO owners,destination FROM public.rr_user_profiles WHERE is_active AND upper(coalesce(access_status,'ACTIVE'))='ACTIVE' AND upper(role_code)='OWNER';
 IF owners<>1 THEN RAISE EXCEPTION 'A unique Admin WhatsApp destination must be configured.';END IF;
 IF length(destination)=10 THEN destination:='91'||destination;END IF;
 IF destination !~ '^91[6-9][0-9]{9}$' THEN RAISE EXCEPTION 'Admin WhatsApp destination unavailable.';END IF;
 dh:=encode(extensions.digest(trim(p_device_id),'sha256'),'hex');
 -- Serialize creation/renewal for the same customer and device.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(c.id::text,0));
 SELECT * INTO a FROM rr_customer_auth_test71.login_approvals WHERE customer_id=c.id AND device_id_hash=dh FOR UPDATE;
 IF a.id IS NOT NULL AND rr_customer_auth_test71.number_verified(a.id) AND a.status='APPROVED' THEN RETURN public.rr_customer_login_request_test71(p_token,p_customer_name,mob,p_device_id);END IF;
 IF a.id IS NULL OR NOT rr_customer_auth_test71.whatsapp_pending(a.id) THEN
 IF (SELECT count(*) FROM rr_customer_auth_test71.whatsapp_challenges wc JOIN rr_customer_auth_test71.login_approvals ap ON ap.id=wc.request_id WHERE ap.customer_id=c.id AND wc.requested_at>clock_timestamp()-interval '15 minutes')>=10 THEN RAISE EXCEPTION 'Too many WhatsApp requests. Wait 15 minutes or contact Admin.';END IF;
 INSERT INTO rr_customer_auth_test71.login_approvals(customer_id,device_id_hash,registered_mobile,requested_name,share_id,status,requested_at,last_opened_at) VALUES(c.id,dh,mob,c.customer_name,s.id,'PENDING',clock_timestamp(),clock_timestamp())
 ON CONFLICT(customer_id,device_id_hash) DO UPDATE SET registered_mobile=excluded.registered_mobile,requested_name=excluded.requested_name,share_id=excluded.share_id,status='PENDING',requested_at=excluded.requested_at,last_opened_at=excluded.last_opened_at,verified_registered_mobile=false,decided_at=NULL,decided_by=NULL,otp_verified_at=NULL,otp_auth_user_id=NULL RETURNING * INTO a;
 INSERT INTO rr_customer_auth_test71.whatsapp_challenges(request_id,code,requested_at,expires_at) VALUES(a.id,upper(encode(extensions.gen_random_bytes(8),'hex')),a.requested_at,clock_timestamp()+interval '15 minutes') ON CONFLICT(request_id) DO UPDATE SET code=excluded.code,requested_at=excluded.requested_at,expires_at=excluded.expires_at,consumed_at=NULL;
 END IF;
 SELECT * INTO w FROM rr_customer_auth_test71.whatsapp_challenges WHERE request_id=a.id;
 PERFORM rr_customer_auth_test71.notify_pending_login(a.id);
 RETURN jsonb_build_object('request_id',a.id,'approval_status','PENDING','customer_name',c.customer_name,'mobile',mob,'verification_method','WHATSAPP_MANUAL','whatsapp_code',w.code,'whatsapp_destination',destination,'whatsapp_expires_at',w.expires_at);
END $$;
CREATE FUNCTION public.rr_customer_whatsapp_approve_test71(p_request_id uuid,p_observed_sender_mobile text,p_received_code text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a rr_customer_auth_test71.login_approvals%rowtype;w rr_customer_auth_test71.whatsapp_challenges%rowtype;actor uuid;mob text:=regexp_replace(coalesce(p_observed_sender_mobile,''),'[^0-9]','','g');current_mobile text;stamp timestamptz:=clock_timestamp();
BEGIN
 PERFORM public.rr_chat_assert_superadmin_v9433();
 SELECT id INTO actor FROM public.rr_user_profiles WHERE auth_user_id=auth.uid() AND is_active AND upper(coalesce(access_status,'ACTIVE'))='ACTIVE';
 IF actor IS NULL THEN RAISE EXCEPTION 'Active Super Admin required.';END IF;
 SELECT * INTO a FROM rr_customer_auth_test71.login_approvals WHERE id=p_request_id FOR UPDATE;
 SELECT * INTO w FROM rr_customer_auth_test71.whatsapp_challenges WHERE request_id=p_request_id FOR UPDATE;
 IF a.id IS NULL OR w.request_id IS NULL OR a.status<>'PENDING' OR w.requested_at IS DISTINCT FROM a.requested_at OR w.consumed_at IS NOT NULL OR w.expires_at<=stamp OR w.code IS DISTINCT FROM upper(trim(p_received_code)) THEN RAISE EXCEPTION 'WhatsApp request code is invalid, expired or already used.';END IF;
 IF length(mob)=12 AND left(mob,2)='91' THEN mob:=right(mob,10);END IF;
 SELECT right(regexp_replace(coalesce(mobile,''),'[^0-9]','','g'),10) INTO current_mobile FROM public.rr_customers WHERE id=a.customer_id AND is_active;
 IF length(mob)<>10 OR mob IS DISTINCT FROM a.registered_mobile OR mob IS DISTINCT FROM current_mobile THEN RAISE EXCEPTION 'Actual WhatsApp sender must match the original registered number.';END IF;
 IF EXISTS(SELECT 1 FROM rr_customer_auth_test71.customer_permissions WHERE customer_id=a.customer_id AND paused) THEN RAISE EXCEPTION 'Customer access paused by Super Admin.';END IF;
 INSERT INTO rr_customer_auth_test71.whatsapp_verifications(request_id,requested_at,registered_mobile,observed_sender_mobile,verified_at,verified_by) VALUES(a.id,a.requested_at,a.registered_mobile,mob,stamp,actor);
 UPDATE rr_customer_auth_test71.whatsapp_challenges SET consumed_at=stamp WHERE request_id=a.id;
 UPDATE rr_customer_auth_test71.login_approvals SET status='APPROVED',verified_registered_mobile=true,decided_at=stamp,decided_by=actor WHERE id=a.id;
 RETURN jsonb_build_object('request_id',a.id,'approval_status','APPROVED','verification_method','WHATSAPP_MANUAL');
END $$;
REVOKE ALL ON FUNCTION public.rr_customer_whatsapp_request_test71(text,text,text,text),public.rr_customer_whatsapp_approve_test71(uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rr_customer_whatsapp_request_test71(text,text,text,text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rr_customer_whatsapp_approve_test71(uuid,text,text) TO authenticated;
