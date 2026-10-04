begin;
do $proof$
declare s record; result1 jsonb;result2 jsonb; lines jsonb; cycle uuid; req uuid; count_cards int;
begin
 select sh.token,c.customer_name,c.mobile,sh.id into s
 from public.rr_market_share_v9420 sh
 join public.rr_customer_session_v9590 ss on ss.share_id=sh.id
 join public.rr_customers c on c.id=ss.customer_id
 join public.rr_customer_chat_v9433 ch on ch.id=ss.chat_id and ch.relation_kind='DIRECT_CUSTOMER'
 where sh.data_mode='TEST' and sh.origin_relation_kind is null and sh.status='ACTIVE'
 order by sh.created_at desc limit 1;
 if s.id is null then raise exception 'No verified outside-share fixture available';end if;
 select jsonb_build_array(jsonb_build_object('lot_no',l.lot_no,'qty',1)) into lines
 from public.rr_market_share_lots_v9420 l join public.rr_fg_stock_balance_v787 b on b.lot_no=l.lot_no and b.data_mode='TEST'
 where l.share_id=s.id and b.available_qty>0 limit 1;
 if lines is null then raise exception 'No in-stock fixture lot';end if;
 execute 'set local role anon';
 result1:=public.rr_direct_collection_submit_requirement_v9684(s.token,s.customer_name,s.mobile,'rollback-only routing verification',lines,null);
 result2:=public.rr_direct_collection_submit_requirement_v9684(s.token,s.customer_name,s.mobile,'rollback-only repeated submit verification',lines,null);
 execute 'reset role';
 if result1->>'requirement_id' is distinct from result2->>'requirement_id' then raise exception 'Repeated submit split requirement';end if;
 cycle:=(result1->>'collection_cycle_id')::uuid;req:=(result1->>'requirement_id')::uuid;
 select count(*) into count_cards from public.rr_customer_chat_messages_v9433
 where archived_at is null and payload->>'direct_collection_cycle_id'=cycle::text and message_type='REQUIREMENT';
 if count_cards<>1 then raise exception 'Expected one active requirement card';end if;
 if not exists(select 1 from public.rr_market_share_v9420 where id=s.id and origin_relation_kind='DIRECT_CUSTOMER' and origin_chat_id=(result1->>'chat_id')::uuid) then raise exception 'Route not bound';end if;
end $proof$;
select 'PASS: outside share adopts direct cycle; repeated submit retains one requirement and one active card; all changes rolled back' as verification;
rollback;