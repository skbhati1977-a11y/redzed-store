BEGIN;
DO $test$
DECLARE c public.rr_collection_cycle_v9586%rowtype; other_c public.rr_collection_cycle_v9586%rowtype;
 uid uuid; rid uuid; line_id uuid; share_id uuid; pi_id uuid; n integer; nc uuid; ctx jsonb; result jsonb; line_qty integer; send_lot text; distributor_share uuid;
BEGIN
 SELECT cy.* INTO c FROM public.rr_collection_cycle_v9586 cy WHERE cy.data_mode='TEST' AND cy.closed_at IS NULL AND cy.status='REQUIREMENT_RECEIVED' AND EXISTS(SELECT 1 FROM public.rr_customer_chat_members_v9433 m JOIN public.rr_user_profiles p ON p.id=m.profile_id WHERE m.chat_id=cy.chat_id AND m.is_active AND p.is_active AND upper(p.role_code) IN('SUPER_ADMIN','OWNER')) ORDER BY cy.created_at DESC LIMIT 1;
 IF c.id IS NULL THEN RAISE EXCEPTION 'Active authorized collection fixture required'; END IF;
 SELECT p.auth_user_id INTO uid FROM public.rr_customer_chat_members_v9433 m JOIN public.rr_user_profiles p ON p.id=m.profile_id WHERE m.chat_id=c.chat_id AND m.is_active AND p.is_active AND upper(p.role_code) IN('SUPER_ADMIN','OWNER') LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub',uid::text,true);
 SELECT r.id,l.id,l.requested_qty INTO rid,line_id,line_qty FROM public.rr_market_requirements_v9420 r JOIN public.rr_market_requirement_lines_v9420 l ON l.requirement_id=r.id WHERE r.collection_cycle_id=c.id LIMIT 1;
 SELECT cs.share_id INTO share_id FROM public.rr_collection_send_v9586 cs WHERE cs.collection_cycle_id=c.id ORDER BY send_seq DESC LIMIT 1;
 SELECT coalesce(max(collection_no),0)+1 INTO n FROM public.rr_collection_cycle_v9586 WHERE customer_id=c.customer_id AND data_mode='TEST';
 BEGIN
  INSERT INTO public.rr_collection_cycle_v9586(customer_id,chat_id,data_mode,collection_no,display_no,status) VALUES(c.customer_id,c.chat_id,'TEST',n,'ROLLBACK TEST','DRAFT');
  RAISE EXCEPTION 'Second active collection accepted';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 -- Another customer's active collection is independent and remains active.
 SELECT * INTO other_c FROM public.rr_collection_cycle_v9586 WHERE data_mode='TEST' AND customer_id<>c.customer_id AND closed_at IS NULL AND status IN('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED') LIMIT 1;
 IF other_c.id IS NULL THEN RAISE EXCEPTION 'Independent customer fixture missing'; END IF;
 UPDATE public.rr_market_requirement_lines_v9420 SET requested_qty=line_qty WHERE id=line_id;
 ctx:=public.rr_sales_collection_context_test71(c.chat_id,NULL,c.id);
 IF ctx->>'collection_cycle_id'<>c.id::text THEN RAISE EXCEPTION 'Update changed active collection'; END IF;
 -- Closure preserves a read-only card until an actual new collection send.
 PERFORM public.rr_collection_customer_close_v9630((SELECT token FROM public.rr_market_share_v9420 WHERE id=share_id));
 IF EXISTS(SELECT 1 FROM public.rr_collection_cycle_v9586 WHERE id=c.id AND closed_at IS NULL) THEN RAISE EXCEPTION 'Customer close failed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.rr_customer_chat_messages_v9433 WHERE archived_at IS NULL AND payload->>'direct_collection_cycle_id'=c.id::text AND (payload->>'read_only')::boolean) THEN RAISE EXCEPTION 'Closed read-only card missing'; END IF;
 ctx:=public.rr_sales_collection_cycle_status_test71(c.chat_id,c.id);
 IF ctx->>'collection_cycle_id'<>c.id::text OR NOT (ctx->>'read_only')::boolean OR (ctx->>'can_send')::boolean THEN RAISE EXCEPTION 'Exact closed view has incorrect context';END IF;
 ctx:=public.rr_chat_requirement_detail_v9508(c.chat_id,rid);
 IF (ctx->>'can_add_update')::boolean OR NOT (ctx->>'read_only')::boolean THEN RAISE EXCEPTION 'Closed staff requirement editable';END IF;
 BEGIN
  UPDATE public.rr_market_requirement_lines_v9420 SET requested_qty=line_qty+1 WHERE id=line_id;
  RAISE EXCEPTION 'Closed requirement quantity changed';
 EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'Closed collection requirement is frozen.%' THEN RAISE; END IF; END;
 BEGIN
  INSERT INTO public.rr_collection_send_v9586(collection_cycle_id,share_id,send_seq,send_kind) VALUES(c.id,share_id,999,'UPDATE');
  RAISE EXCEPTION 'Closed collection send accepted';
 EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'Collection is closed or PI has been made.%' THEN RAISE; END IF; END;
 BEGIN
  UPDATE public.rr_collection_cycle_v9586 SET status='OPENED_NO_RESPONSE',closed_at=NULL WHERE id=c.id;
  RAISE EXCEPTION 'Closed collection reopened';
 EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'Closed or PI collection cannot reopen.%' THEN RAISE; END IF; END;
 ctx:=public.rr_sales_collection_context_test71(c.chat_id,rid,c.id);
 IF ctx->>'collection_cycle_id' IS NOT NULL OR NOT (ctx->>'can_send')::boolean THEN RAISE EXCEPTION 'Closed context does not allow fresh collection'; END IF;
 -- A new number is valid only after closure.
 SELECT w.lot_no INTO send_lot FROM public.rr_web_window_cards_v9329(NULL,NULL,NULL,'TEST',50,0) w WHERE w.available_qty>0 ORDER BY EXISTS(SELECT 1 FROM public.rr_collection_send_v9586 cs JOIN public.rr_market_share_lots_v9420 l ON l.share_id=cs.share_id WHERE cs.collection_cycle_id=c.id AND l.lot_no=w.lot_no) DESC LIMIT 1;
 IF send_lot IS NULL THEN RAISE EXCEPTION 'Available send design fixture required';END IF;
 result:=public.rr_sales_collection_send_test71(c.chat_id,c.customer_id,ARRAY[send_lot],rid,'https://redzed-customer-collection.jggfab2011.chatgpt.site',c.id);
 nc:=(result->>'collection_cycle_id')::uuid;
 IF (result->>'collection_no')::integer<>n THEN RAISE EXCEPTION 'New send did not use customer next collection number';END IF;
 IF nc=c.id THEN RAISE EXCEPTION 'Send after close reused closed collection';END IF;
 ctx:=public.rr_customer_collection_hidden_items_test71(result->>'token',send_lot,true);
 IF NOT (ctx->'hidden_lots' ? send_lot) THEN RAISE EXCEPTION 'Zero qty hide did not persist';END IF;
 ctx:=public.rr_customer_collection_hidden_items_test71(result->>'token',send_lot,false);
 IF ctx->'hidden_lots' ? send_lot THEN RAISE EXCEPTION 'Unhide failed';END IF;
 IF EXISTS(SELECT 1 FROM public.rr_customer_chat_messages_v9433 WHERE archived_at IS NULL AND payload->>'direct_collection_cycle_id'=c.id::text AND message_type IN('LINK','REQUIREMENT','ATTACHMENT') AND coalesce(payload->>'source','')<>'DIRECT_CATEGORY_REQUEST_TEST71') THEN RAISE EXCEPTION 'Old closed card remained after new send';END IF;
 BEGIN
 PERFORM public.rr_collection_add_update_v9587(nc,ARRAY[send_lot]);
 RAISE EXCEPTION 'Already sent zero-qty item duplicated';
 EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'Lot(s) already sent in this Collection:%' THEN RAISE;END IF;END;
 IF NOT EXISTS(SELECT 1 FROM public.rr_collection_cycle_v9586 WHERE id=other_c.id AND closed_at IS NULL) THEN RAISE EXCEPTION 'Other customer affected'; END IF;
 SELECT pc.share_id INTO distributor_share FROM public.rr_market_partner_collection_v67 pc LIMIT 1;
 IF distributor_share IS NOT NULL THEN
  BEGIN
   INSERT INTO public.rr_collection_send_v9586(collection_cycle_id,share_id,send_seq,send_kind) VALUES(nc,distributor_share,999,'UPDATE');
   RAISE EXCEPTION 'Private distributor share attached to direct cycle';
  EXCEPTION WHEN others THEN IF SQLERRM<>'Distributor private share cannot be attached to a REDZED direct collection.' THEN RAISE;END IF;END;
 END IF;
 -- Exercise actual PI link closure on a separate active fixture with requirement.
 SELECT cy.* INTO c FROM public.rr_collection_cycle_v9586 cy WHERE cy.data_mode='TEST' AND cy.closed_at IS NULL AND cy.id<>nc
 AND EXISTS(SELECT 1 FROM public.rr_market_requirements_v9420 r WHERE r.collection_cycle_id=cy.id) LIMIT 1;
 SELECT id INTO rid FROM public.rr_market_requirements_v9420 WHERE collection_cycle_id=c.id LIMIT 1;
 SELECT id INTO pi_id FROM public.rr_fg_pi_v787 WHERE data_mode='TEST' LIMIT 1;
 IF c.id IS NOT NULL AND pi_id IS NOT NULL THEN
  UPDATE public.rr_fg_pi_v787 SET market_requirement_id=rid WHERE id=pi_id;
  IF NOT EXISTS(SELECT 1 FROM public.rr_collection_cycle_v9586 WHERE id=c.id AND status='PI_GENERATED' AND closed_at IS NOT NULL) THEN RAISE EXCEPTION 'PI made did not close collection'; END IF;
  BEGIN
   PERFORM public.rr_collection_add_update_v9587(c.id,ARRAY['ROLLBACK-DESIGN']);
   RAISE EXCEPTION 'PI collection update accepted';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'Collection is closed or PI has been made.%' THEN RAISE; END IF; END;
 END IF;
 IF EXISTS(SELECT 1 FROM public.rr_collection_cycle_v9586 WHERE data_mode='TEST' AND closed_at IS NULL AND status IN('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED') GROUP BY customer_id HAVING count(*)>1) THEN RAISE EXCEPTION 'Duplicate active collections remain'; END IF;
END $test$;
ROLLBACK;
