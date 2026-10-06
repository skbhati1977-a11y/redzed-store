create or replace function public.rr_rm_sale_lots_test71(p_art_no text default null,p_pi_id uuid default null)
returns table(lot_no text,art_no text,item_name text,available_qty numeric,purchase_date date,created_at timestamptz,image text,size_text text)
language plpgsql stable security definer set search_path=public as $fn$
begin
 perform public.rr_market_assert_sales_actor_v9420();
 return query select s.lot_no,upper(trim(l.chat_details_test71->>'art_no')),l.item_name,
 greatest(0,coalesce((select sum(b.available_qty) from public.rr_fg_stock_balance_v787 b where upper(trim(b.lot_no))=upper(trim(s.lot_no)) and b.stock_type='TRADED' and b.data_mode='TEST'),0)-
 coalesce((select sum(r.reserved_qty) from public.rr_pi_reservation_v9630 r where upper(trim(r.lot_no))=upper(trim(s.lot_no)) and r.stock_type='TRADED' and r.data_mode='TEST' and r.status in ('ACTIVE','CONFIRMED') and r.pi_id is distinct from p_pi_id),0))::numeric,
 h.purchase_date,l.created_at,s.final_image_url,l.chat_details_test71->>'size_text'
 from public.rr_rm_stock_v849_2c6 s join public.rr_rm_purchase_lines_v849_2c6 l on l.purchase_line_id=s.source_purchase_line_id
 join public.rr_rm_purchase_header_v849_2c6 h on h.purchase_id=l.purchase_id
 where s.data_mode='TEST' and h.status='POSTED' and s.sale_ready and exists(select 1 from public.rrq_lot_rates_v9300 q where q.lot_no=s.lot_no and q.data_mode='TEST' and q.dispatch_ready and q.final_sale_rate>0) and (p_art_no is null or upper(trim(l.chat_details_test71->>'art_no'))=upper(trim(p_art_no)))
 order by h.purchase_date,l.created_at,s.lot_no;
end $fn$;
revoke all on function public.rr_rm_sale_lots_test71(text,uuid) from public,anon,authenticated;


CREATE OR REPLACE FUNCTION public.rr_pi_customer_document_test71(p_pi_id uuid, p_chat_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p public.rr_fg_pi_v787%rowtype; a public.rr_user_profiles%rowtype; cid uuid; chat uuid; doc jsonb; items jsonb; fp text; delivery public.rr_pi_chat_deliveries_test71%rowtype;
begin
 perform public.rr_fg_assert_user_v787();
 a:=public.rr_chat_actor_profile_v9433();
 if lower(trim(a.role_code)) not in ('owner','super_admin','superadmin','admin','sales','salesman') then raise exception 'Sales/Admin/Super Admin required.'; end if;
 select * into p from public.rr_fg_pi_v787 where id=p_pi_id and data_mode='TEST';
 if not found then raise exception 'Saved TEST PI required.'; end if;
 cid:=nullif(p.buyer_snapshot->>'contact_customer_id','')::uuid;
 if cid is null then raise exception 'PI customer mapping required.'; end if;
 select c.id into chat from public.rr_customer_chat_v9433 c
 where c.customer_id=cid and c.data_mode='TEST' and c.relation_kind='DIRECT_CUSTOMER'
 and (p_chat_id is null or c.id=p_chat_id)
 and exists(select 1 from public.rr_customer_chat_members_v9433 m where m.chat_id=c.id and m.profile_id=a.id and m.is_active)
 order by c.updated_at desc,c.id limit 1;
 if chat is null then raise exception 'Matching party chat and active group membership required.'; end if;
 if p.market_requirement_id is not null and not exists(
 select 1 from public.rr_market_requirements_v9420 r where r.id=p.market_requirement_id and r.customer_id=cid)
 then raise exception 'PI requirement belongs to another customer.'; end if;
 insert into public.rr_pi_document_item_meta_test71(pi_id,lot_no,image_url,size_text,pack_pcs_per_box)
 select p.id,l.lot_no,c->>'image',c->>'size_text',coalesce((c->>'pack_pcs_per_box')::integer,0)
 from (select distinct lot_no from public.rr_fg_pi_lines_v787 where pi_id=p.id) l
 cross join lateral public.rr_pi_lot_context_v9517(l.lot_no,coalesce(p.buyer_snapshot->>'customer_name',p.buyer_snapshot->>'buyer_name'),'TEST') c
 where not exists(select 1 from public.rr_pi_document_item_meta_test71 m where m.pi_id=p.id and m.lot_no=l.lot_no)
 on conflict do nothing;
 select coalesce(jsonb_agg(jsonb_build_object(
 'image_url',m.image_url,'size_text',m.size_text,'pack_pcs_per_box',m.pack_pcs_per_box,'lot_no',l.lot_no,'art_no',l.readymade_art_no_test71,'art_sale_key',l.art_sale_key_test71,'item_name',l.short_item_name,'qty',l.qty,'net_rate',l.final_rate,'amount',l.amount)
 order by l.serial_no,l.lot_no,l.stock_type),'[]'::jsonb) into items from public.rr_fg_pi_lines_v787 l left join public.rr_pi_document_item_meta_test71 m on m.pi_id=l.pi_id and m.lot_no=l.lot_no where l.pi_id=p.id;
 if exists(select 1 from jsonb_array_elements(items) x where nullif(x->>'art_sale_key','') is not null) then
   select jsonb_agg(q.item order by q.first_no) into items from (
     select min(x.ordinality) first_no,case when max(nullif(x.value->>'art_sale_key','')) is null then (jsonb_agg(x.value order by x.ordinality)->0)
       else (jsonb_agg(x.value order by x.ordinality)->0)||jsonb_build_object(
         'lot_no','Art '||(jsonb_agg(x.value order by x.ordinality)->0->>'art_no'),
         'qty',sum((x.value->>'qty')::integer),'amount',sum((x.value->>'amount')::numeric),
         'pack_pcs_per_box',0,'lot_allocations',jsonb_agg(jsonb_build_object('lot_no',x.value->>'lot_no','qty',(x.value->>'qty')::integer) order by x.ordinality))
       end item
     from jsonb_array_elements(items) with ordinality x
     group by coalesce(nullif(x.value->>'art_sale_key',''),'LOT_LINE:'||x.ordinality::text)
   ) q;
 end if;
 if jsonb_array_length(items)=0 then raise exception 'Saved PI items required.'; end if;
 doc:=jsonb_build_object('pi_id',p.id,'document_kind',case when p.status='CI_FINAL' then 'CI' else 'PI' end,
 'layout_version','ITEM_BOX_AMOUNT_FINAL_RATE_V2','created_at',p.created_at,'document_no',case when p.status='CI_FINAL' then coalesce(p.cpi_no,p.pi_no) else p.pi_no end,
 'customer_name',coalesce(p.buyer_snapshot->>'customer_name',p.buyer_snapshot->>'buyer_name'),
 'mobile',p.buyer_snapshot->>'mobile','address',p.buyer_snapshot->>'address','gstin',p.buyer_snapshot->>'gstin',
 'dispatch_details',p.dispatch_details,'lines',items,'sub_total',p.sub_total,'value_added_pct',p.value_added_pct,
 'value_added_amount',p.sub_total*coalesce(p.value_added_pct,0)/100,'freight_amount',p.freight_amount,
 'other_charges',p.packing_other,'gst_amount',p.gst_amount,'round_off',p.round_off,'grand_total',p.grand_total,
 'total_qty',(select sum(l.qty) from public.rr_fg_pi_lines_v787 l where l.pi_id=p.id));
 fp:=md5(doc::text);
 select * into delivery from public.rr_pi_chat_deliveries_test71 where pi_id=p.id and chat_id=chat and fingerprint=fp;
 return jsonb_build_object('chat_id',chat,'fingerprint',fp,'document',doc,
 'already_sent',delivery.pi_id is not null,'message_ids',to_jsonb(delivery.message_ids));
end $function$
;

create or replace function public.rr_rm_sale_context_test71(p_art_no text,p_customer_name text,p_pi_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public as $fn$
declare r record;c jsonb;t jsonb;qty numeric;
begin
 perform public.rr_market_assert_sales_actor_v9420();
 select * into r from public.rr_rm_sale_lots_test71(p_art_no,p_pi_id) order by purchase_date desc,created_at desc limit 1;
 if r.lot_no is null then raise exception 'Readymade Art unavailable or not approved.';end if;
 select sum(available_qty) into qty from public.rr_rm_sale_lots_test71(p_art_no,p_pi_id);
 c:=public.rr_pi_lot_context_v9517(r.lot_no,p_customer_name,'TEST');
 t:=public.rr_trade_effective_rate_v849(r.lot_no,p_customer_name,'TEST');
 return c||jsonb_build_object('art_no',upper(trim(p_art_no)),'reference_lot_no',r.lot_no,'available_qty',qty,'rrq_available',qty,'category',r.item_name,'image',r.image,'size_text',r.size_text,'approved_rate',t->'target_sale_rate','effective_rate',t->'target_sale_rate','rate_path','READYMADE_ART_FIFO');
end $fn$;
revoke all on function public.rr_rm_sale_context_test71(text,text,uuid) from public,anon;
grant execute on function public.rr_rm_sale_context_test71(text,text,uuid) to authenticated;


create or replace function public.rr_rm_sale_search_test71(p_search text,p_pi_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public as $fn$
declare result jsonb;
begin
 perform public.rr_market_assert_sales_actor_v9420();
 select coalesce(jsonb_agg(to_jsonb(q)),'[]') into result from (
 select 'ART:'||s.art_no lot_no,s.art_no, max(s.item_name) category,sum(s.available_qty) available_qty,array_agg(s.lot_no order by s.purchase_date,s.created_at) lot_numbers,
 (array_agg(s.image order by s.purchase_date desc,s.created_at desc))[1] thumbnail,
 (array_agg(s.size_text order by s.purchase_date desc,s.created_at desc))[1] sizes
 from public.rr_rm_sale_lots_test71(null,p_pi_id) s where nullif(s.art_no,'') is not null
 and (s.art_no ilike '%'||trim(replace(upper(p_search),'ART:',''))||'%' or s.item_name ilike '%'||trim(p_search)||'%')
 group by s.art_no having sum(s.available_qty)>0 order by s.art_no limit 20) q;
 return result;
end $fn$;
revoke all on function public.rr_rm_sale_search_test71(text,uuid) from public,anon;
grant execute on function public.rr_rm_sale_search_test71(text,uuid) to authenticated;

