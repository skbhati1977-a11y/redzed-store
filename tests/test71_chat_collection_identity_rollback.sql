begin;
do $proof$
declare actor uuid; chat uuid; cid uuid; lot text; result jsonb;
begin
 select auth_user_id into actor from public.rr_user_profiles where is_active and upper(role_code) in ('OWNER','SUPER_ADMIN','ADMIN','SALES') and auth_user_id is not null limit 1;
 select c.id,c.customer_id into chat,cid from public.rr_customer_chat_v9433 c join public.rr_market_requirements_v9420 r on r.customer_id=c.customer_id
 where r.requirement_display_no='RZ REQUIREMENT 21' and c.data_mode='TEST' and c.status='OPEN' and c.relation_kind='DIRECT_CUSTOMER' limit 1;
 select b.lot_no into lot from public.rr_fg_stock_balance_v787 b where b.data_mode='TEST' and b.available_qty>0
 and not exists(select 1 from public.rr_collection_cycle_v9586 cy join public.rr_collection_send_v9586 se on se.collection_cycle_id=cy.id join public.rr_market_share_lots_v9420 sl on sl.share_id=se.share_id where cy.chat_id=chat and cy.status in ('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED') and sl.lot_no=b.lot_no) limit 1;
 if actor is null or chat is null or lot is null then raise exception 'Fixture unavailable';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 execute 'set local role authenticated';
 result:=public.rr_direct_collection_send_v9684(chat,null,array[lot],null,'https://redzed-customer-collection.jggfab2011.chatgpt.site');
 execute 'reset role';
 if result->>'collection_cycle_id' is null or result->>'url' not like 'https://redzed-customer-collection.jggfab2011.chatgpt.site/s.html?%' then raise exception 'Send/public URL failed';end if;
 if not exists(select 1 from public.rr_collection_cycle_v9586 where id=(result->>'collection_cycle_id')::uuid and customer_id=cid and chat_id=chat) then raise exception 'Wrong customer';end if;
 begin
  perform public.rr_direct_collection_send_v9684(chat,'00000000-0000-0000-0000-000000000000',array[lot],null,'https://redzed-customer-collection.jggfab2011.chatgpt.site');
  raise exception 'Mismatch unexpectedly allowed';
 exception when others then if sqlerrm<>'Customer chat identity mismatch.' then raise;end if; end;
end $proof$;
select 'PASS: authenticated send resolves missing customer_id from exact chat, preserves customer cycle and emits public URL; mismatch rejected; rollback only' verification;
rollback;