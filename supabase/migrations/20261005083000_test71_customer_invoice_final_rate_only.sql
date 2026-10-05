-- Customer PI/CI/RCI exports expose only the saved final per-piece rate. Staff discount remains internal.
create or replace function public.rr_pi_customer_document_test71(p_pi_id uuid,p_chat_id uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
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
 'image_url',m.image_url,'size_text',m.size_text,'pack_pcs_per_box',m.pack_pcs_per_box,'lot_no',l.lot_no,'item_name',l.short_item_name,'qty',l.qty,'net_rate',l.final_rate,'amount',l.amount)
 order by l.serial_no,l.lot_no,l.stock_type),'[]'::jsonb) into items from public.rr_fg_pi_lines_v787 l left join public.rr_pi_document_item_meta_test71 m on m.pi_id=l.pi_id and m.lot_no=l.lot_no where l.pi_id=p.id;
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
end $fn$;

create or replace function public.rr_rci_customer_document_test71(p_rci_id uuid,p_chat_id uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare r public.rr_rci_v9740%rowtype; parent jsonb; doc jsonb; items jsonb; fp text; a public.rr_user_profiles%rowtype; buyer public.rr_buyers_v787%rowtype; cid uuid; chat uuid; candidates uuid[];
begin
 select * into r from public.rr_rci_v9740 where id=p_rci_id and data_mode='TEST' and status='POSTED';
 if not found then raise exception 'Posted TEST RCI required.'; end if;
 perform public.rr_rci_assert_visible_buyer_v9746(r.buyer_id);
 if r.linked_ci_id is not null then
  parent:=public.rr_pi_customer_document_test71(r.linked_ci_id,p_chat_id);
  if r.buyer_id is distinct from (select buyer_id from public.rr_fg_pi_v787 where id=r.linked_ci_id) then raise exception 'RCI customer mismatch.'; end if;
 else
  a:=public.rr_chat_actor_profile_v9433();
  if lower(trim(a.role_code)) not in ('owner','super_admin','superadmin','admin','sales','salesman') then raise exception 'Sales/Admin/Super Admin required.'; end if;
  select * into buyer from public.rr_buyers_v787 where id=r.buyer_id;
  cid:=nullif(r.buyer_snapshot->>'contact_customer_id','')::uuid;
  if cid is null then
   select array_agg(id) into candidates from public.rr_customers where is_active and lower(trim(customer_name))=lower(trim(buyer.buyer_name))
    and nullif(regexp_replace(mobile,'[^0-9]','','g'),'')=nullif(regexp_replace(buyer.contact_no,'[^0-9]','','g'),'');
   if coalesce(cardinality(candidates),0)<>1 then raise exception 'Unique RCI party registration mapping required.'; end if;
   cid:=candidates[1];
  end if;
  select c.id into chat from public.rr_customer_chat_v9433 c where c.customer_id=cid and c.data_mode='TEST' and c.relation_kind='DIRECT_CUSTOMER' and (p_chat_id is null or c.id=p_chat_id)
   and exists(select 1 from public.rr_customer_chat_members_v9433 m where m.chat_id=c.id and m.profile_id=a.id and m.is_active) order by c.updated_at desc,c.id limit 1;
  if chat is null then raise exception 'Matching party chat and active group membership required.'; end if;
  parent:=jsonb_build_object('chat_id',chat,'document',jsonb_build_object('customer_name',buyer.buyer_name,'mobile',buyer.contact_no,'address',buyer.address,'gstin',buyer.gst_no,'layout_version','ITEM_BOX_AMOUNT_FINAL_RATE_V2'));
 end if;
 select jsonb_agg(jsonb_build_object('lot_no',coalesce(original_lot_no,stock_lot_no),'item_name',category_name,'size_text',coalesce(l.size_text,m.size_text),'image_url',coalesce(nullif(l.image_url,''),m.image_url),'pack_pcs_per_box',coalesce(m.pack_pcs_per_box,0),'qty',rci_qty,'net_rate',rate,'amount',amount) order by l.serial_no) into items from public.rr_rci_lines_v9740 l left join public.rr_pi_document_item_meta_test71 m on m.pi_id=r.linked_ci_id and m.lot_no=l.original_lot_no where l.rci_id=r.id;
 if items is null then raise exception 'Saved RCI items required.'; end if;
 doc:=(parent->'document')||jsonb_build_object('pi_id',null,'rci_id',r.id,'document_kind','RCI','document_no',r.rci_no,'created_at',r.created_at,'lines',items,'dispatch_details',r.reason,'sub_total',r.total_amount,'grand_total',r.total_amount,'total_qty',r.total_qty,'value_added_pct',0,'value_added_amount',0,'freight_amount',0,'other_charges',0,'gst_amount',0,'round_off',0);
 fp:=md5(doc::text);
 return jsonb_build_object('document',doc,'chat_id',parent->'chat_id','fingerprint',fp,'already_sent',exists(select 1 from public.rr_rci_chat_deliveries_test71 where rci_id=r.id and chat_id=(parent->>'chat_id')::uuid and fingerprint=fp));
end $fn$;
