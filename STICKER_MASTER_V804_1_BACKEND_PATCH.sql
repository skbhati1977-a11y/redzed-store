begin;

-- REAL FACTORY · Sticker/Metal ID Master frontend read helpers
-- Security-definer RPCs prevent frontend list from depending on direct table RLS.

create or replace function public.rr_accessory_master_list_v804(
  p_item_type text,
  p_data_mode text default 'TEST'
)
returns table(
  id uuid,
  item_no text,
  item_name text,
  item_attr text,
  is_active boolean,
  physical_stock_qty numeric,
  open_requirement_qty numeric,
  reserved_qty numeric,
  free_stock_qty numeric,
  req_now_qty numeric,
  weighted_avg_cost_per_piece numeric,
  image_url text,
  image_media_id uuid,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_type text:=upper(trim(coalesce(p_item_type,'')));
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
begin
  if v_type not in ('STICKER','METAL_ID') then raise exception 'Item Type must be STICKER or METAL_ID.'; end if;
  if v_mode not in ('TEST','REAL') then raise exception 'Data Mode must be TEST or REAL.'; end if;

  if v_type='STICKER' then
    return query
    select
      s.id,
      s.sticker_no,
      coalesce(s.sticker_name,''),
      s.sticker_quality,
      s.is_active,
      coalesce(b.physical_stock_qty,0),
      coalesce(b.open_requirement_qty,0),
      least(coalesce(b.physical_stock_qty,0),coalesce(b.open_requirement_qty,0)),
      coalesce(b.free_stock_qty,0),
      coalesce(b.req_now_qty,0),
      coalesce(b.weighted_avg_cost_per_piece,0),
      lm.file_url,
      lm.id,
      s.created_at,
      s.updated_at
    from public.rr_sticker_master_v803 s
    left join public.rr_accessory_stock_balance_v804 b
      on b.sticker_master_id=s.id and b.data_mode=v_mode and b.item_type='STICKER'
    left join lateral (
      select m.id,m.file_url
      from public.rr_media m
      where m.entity_type='sticker_master_v803'
        and m.entity_id=s.id::text
      order by m.is_cover desc,m.created_at desc
      limit 1
    ) lm on true
    order by s.created_at desc,s.sticker_no;
  else
    return query
    select
      m.id,
      m.metal_id_no,
      coalesce(m.metal_id_name,''),
      m.id_size,
      m.is_active,
      coalesce(b.physical_stock_qty,0),
      coalesce(b.open_requirement_qty,0),
      least(coalesce(b.physical_stock_qty,0),coalesce(b.open_requirement_qty,0)),
      coalesce(b.free_stock_qty,0),
      coalesce(b.req_now_qty,0),
      coalesce(b.weighted_avg_cost_per_piece,0),
      lm.file_url,
      lm.id,
      m.created_at,
      m.updated_at
    from public.rr_metal_id_master_v803 m
    left join public.rr_accessory_stock_balance_v804 b
      on b.metal_id_master_id=m.id and b.data_mode=v_mode and b.item_type='METAL_ID'
    left join lateral (
      select x.id,x.file_url
      from public.rr_media x
      where x.entity_type='metal_id_master_v803'
        and x.entity_id=m.id::text
      order by x.is_cover desc,x.created_at desc
      limit 1
    ) lm on true
    order by m.created_at desc,m.metal_id_no;
  end if;
end;
$$;

grant execute on function public.rr_accessory_master_list_v804(text,text) to authenticated;

create or replace function public.rr_accessory_purchase_history_v804(
  p_item_type text,
  p_master_id uuid,
  p_data_mode text default 'TEST'
)
returns table(
  id uuid,
  entry_type text,
  vendor_name text,
  bill_no text,
  bill_date date,
  qty numeric,
  rate_per_piece numeric,
  notes text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_type text:=upper(trim(coalesce(p_item_type,'')));
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
begin
  if v_type not in ('STICKER','METAL_ID') then raise exception 'Item Type must be STICKER or METAL_ID.'; end if;
  if p_master_id is null then raise exception 'Master item required.'; end if;
  return query
  select l.id,l.entry_type,l.vendor_name,l.bill_no,l.bill_date,l.qty,l.rate_per_piece,l.notes,l.created_at
  from public.rr_accessory_purchase_ledger_v804 l
  where l.data_mode=v_mode
    and l.item_type=v_type
    and ((v_type='STICKER' and l.sticker_master_id=p_master_id)
      or (v_type='METAL_ID' and l.metal_id_master_id=p_master_id))
  order by l.created_at desc;
end;
$$;

grant execute on function public.rr_accessory_purchase_history_v804(text,uuid,text) to authenticated;

notify pgrst, 'reload schema';
commit;
