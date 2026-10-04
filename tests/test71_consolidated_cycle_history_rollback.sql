begin;
do $proof$
declare actor uuid; chat uuid; cid uuid; cy uuid; rid uuid; mid uuid; lots text[]; result jsonb; history jsonb; before_count int; n int; token text; cname text; mobile text;
begin
 select r.id,c.id,c.customer_id,r.collection_cycle_id,r.customer_name,r.mobile into rid,chat,cid,cy,cname,mobile
 from public.rr_market_requirements_v9420 r join public.rr_customer_chat_v9433 c on c.customer_id=r.customer_id
 where r.requirement_display_no='RZ REQUIREMENT 21' and c.data_mode='TEST' and c.status='OPEN' and c.relation_kind='DIRECT_CUSTOMER' limit 1;
 select p.auth_user_id into actor from public.rr_user_profiles p join public.rr_customer_chat_members_v9433 m on m.profile_id=p.id
 where m.chat_id=chat and m.is_active and p.is_active and upper(p.role_code) in('OWNER','SUPER_ADMIN','ADMIN','SALES') and p.auth_user_id is not null limit 1;
 select id into mid from public.rr_customer_chat_messages_v9433 where chat_id=chat and archived_at is null and message_type='REQUIREMENT' and payload->>'requirement_id'=rid::text;
 select array_agg(lot_no) into lots from (select distinct b.lot_no from public.rr_fg_stock_balance_v787 b where b.data_mode='TEST' and b.available_qty>1 and not exists(select 1 from public.rr_collection_send_v9586 se join public.rr_market_share_lots_v9420 sl on sl.share_id=se.share_id where se.collection_cycle_id=cy and sl.lot_no=b.lot_no) limit 2) q;
 if actor is null or mid is null or coalesce(array_length(lots,1),0)<2 then raise exception 'Fixture unavailable';end if;
 before_count:=jsonb_array_length(public.rr_direct_cycle_history_test71(cy));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 execute 'set local role authenticated';
 for n in 1..2 loop
  result:=public.rr_direct_collection_send_v9684(chat,null,array[lots[n]],rid,'https://redzed-customer-collection.jggfab2011.chatgpt.site');
 end loop;
 history:=public.rr_chat_direct_cycle_state_test71(chat);
 execute 'reset role';
 if not exists(select 1 from public.rr_customer_chat_messages_v9433 where id=mid and message_type='REQUIREMENT' and archived_at is null) then raise exception 'Requirement card was overwritten';end if;
 if jsonb_array_length(history->'update_history')<>before_count+2 then raise exception 'Missing collection history';end if;
 token:=result->>'token';
 execute 'set local role anon';
 history:=public.rr_collection_current_state_v9633(token);
 if (history->>'collection_update_no')::int<=(history->>'requirement_response_collection_update_no')::int then raise exception 'New collection response must be pending';end if;
 result:=public.rr_direct_collection_submit_requirement_v9684(token,cname,mobile,'Rollback history proof',jsonb_build_array(jsonb_build_object('lot_no',lots[2],'qty',1)),rid);
 history:=public.rr_collection_current_state_v9633(token);
 execute 'reset role';
 if jsonb_array_length(history->'update_history')<>before_count+3 then raise exception 'Missing requirement confirmation';end if;
 if (history->>'collection_update_no')::int<>(history->>'requirement_response_collection_update_no')::int then raise exception 'Latest collection not confirmed';end if;
 if (select count(*) from public.rr_customer_chat_messages_v9433 where chat_id=chat and archived_at is null and message_type='REQUIREMENT' and payload->>'direct_requirement_root_id'=rid::text)<>1 then raise exception 'Requirement split';end if;
 begin
  execute 'set local role anon';
  perform public.rr_chat_direct_cycle_state_test71(chat);
  raise exception 'Anon staff history exposed';
 exception when insufficient_privilege then execute 'reset role'; end;
end $proof$;
select 'PASS: two collection updates preserve requirement card; customer and staff share history; requirement confirmation enters same cycle; pending clears; anonymous staff access denied; rollback only' verification;
rollback;
