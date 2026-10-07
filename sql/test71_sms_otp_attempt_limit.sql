GRANT EXECUTE ON FUNCTION public.rr_customer_login_otp_prepare_test71(text,text,text,text) TO service_role;
CREATE OR REPLACE FUNCTION public.rr_customer_login_otp_challenge_service_test71(p_challenge_id uuid,p_device_id text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE ch rr_customer_auth_test71.otp_challenges%rowtype;
BEGIN
 IF auth.role()<>'service_role' THEN RAISE EXCEPTION 'SMS verification service required.';END IF;
 SELECT * INTO ch FROM rr_customer_auth_test71.otp_challenges WHERE id=p_challenge_id AND device_id_hash=encode(extensions.digest(trim(coalesce(p_device_id,'')),'sha256'),'hex') AND consumed_at IS NULL AND expires_at>clock_timestamp() FOR UPDATE;
 IF ch.id IS NULL THEN RAISE EXCEPTION 'OTP challenge expired, exhausted or device does not match.';END IF;
 PERFORM pg_advisory_xact_lock(hashtext('RR_TEST71_SMS_ATTEMPTS:'||ch.customer_id::text));
 IF (SELECT coalesce(sum(verification_attempts),0) FROM rr_customer_auth_test71.otp_challenges WHERE customer_id=ch.customer_id AND created_at>clock_timestamp()-interval '15 minutes')>=5 THEN RAISE EXCEPTION 'OTP attempt limit reached. Wait 15 minutes.';END IF;
 UPDATE rr_customer_auth_test71.otp_challenges SET verification_attempts=verification_attempts+1 WHERE id=ch.id;
 RETURN jsonb_build_object('phone','+91'||ch.registered_mobile);
END $fn$;
REVOKE ALL ON FUNCTION public.rr_customer_login_otp_challenge_service_test71(uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rr_customer_login_otp_challenge_service_test71(uuid,text) TO service_role;
