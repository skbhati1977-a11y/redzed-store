CREATE OR REPLACE FUNCTION public.rr_rm_chat_fast_queue_test71(p_status text DEFAULT 'WORKING'::text, p_search text DEFAULT ''::text, p_category text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare role text;buy boolean;cards jsonb:='[]';drafts jsonb:='[]';cats jsonb:='[]';oc integer;wc integer;
begin
 perform public.rr_fg_assert_user_v787();role:=public.rr_costing_user_scope_v760(null)->>'effective_role';
 if role is null or role not in('OWNER','SUPER_ADMIN','ADMIN','ACCOUNTS','SALES','MANAGER') then raise exception 'Readymade access requires purchase, Sales or management role.';end if;
 buy:=role in('OWNER','SUPER_ADMIN','ADMIN','ACCOUNTS');
 select case when buy then 1+count(*)::int else 0 end into oc from public.rr_rm_purchase_header_v849_2c6 where data_mode='TEST' and status='DRAFT';
 select count(distinct coalesce(nullif(upper(trim(coalesce(w.art_no,l.chat_details_test71->>'art_no'))),''),'LOT:'||s.lot_no))::int into wc from public.rr_rm_stock_v849_2c6 s join public.rr_rm_purchase_lines_v849_2c6 l on l.purchase_line_id=s.source_purchase_line_id left join public.rr_web_window_lot_profile_v9329 w on w.lot_no=s.lot_no and w.data_mode='TEST' where s.data_mode='TEST';
 if upper(p_status) in('OPEN','SEARCH') and buy then
  select coalesce(jsonb_agg(d.value||jsonb_build_object('lines',(select jsonb_agg(to_jsonb(l)-'created_by'-'markup_per_pc'-'markup_mode'-'target_sale_rate'-'minimum_allowed_sale_rate'-'max_customer_discount_per_pc'||l.chat_details_test71 order by l.lot_no) from public.rr_rm_purchase_lines_v849_2c6 l where l.purchase_id=(d.value->>'purchase_id')::uuid))),'[]') into drafts
  from jsonb_array_elements(public.rr_rm_purchase_drafts_test71()) d where coalesce(p_search,'')='' or concat_ws(' ',d.value->>'purchase_no',d.value->>'supplier_name',d.value->>'bill_no',d.value->'lines') ilike '%'||p_search||'%';
 end if;
 if upper(p_status) in('WORKING','SEARCH') then
  select coalesce(jsonb_agg(jsonb_build_object('market_ready',coalesce((public.rr_rm_market_readiness_test71(s.lot_no)->>'market_ready')::boolean,false),'mapping_ready',(public.rr_rm_market_readiness_test71(s.lot_no)->>'mapping_ready')::boolean,'missing_fields',public.rr_rm_market_readiness_test71(s.lot_no)->'missing_fields','purchase_created_at',l.created_at,'art_available_qty',(select coalesce(sum(s2.available_qty),0) from public.rr_rm_stock_v849_2c6 s2 join public.rr_rm_purchase_lines_v849_2c6 l2 on l2.purchase_line_id=s2.source_purchase_line_id left join public.rr_web_window_lot_profile_v9329 w2 on w2.lot_no=s2.lot_no and w2.data_mode='TEST' where s2.data_mode='TEST' and coalesce(nullif(upper(trim(coalesce(w2.art_no,l2.chat_details_test71->>'art_no'))),''),'LOT:'||s2.lot_no)=coalesce(nullif(upper(trim(coalesce(w.art_no,l.chat_details_test71->>'art_no'))),''),'LOT:'||s.lot_no)),'stock_id',s.stock_id,'lot_no',s.lot_no,'item_name',s.item_name,'received_qty',s.qty_received,'available_qty',s.available_qty,'image_url',s.final_image_url,'approved_rate',q.final_sale_rate,'approval_ready',coalesce(q.dispatch_ready,false) and s.sale_ready,'category',coalesce(w.category,l.chat_details_test71->>'category','Uncategorised'),'size_text',coalesce(w.size_text,l.chat_details_test71->>'size_text'),'cloth_name',coalesce(w.cloth_name,l.chat_details_test71->>'cloth_name'),'art_no',coalesce(w.art_no,l.chat_details_test71->>'art_no'),'colours_text',l.chat_details_test71->>'colours_text','caption_note',l.chat_details_test71->>'caption_note','costing',jsonb_build_object('costing_complete',s.costing_snapshot_test71 is not null,'frozen',s.costing_snapshot_test71 is not null),'requested_rate',case when role in('OWNER','SUPER_ADMIN','ADMIN') then l.chat_details_test71->'final_rate' else null end) order by s.lot_no),'[]') into cards
  from public.rr_rm_stock_v849_2c6 s join public.rr_rm_purchase_lines_v849_2c6 l on l.purchase_line_id=s.source_purchase_line_id
  left join public.rr_web_window_lot_profile_v9329 w on w.lot_no=s.lot_no and w.data_mode='TEST'
  left join public.rrq_lot_rates_v9300 q on q.lot_no=s.lot_no and q.data_mode='TEST'
  where s.data_mode='TEST' and (coalesce(p_search,'')='' or concat_ws(' ',s.lot_no,s.item_name,w.category,l.chat_details_test71->>'category',w.art_no,l.chat_details_test71->>'art_no',l.chat_details_test71->>'colours_text') ilike '%'||p_search||'%')
  and (coalesce(p_category,'')='' or lower(coalesce(w.category,l.chat_details_test71->>'category','Uncategorised'))=lower(p_category));
  select coalesce(jsonb_agg(cat order by cat),'[]') into cats from(select distinct coalesce(w.category,l.chat_details_test71->>'category','Uncategorised') cat from public.rr_rm_stock_v849_2c6 s join public.rr_rm_purchase_lines_v849_2c6 l on l.purchase_line_id=s.source_purchase_line_id left join public.rr_web_window_lot_profile_v9329 w on w.lot_no=s.lot_no and w.data_mode='TEST' where s.data_mode='TEST') a;
 end if;
 return jsonb_build_object('role',role,'can_complete_mapping',role in('OWNER','SUPER_ADMIN','ADMIN','MANAGER','ACCOUNTS'),'can_purchase',buy,'can_approve',role in('OWNER','SUPER_ADMIN','ADMIN'),'can_view_cost',role in('OWNER','SUPER_ADMIN'),'cards',cards,'drafts',drafts,'categories',cats,'counts',jsonb_build_object('OPEN',oc,'WORKING',wc));
end $function$

