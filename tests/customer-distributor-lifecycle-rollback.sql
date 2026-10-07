BEGIN;
DO $test$
DECLARE pc public.rr_market_partner_collection_v67%rowtype; sh public.rr_market_share_v9420%rowtype; ord public.rr_market_partner_order_v67%rowtype;
 new_share uuid; new_pc uuid:=gen_random_uuid(); next_root uuid:=gen_random_uuid(); next_share uuid; oid uuid:=gen_random_uuid(); seq bigint; no bigint; next_update integer; frozen_line uuid;
BEGIN
 SELECT p.* INTO pc FROM public.rr_market_partner_collection_v67 p JOIN rr_collection_rules_test71.partner_cycles g ON g.root_id=coalesce(p.root_collection_id,p.id) WHERE g.status='OPEN' AND NOT p.legacy_hidden_v78 ORDER BY p.collection_update_no DESC LIMIT 1;
 IF pc.id IS NULL THEN RAISE EXCEPTION 'Distributor open fixture required';END IF;
 SELECT * INTO sh FROM public.rr_market_share_v9420 WHERE id=pc.share_id;
 SELECT coalesce(max(collection_update_no),0)+1 INTO next_update FROM public.rr_market_partner_collection_v67 WHERE root_collection_id=pc.root_collection_id AND NOT legacy_hidden_v78;
 BEGIN
  INSERT INTO public.rr_market_partner_collection_v67(id,owner_customer_id,partner_customer_id,share_id,root_collection_id,collection_no,collection_update_no,status)
  VALUES(next_root,pc.owner_customer_id,pc.partner_customer_id,pc.share_id,next_root,pc.collection_no+1,0,'SENT');
  RAISE EXCEPTION 'Second distributor root accepted';
 EXCEPTION WHEN unique_violation THEN NULL;END;
 new_share:=gen_random_uuid();
 INSERT INTO public.rr_market_share_v9420 SELECT (jsonb_populate_record(NULL::public.rr_market_share_v9420,to_jsonb(sh)||jsonb_build_object('id',new_share,'token',encode(extensions.gen_random_bytes(24),'hex'),'short_code',upper(substr(md5(new_share::text),1,10))))).*;
 INSERT INTO public.rr_market_partner_collection_v67(id,owner_customer_id,partner_customer_id,share_id,root_collection_id,collection_no,collection_update_no,status)
 VALUES(new_pc,pc.owner_customer_id,pc.partner_customer_id,new_share,pc.root_collection_id,pc.collection_no,next_update,'SENT');
 IF NOT EXISTS(SELECT 1 FROM public.rr_market_partner_collection_v67 WHERE id=new_pc AND collection_no=pc.collection_no) THEN RAISE EXCEPTION 'Update changed root number';END IF;
 SELECT * INTO ord FROM public.rr_market_partner_order_v67 WHERE data_mode='TEST' LIMIT 1;
 SELECT coalesce(max(sequence_no),0)+100 INTO seq FROM public.rr_market_partner_order_v67 WHERE owner_customer_id=pc.owner_customer_id;
 INSERT INTO public.rr_market_partner_order_v67 SELECT (jsonb_populate_record(NULL::public.rr_market_partner_order_v67,to_jsonb(ord)||jsonb_build_object('id',oid,'collection_id',new_pc,'status','DRAFT','order_ref','ROLLBACK TEST '||oid,'sequence_no',seq,'customer_closed_at',null,'distributor_pi_created_at',null,'pi_ref',null,'ci_ref',null,'linked_requirement_id',null,'requirement_no',null,'requirement_update_no',0,'requirement_display_no',null))).*;
 UPDATE public.rr_market_partner_order_v67 SET status='READY',customer_closed_at=now() WHERE id=oid;
 IF NOT EXISTS(SELECT 1 FROM rr_collection_rules_test71.partner_cycles WHERE root_id=pc.root_collection_id AND status='CLOSED') THEN RAISE EXCEPTION 'Customer close did not close distributor root';END IF;
 BEGIN
 UPDATE public.rr_market_partner_collection_line_v67 SET lot_no=lot_no WHERE collection_id=pc.id;
 IF FOUND THEN RAISE EXCEPTION 'Closed distributor collection items remained editable';END IF;
 EXCEPTION WHEN others THEN IF SQLERRM<>'Closed distributor collection items are view only' THEN RAISE;END IF;END;
 BEGIN
  INSERT INTO public.rr_market_partner_collection_v67(id,owner_customer_id,partner_customer_id,share_id,root_collection_id,collection_no,collection_update_no,status)
  VALUES(gen_random_uuid(),pc.owner_customer_id,pc.partner_customer_id,new_share,pc.root_collection_id,pc.collection_no,next_update+1,'SENT');
  RAISE EXCEPTION 'Closed distributor update accepted';
 EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'Distributor collection is closed.%' THEN RAISE;END IF;END;
 next_share:=gen_random_uuid();
 INSERT INTO public.rr_market_share_v9420 SELECT (jsonb_populate_record(NULL::public.rr_market_share_v9420,to_jsonb(sh)||jsonb_build_object('id',next_share,'token',encode(extensions.gen_random_bytes(24),'hex'),'short_code',upper(substr(md5(next_share::text),1,10))))).*;
 INSERT INTO public.rr_market_partner_collection_v67(id,owner_customer_id,partner_customer_id,share_id,root_collection_id,collection_no,collection_update_no,status)
 VALUES(next_root,pc.owner_customer_id,pc.partner_customer_id,next_share,next_root,pc.collection_no+1,0,'SENT');
 IF NOT EXISTS(SELECT 1 FROM rr_collection_rules_test71.partner_cycles WHERE root_id=next_root AND status='OPEN' AND collection_no=pc.collection_no+1) THEN RAISE EXCEPTION 'New distributor number failed after close';END IF;
 SELECT l.id INTO frozen_line FROM public.rr_market_partner_order_line_v67 l JOIN public.rr_market_partner_order_v67 o ON o.id=l.order_id JOIN public.rr_market_partner_collection_v67 map ON map.id=o.collection_id JOIN rr_collection_rules_test71.partner_cycles gate ON gate.root_id=coalesce(map.root_collection_id,map.id) WHERE gate.status='CLOSED' LIMIT 1;
 IF frozen_line IS NOT NULL THEN
  BEGIN
   UPDATE public.rr_market_partner_order_line_v67 SET requested_qty=requested_qty+1 WHERE id=frozen_line;
   RAISE EXCEPTION 'Closed distributor quantity edited';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'Closed distributor requirement quantity is frozen.%' THEN RAISE;END IF;END;
 END IF;
 IF EXISTS(SELECT 1 FROM rr_collection_rules_test71.partner_cycles WHERE status='OPEN' GROUP BY owner_customer_id,partner_customer_id HAVING count(*)>1) THEN RAISE EXCEPTION 'Distributor duplicate root remains';END IF;
END $test$;
ROLLBACK;
