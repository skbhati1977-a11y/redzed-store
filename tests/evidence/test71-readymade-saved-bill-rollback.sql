begin;
select set_config('request.jwt.claim.sub',(select auth_user_id::text from public.rr_user_profiles where is_active and lower(role_code)='owner' limit 1),true);
do $test$
declare art text:='RM-ART-AUDIT-'||substr(gen_random_uuid()::text,1,8);lot1 text;lot2 text;lot3 text;cat text;supplier text;
payload jsonb;j jsonb;profile jsonb;receipt jsonb;again jsonb;files jsonb;pid1 uuid;pid2 uuid;sid1 uuid;piid uuid;lineid uuid;revision bigint;first_time timestamptz;failed boolean;
buyer text:='RM-ART-BUYER-'||substr(gen_random_uuid()::text,1,8);path text;event_id uuid:=gen_random_uuid();
begin
select category_name into cat from public.rr_art_categories where is_active order by category_name limit 1;
select supplier_name into supplier from public.rr_suppliers where is_active order by supplier_name limit 1;
lot1:=art||'-1';lot2:=art||'-2';lot3:=art||'-3';
payload:=jsonb_build_array(jsonb_build_object('lot_no',lot1,'item_name','Mapped Shirt','category',cat,'size_text','L, XL, XXL','colours_text','Red','cloth_name','Cotton','art_no',art,'art_revision',0,'bill_qty',540,'qty',530,'purchase_rate',100,'final_rate',2000,'final_image_url','https://example.com/art.jpg'));
j:=public.rr_rm_chat_save_test71(null,supplier,lot1,date '2038-01-15',payload,true);pid1:=(j->>'purchase_id')::uuid;
select stock_id into sid1 from public.rr_rm_stock_v849_2c6 where source_purchase_id=pid1;
profile:=public.rr_rm_art_catalog_test71(art)->'rows'->0;revision:=(profile->>'art_revision')::bigint;first_time:=(profile->>'effective_from')::timestamptz;
if profile->>'item_name'<>'Mapped Shirt' or (profile->>'purchase_rate')::numeric<>100 or (profile->>'final_rate')::numeric<>2000 or (profile->>'available_qty')::numeric<>530 or profile->>'final_image_url'<>'https://example.com/art.jpg' then raise exception 'Initial Art mapping failed';end if;
receipt:=public.rr_rm_receipt_prepare_test71(pid1);
if receipt->'lines'->0->>'item_name'<>'Mapped Shirt' or receipt->'lines'->0->>'art_no'<>art or receipt->'lines'->0->>'voucher_no' is null or receipt->>'supplier_name'<>supplier then raise exception 'Receipt snapshot missing mapped item, Art, supplier or financial voucher';end if;
j:=public.rr_rm_saved_bill_test71('  '||supplier||'  ',lot1);
if not (j->>'found')::boolean or j->>'status'<>'POSTED' or j->'receipt'->>'purchase_id'<>pid1::text or j->'receipt'->'lines'->0->>'voucher_no' is null then raise exception 'Saved bill receipt lookup failed';end if;
if (public.rr_rm_saved_bill_test71(supplier,lot1||'-MISSING')->>'found')::boolean then raise exception 'Non-existing bill matched';end if;
-- New purchase changes rates prospectively, not the first purchase/stock/note.
payload:=jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(payload,'{0,lot_no}',to_jsonb(lot2)),'{0,art_revision}',to_jsonb(revision)),'{0,qty}','550'),'{0,purchase_rate}','120'),'{0,final_rate}','2100');
j:=public.rr_rm_chat_save_test71(null,supplier,lot2,date '2038-01-16',payload,true);pid2:=(j->>'purchase_id')::uuid;
profile:=public.rr_rm_art_catalog_test71(art)->'rows'->0;
if (profile->>'purchase_rate')::numeric<>120 or (profile->>'final_rate')::numeric<>2100 or (profile->>'available_qty')::numeric<>1080 or (profile->>'effective_from')::timestamptz<first_time then raise exception 'Prospective rates/live purchase balance failed';end if;
if (select purchase_rate from public.rr_rm_stock_v849_2c6 where stock_id=sid1)<>100 or (public.rr_rm_receipt_summary_test71(pid1)->'lines'->0->>'note_amount')::numeric<>1000 or (select final_sale_rate from public.rrq_lot_rates_v9300 where lot_no=lot1 and data_mode='TEST')<>2000 then raise exception 'Historical rates/note were changed';end if;
again:=public.rr_rm_receipt_prepare_test71(pid1);
if again<>receipt then raise exception 'Repeated receipt preparation changed template';end if;
-- A stale loaded Art revision must fail atomically.
payload:=jsonb_set(payload,'{0,lot_no}',to_jsonb(lot3));failed:=false;
begin perform public.rr_rm_chat_save_test71(null,supplier,lot3,date '2038-01-17',payload,true);
exception when others then failed:=SQLERRM like 'Art details changed%';end;
if not failed or exists(select 1 from public.rr_rm_purchase_header_v849_2c6 where bill_no_test71=lot3) then raise exception 'Stale Art revision did not block confirmation atomically';end if;
-- Exercise the actual CI sale and sales return stock engines.
insert into public.rr_customers(customer_name,is_active,allowed_discount_per_piece) values(buyer,true,0);
j:=public.rr_fg_save_pi_v787(null,buyer,'AUDIT',jsonb_build_array(jsonb_build_object('lot_no',lot1,'stock_type','TRADED','qty',7,'rate',2000,'gross_rate',2000,'party_discount_per_piece',0)),0,0,true,'TEST');piid:=(j->>'pi_id')::uuid;
profile:=public.rr_rm_art_catalog_test71(art)->'rows'->0;
if (profile->>'available_qty')::numeric<>1073 then raise exception 'CI sale not reflected in Art balance';end if;
select id into lineid from public.rr_fg_pi_lines_v787 where pi_id=piid;
perform public.rr_fg_post_return_v787('KNOWN',lineid,null,null,2,'Art audit return','TEST');
if (public.rr_rm_art_catalog_test71(art)->'rows'->0->>'available_qty')::numeric<>1075 then raise exception 'Sales return Art balance failed';end if;
-- Both bills remain separate, while Working balance is grouped by Art across search filters.
j:=public.rr_rm_chat_fast_queue_test71('WORKING',lot1,'');
if jsonb_array_length(j->'cards')<>1 or (j->'cards'->0->>'art_available_qty')::numeric<>1075 then raise exception 'Filtered Working Art balance failed';end if;
perform public.rr_rm_purchase_return_test71(sid1,3,'Art card purchase return',date '2038-01-20','Grouped Art audit',gen_random_uuid()::text);
j:=public.rr_rm_chat_fast_queue_test71('WORKING',art,'');
if jsonb_array_length(j->'cards')<>2 or exists(select 1 from jsonb_array_elements(j->'cards') c where (c->>'art_available_qty')::numeric<>1072) then raise exception 'Working grouped purchase return balance failed';end if;
if (select count(*) from public.rr_rm_purchase_header_v849_2c6 where purchase_id in(pid1,pid2) and status='POSTED')<>2 then raise exception 'Purchase bills were consolidated';end if;
-- File metadata contracts; storage rows below are rollback-only metadata fixtures, not delivered JPGs.
path:='readymade/test71/receipts/'||pid1||'/audit.jpg';
insert into storage.objects(bucket_id,name,owner_id,metadata) values('redzed-media',path,auth.uid()::text,jsonb_build_object('mimetype','image/jpeg','size',100));
files:=jsonb_build_array(jsonb_build_object('name','REDZED-audit-1.jpg','path',path,'sha256',repeat('a',64)));
again:=public.rr_rm_receipt_files_save_test71(pid1,files);
if again->'files'<>files then raise exception 'Receipt file metadata not linked';end if;
again:=public.rr_rm_receipt_files_save_test71(pid1,jsonb_build_array(jsonb_build_object('name','ignored.jpg')));
if again->'files'<>files then raise exception 'Repeated file save overwrote frozen JPG metadata';end if;
perform public.rr_rm_receipt_share_record_test71(pid1,event_id);perform public.rr_rm_receipt_share_record_test71(pid1,event_id);
if (select jsonb_array_length(share_events) from public.rr_rm_receipt_assets_test71 where purchase_id=pid1)<>1 then raise exception 'Duplicate share event recorded';end if;
if (select count(*) from public.rr_account_transactions_v805 where source_module='READYMADE_RECEIPT_SHORT_DEBIT' and source_record_id=(select purchase_line_id::text from public.rr_rm_purchase_lines_v849_2c6 where purchase_id=pid1))<>1 then raise exception 'Repeated share duplicated Debit Note';end if;
if has_function_privilege('anon','public.rr_rm_art_catalog_test71(text)','execute') or has_table_privilege('authenticated','public.rr_rm_art_versions_test71','select') then raise exception 'Art private rates exposed';end if;
payload:=jsonb_set(jsonb_set(jsonb_set(payload,'{0,lot_no}',to_jsonb(lot3)),'{0,art_no}',to_jsonb(art||'-DRAFT')),'{0,art_revision}','0');
j:=public.rr_rm_chat_save_test71(null,supplier,lot3,date '2038-01-17',payload,false);
j:=public.rr_rm_saved_bill_test71(supplier,lot3);
if j->>'status'<>'DRAFT' or j->'draft'->'lines'->0->>'lot_no'<>lot3 or (j->'draft'->'lines'->0->>'purchase_rate')::numeric<>120 then raise exception 'Saved draft lookup failed';end if;
if has_function_privilege('anon','public.rr_rm_saved_bill_test71(text,text)','execute') then raise exception 'Saved bill exposed to anon';end if;
perform set_config('rm.art.audit','PASS: saved posted bill receipt and draft recovery; normalized supplier; missing bill; anon denied; Art defaults/history; prospective rates; original purchase unchanged; stale revision guard; live purchase/CI sale/return balance; immutable receipt/JPG metadata; repeat share/note idempotency; private access',true);
end $test$;
select current_setting('rm.art.audit') art_receipt_result;
rollback;


