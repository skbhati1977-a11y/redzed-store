BEGIN;
DO $test$
DECLARE fixture public.rr_collection_cycle_v9586%rowtype; other_fixture public.rr_collection_cycle_v9586%rowtype;
 actor uuid; lot text; method text; created uuid; next_no integer; con text; preserved integer; failed boolean;
BEGIN
 SELECT c.* INTO fixture FROM public.rr_collection_cycle_v9586 c JOIN public.rr_customer_chat_v9433 ch ON ch.id=c.chat_id
 WHERE c.data_mode='TEST' AND ch.relation_kind='DIRECT_CUSTOMER' AND c.closed_at IS NULL
 AND c.status IN('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED') ORDER BY c.created_at DESC LIMIT 1;
 IF fixture.id IS NULL THEN RAISE EXCEPTION 'Open collection fixture required'; END IF;
 SELECT p.auth_user_id INTO actor FROM public.rr_user_profiles p WHERE p.is_active AND upper(coalesce(p.role_code,'')) IN('SUPER_ADMIN','OWNER') AND upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE' LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 SELECT l.lot_no INTO lot FROM public.rr_collection_send_v9586 s JOIN public.rr_market_share_lots_v9420 l ON l.share_id=s.share_id WHERE s.collection_cycle_id=fixture.id LIMIT 1;
 IF lot IS NULL THEN RAISE EXCEPTION 'Lot fixture required'; END IF;
 SELECT count(*) INTO preserved FROM public.rr_collection_cycle_v9586 WHERE customer_id=fixture.customer_id AND data_mode='TEST';
 FOREACH method IN ARRAY ARRAY['rr_collection_create_first_v61','rr_collection_create_first_v67','rr_collection_create_first_v9587'] LOOP
  failed:=false;
  BEGIN
   EXECUTE format('SELECT public.%I($1,$2,$3)',method) USING fixture.customer_id,ARRAY[lot],'TEST';
  EXCEPTION WHEN unique_violation THEN
   GET STACKED DIAGNOSTICS con=CONSTRAINT_NAME;
   IF con<>'test71_one_open_collection_per_customer' THEN RAISE; END IF;
   failed:=true;
  END;
  IF NOT failed THEN RAISE EXCEPTION 'Creator % bypassed open collection rule',method; END IF;
 END LOOP;
 IF preserved<>(SELECT count(*) FROM public.rr_collection_cycle_v9586 WHERE customer_id=fixture.customer_id AND data_mode='TEST') THEN RAISE EXCEPTION 'Failed creation left a new record'; END IF;
 -- Existing quantity/requirement updates remain possible.
 UPDATE public.rr_collection_cycle_v9586 SET status='REQUIREMENT_RECEIVED' WHERE id=fixture.id;
 -- Close every historical open fixture only within this rolled-back transaction.
 UPDATE public.rr_collection_cycle_v9586 SET status='CLOSED',closed_at=now(),close_reason='ROLLBACK TEST ONLY'
 WHERE customer_id=fixture.customer_id AND data_mode='TEST' AND closed_at IS NULL AND status IN('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED');
 SELECT coalesce(max(collection_no),0)+100 INTO next_no FROM public.rr_collection_cycle_v9586 WHERE customer_id=fixture.customer_id AND data_mode='TEST';
 INSERT INTO public.rr_collection_cycle_v9586(customer_id,chat_id,data_mode,collection_no,display_no,status)
 VALUES(fixture.customer_id,fixture.chat_id,'TEST',next_no,'RULE ROLLBACK TEST','DRAFT') RETURNING id INTO created;
 UPDATE public.rr_collection_cycle_v9586 SET status='SENT_NOT_OPENED' WHERE id=created;
 BEGIN
  UPDATE public.rr_collection_cycle_v9586 SET status='OPENED_NO_RESPONSE',closed_at=NULL WHERE id=fixture.id;
  RAISE EXCEPTION 'Reopen bypassed active collection';
 EXCEPTION WHEN unique_violation THEN
  GET STACKED DIAGNOSTICS con=CONSTRAINT_NAME;
  IF con<>'test71_one_open_collection_per_customer' THEN RAISE; END IF;
 END;
 UPDATE public.rr_collection_cycle_v9586 SET status='CLOSED',closed_at=now() WHERE id=created;
 UPDATE public.rr_collection_cycle_v9586 SET status='OPENED_NO_RESPONSE',closed_at=NULL WHERE id=fixture.id;
 IF has_table_privilege('anon','rr_collection_rules_test71.customer_cycle_lock','UPDATE') OR has_function_privilege('anon','rr_collection_rules_test71.enforce_one_open_collection()','EXECUTE') THEN RAISE EXCEPTION 'Private guard exposed'; END IF;
END $test$;
ROLLBACK;
