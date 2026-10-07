BEGIN;
DO $test$
DECLARE
 s public.rr_market_share_v9420%rowtype; c public.rr_customers%rowtype;
 dev text:=encode(extensions.gen_random_bytes(24),'hex'); dev2 text:=encode(extensions.gen_random_bytes(24),'hex');
 response jsonb; again jsonb; approved jsonb; admin_uid uuid; other_uid uuid; request_id uuid;
 mobile text; state jsonb; summary jsonb; qty bigint; forbidden boolean:=false;
 otp_uid uuid;otp_sid uuid:=extensions.gen_random_uuid();otp_challenge jsonb;otp_claims text;
BEGIN
 SELECT * INTO s FROM public.rr_market_share_v9420 WHERE status='ACTIVE' AND data_mode='TEST'
  AND customer_id IS NOT NULL AND origin_relation_kind='DIRECT_CUSTOMER' ORDER BY created_at DESC LIMIT 1;
 IF s.id IS NULL THEN RAISE EXCEPTION 'Direct customer fixture missing'; END IF;
 SELECT * INTO c FROM public.rr_customers WHERE id=s.customer_id AND is_active;
 mobile:=right(regexp_replace(c.mobile,'[^0-9]','','g'),10);
 PERFORM set_config('request.jwt.claim.sub','',true);PERFORM set_config('request.jwt.claims','{}',true);PERFORM set_config('request.headers','{}',true);
 BEGIN
  PERFORM public.rr_customer_session_issue_bound_v9680(s.token,c.customer_name,'0000000000',dev);
  RAISE EXCEPTION 'Wrong number accepted';
 EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'Mobile does not match%' THEN RAISE; END IF; END;
 -- Rollback-only trusted SMS proof fixture; no SMS is sent and no production proof persists.
 SELECT id INTO otp_uid FROM auth.users WHERE phone='91'||mobile;
 IF otp_uid IS NULL THEN otp_uid:=extensions.gen_random_uuid();INSERT INTO auth.users(id,phone,phone_confirmed_at,is_anonymous) VALUES(otp_uid,'91'||mobile,clock_timestamp(),false);ELSE UPDATE auth.users SET phone_confirmed_at=clock_timestamp(),is_anonymous=false WHERE id=otp_uid;END IF;
 INSERT INTO auth.sessions(id,user_id,created_at) VALUES(otp_sid,otp_uid,clock_timestamp());
 otp_challenge:=public.rr_customer_login_otp_prepare_test71(s.token,c.customer_name,mobile,dev);
 otp_claims:=current_setting('request.jwt.claims',true);PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 PERFORM public.rr_customer_login_otp_complete_service_test71((otp_challenge->>'challenge_id')::uuid,dev,otp_uid,otp_sid);
 PERFORM set_config('request.jwt.claims',coalesce(otp_claims,'{}'),true);
 response:=public.rr_customer_session_issue_bound_v9680(s.token,c.customer_name,mobile,dev);
 IF response->>'approval_status'<>'PENDING' OR response ? 'session_token' THEN RAISE EXCEPTION 'Unapproved device received session'; END IF;
 request_id:=(response->>'request_id')::uuid;
 again:=public.rr_customer_session_issue_v9590(s.token,c.customer_name,mobile,dev);
 IF again->>'request_id'<>response->>'request_id' OR again ? 'session_token' THEN RAISE EXCEPTION 'Raw issuer bypass or duplicate request'; END IF;
 BEGIN
  PERFORM public.rr_customer_login_approval_decide_test71(request_id,'APPROVED',true);
  RAISE EXCEPTION 'Anonymous approval accepted';
 EXCEPTION WHEN others THEN IF SQLERRM NOT IN('ERP user profile is missing.','Super Admin ID required.') THEN RAISE; END IF; END;
 BEGIN
  PERFORM public.rr_market_share_view_v9420(s.token);
  RAISE EXCEPTION 'Token-only collection exposed';
 EXCEPTION WHEN others THEN IF SQLERRM<>'Customer session required.' THEN RAISE; END IF; END;
 BEGIN
  PERFORM public.rr_chat_customer_messages_v9434(s.token,mobile,'GROUP',10);
  RAISE EXCEPTION 'Legacy token-only chat exposed';
 EXCEPTION WHEN others THEN IF SQLERRM<>'Customer session required.' THEN RAISE; END IF; END;
 BEGIN PERFORM public.rr_chat_customer_bootstrap_v9434(s.token,c.customer_name,mobile); RAISE EXCEPTION 'Bootstrap bypass accepted';
 EXCEPTION WHEN others THEN IF SQLERRM<>'Customer session required.' THEN RAISE; END IF; END;
 EXECUTE 'SET LOCAL ROLE anon';
 IF EXISTS(SELECT 1 FROM public.rr_market_share_v9420 WHERE id=s.id) THEN RAISE EXCEPTION 'Anonymous raw share bypass'; END IF;
 IF EXISTS(SELECT 1 FROM public.rr_market_share_lots_v9420 WHERE share_id=s.id) THEN RAISE EXCEPTION 'Anonymous raw lot bypass'; END IF;
 IF EXISTS(SELECT 1 FROM public.rr_market_requirements_v9420 WHERE share_id=s.id) THEN RAISE EXCEPTION 'Anonymous raw requirement bypass'; END IF;
 EXECUTE 'RESET ROLE';
 IF has_table_privilege('anon','rr_customer_auth_test71.login_approvals','SELECT') OR has_table_privilege('authenticated','rr_customer_auth_test71.login_approvals','UPDATE') THEN RAISE EXCEPTION 'Approval table exposed'; END IF;
 SELECT auth_user_id INTO other_uid FROM public.rr_user_profiles WHERE is_active AND upper(coalesce(access_status,'ACTIVE'))='ACTIVE' AND upper(coalesce(role_code,'')) NOT IN('SUPER_ADMIN','OWNER') LIMIT 1;
 IF other_uid IS NOT NULL THEN
  PERFORM set_config('request.jwt.claim.sub',other_uid::text,true);
  BEGIN PERFORM public.rr_customer_login_approval_decide_test71(request_id,'APPROVED',true); RAISE EXCEPTION 'Non-owner approval accepted';
  EXCEPTION WHEN others THEN IF SQLERRM<>'Super Admin ID required.' THEN RAISE; END IF; END;
 END IF;
 SELECT auth_user_id INTO admin_uid FROM public.rr_user_profiles WHERE is_active AND upper(coalesce(access_status,'ACTIVE'))='ACTIVE' AND upper(coalesce(role_code,'')) IN('SUPER_ADMIN','OWNER') LIMIT 1;
 IF admin_uid IS NULL THEN RAISE EXCEPTION 'Super Admin fixture missing'; END IF;
 PERFORM set_config('request.jwt.claim.sub',admin_uid::text,true);
 BEGIN PERFORM public.rr_customer_login_approval_decide_test71(request_id,'APPROVED',false); RAISE EXCEPTION 'Unverified approval accepted';
 EXCEPTION WHEN others THEN IF SQLERRM<>'Verify the original registered mobile before approving this device.' THEN RAISE; END IF; END;
 PERFORM public.rr_customer_login_approval_decide_test71(request_id,'APPROVED',true);
 PERFORM set_config('request.jwt.claim.sub','',true);
 approved:=public.rr_customer_session_issue_bound_v9680(s.token,c.customer_name,mobile,dev);
 IF approved->>'session_token' IS NULL THEN RAISE EXCEPTION 'Approved device cannot login'; END IF;
 PERFORM public.rr_customer_session_validate_v9590(approved->>'session_token',dev);
 PERFORM set_config('request.headers',jsonb_build_object('x-rr-customer-session',approved->>'session_token','x-rr-customer-device',dev)::text,true);
 EXECUTE 'SET LOCAL ROLE anon';
 IF NOT EXISTS(SELECT 1 FROM public.rr_market_share_v9420 WHERE id=s.id) THEN RAISE EXCEPTION 'Approved raw share read denied'; END IF;
 IF EXISTS(SELECT 1 FROM public.rr_market_share_v9420 WHERE data_mode='TEST' AND customer_id IS DISTINCT FROM s.customer_id AND origin_relation_kind='DIRECT_CUSTOMER' AND public.rr_market_share_relation_v81(token)<>'DISTRIBUTOR_CUSTOMER') THEN RAISE EXCEPTION 'Other customer raw share exposed'; END IF;
 DELETE FROM public.rr_market_share_v9420 WHERE id=s.id;
 IF FOUND THEN RAISE EXCEPTION 'Customer raw share delete allowed'; END IF;
 EXECUTE 'RESET ROLE';
 PERFORM set_config('request.headers','{}',true);

 BEGIN PERFORM public.rr_customer_session_validate_v9590(approved->>'session_token',dev2); RAISE EXCEPTION 'Other device accepted';
 EXCEPTION WHEN others THEN IF SQLERRM<>'Trusted device does not match.' THEN RAISE; END IF; END;
 again:=public.rr_customer_session_issue_bound_v9680(s.token,c.customer_name,mobile,dev2);
 IF again->>'approval_status'<>'OTP_REQUIRED' OR again ? 'session_token' THEN RAISE EXCEPTION 'Approval transferred to another phone'; END IF;
 BEGIN PERFORM public.rr_customer_login_status_test71(request_id,dev2); RAISE EXCEPTION 'Other device can poll approval';
 EXCEPTION WHEN others THEN IF SQLERRM<>'Login request unavailable for this device.' THEN RAISE; END IF; END;
 PERFORM set_config('request.headers',jsonb_build_object('x-rr-customer-session',approved->>'session_token','x-rr-customer-device',dev)::text,true);
 PERFORM public.rr_market_share_view_v9420(s.token);
 PERFORM public.rr_chat_customer_messages_v9434(s.token,mobile,'GROUP',10);
 state:=public.rr_collection_current_state_v9633(s.token);
 summary:=public.rr_collection_customer_requirement_summary_v9778(state->>'latest_collection_token');
 IF summary->>'collection_cycle_id' IS DISTINCT FROM state->>'collection_cycle_id' THEN RAISE EXCEPTION 'Requirement and displayed collection differ'; END IF;
 PERFORM set_config('request.jwt.claim.sub',admin_uid::text,true);
 PERFORM public.rr_customer_login_approval_decide_test71(request_id,'REVOKED',false);
 PERFORM set_config('request.jwt.claim.sub','',true);
 BEGIN PERFORM public.rr_customer_session_validate_v9590(approved->>'session_token',dev);
 PERFORM set_config('request.headers',jsonb_build_object('x-rr-customer-session',approved->>'session_token','x-rr-customer-device',dev)::text,true);
 EXECUTE 'SET LOCAL ROLE anon';
 IF NOT EXISTS(SELECT 1 FROM public.rr_market_share_v9420 WHERE id=s.id) THEN RAISE EXCEPTION 'Approved raw share read denied'; END IF;
 IF EXISTS(SELECT 1 FROM public.rr_market_share_v9420 WHERE data_mode='TEST' AND customer_id IS DISTINCT FROM s.customer_id AND origin_relation_kind='DIRECT_CUSTOMER' AND public.rr_market_share_relation_v81(token)<>'DISTRIBUTOR_CUSTOMER') THEN RAISE EXCEPTION 'Other customer raw share exposed'; END IF;
 DELETE FROM public.rr_market_share_v9420 WHERE id=s.id;
 IF FOUND THEN RAISE EXCEPTION 'Customer raw share delete allowed'; END IF;
 EXECUTE 'RESET ROLE';
 PERFORM set_config('request.headers','{}',true);
 RAISE EXCEPTION 'Revoked device retained access';
 EXCEPTION WHEN others THEN IF SQLERRM<>'Super Admin approval required for this device.' THEN RAISE; END IF; END;
END $test$;
ROLLBACK;
