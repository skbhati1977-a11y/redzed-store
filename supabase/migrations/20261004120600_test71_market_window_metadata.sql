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
         coalesce(q.final_sale_rate, pr.sale_rate) sale_rate,
         coalesce(s.available_qty,0)::int available_qty,
         coalesce(p.pipeline_qty,0)::int pipeline_qty,
         w.cb_no,w.art_no,w.print_no,w.metal_id_no,w.cloth_name,w.gsm,
         coalesce(w.item_name, pr.short_item_name, s.short_item_name) item_name,
         w.sleeves,
         coalesce(nullif(trim(w.category),''), ac.category_name, nullif(trim(am.category),''),'') category,
         coalesce(w.caption_override, med.media->0->>'customer_caption', med.media->0->>'caption') caption_base,
         med.primary_image_url,
         coalesce(med.image_count,0)::int image_count,
         coalesce(med.media,'[]'::jsonb) media
  from stock s
  full join pipe p on p.lot_no=s.lot_no
  full join public.rr_fg_products_v787 pr on pr.lot_no=coalesce(s.lot_no,p.lot_no)
  left join public.rr_web_window_lot_profile_v9329 w on w.lot_no=coalesce(s.lot_no,p.lot_no,pr.lot_no) and w.data_mode=coalesce(p_data_mode,'TEST')
  left join public.rrq_lot_rates_v9300 q on q.lot_no=coalesce(s.lot_no,p.lot_no,pr.lot_no) and q.data_mode=coalesce(p_data_mode,'TEST')
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
$function$;

-- Add colour metadata without changing the established cards RPC return signature.
create or replace function public.rr_market_window_colours_v1(p_lots text[],p_data_mode text default 'TEST')
returns jsonb language sql stable security definer set search_path to '' as $colour$
select coalesce(jsonb_object_agg(x.lot_no,x.colours),'{}'::jsonb) from(
 select c.lot_no,(select string_agg(distinct nullif(trim(z.colour_name),''),' / ' order by nullif(trim(z.colour_name),''))
 from public.rr_upm_cut_size_rows_v726(c.lot_no) z where z.cutting_qty>0 and lower(trim(z.colour_name))<>'colour') colours
 from public.rr_web_window_cards_v9329(null,null,null,p_data_mode,150,0)c
 where c.lot_no=any(p_lots)
)x;
$colour$;
revoke all on function public.rr_market_window_colours_v1(text[],text) from public,anon;
grant execute on function public.rr_market_window_colours_v1(text[],text) to authenticated,service_role;

