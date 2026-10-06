begin;
select public.rr_fg_assert_user_v787();
do $$
declare j jsonb;pid uuid;sid uuid;q jsonb;lot text:='RM-CHAT-AUDIT-'||substr(gen_random_uuid()::text,1,8);ln jsonb;rate numeric;
begin
 ln:=jsonb_build_array(jsonb_build_object('lot_no',lot,'item_name','Chat Polo','category','RM Audit Polo','size_text','L / XL','colours_text','Red / White','cloth_name','Cotton','art_no','RA40','caption_note','Final garment','qty',24,'purchase_rate',100,'final_image_url','https://example.com/final.jpg','final_rate',2000));
 j:=public.rr_rm_chat_save_test71(null,'RM Chat Audit Supplier',lot,date '2032-01-15',ln,false);pid:=(j->>'purchase_id')::uuid;
 q:=public.rr_rm_chat_queue_test71(lot,'');
 if jsonb_array_length(q->'drafts')<>1 or jsonb_array_length(q->'cards')<>0 then raise exception 'Draft lifecycle failed';end if;
 if q->'drafts'->0->'lines'->0->>'category'<>'RM Audit Polo' then raise exception 'Draft category lost';end if;
 j:=public.rr_rm_chat_save_test71(pid,'RM Chat Audit Supplier',lot,date '2032-01-15',ln,true);
 q:=public.rr_rm_chat_queue_test71(lot,'RM Audit Polo');
 if jsonb_array_length(q->'drafts')<>0 or jsonb_array_length(q->'cards')<>1 then raise exception 'Posted lifecycle failed';end if;
 if (q->'cards'->0->>'available_qty')::numeric<>24 or q->'cards'->0->>'colours_text'<>'Red / White' then raise exception 'Stock or caption mismatch';end if;
 if (q->'cards'->0->>'approved_rate')::numeric<>2000 then raise exception 'Purchase final rate not wired to RRQ';end if;
 if (select category from public.rr_web_window_cards_v9329(lot,'RM Audit Polo',null,'TEST',10,0) where lot_no=lot)<>'RM Audit Polo' then raise exception 'Market category missing';end if;
 if (select size_text from public.rr_web_window_cards_v9329(lot,null,null,'TEST',10,0) where lot_no=lot)<>'L / XL' then raise exception 'Market size mismatch';end if;
 if (select caption from public.rr_web_window_cards_v9329(lot,null,null,'TEST',10,0) where lot_no=lot) not like '%Red / White%' then raise exception 'Shared caption colours missing';end if;
 perform public.rr_rm_chat_save_test71(pid,'RM Chat Audit Supplier',lot,date '2032-01-15',ln,true);
 if (select count(*) from public.rr_account_transactions_v805 where source_module='READYMADE_PURCHASE' and source_record_id=pid::text)<>1 then raise exception 'Duplicate Accounts';end if;
 select stock_id into sid from public.rr_rm_stock_v849_2c6 where source_purchase_id=pid;
 perform public.rr_rm_purchase_return_test71(sid,2,'Chat Audit return',date '2032-01-20',null,lot||'-RETURN');
 q:=public.rr_rm_chat_queue_test71(lot,'');
 if (q->'cards'->0->>'available_qty')::numeric<>22 then raise exception 'Chat return balance stale';end if;
 if has_function_privilege('anon','public.rr_rm_chat_save_test71(uuid,text,text,date,jsonb,boolean)','execute') or has_function_privilege('anon','public.rr_rm_chat_queue_test71(text,text)','execute') then raise exception 'Anonymous Readymade access';end if;
 perform set_config('rm.chat.audit','PASS: draft to WORKING; image/category/size/colour; final rate RRQ; Market mirror; duplicate purchase protection; live return balance; anon denied',true);
end $$;
select current_setting('rm.chat.audit') as readymade_chat_result;
rollback;
