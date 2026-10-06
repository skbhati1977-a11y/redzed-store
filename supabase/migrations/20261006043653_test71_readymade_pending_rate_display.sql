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
       coalesce(b.caption_base,
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
       ) caption,
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
where (coalesce(p_search,'')='' or concat_ws(' ',b.lot_no,b.cb_no,b.art_no,b.print_no,b.metal_id_no,b.short_item_name,b.full_item_name,b.item_name) ilike '%'||trim(p_search)||'%')
  and (coalesce(p_category,'')='' or lower(coalesce(b.category,''))=lower(p_category))
  and (coalesce(p_stock_status,'')='' or lower(case when b.available_qty>=108 then 'IN_STOCK' when b.available_qty between 1 and 107 then 'LOW_STOCK' when b.available_qty=0 and b.pipeline_qty>0 then 'COMING_SOON' else 'SOLD_OUT' end)=lower(p_stock_status))
order by search_rank, b.lot_no
limit greatest(1,least(coalesce(p_limit,60),150)) offset greatest(0,coalesce(p_offset,0));
$function$
;

create or replace function public.rr_rm_finish_purchase_test71(p_purchase_id uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare h record;s record;party uuid;purchase_ledger uuid;tx jsonb;costj jsonb;
begin
 perform public.rr_rm_assert_operator_test71();
 select * into h from public.rr_rm_purchase_header_v849_2c6 where purchase_id=p_purchase_id for update;
 if not found or h.data_mode<>'TEST' then raise exception 'TEST Readymade purchase required.'; end if;
 party:=public.rr_supplier_ledger_resolve_v806(h.supplier_name);
 select l.id into purchase_ledger from public.rr_ledgers_v805 l join public.rr_account_categories_v805 c on c.id=l.category_id where c.category_code='OTHER_MATERIAL_PURCHASE' and l.is_active order by l.created_at limit 1;
 if purchase_ledger is null then raise exception 'Readymade Purchase account mapping required.'; end if;
 for s in select * from public.rr_rm_stock_v849_2c6 where source_purchase_id=p_purchase_id order by lot_no loop
 perform public.rr_rm_sync_trade_stock_to_fg_v849(s.stock_id);
 insert into public.rr_fg_products_v787(lot_no,full_item_name,short_item_name,sale_rate,image_url,active)
 values(s.lot_no,s.item_name,s.item_name,0,s.final_image_url,true)
 on conflict(lot_no) do update set full_item_name=excluded.full_item_name,short_item_name=excluded.short_item_name,image_url=excluded.image_url;
 end loop;
 if not exists(select 1 from public.rr_account_transactions_v805 where source_module='READYMADE_PURCHASE' and source_record_id=p_purchase_id::text and data_mode=h.data_mode and status<>'REVERSED') then
 tx:=public.rr_accounts_mirror_post_v806('PURCHASE',h.total_purchase_amount,jsonb_build_array(jsonb_build_object('ledger_id',purchase_ledger,'dr',h.total_purchase_amount,'cr',0),jsonb_build_object('ledger_id',party,'dr',0,'cr',h.total_purchase_amount)),'READYMADE_PURCHASE',p_purchase_id::text,party,coalesce(h.bill_no_test71,h.purchase_no),h.purchase_date,'Readymade garments purchase',h.data_mode);
 update public.rr_rm_purchase_header_v849_2c6 set supplier_ledger_id_test71=party,account_transaction_id_test71=(tx->>'transaction_id')::uuid where purchase_id=p_purchase_id;
 end if;
 return jsonb_build_object('ok',true);
end $$;
