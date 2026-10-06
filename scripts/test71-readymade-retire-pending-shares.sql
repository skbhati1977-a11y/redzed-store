CREATE OR REPLACE FUNCTION public.rr_web_window_snapshot_test71(p_search text DEFAULT NULL::text, p_category text DEFAULT NULL::text, p_stock_status text DEFAULT NULL::text, p_data_mode text DEFAULT 'TEST'::text, p_limit integer DEFAULT 60, p_offset integer DEFAULT 0)
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
where (coalesce(p_search,'')='' or concat_ws(' ',b.lot_no,b.cb_no,b.art_no,b.print_no,b.metal_id_no,b.short_item_name,b.full_item_name,b.item_name) ilike '%'||trim(p_search)||'%')
  and (coalesce(p_category,'')='' or lower(coalesce(b.category,''))=lower(p_category))
  and (coalesce(p_stock_status,'')='' or lower(case when b.available_qty>=108 then 'IN_STOCK' when b.available_qty between 1 and 107 then 'LOW_STOCK' when b.available_qty=0 and b.pipeline_qty>0 then 'COMING_SOON' else 'SOLD_OUT' end)=lower(p_stock_status))
order by search_rank, b.lot_no
limit greatest(1,least(coalesce(p_limit,60),150)) offset greatest(0,coalesce(p_offset,0));
$function$
;
revoke all on function public.rr_web_window_snapshot_test71(text,text,text,text,integer,integer) from public,anon,authenticated;
CREATE OR REPLACE FUNCTION public.rr_market_share_snapshot_test71(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  s public.rr_market_share_v9420%rowtype;
  v_map public.rr_market_partner_collection_v67%rowtype;
  v_current public.rr_market_partner_collection_v67%rowtype;
  v_latest public.rr_market_partner_order_v67%rowtype;
  v_root uuid;
  rows jsonb;
  v_header text;
  v_collections jsonb;
  v_requirements jsonb;
  v_requirement jsonb;
  v_pi jsonb;
  v_ci jsonb;
begin
  select * into s from public.rr_market_share_v9420
  where (token=p_token or short_code=upper(p_token)) and status='ACTIVE'
  order by case when token=p_token then 0 else 1 end limit 1;
  if not found then raise exception 'Share link unavailable.'; end if;
  update public.rr_market_share_v9420 set last_opened_at=now() where id=s.id;
  select * into v_map from public.rr_market_partner_collection_v67 where share_id=s.id;
  if v_map.id is null then
    select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object(
      'cloth_name',r.cloth_name,'category',r.category,'size_text',r.size_text,'item_name',r.item_name
    ) order by l.sort_no),'[]'::jsonb) into rows
    from public.rr_market_share_lots_v9420 l
    cross join lateral public.rr_web_window_snapshot_test71(l.lot_no,null,null,s.data_mode,1,0)c
    cross join lateral public.rr_web_lot_fields_resolve_v9624(l.lot_no,s.data_mode)r
    where l.share_id=s.id and c.lot_no=l.lot_no;
    return jsonb_build_object('share_id',s.id,'customer_name',s.customer_name,'created_at',s.created_at,
      'rows',rows,'header_title','REDZED · COLLECTION','collections','[]'::jsonb,
      'requirements','[]'::jsonb,'requirement_locked',false);
  end if;

  v_root:=coalesce(v_map.root_collection_id,v_map.id);
  select pc.* into v_current from public.rr_market_partner_collection_v67 pc
  where coalesce(pc.root_collection_id,pc.id)=v_root
  order by pc.collection_update_no desc,pc.created_at desc limit 1;
  v_header:=public.rr_market_partner_header_v67(v_map.owner_customer_id,v_map.partner_customer_id);
  select o.* into v_latest from public.rr_market_partner_order_v67 o
  join public.rr_market_partner_collection_v67 pc on pc.id=o.collection_id
  where coalesce(pc.root_collection_id,pc.id)=v_root and o.status<>'SUPERSEDED'
  order by o.requirement_update_no desc,o.created_at desc limit 1;

  with latest_line as(
    select distinct on(l.lot_no) l.*,pc.collection_update_no
    from public.rr_market_partner_collection_v67 pc
    join public.rr_market_partner_collection_line_v67 l on l.collection_id=pc.id
    where coalesce(pc.root_collection_id,pc.id)=v_root
    order by l.lot_no,pc.collection_update_no desc,l.created_at desc
  )
  select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object(
    'cloth_name',coalesce(pl.cloth_name,r.cloth_name),'category',coalesce(pl.category,r.category),
    'size_text',coalesce(pl.size_text,r.size_text),'item_name',r.item_name,'media',pl.media,
    'sale_rate',pl.final_customer_rate,'display_sale_rate',pl.distributor_sale_rate,
    'discount_amount',pl.discount_amount,'stock_status',pl.stock_status,'hide_exact_stock',true
  ) order by pl.collection_update_no desc,pl.created_at desc),'[]'::jsonb) into rows
  from latest_line pl
  cross join lateral public.rr_web_window_snapshot_test71(pl.lot_no,null,null,'TEST',1,0)c
  cross join lateral public.rr_web_lot_fields_resolve_v9624(pl.lot_no,'TEST')r
  where c.lot_no=pl.lot_no;

  v_collections:=jsonb_build_array(jsonb_build_object(
    'id',v_root,'display_no','COLLECTION '||v_current.collection_no::text||
      case when v_current.collection_update_no>0 then ' · UPDATE '||v_current.collection_update_no::text else '' end,
    'created_at',v_current.created_at,'lines',(
      with latest_line as(
        select distinct on(l.lot_no) l.*,pc.collection_update_no
        from public.rr_market_partner_collection_v67 pc
        join public.rr_market_partner_collection_line_v67 l on l.collection_id=pc.id
        where coalesce(pc.root_collection_id,pc.id)=v_root
        order by l.lot_no,pc.collection_update_no desc,l.created_at desc
      ) select coalesce(jsonb_agg(jsonb_build_object(
        'lot_no',l.lot_no,'category',l.category,'size_text',l.size_text,
        'image_url',l.primary_image_url,'stock_status',l.stock_status,
        'sale_rate',l.distributor_sale_rate,'discount',l.discount_amount,
        'final_rate',l.final_customer_rate
      ) order by l.collection_update_no desc,l.created_at desc),'[]'::jsonb) from latest_line l
    )
  ));
  if v_latest.id is not null then
    v_requirements:=jsonb_build_array(jsonb_build_object(
      'id',v_latest.id,'display_no',v_latest.requirement_display_no,'status',v_latest.status,
      'created_at',v_latest.created_at,'closed_at',v_latest.customer_closed_at,
      'redzed_pushed_at',v_latest.redzed_pushed_at,'lines',(
        select coalesce(jsonb_agg(jsonb_build_object(
          'id',l.id,'lot_no',l.lot_no,'category',l.category,'size_text',l.size_text,
          'image_url',l.image_url,'qty',l.requested_qty,'rate',l.final_customer_rate
        ) order by l.lot_no),'[]'::jsonb)
        from public.rr_market_partner_order_line_v67 l where l.order_id=v_latest.id
      )
    ));
    v_requirement:=jsonb_build_object('id',v_latest.id,'display_no',v_latest.requirement_display_no,
      'status',v_latest.status,'can_update',v_latest.status='DRAFT','can_close',v_latest.status='DRAFT',
      'customer_closed_at',v_latest.customer_closed_at,'redzed_pushed_at',v_latest.redzed_pushed_at);
    if v_latest.customer_pi_visible and v_latest.pi_ref is not null then
      v_pi:=(select jsonb_build_object('ref',o.pi_ref,'status',o.customer_pi_status,'note',o.customer_pi_note,
        'lines',(select jsonb_agg(jsonb_build_object(
          'id',l.id,'lot_no',l.lot_no,'category',l.category,'size_text',l.size_text,
          'image_url',l.image_url,'requested_qty',l.requested_qty,
          'proposed_qty',coalesce(l.proposed_qty,l.requested_qty),'rate',l.final_customer_rate,
          'decision',l.customer_pi_decision,'customer_qty',l.customer_pi_qty
        ) order by l.lot_no) from public.rr_market_partner_order_line_v67 l where l.order_id=o.id))
      from public.rr_market_partner_order_v67 o where o.id=v_latest.id);
    end if;
    if v_latest.customer_ci_visible and v_latest.ci_ref is not null then
      v_ci:=(select jsonb_build_object('ref',o.ci_ref,'pi_ref',o.pi_ref,
        'lines',(select jsonb_agg(jsonb_build_object(
          'lot_no',l.lot_no,'category',l.category,'size_text',l.size_text,'image_url',l.image_url,
          'qty',coalesce(l.confirmed_qty,l.customer_pi_qty,l.proposed_qty,l.requested_qty),
          'rate',l.final_customer_rate
        ) order by l.lot_no) from public.rr_market_partner_order_line_v67 l where l.order_id=o.id))
      from public.rr_market_partner_order_v67 o where o.id=v_latest.id);
    end if;
  else
    v_requirements:='[]'::jsonb;
  end if;
  return jsonb_build_object('share_id',s.id,'customer_name',s.customer_name,'created_at',s.created_at,
    'rows',rows,'header_title',v_header,'collection_display_no',v_current.collection_display_no,
    'collections',v_collections,'requirements',v_requirements,'requirement',v_requirement,
    'pi',v_pi,'ci',v_ci,'requirement_locked',coalesce(v_latest.status<>'DRAFT',false));
end
$function$
;
revoke all on function public.rr_market_share_snapshot_test71(text) from public,anon,authenticated;

-- Keep audit snapshots, retire only cards in open TEST customer collections.
create table if not exists public.rr_rm_retired_share_cards_test71(
share_id uuid not null references public.rr_market_share_v9420(id),lot_no text not null,retired_at timestamptz not null default now(),reason text not null,primary key(share_id,lot_no));
alter table public.rr_rm_retired_share_cards_test71 enable row level security;
revoke all on public.rr_rm_retired_share_cards_test71 from public,anon,authenticated;

insert into public.rr_rm_retired_share_cards_test71(share_id,lot_no,reason)
select sl.share_id,sl.lot_no,'Readymade mapping / approved positive final rate incomplete'
from public.rr_market_share_lots_v9420 sl join public.rr_market_share_v9420 sh on sh.id=sl.share_id
join public.rr_rm_stock_v849_2c6 rm on rm.lot_no=sl.lot_no and rm.data_mode='TEST'
left join public.rr_collection_send_v9586 cs on cs.share_id=sh.id
left join public.rr_collection_cycle_v9586 cy on cy.id=cs.collection_cycle_id
where sh.data_mode='TEST' and sh.status='ACTIVE' and not coalesce((public.rr_rm_market_readiness_test71(rm.lot_no)->>'market_ready')::boolean,false)
and (cy.id is null or cy.status not in('CLOSED','CLOSED_NO_RESPONSE','CANCELLED','PI_GENERATED','CI_GENERATED'))
on conflict do nothing;

create or replace function public.rr_market_share_view_v9420(p_token text)
returns jsonb language plpgsql security definer set search_path to public as $$
declare d jsonb; sid uuid; closed boolean; filtered jsonb;
begin
d:=public.rr_market_share_snapshot_test71(p_token);sid:=(d->>'share_id')::uuid;
select exists(select 1 from public.rr_collection_send_v9586 cs join public.rr_collection_cycle_v9586 cy on cy.id=cs.collection_cycle_id where cs.share_id=sid and cy.status in('CLOSED','CLOSED_NO_RESPONSE','CANCELLED','PI_GENERATED','CI_GENERATED')) into closed;
if not closed and exists(select 1 from public.rr_market_share_v9420 where id=sid and data_mode='TEST') then
select coalesce(jsonb_agg(e.value order by e.ordinality),'[]') into filtered from jsonb_array_elements(coalesce(d->'rows','[]')) with ordinality e
where not exists(select 1 from public.rr_rm_retired_share_cards_test71 r where r.share_id=sid and r.lot_no=e.value->>'lot_no')
and (not exists(select 1 from public.rr_rm_stock_v849_2c6 s where s.lot_no=e.value->>'lot_no' and s.data_mode='TEST') or coalesce((public.rr_rm_market_readiness_test71(e.value->>'lot_no')->>'market_ready')::boolean,false));
d:=jsonb_set(d,'{rows}',filtered)||jsonb_build_object('retired_card_notice','Only fully mapped, approved-rate Readymade cards are available.');
end if;
return d;
end $$;

create or replace function public.rr_rm_request_approval_test71(p_lot_no text)
returns jsonb language plpgsql security definer set search_path to public as $$
declare role text;s public.rr_rm_stock_v849_2c6%rowtype;n integer;route text;
begin
perform public.rr_fg_assert_user_v787();role:=public.rr_costing_user_scope_v760(null)->>'effective_role';
if role is null or role not in('OWNER','SUPER_ADMIN','ADMIN','MANAGER','ACCOUNTS') then raise exception 'Mapping authority required.';end if;
select * into s from public.rr_rm_stock_v849_2c6 where lot_no=trim(p_lot_no) and data_mode='TEST';
if s.stock_id is null then raise exception 'TEST Readymade lot unavailable.';end if;
if coalesce((public.rr_rm_market_readiness_test71(s.lot_no)->>'market_ready')::boolean,false) then return jsonb_build_object('status','READY');end if;
route:='test70-cb-purchase-real-chat-pilot.html?rc_view=chat&rc_kind=group&rc_id=READYMADE&rc_status=WORKING&rm_mapping=PENDING';
insert into public.rr_targeted_push_outbox_v708(event_key,recipient_worker_id,title,body,route_url,payload)
select 'RM_APPROVAL_TEST71:'||s.stock_id::text,w.worker_id,'Readymade completion / approval required','Lot '||s.lot_no||' · Complete mapping, monthly costing and approve final sale rate.',route,jsonb_build_object('source','RM_APPROVAL_TEST71','lot_no',s.lot_no)
from public.rr_user_profiles p join public.rr_worker_directory_unified_v1 w on w.linked_auth_user_id=p.auth_user_id
where p.is_active and w.is_active and upper(p.role_code) in('OWNER','SUPER_ADMIN','SUPERADMIN')
on conflict(event_key,recipient_worker_id) do nothing;
get diagnostics n=row_count;return jsonb_build_object('status','REQUESTED','new_notifications',n);
end $$;
revoke all on function public.rr_rm_request_approval_test71(text) from public,anon;
grant execute on function public.rr_rm_request_approval_test71(text) to authenticated;

