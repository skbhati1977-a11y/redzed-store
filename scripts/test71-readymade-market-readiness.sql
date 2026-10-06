-- TEST71: one readiness boundary shared by Working, MW and share creation.
create or replace function public.rr_rm_market_readiness_test71(p_lot_no text)
returns jsonb language sql stable security definer set search_path to public as $$
select jsonb_build_object('mapping_ready',cardinality(a.mapping)=0,'market_ready',cardinality(a.mapping)=0 and a.approved,
'missing_fields',to_jsonb(a.mapping||case when a.approved then array[]::text[] else array['Final sale-rate approval'] end))
from (
select array_remove(array[
case when nullif(trim(s.item_name),'') is null then 'Garment name' end,
case when s.final_image_url is null or s.final_image_url !~* '^https?://' then 'Final photo' end,
case when not exists(select 1 from public.rr_art_categories c where c.is_active and c.category_name=coalesce(nullif(trim(w.category),''),l.chat_details_test71->>'category')) then 'Category' end,
case when regexp_replace(coalesce(nullif(trim(w.size_text),''),l.chat_details_test71->>'size_text',''),'[\s,/]','','g') not in ('LXLXXL','2XL3XL4XL','3XL4XL5XL','MLXLXXL','MLXL','LXL','LXXL','FREESIZE') then 'Sizes' end,
case when coalesce(s.purchase_rate,0)<=0 then 'Purchase rate' end],null) mapping,
coalesce(q.dispatch_ready,false) and coalesce(s.sale_ready,false) and coalesce(q.final_sale_rate,0)>0 and q.final_sale_rate::text not in('NaN','Infinity','-Infinity') and coalesce((s.costing_snapshot_test71->>'costing_complete')::boolean,false) approved
from public.rr_rm_stock_v849_2c6 s
join public.rr_rm_purchase_lines_v849_2c6 l on l.purchase_line_id=s.source_purchase_line_id
left join public.rr_web_window_lot_profile_v9329 w on w.lot_no=s.lot_no and w.data_mode='TEST'
left join public.rrq_lot_rates_v9300 q on q.lot_no=s.lot_no and q.data_mode='TEST'
where upper(trim(s.lot_no))=upper(trim(p_lot_no)) and s.data_mode='TEST')a
$$;
revoke all on function public.rr_rm_market_readiness_test71(text) from public,anon;
grant execute on function public.rr_rm_market_readiness_test71(text) to authenticated;

create or replace function public.rr_rm_complete_mapping_test71(p_lot_no text,p_fields jsonb)
returns jsonb language plpgsql security definer set search_path to public as $$
declare s public.rr_rm_stock_v849_2c6%rowtype; role text; cat text; sz text; item text; photo text;
begin
perform public.rr_fg_assert_user_v787();role:=public.rr_costing_user_scope_v760(null)->>'effective_role';
if role is null or role not in('OWNER','SUPER_ADMIN','ADMIN','MANAGER','ACCOUNTS') then raise exception 'Admin, Manager or Accounts mapping authority required.';end if;
select * into s from public.rr_rm_stock_v849_2c6 where lot_no=trim(p_lot_no) and data_mode='TEST' for update;
if not found then raise exception 'TEST Readymade lot unavailable.';end if;
cat:=trim(p_fields->>'category');sz:=trim(p_fields->>'size_text');item:=trim(p_fields->>'item_name');photo:=trim(p_fields->>'final_image_url');
if not exists(select 1 from public.rr_art_categories where is_active and category_name=cat) then raise exception 'Select existing active category.';end if;
if sz not in('L, XL, XXL','2XL, 3XL, 4XL','3XL, 4XL, 5XL','M, L, XL, XXL','M, L, XL','L, XL','L, XXL','FREE SIZE') then raise exception 'Select existing size family.';end if;
if nullif(item,'') is null or photo is null or photo !~* '^https?://' then raise exception 'Garment name and final photo required.';end if;
update public.rr_rm_stock_v849_2c6 set item_name=item,final_image_url=photo,updated_at=now() where stock_id=s.stock_id;
update public.rr_fg_products_v787 set short_item_name=item,full_item_name=item,size_text=sz where lot_no=s.lot_no;
update public.rr_rm_purchase_lines_v849_2c6 set item_name=item,final_image_url=photo,
chat_details_test71=coalesce(chat_details_test71,'{}')||jsonb_build_object('category',cat,'size_text',sz,'cloth_name',trim(p_fields->>'cloth_name'),'art_no',trim(p_fields->>'art_no'),'colours_text',trim(p_fields->>'colours_text'),'caption_note',trim(p_fields->>'caption_note'))
where purchase_line_id=s.source_purchase_line_id;
insert into public.rr_web_window_lot_profile_v9329(data_mode,lot_no,item_name,category,size_text,cloth_name,art_no)
values('TEST',s.lot_no,item,cat,sz,trim(p_fields->>'cloth_name'),trim(p_fields->>'art_no'))
on conflict(data_mode,lot_no) do update set item_name=excluded.item_name,category=excluded.category,size_text=excluded.size_text,cloth_name=excluded.cloth_name,art_no=excluded.art_no,updated_at=now();
return public.rr_rm_market_readiness_test71(s.lot_no);
end $$;
revoke all on function public.rr_rm_complete_mapping_test71(text,jsonb) from public,anon;
grant execute on function public.rr_rm_complete_mapping_test71(text,jsonb) to authenticated;
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
 select count(*)::int into wc from public.rr_rm_stock_v849_2c6 where data_mode='TEST';
 if upper(p_status) in('OPEN','SEARCH') and buy then
  select coalesce(jsonb_agg(d.value||jsonb_build_object('lines',(select jsonb_agg(to_jsonb(l)-'created_by'-'markup_per_pc'-'markup_mode'-'target_sale_rate'-'minimum_allowed_sale_rate'-'max_customer_discount_per_pc'||l.chat_details_test71 order by l.lot_no) from public.rr_rm_purchase_lines_v849_2c6 l where l.purchase_id=(d.value->>'purchase_id')::uuid))),'[]') into drafts
  from jsonb_array_elements(public.rr_rm_purchase_drafts_test71()) d where coalesce(p_search,'')='' or concat_ws(' ',d.value->>'purchase_no',d.value->>'supplier_name',d.value->>'bill_no',d.value->'lines') ilike '%'||p_search||'%';
 end if;
 if upper(p_status) in('WORKING','SEARCH') then
  select coalesce(jsonb_agg(jsonb_build_object('market_ready',coalesce((public.rr_rm_market_readiness_test71(s.lot_no)->>'market_ready')::boolean,false),'mapping_ready',(public.rr_rm_market_readiness_test71(s.lot_no)->>'mapping_ready')::boolean,'missing_fields',public.rr_rm_market_readiness_test71(s.lot_no)->'missing_fields','stock_id',s.stock_id,'lot_no',s.lot_no,'item_name',s.item_name,'received_qty',s.qty_received,'available_qty',s.available_qty,'image_url',s.final_image_url,'approved_rate',q.final_sale_rate,'approval_ready',coalesce(q.dispatch_ready,false) and s.sale_ready,'category',coalesce(w.category,l.chat_details_test71->>'category','Uncategorised'),'size_text',coalesce(w.size_text,l.chat_details_test71->>'size_text'),'cloth_name',coalesce(w.cloth_name,l.chat_details_test71->>'cloth_name'),'art_no',coalesce(w.art_no,l.chat_details_test71->>'art_no'),'colours_text',l.chat_details_test71->>'colours_text','caption_note',l.chat_details_test71->>'caption_note','costing',jsonb_build_object('costing_complete',s.costing_snapshot_test71 is not null,'frozen',s.costing_snapshot_test71 is not null),'requested_rate',case when role in('OWNER','SUPER_ADMIN','ADMIN') then l.chat_details_test71->'final_rate' else null end) order by s.lot_no),'[]') into cards
  from public.rr_rm_stock_v849_2c6 s join public.rr_rm_purchase_lines_v849_2c6 l on l.purchase_line_id=s.source_purchase_line_id
  left join public.rr_web_window_lot_profile_v9329 w on w.lot_no=s.lot_no and w.data_mode='TEST'
  left join public.rrq_lot_rates_v9300 q on q.lot_no=s.lot_no and q.data_mode='TEST'
  where s.data_mode='TEST' and (coalesce(p_search,'')='' or concat_ws(' ',s.lot_no,s.item_name,w.category,l.chat_details_test71->>'category',w.art_no,l.chat_details_test71->>'colours_text') ilike '%'||p_search||'%')
  and (coalesce(p_category,'')='' or lower(coalesce(w.category,l.chat_details_test71->>'category','Uncategorised'))=lower(p_category));
  select coalesce(jsonb_agg(cat order by cat),'[]') into cats from(select distinct coalesce(w.category,l.chat_details_test71->>'category','Uncategorised') cat from public.rr_rm_stock_v849_2c6 s join public.rr_rm_purchase_lines_v849_2c6 l on l.purchase_line_id=s.source_purchase_line_id left join public.rr_web_window_lot_profile_v9329 w on w.lot_no=s.lot_no and w.data_mode='TEST' where s.data_mode='TEST') a;
 end if;
 return jsonb_build_object('role',role,'can_complete_mapping',role in('OWNER','SUPER_ADMIN','ADMIN','MANAGER','ACCOUNTS'),'can_purchase',buy,'can_approve',role in('OWNER','SUPER_ADMIN','ADMIN'),'can_view_cost',role in('OWNER','SUPER_ADMIN'),'cards',cards,'drafts',drafts,'categories',cats,'counts',jsonb_build_object('OPEN',oc,'WORKING',wc));
end $function$
;
CREATE OR REPLACE FUNCTION public.rr_web_window_cards_v9329(p_search text DEFAULT NULL::text, p_category text DEFAULT NULL::text, p_stock_status text DEFAULT NULL::text, p_data_mode text DEFAULT 'TEST'::text, p_limit integer DEFAULT 60, p_offset integer DEFAULT 0)
 RETURNS TABLE(lot_no text, short_item_name text, full_item_name text, size_text text, sale_rate numeric, available_qty integer, pipeline_qty integer, stock_status text, cb_no text, art_no text, print_no text, metal_id_no text, cloth_name text, gsm numeric, item_name text, sleeves text, category text, caption text, primary_image_url text, image_count integer, hidden_image_count integer, media jsonb, search_rank integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
with stock as (
  select lot_no,
         max(short_item_name) short_item_name,
         sum(available_qty)::int available_qty,
         max(sale_rate) sale_rate,
         max(data_mode) data_mode
  from public.rr_fg_stock_balance_v787
  where data_mode=coalesce(p_data_mode,'TEST')
  group by lot_no
), pipe as (
  select lot_no, sum(qty)::int pipeline_qty
  from public.rr_fg_boxes_v787
  where data_mode=coalesce(p_data_mode,'TEST')
    and status in ('PACK_DRAFT','READY_DESPATCH','IN_TRANSIT')
  group by lot_no
), media as (
  select m.lot_no,
         count(*)::int image_count,
         (array_agg(coalesce(m.image_url,m.storage_path) order by coalesce(m.variant_no,0), m.published_at nulls last))[1] primary_image_url,
         jsonb_agg(jsonb_build_object(
           'media_id',m.media_id,
           'variant_no',m.variant_no,
           'image_url',m.image_url,
           'storage_path',m.storage_path,
           'caption',m.caption,
           'customer_caption',m.customer_caption
         ) order by coalesce(m.variant_no,0), m.published_at nulls last) media
  from public.rr_fg_webstore_media_v808 m
  where m.data_mode=coalesce(p_data_mode,'TEST')
  group by m.lot_no
), base as (
  select coalesce(s.lot_no,p.lot_no,pr.lot_no) lot_no,
         coalesce(s.short_item_name, pr.short_item_name, pr.lot_no) short_item_name,
         coalesce(pr.full_item_name, s.short_item_name, pr.lot_no) full_item_name,
         coalesce(nullif(array_to_string(cl.size_set,' / '),''), nullif(array_to_string(pl.selected_sizes,' / '),''), nullif(pl.size_combo,''), nullif(trim(w.size_text),''), nullif(trim(pr.size_text),'')) size_text,
         case when tr.stock_id is not null then q.final_sale_rate else coalesce(q.final_sale_rate,pr.sale_rate) end sale_rate,
         coalesce(s.available_qty,0)::int available_qty,
         coalesce(p.pipeline_qty,0)::int pipeline_qty,
         w.cb_no,w.art_no,w.print_no,w.metal_id_no,w.cloth_name,w.gsm,
         coalesce(w.item_name, pr.short_item_name, s.short_item_name) item_name,
         w.sleeves,
         rml.chat_details_test71 rm_details,
         coalesce(nullif(trim(w.category),''), ac.category_name, nullif(trim(am.category),''),'') category,
         coalesce(w.caption_override, med.media->0->>'customer_caption', med.media->0->>'caption') caption_base,
         coalesce(med.primary_image_url,tr.final_image_url) primary_image_url,
         coalesce(med.image_count,case when tr.final_image_url is not null then 1 else 0 end)::int image_count,
         coalesce(med.media,case when tr.final_image_url is not null then jsonb_build_array(jsonb_build_object('image_url',tr.final_image_url,'caption',tr.item_name)) else '[]'::jsonb end) media
  from stock s
  full join pipe p on p.lot_no=s.lot_no
  full join public.rr_fg_products_v787 pr on pr.lot_no=coalesce(s.lot_no,p.lot_no)
  left join public.rr_web_window_lot_profile_v9329 w on w.lot_no=coalesce(s.lot_no,p.lot_no,pr.lot_no) and w.data_mode=coalesce(p_data_mode,'TEST')
  left join public.rrq_lot_rates_v9300 q on q.lot_no=coalesce(s.lot_no,p.lot_no,pr.lot_no) and q.data_mode=coalesce(p_data_mode,'TEST')
  left join public.rr_rm_stock_v849_2c6 tr on tr.lot_no=coalesce(s.lot_no,p.lot_no,pr.lot_no) and tr.data_mode=coalesce(p_data_mode,'TEST')
  left join public.rr_rm_purchase_lines_v849_2c6 rml on rml.purchase_line_id=tr.source_purchase_line_id
  left join public.rr_upm_lot_registry lr on lr.lot_no=coalesce(s.lot_no,p.lot_no,pr.lot_no)
  left join public.rr_cutting_lots_v3 cl on lr.source_table='rr_cutting_lots_v3' and cl.id::text=lr.source_id
  left join public.rr_production_lots pl on lr.source_table='rr_production_lots' and pl.id::text=lr.source_id
  left join public.rr_art_master am on am.id::text=lr.art_id
  left join public.rr_art_categories ac on ac.id=am.art_category_id
  left join media med on med.lot_no=coalesce(s.lot_no,p.lot_no,pr.lot_no)
)
select b.lot_no,
       b.short_item_name,
       b.full_item_name,
       b.size_text,
       b.sale_rate,
       b.available_qty,
       b.pipeline_qty,
       case when b.available_qty>=108 then 'IN_STOCK'
            when b.available_qty between 1 and 107 then 'LOW_STOCK'
            when b.available_qty=0 and b.pipeline_qty>0 then 'COMING_SOON'
            else 'SOLD_OUT' end stock_status,
       b.cb_no,b.art_no,b.print_no,b.metal_id_no,b.cloth_name,b.gsm,b.item_name,b.sleeves,
       b.category,
       case when b.rm_details is not null then concat_ws(chr(10),
         'REDZED · '||b.lot_no,b.full_item_name,
         'Category: '||b.category,'Art: '||coalesce(b.art_no,''),
         'Size: '||coalesce(b.size_text,''),'Cloth: '||coalesce(b.cloth_name,''),
         'Colours: '||coalesce(b.rm_details->>'colours_text',''),
         nullif(b.rm_details->>'caption_note',''),
         'Sales rate: '||case when b.sale_rate is null then 'Approval pending' else '₹'||b.sale_rate::text||'/PCS' end,
         'Available: '||b.available_qty::text||' PCS')
       else coalesce(b.caption_base,
         '📦 Lot No: '||b.lot_no||chr(10)||
         '🧵 Cloth Name: '||coalesce(b.cloth_name,'')||chr(10)||
         '⚖️ GSM: '||coalesce(b.gsm::text,'')||chr(10)||
         '👕 Item Name: '||coalesce(b.item_name,b.short_item_name,'')||chr(10)||
         '📏 Size: '||coalesce(b.size_text,'')||chr(10)||
         '🧥 Sleeves: '||coalesce(b.sleeves,'')||chr(10)||
         '💰 Sale Rate: '||case when b.sale_rate is null then '—' else '₹'||b.sale_rate::text||'/pcs' end||chr(10)||chr(10)||
         '✨ New Arrival'||chr(10)||
         case when b.available_qty>=108 then '✅ In Stock' when b.available_qty between 1 and 107 then '⚠️ Low Stock' when b.available_qty=0 and b.pipeline_qty>0 then '⏳ Coming Soon' else '❌ Sold Out' end||chr(10)||
         '🏷️ Category: '||coalesce(b.category,'')||chr(10)||
         '🎨 Colours: '
       ) end caption,
       b.primary_image_url,
       b.image_count,
       greatest(b.image_count-1,0) hidden_image_count,
       b.media,
       case
        when coalesce(p_search,'')='' then 100
        when b.lot_no=trim(p_search) then 0
        when b.lot_no ilike trim(p_search)||'%' then 1
        when concat_ws(' ',b.lot_no,b.cb_no,b.art_no,b.print_no,b.metal_id_no,b.short_item_name,b.full_item_name,b.item_name) ilike '%'||trim(p_search)||'%' then 2
        else 9 end search_rank
from base b
where (coalesce(p_data_mode,'TEST')<>'TEST' or not exists(select 1 from public.rr_rm_stock_v849_2c6 rs where rs.lot_no=b.lot_no and rs.data_mode='TEST') or coalesce((public.rr_rm_market_readiness_test71(b.lot_no)->>'market_ready')::boolean,false))
  and (coalesce(p_search,'')='' or concat_ws(' ',b.lot_no,b.cb_no,b.art_no,b.print_no,b.metal_id_no,b.short_item_name,b.full_item_name,b.item_name) ilike '%'||trim(p_search)||'%')
  and (coalesce(p_category,'')='' or lower(coalesce(b.category,''))=lower(p_category))
  and (coalesce(p_stock_status,'')='' or lower(case when b.available_qty>=108 then 'IN_STOCK' when b.available_qty between 1 and 107 then 'LOW_STOCK' when b.available_qty=0 and b.pipeline_qty>0 then 'COMING_SOON' else 'SOLD_OUT' end)=lower(p_stock_status))
order by search_rank, b.lot_no
limit greatest(1,least(coalesce(p_limit,60),150)) offset greatest(0,coalesce(p_offset,0));
$function$
;
CREATE OR REPLACE FUNCTION public.rr_rm_approve_rate_test71(p_lot_no text, p_final_rate numeric, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s record;j jsonb;r jsonb;
begin
 perform public.rr_rm_assert_operator_test71();
 if p_final_rate is null or p_final_rate<=0 or p_final_rate::text in('NaN','Infinity','-Infinity') then raise exception 'Positive final sale rate required.';end if;
 if not coalesce((public.rr_rm_market_readiness_test71(p_lot_no)->>'mapping_ready')::boolean,false) then raise exception 'Complete garment mapping in Readymade Working before approving final rate.';end if;
 if lower(public.rr_costing_user_scope_v760(null)->>'effective_role') not in('owner','super_admin','superadmin','admin') then raise exception 'Owner / Admin rate approval required.';end if;
 perform pg_advisory_xact_lock(hashtextextended('RM:'||upper(trim(p_lot_no))||':TEST',0));
 select * into s from public.rr_rm_stock_v849_2c6 where upper(trim(lot_no))=upper(trim(p_lot_no)) and data_mode='TEST' for update;
 if not found then raise exception 'Readymade lot not found.';end if;
 if s.sale_ready and exists(select 1 from public.rrq_lot_rates_v9300 q where q.lot_no=s.lot_no and q.data_mode='TEST' and q.dispatch_ready and q.final_sale_rate>0) then raise exception 'Final rate already approved; read only.';end if;
 -- Freeze full private costing under owner scope; Admin can approve but cannot read it.
 if s.costing_snapshot_test71 is null then
 if lower(public.rr_costing_user_scope_v760(null)->>'effective_role') not in('owner','super_admin','superadmin') then raise exception 'Owner must finalize Readymade costing first.';end if;
 j:=public.rr_rm_costing_test71(s.lot_no,'TEST');
 if not coalesce((j->>'costing_complete')::boolean,false) then raise exception 'Monthly weighted allocation is pending.';end if;
 update public.rr_rm_stock_v849_2c6 set costing_snapshot_test71=j||jsonb_build_object('frozen',true,'frozen_at',now()) where stock_id=s.stock_id;
 end if;
 r:=public.rrq_apply_packing_rate_core_test71(s.lot_no,p_final_rate,'TEST',p_reason);
 update public.rr_rm_stock_v849_2c6 set target_sale_rate=p_final_rate,minimum_allowed_sale_rate=greatest(0,p_final_rate-max_customer_discount_per_pc),markup_mode='DEFAULT_22',markup_per_pc=22,sale_ready=true where stock_id=s.stock_id;
 return r;
end $function$
;

