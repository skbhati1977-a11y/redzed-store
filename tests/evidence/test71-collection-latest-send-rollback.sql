begin;
select set_config('request.jwt.claim.sub',(select auth_user_id::text from public.rr_user_profiles where is_active and upper(role_code) in ('OWNER','SUPER_ADMIN') limit 1),true);
create temporary table rm_collection_flow_result(result jsonb) on commit drop;
do $$
declare chat uuid;ctx jsonb;beforej jsonb;posted jsonb;sent jsonb;afterj jsonb;lot text:='RM-FLOW-'||substr(gen_random_uuid()::text,1,8);cat text;dupe boolean:=false;
begin
 select id into chat from public.rr_customer_chat_v9433 where customer_name ilike '%Reeka%' and data_mode='TEST' and status='OPEN' limit 1;
 ctx:=public.rr_sales_collection_context_test71(chat);
 beforej:=public.rr_sales_collection_cycle_status_test71(chat,(ctx->>'collection_cycle_id')::uuid);
 cat:=coalesce(ctx->'categories'->>0,'Flat Polo Collar');
 posted:=public.rr_rm_chat_save_test71(null,'RM Flow Audit Supplier',lot,date '2032-01-15',jsonb_build_array(jsonb_build_object('lot_no',lot,'item_name','Flow Audit Polo','category',cat,'size_text','L / XL','qty',24,'purchase_rate',100,'final_image_url','https://example.com/flow-audit.jpg')),true);
 sent:=public.rr_sales_collection_send_test71(chat,(ctx->>'customer_id')::uuid,array[lot],null,'https://redzed-customer-collection.jggfab2011.chatgpt.site',(ctx->>'collection_cycle_id')::uuid);
 afterj:=public.rr_sales_collection_live_status_test71(chat);
 if afterj->>'collection_cycle_id'<>sent->>'collection_cycle_id' then raise exception 'Latest send not selected';end if;
 if (afterj->>'collection_update_no')::int<>(beforej->>'collection_update_no')::int+1 then raise exception 'Update did not increment';end if;
 if jsonb_array_length(public.rr_sales_collection_cards_test71(chat,null,(sent->>'collection_cycle_id')::uuid,lot)->'rows')<>0 then raise exception 'Already sent design still visible';end if;
 begin perform public.rr_sales_collection_send_test71(chat,(ctx->>'customer_id')::uuid,array[lot],null,'https://redzed-customer-collection.jggfab2011.chatgpt.site',(sent->>'collection_cycle_id')::uuid);exception when others then if sqlerrm ilike '%already sent%' then dupe:=true;else raise;end if;end;
 if not dupe then raise exception 'Duplicate send not blocked';end if;
 insert into rm_collection_flow_result values(jsonb_build_object('collection',afterj->>'collection_display_no','update_before',beforej->>'collection_update_no','update_after',afterj->>'collection_update_no','new_message_confirmed',sent->>'chat_message_id' is not null,'sent_design_hidden',true,'repeat_send_blocked',dupe,'rolled_back',true));
end $$;
select result from rm_collection_flow_result;
rollback;
