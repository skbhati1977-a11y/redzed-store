begin;
select set_config('request.jwt.claim.sub','893c58dd-420b-4dfa-aff7-844e20e634c5',true);
do $test$
declare
 chat uuid:='ad04bab0-22f6-4b03-92ae-d558142419bc'; cycle uuid:='3c8f576a-09fc-4ed4-b4b7-bd99b12aea12';
 ctx jsonb; cards jsonb; sent jsonb; summary jsonb; result jsonb; token text; lot text; wrong text;
 lines jsonb; previous_qty integer; previous_lot text; newrows jsonb; before_sends integer;
begin
 ctx:=public.rr_sales_collection_context_test71(chat,null,cycle);
 cards:=public.rr_sales_collection_cards_test71(chat,null,cycle,null,null,null,150,0);
 if not (ctx->>'can_send')::boolean then raise exception 'FAIL: fixture unexpectedly terminal'; end if;
 if exists(select 1 from jsonb_array_elements(cards->'rows') r where ctx->'sent_lots' ? upper(trim(r->>'lot_no')))
 then raise exception 'FAIL: sent lot visible'; end if;
 if exists(select 1 from jsonb_array_elements(cards->'rows') r where not exists(select 1 from jsonb_array_elements_text(ctx->'categories') c where lower(trim(c))=lower(trim(r->>'category'))))
 then raise exception 'FAIL: unrelated category visible'; end if;
 begin
  perform public.rr_sales_collection_context_test71(chat,null,(select id from public.rr_collection_cycle_v9586 where chat_id<>chat and data_mode='TEST' limit 1));
  raise exception 'FAIL: cross-party accepted';
 exception when others then if SQLERRM like 'FAIL:%' then raise; end if; end;
 begin
  perform public.rr_sales_collection_send_test71(chat,null,array[(ctx->'sent_lots'->>0)],null,'https://redzed-customer-collection.jggfab2011.chatgpt.site',cycle);
  raise exception 'FAIL: duplicate send accepted';
 exception when others then if SQLERRM like 'FAIL:%' then raise; end if; end;
 select w.lot_no into wrong from public.rr_web_window_cards_v9329(null,null,null,'TEST',150,0) w
  where not(ctx->'sent_lots' ? upper(trim(w.lot_no))) and not exists(
   select 1 from jsonb_array_elements_text(ctx->'categories') c where lower(trim(c))=lower(trim(w.category))) limit 1;
 if wrong is not null then
  begin
   perform public.rr_sales_collection_send_test71(chat,null,array[wrong],null,'https://redzed-customer-collection.jggfab2011.chatgpt.site',cycle);
   raise exception 'FAIL: wrong category accepted';
  exception when others then if SQLERRM like 'FAIL:%' then raise; end if; end;
 end if;
 lot:=cards->'rows'->0->>'lot_no';
 if lot is null then raise exception 'FAIL: no eligible fixture design'; end if;
 select count(*) into before_sends from public.rr_collection_send_v9586 where collection_cycle_id=cycle;
 sent:=public.rr_sales_collection_send_test71(chat,null,array[lot],null,'https://redzed-customer-collection.jggfab2011.chatgpt.site',cycle);
 if sent->>'collection_cycle_id'<>cycle::text then raise exception 'FAIL: send moved cycle'; end if;
 if (select count(*) from public.rr_collection_send_v9586 where collection_cycle_id=cycle)<>before_sends+1 then raise exception 'FAIL: send count'; end if;
 token:=sent->>'token';
 cards:=public.rr_sales_collection_cards_test71(chat,null,cycle,null,null,null,150,0);
 if exists(select 1 from jsonb_array_elements(cards->'rows') r where r->>'lot_no'=lot) then raise exception 'FAIL: just sent design remains selectable'; end if;
 summary:=public.rr_collection_customer_requirement_summary_v9637(token);
 select l->>'lot_no',(l->>'requested_qty')::integer into previous_lot,previous_qty
 from jsonb_array_elements(summary->'lines') l where (l->>'requested_qty')::integer>0 limit 1;
 if previous_lot is null then raise exception 'FAIL: old requirement lost'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('lot_no',l->>'lot_no','qty',
  case when l->>'lot_no'=previous_lot then previous_qty+1 else (l->>'requested_qty')::integer end)),'[]')
 into lines from jsonb_array_elements(summary->'lines') l;
 lines:=lines||jsonb_build_array(jsonb_build_object('lot_no',lot,'qty',3));
 result:=public.rr_direct_collection_submit_requirement_v9684(token,'ignored','ignored','rollback regression',lines,null);
 if result->>'requirement_id' is distinct from ctx->>'requirement_id' then raise exception 'FAIL: requirement identity changed'; end if;
 summary:=public.rr_collection_customer_requirement_summary_v9637(token);
 if not exists(select 1 from jsonb_array_elements(summary->'lines') l where l->>'lot_no'=previous_lot and (l->>'requested_qty')::integer=previous_qty+1)
 then raise exception 'FAIL: existing quantity change skipped'; end if;
 if not exists(select 1 from jsonb_array_elements(summary->'lines') l where l->>'lot_no'=lot and (l->>'requested_qty')::integer=3)
 then raise exception 'FAIL: new design missing'; end if;
 newrows:=public.rr_collection_cycle_share_view_v9686(token);
 if newrows->'rows'->0->>'lot_no'<>lot then raise exception 'FAIL: newest design not first'; end if;
 select jsonb_agg(jsonb_build_object('lot_no',l->>'lot_no','qty',
  case when l->>'lot_no'=previous_lot then 0 else (l->>'requested_qty')::integer end))
 into lines from jsonb_array_elements(summary->'lines') l;
 perform public.rr_direct_collection_submit_requirement_v9684(token,'ignored','ignored','rollback removal',lines,null);
 summary:=public.rr_collection_customer_requirement_summary_v9637(token);
 if not exists(select 1 from jsonb_array_elements(summary->'lines') l where l->>'lot_no'=previous_lot and (l->>'requested_qty')::integer=0)
 then raise exception 'FAIL: removed quantity resurrected'; end if;
 if not exists(select 1 from public.rr_collection_activity_v9633 where collection_cycle_id=cycle and payload ? 'previous_lines')
 then raise exception 'FAIL: quantity audit missing'; end if;
 -- One authoritative requirement card remains after multiple updates.
 if (select count(*) from public.rr_customer_chat_messages_v9433 m where m.chat_id=chat and archived_at is null and message_type='REQUIREMENT' and payload->>'direct_collection_cycle_id'=cycle::text)<>1
 then raise exception 'FAIL: duplicate requirement card'; end if;
end $test$;
select 'PASS: category filter, sent exclusion, cross-party rejection, duplicate rejection, wrong category rejection, same-cycle update, old qty carry, qty change, new qty, new-first order, zero removal, audit, one requirement card' result;
rollback;
