BEGIN;
DO $test$
DECLARE s public.rr_market_share_v9420%rowtype;c public.rr_customers%rowtype;r jsonb;ch uuid;dev text:='test71-otp-security-rollback-device';before_count bigint;
BEGIN
 SELECT ms.* INTO s FROM public.rr_market_share_v9420 ms JOIN public.rr_customers rc ON rc.id=ms.customer_id WHERE ms.status='ACTIVE' AND ms.data_mode='TEST' AND rc.is_active AND length(regexp_replace(rc.mobile,'[^0-9]','','g'))>=10 AND public.rr_market_share_relation_v81(ms.token)<>'DISTRIBUTOR_CUSTOMER' LIMIT 1;
 IF s.id IS NULL THEN RAISE EXCEPTION 'Active test fixture required';END IF;
 SELECT * INTO c FROM public.rr_customers WHERE id=s.customer_id;
 SELECT count(*) INTO before_count FROM rr_customer_auth_test71.login_approvals;
 r:=public.rr_customer_login_request_test71(s.token,'False typed name',right(regexp_replace(c.mobile,'[^0-9]','','g'),10),dev);
 IF r->>'approval_status'<>'OTP_REQUIRED' THEN RAISE EXCEPTION 'Typed number bypass';END IF;
 IF (SELECT count(*) FROM rr_customer_auth_test71.login_approvals)<>before_count THEN RAISE EXCEPTION 'Unverified approval created';END IF;
 IF has_function_privilege('anon','public.rr_customer_login_otp_complete_service_test71(uuid,text,uuid,uuid)','execute') OR has_function_privilege('authenticated','public.rr_customer_login_otp_complete_service_test71(uuid,text,uuid,uuid)','execute') THEN RAISE EXCEPTION 'Completion publicly callable';END IF;
 r:=public.rr_customer_login_otp_prepare_test71(s.token,'False typed name',right(regexp_replace(c.mobile,'[^0-9]','','g'),10),dev);ch:=(r->>'challenge_id')::uuid;
 IF r->>'customer_name'<>c.customer_name THEN RAISE EXCEPTION 'Typed name impersonation';END IF;
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 BEGIN PERFORM public.rr_customer_login_otp_challenge_service_test71(ch,'wrong-device-binding-123456');RAISE EXCEPTION 'Wrong device accepted';EXCEPTION WHEN OTHERS THEN IF SQLERRM='Wrong device accepted' THEN RAISE;END IF;END;
 FOR i IN 1..5 LOOP PERFORM public.rr_customer_login_otp_challenge_service_test71(ch,dev);END LOOP;
 BEGIN PERFORM public.rr_customer_login_otp_challenge_service_test71(ch,dev);RAISE EXCEPTION 'Limit bypass';EXCEPTION WHEN OTHERS THEN IF SQLERRM='Limit bypass' THEN RAISE;END IF;END;
 r:=public.rr_customer_login_otp_prepare_test71(s.token,c.customer_name,c.mobile,dev);ch:=(r->>'challenge_id')::uuid;
 BEGIN PERFORM public.rr_customer_login_otp_challenge_service_test71(ch,dev);RAISE EXCEPTION 'New challenge reset limit';EXCEPTION WHEN OTHERS THEN IF SQLERRM='New challenge reset limit' THEN RAISE;END IF;END;
 IF (SELECT count(*) FROM rr_customer_auth_test71.login_approvals)<>before_count THEN RAISE EXCEPTION 'Failure generated approval';END IF;
END $test$;
ROLLBACK;
SELECT 'PASS: no typed-number approval; canonical name; service-only completion; device binding; aggregate attempt limits; rollback' result;
