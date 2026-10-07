-- Only server SMS verify success can complete a phone ownership challenge.
DROP FUNCTION public.rr_customer_login_otp_complete_test71(uuid,text);
ALTER TABLE rr_customer_auth_test71.otp_challenges ADD COLUMN verification_attempts integer NOT NULL DEFAULT 0;
CREATE FUNCTION public.rr_customer_login_otp_challenge_service_test71(p_challenge_id uuid,p_device_id text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE ch rr_customer_auth_test71.otp_challenges%rowtype;
BEGIN
 IF auth.role()<>'service_role' THEN RAISE EXCEPTION 'SMS verification service required.';END IF;
 UPDATE rr_customer_auth_test71.otp_challenges SET verification_attempts=verification_attempts+1 WHERE id=p_challenge_id AND device_id_hash=encode(extensions.digest(trim(coalesce(p_device_id,'')),'sha256'),'hex') AND consumed_at IS NULL AND expires_at>clock_timestamp() AND verification_attempts<5 RETURNING * INTO ch;
 IF ch.id IS NULL THEN RAISE EXCEPTION 'OTP challenge expired, exhausted or device does not match.';END IF;
 RETURN jsonb_build_object('phone','+91'||ch.registered_mobile);
END $fn$;
REVOKE ALL ON FUNCTION public.rr_customer_login_otp_challenge_service_test71(uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rr_customer_login_otp_challenge_service_test71(uuid,text) TO service_role;
CREATE FUNCTION public.rr_customer_login_otp_complete_service_test71(p_challenge_id uuid,p_device_id text,p_auth_user_id uuid,p_auth_session_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE ch rr_customer_auth_test71.otp_challenges%rowtype;u auth.users%rowtype;c public.rr_customers%rowtype;a rr_customer_auth_test71.login_approvals%rowtype;sid uuid:=p_auth_session_id;
BEGIN
 IF auth.role()<>'service_role' THEN RAISE EXCEPTION 'SMS verification service required.';END IF;
 SELECT * INTO ch FROM rr_customer_auth_test71.otp_challenges WHERE id=p_challenge_id AND device_id_hash=encode(extensions.digest(trim(coalesce(p_device_id,'')),'sha256'),'hex') AND consumed_at IS NULL AND expires_at>clock_timestamp() FOR UPDATE;
 IF ch.id IS NULL THEN RAISE EXCEPTION 'OTP challenge expired or device does not match.';END IF;
 SELECT * INTO u FROM auth.users WHERE id=p_auth_user_id AND phone_confirmed_at IS NOT NULL AND NOT is_anonymous;
 SELECT * INTO c FROM public.rr_customers WHERE id=ch.customer_id AND is_active;
 IF u.id IS NULL OR regexp_replace(coalesce(u.phone,''),'[^0-9]','','g') IS DISTINCT FROM '91'||ch.registered_mobile OR c.id IS NULL OR right(regexp_replace(coalesce(c.mobile,''),'[^0-9]','','g'),10) IS DISTINCT FROM ch.registered_mobile THEN RAISE EXCEPTION 'SMS OTP verified phone does not match the original registered number.';END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.sessions se WHERE se.id=sid AND se.user_id=u.id AND se.created_at>=ch.created_at-interval '30 seconds' AND (se.not_after IS NULL OR se.not_after>clock_timestamp())) THEN RAISE EXCEPTION 'Verified SMS OTP session unavailable.';END IF;
 IF EXISTS(SELECT 1 FROM rr_customer_auth_test71.customer_permissions WHERE customer_id=c.id AND paused) THEN RAISE EXCEPTION 'Customer access paused by Super Admin.';END IF;
 INSERT INTO rr_customer_auth_test71.login_approvals(customer_id,device_id_hash,registered_mobile,requested_name,share_id,otp_verified_at,otp_auth_user_id) VALUES(c.id,ch.device_id_hash,ch.registered_mobile,c.customer_name,ch.share_id,clock_timestamp(),u.id)
 ON CONFLICT(customer_id,device_id_hash) DO UPDATE SET status=CASE WHEN login_approvals.otp_verified_at IS NULL OR login_approvals.status IN('REJECTED','REVOKED') OR login_approvals.registered_mobile<>excluded.registered_mobile THEN 'PENDING' ELSE login_approvals.status END,verified_registered_mobile=CASE WHEN login_approvals.otp_verified_at IS NULL OR login_approvals.status IN('REJECTED','REVOKED') OR login_approvals.registered_mobile<>excluded.registered_mobile THEN false ELSE login_approvals.verified_registered_mobile END,requested_name=excluded.requested_name,registered_mobile=excluded.registered_mobile,share_id=excluded.share_id,otp_verified_at=excluded.otp_verified_at,otp_auth_user_id=excluded.otp_auth_user_id,last_opened_at=clock_timestamp(),requested_at=clock_timestamp()
 RETURNING * INTO a;
 UPDATE rr_customer_auth_test71.otp_challenges SET consumed_at=clock_timestamp() WHERE id=ch.id;
 RETURN jsonb_build_object('request_id',a.id,'approval_status',a.status,'customer_name',c.customer_name,'mobile',ch.registered_mobile,'otp_verified',true);
END $fn$;
REVOKE ALL ON FUNCTION public.rr_customer_login_otp_complete_service_test71(uuid,text,uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rr_customer_login_otp_complete_service_test71(uuid,text,uuid,uuid) TO service_role;
