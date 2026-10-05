begin;
select set_config('request.jwt.claim.sub','893c58dd-420b-4dfa-aff7-844e20e634c5',true);
do $test$
declare cy public.rr_collection_cycle_v9586%rowtype; token text; ctx jsonb; reqmsg uuid; before_msg text; cards jsonb; lot text; sent jsonb;
begin
 select c.* into cy from public.rr_collection_cycle_v9586 c join public.rr_customer_chat_v9433 ch on ch.id=c.chat_id where ch.customer_name='Reeka Bhati' and c.data_mode='TEST' order by c.created_at desc limit 1;
 select s.token into token from public.rr_collection_send_v9586 cs join public.rr_market_share_v9420 s on s.id=cs.share_id where cs.collection_cycle_id=cy.id order by cs.send_seq desc limit 1;
 ctx:=public.rr_sales_collection_live_status_test71(cy.chat_id);
 if ctx->>'latest_collection_token' is distinct from token then raise exception 'FAIL belt token not latest';end if;
 perform public.rr_collection_more_samples_request_v9630(token,array['Band Collar'],'rollback category preserved');
 select id,body into reqmsg,before_msg from public.rr_customer_chat_messages_v9433 where chat_id=cy.chat_id and payload->>'source'='DIRECT_CATEGORY_REQUEST_TEST71' and archived_at is null order by created_at desc limit 1;
 cards:=public.rr_sales_collection_cards_test71(cy.chat_id,null,cy.id,null,null,null,150,0);
 lot:=cards->'rows'->0->>'lot_no';
 if lot is null then raise exception 'FAIL no eligible design';end if;
 sent:=public.rr_sales_collection_send_test71(cy.chat_id,cy.customer_id,array[lot],null,'https://redzed-customer-collection.jggfab2011.chatgpt.site',cy.id);
 if not exists(select 1 from public.rr_customer_chat_messages_v9433 where id=reqmsg and sender_kind='CUSTOMER' and body=before_msg and archived_at is null and payload->>'source'='DIRECT_CATEGORY_REQUEST_TEST71') then raise exception 'FAIL sales send overwrote category request';end if;
 if sent->>'chat_message_id'=reqmsg::text then raise exception 'FAIL reused customer request id';end if;
 if (select count(*) from public.rr_chat_push_outbox_v61 where message_id=(sent->>'chat_message_id')::uuid)<>1 then raise exception 'FAIL duplicate collection push seed';end if;
end $test$;
select 'PASS: latest belt token, category request preserved on collection send, different sender message id, single collection push seed' result;
rollback;