BEGIN;
DO $test$
DECLARE sh public.rr_market_share_v9420%rowtype;c public.rr_customers%rowtype;rid uuid;device text:=encode(extensions.gen_random_bytes(24),'hex');result jsonb;n integer;n2 integer;uid uuid;
BEGIN
 SELECT s.* INTO sh FROM public.rr_market_share_v9420 s JOIN public.rr_customers cu ON cu.id=s.customer_id AND cu.is_active WHERE s.data_mode='TEST' AND s.status='ACTIVE' AND length(right(regexp_replace(coalesce(cu.mobile,''),'[^0-9]','','g'),10))=10 AND public.rr_market_share_relation_v81(s.token)<>'DISTRIBUTOR_CUSTOMER' LIMIT 1;
 SELECT * INTO c FROM public.rr_customers WHERE id=sh.customer_id;
 SELECT auth_user_id INTO uid FROM public.rr_user_profiles WHERE is_active AND upper(role_code) IN('SUPER_ADMIN','OWNER') AND upper(coalesce(access_status,'ACTIVE'))='ACTIVE' LIMIT 1;
 IF sh.id IS NULL OR uid IS NULL THEN RAISE EXCEPTION 'Fixture missing';END IF;
 result:=public.rr_customer_login_request_test71(sh.token,c.customer_name,right(regexp_replace(c.mobile,'[^0-9]','','g'),10),device);rid:=(result->>'request_id')::uuid;
 SELECT count(*) INTO n FROM public.rr_targeted_push_outbox_v708 WHERE payload->>'login_request_id'=rid::text;
 IF n=0 THEN RAISE EXCEPTION 'Pending login did not enqueue push';END IF;
 IF EXISTS(SELECT 1 FROM public.rr_targeted_push_outbox_v708 o WHERE o.payload->>'login_request_id'=rid::text AND (o.route_url NOT LIKE '%rc_id=ADMIN%rc_status=OPEN%rc_login_request='||rid::text||'%' OR NOT EXISTS(SELECT 1 FROM public.rr_user_profiles p WHERE is_active AND upper(role_code) IN('SUPER_ADMIN','OWNER') AND coalesce(public.rr_push_worker_id_v712(p.id),p.auth_user_id)=o.recipient_worker_id))) THEN RAISE EXCEPTION 'Wrong recipient or approval focus route';END IF;
 PERFORM public.rr_customer_login_status_test71(rid,device);PERFORM public.rr_customer_login_status_test71(rid,device);
 SELECT count(*) INTO n2 FROM public.rr_targeted_push_outbox_v708 WHERE payload->>'login_request_id'=rid::text;
 IF n2<>n THEN RAISE EXCEPTION 'Status polling sent extra push';END IF;
 BEGIN PERFORM public.rr_customer_login_remind_test71(rid,'WRONG DEVICE');RAISE EXCEPTION 'Wrong device accepted';EXCEPTION WHEN others THEN IF SQLERRM<>'Login request unavailable for this device.' THEN RAISE;END IF;END;
 UPDATE rr_customer_auth_test71.login_approvals SET last_push_at=clock_timestamp()-interval '6 seconds' WHERE id=rid;
 PERFORM public.rr_customer_login_remind_test71(rid,device);
 SELECT count(*) INTO n2 FROM public.rr_targeted_push_outbox_v708 WHERE payload->>'login_request_id'=rid::text;
 IF n2<>n*2 THEN RAISE EXCEPTION 'Reopening pending chat did not remind';END IF;
 PERFORM set_config('request.jwt.claim.sub',uid::text,true);
 result:=public.rr_customer_login_approval_list_test71();IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(result) row WHERE row->>'request_id'=rid::text AND row->>'status'='PENDING') THEN RAISE EXCEPTION 'Admin OPEN projection missing request';END IF;
 PERFORM public.rr_customer_login_approval_decide_test71(rid,'APPROVED',true);
 PERFORM public.rr_customer_login_remind_test71(rid,device);
 SELECT count(*) INTO n FROM public.rr_targeted_push_outbox_v708 WHERE payload->>'login_request_id'=rid::text;
 IF n<>n2 THEN RAISE EXCEPTION 'Approved login still sent reminders';END IF;
 IF EXISTS(SELECT 1 FROM public.rr_targeted_push_outbox_v708 o WHERE o.payload->>'login_request_id'=rid::text AND public.rr_customer_login_push_pending_test71(rid,o.recipient_worker_id)) THEN RAISE EXCEPTION 'Resolved approval allowed dispatch';END IF;
END $test$;
ROLLBACK;
