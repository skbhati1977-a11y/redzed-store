-- TEST71 V3: one CB requirement becomes one media-rich receipt attachment.
-- The first manual WhatsApp share carries one permanent LIVE UPDATE link.
-- Partial receipt keeps the projection live; full received confirmation retires it
-- to CLOSE REQUIREMENT without exposing the rest of the application.
begin;

alter table public.rr_cb_requirement_send_log_v1
  add column if not exists share_event_id uuid,
  add column if not exists share_channel text,
  add column if not exists receipt_no text,
  add column if not exists attachment_manifest jsonb,
  add column if not exists receipt_snapshot jsonb;

create unique index if not exists rr_cb_receipt_share_event_v2_idx
on public.rr_cb_requirement_send_log_v1(share_event_id)
where share_event_id is not null;

create table if not exists public.rr_cb_requirement_live_link_v1(
  id uuid primary key default gen_random_uuid(),
  cb_id uuid not null references public.rr_fabric_purchases(id) on delete cascade,
  requirement_type text not null,
  source_id uuid not null,
  short_code text not null unique,
  share_note text,
  is_active boolean not null default true,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revoked_at timestamptz,
  last_opened_at timestamptz,
  retired_at timestamptz,
  last_status text not null default 'LIVE_UPDATE',
  constraint rr_cb_requirement_live_link_type_chk
    check(requirement_type in('MATERIAL','STICKER','METAL_ID')),
  unique(cb_id,requirement_type,source_id)
);

alter table public.rr_cb_requirement_live_link_v1
  add column if not exists retired_at timestamptz,
  add column if not exists last_status text not null default 'LIVE_UPDATE';

alter table public.rr_cb_requirement_live_link_v1 enable row level security;
revoke all on table public.rr_cb_requirement_live_link_v1 from public,anon,authenticated;
grant all on table public.rr_cb_requirement_live_link_v1 to service_role;

create index if not exists rr_cb_requirement_live_link_lookup_v1_idx
on public.rr_cb_requirement_live_link_v1(short_code)
where is_active;

create table if not exists public.rr_cb_requirement_receipt_confirmation_v1(
  id uuid primary key default gen_random_uuid(),
  cb_id uuid not null references public.rr_fabric_purchases(id) on delete cascade,
  requirement_type text not null,
  source_id uuid not null,
  received_qty numeric not null default 0 check(received_qty>=0),
  unit text not null,
  fully_received_confirmed boolean not null default false,
  source_reference text,
  confirmed_by uuid default auth.uid(),
  confirmed_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint rr_cb_requirement_receipt_confirmation_type_chk
    check(requirement_type in('MATERIAL','STICKER','METAL_ID')),
  unique(cb_id,requirement_type,source_id)
);

alter table public.rr_cb_requirement_receipt_confirmation_v1 enable row level security;
revoke all on table public.rr_cb_requirement_receipt_confirmation_v1
from public,anon,authenticated;
grant all on table public.rr_cb_requirement_receipt_confirmation_v1 to service_role;

create or replace function public.rr_cb_requirement_colour_projection_v1(
  p_cb_id uuid,
  p_requirement_type text,
  p_source_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path to 'public','pg_temp'
as $function$
with req as (
  select r.*,
         public.rr_cb_profile_yield_v1(r.cb_unit_id) yield_snapshot
  from public.rr_cb_derived_requirement_v1 r
  where r.cb_id=p_cb_id
    and r.active
    and r.requirement_type=upper(trim(p_requirement_type))
    and r.source_id=p_source_id
    and r.required_qty>0
),
appx as (
  select r.cb_unit_id,r.root_set_no,r.profile_label,r.unit,r.qty_per_piece,
         c.id colour_id,c.col_no colour_no,
         coalesce(nullif(c.colour_name,''),'C'||c.col_no) colour_name,
         c.image_url thumbnail_url,
         coalesce(nullif(y.row->>'estimated_pcs','')::numeric,0) appx_pcs
  from req r
  join public.rr_cb_colours c on c.cb_id=r.cb_id
  left join lateral (
    select x.row
    from jsonb_array_elements(coalesce(r.yield_snapshot->'rows','[]'::jsonb)) x(row)
    where nullif(x.row->>'colour_no','')::integer=c.col_no
    limit 1
  ) y on true
),
actual_rows as (
  select r.cb_unit_id,b.cb_colour_id colour_id,
         greatest(coalesce(b.actual_qty,b.planned_qty,0),0)::numeric actual_pcs
  from req r
  join public.rr_cutting_lots_v3 l on l.cb_unit_id=r.cb_unit_id
    and upper(coalesce(l.status,'')) not in('CANCELLED','CANCELED')
  join public.rr_cutting_breakup_v3 b on b.cutting_lot_id=l.id

  union all

  select r.cb_unit_id,b.cb_colour_id,
         greatest(coalesce(b.planned_qty,0),0)::numeric
  from req r
  join public.rr_production_lots l on l.cb_unit_id=r.cb_unit_id
    and upper(coalesce(l.status,'')) not in('CANCELLED','CANCELED')
  join public.rr_production_lot_breakup_v3 b on b.production_lot_id=l.id
),
actual as (
  select a.cb_unit_id,a.colour_id,sum(a.actual_pcs)::numeric actual_pcs
  from actual_rows a
  group by a.cb_unit_id,a.colour_id
),
base as (
  select a.*,
         nullif(coalesce(x.actual_pcs,0),0) actual_pcs,
         case when coalesce(x.actual_pcs,0)>0 then x.actual_pcs else a.appx_pcs end effective_pcs,
         case when upper(a.unit)='KG'
           then coalesce(a.qty_per_piece,0)/1000.0
           else coalesce(a.qty_per_piece,0)
         end qty_factor,
         case when coalesce(x.actual_pcs,0)>0 then 'ACTUAL' else 'APPX' end source_mode
  from appx a
  left join actual x on x.cb_unit_id=a.cb_unit_id and x.colour_id=a.colour_id
  where a.appx_pcs>0 or coalesce(x.actual_pcs,0)>0
),
calc as (
  select b.*,
         round((b.appx_pcs*b.qty_factor)::numeric,case when upper(b.unit)='KG' then 3 else 0 end) appx_required_qty,
         case when b.actual_pcs is null then null
           else round((b.actual_pcs*b.qty_factor)::numeric,case when upper(b.unit)='KG' then 3 else 0 end)
         end actual_required_qty,
         round((b.effective_pcs*b.qty_factor)::numeric,case when upper(b.unit)='KG' then 3 else 0 end) effective_required_qty
  from base b
),
totals as (
  select count(*) row_count,
         count(*) filter(where source_mode='ACTUAL') actual_row_count,
         coalesce(sum(appx_pcs),0) appx_pcs,
         coalesce(sum(actual_pcs),0) actual_pcs,
         coalesce(sum(effective_pcs),0) effective_pcs,
         coalesce(sum(appx_required_qty),0) appx_required_qty,
         coalesce(sum(actual_required_qty),0) actual_required_qty,
         coalesce(sum(effective_required_qty),0) effective_required_qty
  from calc
)
select jsonb_build_object(
  'mode',case
    when totals.actual_row_count=0 then 'APPX'
    when totals.actual_row_count=totals.row_count then 'ACTUAL'
    else 'HYBRID'
  end,
  'rows',coalesce((
    select jsonb_agg(jsonb_build_object(
      'set_no',c.root_set_no,
      'profile_label',c.profile_label,
      'colour_id',c.colour_id,
      'colour_no',c.colour_no,
      'colour_name',c.colour_name,
      'thumbnail_url',c.thumbnail_url,
      'appx_pcs',c.appx_pcs,
      'actual_pcs',c.actual_pcs,
      'effective_pcs',c.effective_pcs,
      'difference_pcs',case when c.actual_pcs is null then null else c.actual_pcs-c.appx_pcs end,
      'qty_per_piece',c.qty_per_piece,
      'unit',c.unit,
      'appx_required_qty',c.appx_required_qty,
      'actual_required_qty',c.actual_required_qty,
      'required_qty',c.effective_required_qty,
      'difference_qty',case when c.actual_pcs is null then null else c.effective_required_qty-c.appx_required_qty end,
      'source_mode',c.source_mode
    ) order by c.root_set_no,c.profile_label,c.colour_no)
    from calc c
  ),'[]'::jsonb),
  'totals',jsonb_build_object(
    'row_count',totals.row_count,
    'actual_row_count',totals.actual_row_count,
    'appx_pcs',totals.appx_pcs,
    'actual_pcs',totals.actual_pcs,
    'effective_pcs',totals.effective_pcs,
    'appx_required_qty',totals.appx_required_qty,
    'actual_required_qty',totals.actual_required_qty,
    'effective_required_qty',totals.effective_required_qty,
    'difference_qty',totals.effective_required_qty-totals.appx_required_qty
  )
)
from totals
$function$;

revoke all on function public.rr_cb_requirement_colour_projection_v1(uuid,text,uuid)
from public,anon,authenticated;

create or replace function public.rr_cb_requirement_fulfilment_projection_v1(
  p_cb_id uuid,
  p_requirement_type text,
  p_source_id uuid,
  p_required_qty numeric,
  p_unit text
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_type text:=upper(trim(coalesce(p_requirement_type,'')));
  v_required numeric:=greatest(coalesce(p_required_qty,0),0);
  v_purchase_received numeric:=0;
  v_purchase_rows integer:=0;
  v_purchase_pending integer:=0;
  v_manual public.rr_cb_requirement_receipt_confirmation_v1%rowtype;
  v_received numeric:=0;
  v_confirmed boolean:=false;
  v_confirmed_at timestamptz;
  v_source text:='NONE';
begin
  if v_type='MATERIAL' then
    select
      coalesce(sum(
        case
          when upper(coalesce(e.requirement_state,''))='CONFIRMED'
           and nullif(trim(coalesce(e.vendor_bill_no,'')),'') is not null
           and e.bill_date is not null
          then greatest(coalesce(nullif(e.original_quantity,0),e.quantity,0),0)
          else 0
        end
      ),0),
      count(*),
      count(*) filter(where
        upper(coalesce(e.requirement_state,''))<>'CONFIRMED'
        or nullif(trim(coalesce(e.vendor_bill_no,'')),'') is null
        or e.bill_date is null
      )
    into v_purchase_received,v_purchase_rows,v_purchase_pending
    from public.rr_cb_purchase_entries e
    where e.cb_id=p_cb_id
      and e.material_category_id=p_source_id
      and upper(coalesce(e.operation_status,'ACTIVE')) not in(
        'RETURNED','CANCELLED','CANCELED','VOID','REVERSED','TEST_RETIRED'
      );
  end if;

  select * into v_manual
  from public.rr_cb_requirement_receipt_confirmation_v1 c
  where c.cb_id=p_cb_id
    and c.requirement_type=v_type
    and c.source_id=p_source_id;

  v_received:=greatest(
    coalesce(v_purchase_received,0),
    coalesce(v_manual.received_qty,0)
  );

  if coalesce(v_manual.fully_received_confirmed,false)
     and coalesce(v_manual.received_qty,0)+0.0005>=v_required then
    v_confirmed:=true;
    v_confirmed_at:=v_manual.confirmed_at;
    v_source:='RECEIVING_CONFIRMATION';
  elsif v_type='MATERIAL'
     and v_purchase_rows>0
     and v_purchase_pending=0
     and v_purchase_received+0.0005>=v_required then
    v_confirmed:=true;
    select max(e.updated_at) into v_confirmed_at
    from public.rr_cb_purchase_entries e
    where e.cb_id=p_cb_id
      and e.material_category_id=p_source_id
      and upper(coalesce(e.requirement_state,''))='CONFIRMED'
      and nullif(trim(coalesce(e.vendor_bill_no,'')),'') is not null
      and e.bill_date is not null
      and upper(coalesce(e.operation_status,'ACTIVE')) not in(
        'RETURNED','CANCELLED','CANCELED','VOID','REVERSED','TEST_RETIRED'
      );
    v_source:='CB_PURCHASE_CONFIRMED';
  elsif v_received>0 then
    v_source:=case when coalesce(v_manual.received_qty,0)>=coalesce(v_purchase_received,0)
      then 'RECEIVING_CONFIRMATION' else 'CB_PURCHASE_PARTIAL' end;
  end if;

  return jsonb_build_object(
    'status',case when v_confirmed then 'CLOSED' when v_received>0 then 'PARTIAL' else 'OPEN' end,
    'label',case when v_confirmed then 'CLOSE REQUIREMENT' else 'LIVE UPDATE' end,
    'fully_received_confirmed',v_confirmed,
    'required_qty',v_required,
    'received_qty',v_received,
    'balance_qty',greatest(v_required-v_received,0),
    'unit',upper(coalesce(nullif(trim(p_unit),''),'PCS')),
    'confirmation_source',v_source,
    'confirmed_at',v_confirmed_at
  );
end
$function$;

revoke all on function public.rr_cb_requirement_fulfilment_projection_v1(
  uuid,text,uuid,numeric,text
) from public,anon,authenticated;

create or replace function public.rr_cb_requirement_received_confirm_v1(
  p_cb_id uuid,
  p_requirement_type text,
  p_source_id uuid,
  p_received_qty numeric,
  p_unit text,
  p_source_reference text default null,
  p_fully_received_confirmed boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_type text:=upper(trim(coalesce(p_requirement_type,'')));
  v_required numeric;
  v_unit text;
  v_row public.rr_cb_requirement_receipt_confirmation_v1%rowtype;
begin
  perform public.rr_cb_department_assert_authority_v600();

  if v_type not in('MATERIAL','STICKER','METAL_ID') then
    raise exception 'Requirement type invalid.';
  end if;
  if coalesce(p_received_qty,0)<0 then
    raise exception 'Received quantity cannot be negative.';
  end if;

  select sum(r.required_qty),max(r.unit)
  into v_required,v_unit
  from public.rr_cb_derived_requirement_v1 r
  where r.cb_id=p_cb_id and r.active
    and r.requirement_type=v_type and r.source_id=p_source_id
    and r.required_qty>0;

  if v_required is null then raise exception 'Active requirement not found.'; end if;
  if upper(trim(coalesce(p_unit,v_unit,'')))<>upper(trim(coalesce(v_unit,''))) then
    raise exception 'Received unit does not match requirement unit.';
  end if;
  if coalesce(p_fully_received_confirmed,false)
     and coalesce(p_received_qty,0)+0.0005<v_required then
    raise exception 'Full receipt cannot be confirmed below the current required quantity.';
  end if;

  insert into public.rr_cb_requirement_receipt_confirmation_v1(
    cb_id,requirement_type,source_id,received_qty,unit,
    fully_received_confirmed,source_reference,confirmed_by,confirmed_at,updated_at
  ) values(
    p_cb_id,v_type,p_source_id,coalesce(p_received_qty,0),upper(v_unit),
    coalesce(p_fully_received_confirmed,false),
    nullif(left(trim(coalesce(p_source_reference,'')),160),''),
    auth.uid(),case when coalesce(p_fully_received_confirmed,false) then now() else null end,now()
  )
  on conflict(cb_id,requirement_type,source_id) do update
  set received_qty=excluded.received_qty,
      unit=excluded.unit,
      fully_received_confirmed=excluded.fully_received_confirmed,
      source_reference=excluded.source_reference,
      confirmed_by=excluded.confirmed_by,
      confirmed_at=case when excluded.fully_received_confirmed then now() else null end,
      updated_at=now()
  returning * into v_row;

  return public.rr_cb_requirement_fulfilment_projection_v1(
    p_cb_id,v_type,p_source_id,v_required,v_unit
  )||jsonb_build_object('ok',true,'confirmation_id',v_row.id);
end
$function$;

revoke all on function public.rr_cb_requirement_received_confirm_v1(
  uuid,text,uuid,numeric,text,text,boolean
) from public,anon,authenticated;
grant execute on function public.rr_cb_requirement_received_confirm_v1(
  uuid,text,uuid,numeric,text,text,boolean
) to authenticated;

create or replace function public.rr_cb_requirement_live_link_v1(
  p_cb_id uuid,
  p_requirement_type text,
  p_source_id uuid,
  p_short_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_type text:=upper(trim(coalesce(p_requirement_type,'')));
  v_link public.rr_cb_requirement_live_link_v1%rowtype;
  v_code text;
  v_try integer:=0;
begin
  perform public.rr_cb_department_assert_authority_v600();
  if v_type not in('MATERIAL','STICKER','METAL_ID') then
    raise exception 'Requirement type invalid.';
  end if;
  if not exists(
    select 1 from public.rr_cb_derived_requirement_v1 r
    where r.cb_id=p_cb_id and r.active and r.requirement_type=v_type
      and r.source_id=p_source_id and r.required_qty>0
  ) then raise exception 'Active requirement not found.'; end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'CB_LIVE_LINK:'||p_cb_id::text||':'||v_type||':'||p_source_id::text,3
  ));

  select * into v_link
  from public.rr_cb_requirement_live_link_v1 l
  where l.cb_id=p_cb_id and l.requirement_type=v_type and l.source_id=p_source_id
  for update;

  if v_link.id is null then
    loop
      v_try:=v_try+1;
      v_code:=upper(substr(encode(extensions.gen_random_bytes(12),'hex'),1,20));
      begin
        insert into public.rr_cb_requirement_live_link_v1(
          cb_id,requirement_type,source_id,short_code,share_note,created_by
        ) values(
          p_cb_id,v_type,p_source_id,v_code,
          nullif(left(trim(coalesce(p_short_note,'')),240),''),auth.uid()
        ) returning * into v_link;
        exit;
      exception when unique_violation then
        if v_try>=8 then raise; end if;
      end;
    end loop;
  else
    update public.rr_cb_requirement_live_link_v1
    set share_note=coalesce(nullif(left(trim(coalesce(p_short_note,'')),240),''),share_note),
        is_active=true,revoked_at=null,updated_at=now()
    where id=v_link.id
    returning * into v_link;
  end if;

  return jsonb_build_object(
    'ok',true,
    'short_code',v_link.short_code,
    'label','LIVE UPDATE',
    'permanent',true
  );
end
$function$;

revoke all on function public.rr_cb_requirement_live_link_v1(uuid,text,uuid,text)
from public,anon,authenticated;
grant execute on function public.rr_cb_requirement_live_link_v1(uuid,text,uuid,text)
to authenticated;

create or replace function public.rr_cb_requirement_live_projection_v1(p_short_code text)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_link public.rr_cb_requirement_live_link_v1%rowtype;
  v_result jsonb;
  v_colour jsonb;
  v_fulfilment jsonb;
  v_required numeric:=0;
  v_unit text;
  v_closed boolean:=false;
begin
  select * into v_link
  from public.rr_cb_requirement_live_link_v1 l
  where l.short_code=upper(trim(coalesce(p_short_code,'')))
    and l.is_active and l.revoked_at is null;

  if v_link.id is null then raise exception 'LIVE UPDATE link unavailable.'; end if;

  v_colour:=public.rr_cb_requirement_colour_projection_v1(
    v_link.cb_id,v_link.requirement_type,v_link.source_id
  );

  select jsonb_build_object(
    'ok',true,
    'cb_no',max(fp.cb_no),
    'requirement_type',v_link.requirement_type,
    'item_no',max(r.item_no),
    'item_name',max(r.item_name),
    'profile_labels',to_jsonb(array_agg(distinct r.profile_label order by r.profile_label)),
    'appx_pcs',coalesce((v_colour#>>'{totals,appx_pcs}')::numeric,0),
    'cutting_pcs',coalesce((v_colour#>>'{totals,actual_pcs}')::numeric,0),
    'required_qty',coalesce((v_colour#>>'{totals,effective_required_qty}')::numeric,sum(r.required_qty),0),
    'appx_required_qty',coalesce((v_colour#>>'{totals,appx_required_qty}')::numeric,0),
    'difference_qty',coalesce((v_colour#>>'{totals,difference_qty}')::numeric,0),
    'unit',max(r.unit),
    'revision_no',max(r.revision_no),
    'mode',max(r.fulfilment_method),
    'supplier_name',max(r.supplier_name),
    'short_note',coalesce(v_link.share_note,'Please confirm availability and expected delivery.'),
    'projection_mode',coalesce(v_colour->>'mode','APPX'),
    'colour_projection',coalesce(v_colour,'{}'::jsonb),
    'updated_at',greatest(max(r.updated_at),max(fp.updated_at)),
    'receipt_no','CB'||max(fp.cb_no)||'-'||case v_link.requirement_type
      when 'MATERIAL' then 'MAT' when 'STICKER' then 'STK' else 'MID' end||
      '-'||left(v_link.source_id::text,8)||'-R'||max(r.revision_no)
  ) into v_result
  from public.rr_cb_derived_requirement_v1 r
  join public.rr_fabric_purchases fp on fp.id=r.cb_id
  where r.cb_id=v_link.cb_id and r.active
    and r.requirement_type=v_link.requirement_type
    and r.source_id=v_link.source_id and r.required_qty>0;

  if v_result->>'cb_no' is null then raise exception 'Requirement is no longer available.'; end if;

  v_required:=coalesce((v_result->>'required_qty')::numeric,0);
  v_unit:=coalesce(v_result->>'unit','PCS');
  v_fulfilment:=public.rr_cb_requirement_fulfilment_projection_v1(
    v_link.cb_id,v_link.requirement_type,v_link.source_id,v_required,v_unit
  );
  v_closed:=coalesce((v_fulfilment->>'fully_received_confirmed')::boolean,false);
  v_result:=v_result||jsonb_build_object(
    'live',not v_closed,
    'closed',v_closed,
    'label',case when v_closed then 'CLOSE REQUIREMENT' else 'LIVE UPDATE' end,
    'link_state',case when v_closed then 'CLOSED' else 'LIVE_UPDATE' end,
    'fulfilment',v_fulfilment
  );

  update public.rr_cb_requirement_live_link_v1
  set last_opened_at=now(),
      last_status=case when v_closed then 'CLOSED' else 'LIVE_UPDATE' end,
      retired_at=case
        when v_closed then coalesce(retired_at,now())
        else null
      end,
      updated_at=case when last_status is distinct from
        (case when v_closed then 'CLOSED' else 'LIVE_UPDATE' end)
        then now() else updated_at end
  where id=v_link.id;

  return v_result;
end
$function$;

revoke all on function public.rr_cb_requirement_live_projection_v1(text)
from public,anon,authenticated;
grant execute on function public.rr_cb_requirement_live_projection_v1(text)
to anon,authenticated;

create or replace function public.rr_cb_requirement_share_context_v1(
  p_cb_id uuid,
  p_requirement_type text,
  p_source_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_type text:=upper(trim(coalesce(p_requirement_type,'')));
  v_cb_no text;
  v_short_note text;
  v_item_no text;
  v_item_name text;
  v_unit text;
  v_fulfil text;
  v_appx numeric:=0;
  v_cutting numeric:=0;
  v_required numeric:=0;
  v_supplier_name text;
  v_revision integer:=1;
  v_profiles text[];
  v_attachments jsonb:='[]'::jsonb;
  v_colour_projection jsonb:='{}'::jsonb;
  v_fulfilment jsonb:='{}'::jsonb;
begin
  perform public.rr_cb_department_assert_authority_v600();

  if v_type not in('MATERIAL','STICKER','METAL_ID') then
    raise exception 'Requirement type invalid.';
  end if;

  select fp.cb_no,nullif(trim(fp.notes),'')
  into v_cb_no,v_short_note
  from public.rr_fabric_purchases fp
  where fp.id=p_cb_id;

  if v_cb_no is null then raise exception 'CB not found.'; end if;

  select max(r.item_no),max(r.item_name),max(r.unit),max(r.fulfilment_method),
         sum(coalesce(r.appx_pcs,case when r.basis='YIELD' then r.basis_pcs else 0 end)),
         sum(coalesce(r.cutting_pcs,case when r.basis='CUTTING_ACTUAL' then r.basis_pcs else 0 end)),
         sum(r.required_qty),max(r.supplier_name),max(r.revision_no),
         array_agg(distinct r.profile_label order by r.profile_label)
  into v_item_no,v_item_name,v_unit,v_fulfil,v_appx,v_cutting,v_required,
       v_supplier_name,v_revision,v_profiles
  from public.rr_cb_derived_requirement_v1 r
  where r.cb_id=p_cb_id
    and r.active
    and r.requirement_type=v_type
    and r.source_id=p_source_id
    and r.required_qty>0;

  if v_item_name is null then raise exception 'Active requirement not found.'; end if;

  with req as (
    select distinct r.cb_unit_id,r.profile_label,r.root_set_no
    from public.rr_cb_derived_requirement_v1 r
    where r.cb_id=p_cb_id
      and r.active
      and r.requirement_type=v_type
      and r.source_id=p_source_id
      and r.required_qty>0
  ),
  requirement_item_rows as (
    select 10 sort_group,0 root_set_no,'' profile_label,
           'ITEM' kind,
           'ITEM · '||coalesce(mc.category_name,v_item_name) label,
           med.file_url
    from public.rr_material_categories mc
    left join public.rr_material_master_v805 mm on mm.id=mc.material_master_id
    left join lateral (
      select m.file_url
      from public.rr_media m
      where m.entity_type='material_master_v805'
        and m.entity_id=mm.id::text
        and nullif(m.file_url,'') is not null
      order by coalesce(m.is_cover,false) desc,coalesce(m.sort_order,999),m.created_at
      limit 1
    ) med on true
    where v_type='MATERIAL' and mc.id=p_source_id and med.file_url is not null

    union all

    select 10,0,'','STICKER',
           'STICKER · '||coalesce(sm.sticker_no,'')||
             case when nullif(sm.sticker_name,'') is not null then ' · '||sm.sticker_name else '' end,
           coalesce(med.file_url,nullif(sm.image_url,''))
    from public.rr_sticker_master_library_v803 sm
    left join lateral (
      select m.file_url
      from public.rr_media m
      where m.entity_type='sticker_master_v803'
        and m.entity_id=sm.id::text
        and nullif(m.file_url,'') is not null
      order by coalesce(m.is_cover,false) desc,coalesce(m.sort_order,999),m.created_at
      limit 1
    ) med on true
    where v_type='STICKER' and sm.id=p_source_id
      and coalesce(med.file_url,nullif(sm.image_url,'')) is not null

    union all

    select 10,0,'','METAL ID',
           'METAL ID · '||coalesce(mm.metal_id_no,'')||
             case when nullif(mm.metal_id_name,'') is not null then ' · '||mm.metal_id_name else '' end,
           coalesce(med.file_url,nullif(mm.image_url,''))
    from public.rr_metal_id_master_library_v803 mm
    left join lateral (
      select m.file_url
      from public.rr_media m
      where m.entity_type='metal_id_master_v803'
        and m.entity_id=mm.id::text
        and nullif(m.file_url,'') is not null
      order by coalesce(m.is_cover,false) desc,coalesce(m.sort_order,999),m.created_at
      limit 1
    ) med on true
    where v_type='METAL_ID' and mm.id=p_source_id
      and coalesce(med.file_url,nullif(mm.image_url,'')) is not null
  ),
  art_rows as (
    select 20 sort_group,q.root_set_no,coalesce(q.profile_label,'') profile_label,
           'ART' kind,
           coalesce(q.profile_label||' · ','')||'ART '||coalesce(am.art_no,'')||
             case when nullif(am.item_name,'') is not null then ' · '||am.item_name else '' end label,
           med.file_url
    from req q
    join public.rr_cb_art_assignments ca on ca.cb_id=q.cb_unit_id
    join public.rr_art_master am on am.id=ca.art_id
    left join lateral (
      select x.file_url
      from (
        select m.file_url,0 source_rank,coalesce(m.is_cover,false) is_cover,
               coalesce(m.sort_order,999) sort_order,m.created_at
        from public.rr_media m
        where m.entity_type='art'
          and m.entity_id=am.id::text
          and nullif(m.file_url,'') is not null
        union all
        select p.image_url,1,false,999,p.created_at
        from public.products p
        where upper(trim(p.art_no))=upper(trim(am.art_no))
          and nullif(p.image_url,'') is not null
      ) x
      order by x.source_rank,x.is_cover desc,x.sort_order,x.created_at
      limit 1
    ) med on true
    where med.file_url is not null
  ),
  print_rows as (
    select 30 sort_group,q.root_set_no,coalesce(q.profile_label,'') profile_label,
           'PRINT' kind,
           coalesce(q.profile_label||' · ','')||'PRINT '||coalesce(pm.print_no,'')||
             case when nullif(pm.print_name,'') is not null then ' · '||pm.print_name else '' end label,
           coalesce(nullif(pm.garment_preview_url,''),nullif(pm.artwork_url,''),med.file_url) file_url
    from req q
    join public.rr_cb_art_assignments ca on ca.cb_id=q.cb_unit_id
    join public.rr_cb_print_assignments pa on pa.assignment_id=ca.id
    join public.rr_print_master pm on pm.id=pa.print_id
    left join lateral (
      select m.file_url
      from public.rr_media m
      where m.entity_type='printing'
        and m.entity_id=pm.id::text
        and nullif(m.file_url,'') is not null
      order by coalesce(m.is_cover,false) desc,coalesce(m.sort_order,999),m.created_at
      limit 1
    ) med on true
    where coalesce(nullif(pm.garment_preview_url,''),nullif(pm.artwork_url,''),med.file_url) is not null
  ),
  linked_sticker_rows as (
    select 40 sort_group,q.root_set_no,coalesce(q.profile_label,'') profile_label,
           'STICKER' kind,
           coalesce(q.profile_label||' · ','')||'STICKER '||coalesce(sm.sticker_no,'')||
             case when nullif(sm.sticker_name,'') is not null then ' · '||sm.sticker_name else '' end label,
           coalesce(med.file_url,nullif(sm.image_url,'')) file_url
    from req q
    join public.rr_cb_art_assignments ca on ca.cb_id=q.cb_unit_id
    join public.rr_cb_sticker_assignments sa on sa.assignment_id=ca.id
    join public.rr_art_sticker_instructions si on si.id=sa.sticker_instruction_id and si.is_active
    join public.rr_sticker_master_library_v803 sm on sm.id=si.sticker_master_id
    left join lateral (
      select m.file_url
      from public.rr_media m
      where m.entity_type='sticker_master_v803'
        and m.entity_id=sm.id::text
        and nullif(m.file_url,'') is not null
      order by coalesce(m.is_cover,false) desc,coalesce(m.sort_order,999),m.created_at
      limit 1
    ) med on true
    where coalesce(med.file_url,nullif(sm.image_url,'')) is not null
  ),
  linked_metal_rows as (
    select 50 sort_group,q.root_set_no,coalesce(q.profile_label,'') profile_label,
           'METAL ID' kind,
           coalesce(q.profile_label||' · ','')||'METAL ID '||coalesce(mm.metal_id_no,'')||
             case when nullif(mm.metal_id_name,'') is not null then ' · '||mm.metal_id_name else '' end label,
           coalesce(med.file_url,nullif(mm.image_url,'')) file_url
    from req q
    join public.rr_cb_art_assignments ca on ca.cb_id=q.cb_unit_id
    join public.rr_cb_metal_id_assignments_v801 ma on ma.assignment_id=ca.id
    join public.rr_art_metal_id_instructions_v801 mi on mi.id=ma.metal_id_instruction_id and mi.is_active
    join public.rr_metal_id_master_library_v803 mm on mm.id=mi.metal_id_master_id
    left join lateral (
      select m.file_url
      from public.rr_media m
      where m.entity_type='metal_id_master_v803'
        and m.entity_id=mm.id::text
        and nullif(m.file_url,'') is not null
      order by coalesce(m.is_cover,false) desc,coalesce(m.sort_order,999),m.created_at
      limit 1
    ) med on true
    where coalesce(med.file_url,nullif(mm.image_url,'')) is not null
  ),
  colour_rows as (
    select 60 sort_group,c.col_no root_set_no,'' profile_label,
           'ITEM / COLOUR' kind,
           'ITEM / COLOUR '||c.col_no||
             case when nullif(c.colour_name,'') is not null then ' · '||c.colour_name else '' end label,
           c.image_url file_url
    from public.rr_cb_colours c
    where c.cb_id=p_cb_id and nullif(c.image_url,'') is not null
  ),
  all_rows as (
    select * from requirement_item_rows
    union all select * from art_rows
    union all select * from print_rows
    union all select * from linked_sticker_rows
    union all select * from linked_metal_rows
    union all select * from colour_rows
  ),
  dedup as (
    select distinct on (file_url)
           sort_group,root_set_no,profile_label,kind,label,file_url
    from all_rows
    where nullif(file_url,'') is not null
    order by file_url,sort_group,root_set_no,label
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'kind',kind,
        'label',label,
        'profile_label',nullif(profile_label,''),
        'url',file_url
      )
      order by sort_group,root_set_no,label
    ),
    '[]'::jsonb
  )
  into v_attachments
  from dedup;

  v_colour_projection:=public.rr_cb_requirement_colour_projection_v1(
    p_cb_id,v_type,p_source_id
  );
  if coalesce((v_colour_projection#>>'{totals,row_count}')::integer,0)>0 then
    v_appx:=coalesce((v_colour_projection#>>'{totals,appx_pcs}')::numeric,v_appx,0);
    v_cutting:=coalesce((v_colour_projection#>>'{totals,actual_pcs}')::numeric,v_cutting,0);
    v_required:=coalesce(
      (v_colour_projection#>>'{totals,effective_required_qty}')::numeric,
      v_required,0
    );
  end if;
  v_fulfilment:=public.rr_cb_requirement_fulfilment_projection_v1(
    p_cb_id,v_type,p_source_id,v_required,v_unit
  );

  return jsonb_build_object(
    'ok',true,
    'receipt_version','V3_LIVE_SINGLE_ATTACHMENT',
    'cb_id',p_cb_id,
    'cb_no',v_cb_no,
    'requirement_type',v_type,
    'source_id',p_source_id,
    'item_no',v_item_no,
    'item_name',v_item_name,
    'unit',v_unit,
    'fulfilment_method',v_fulfil,
    'appx_pcs',coalesce(v_appx,0),
    'cutting_pcs',coalesce(v_cutting,0),
    'required_qty',coalesce(v_required,0),
    'supplier_name',v_supplier_name,
    'revision_no',v_revision,
    'short_note',coalesce(
      v_short_note,
      case when upper(coalesce(v_fulfil,'PURCHASE'))='MAKING'
        then 'Please confirm making status.'
        else 'Please confirm availability and expected delivery.'
      end
    ),
    'profile_labels',to_jsonb(coalesce(v_profiles,'{}'::text[])),
    'attachments',coalesce(v_attachments,'[]'::jsonb),
    'colour_projection',coalesce(v_colour_projection,'{}'::jsonb),
    'fulfilment',coalesce(v_fulfilment,'{}'::jsonb)
  );
end
$function$;

revoke all on function public.rr_cb_requirement_share_context_v1(uuid,text,uuid)
from public,anon,authenticated;
grant execute on function public.rr_cb_requirement_share_context_v1(uuid,text,uuid)
to authenticated;

create or replace function public.rr_cb_requirement_receipt_context_v2(
  p_cb_id uuid,
  p_requirement_type text,
  p_source_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  d jsonb;
  rows_json jsonb;
  n integer:=0;
  last_rev integer:=0;
  typ text:=upper(trim(coalesce(p_requirement_type,'')));
begin
  perform public.rr_cb_department_assert_authority_v600();
  d:=public.rr_cb_requirement_share_context_v1(p_cb_id,typ,p_source_id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,
    'cb_unit_id',r.cb_unit_id,
    'set_no',r.root_set_no,
    'profile_label',r.profile_label,
    'appx_pcs',r.appx_pcs,
    'cutting_pcs',r.cutting_pcs,
    'required_qty',r.required_qty,
    'revision_no',r.revision_no,
    'art_no',am.art_no,
    'category',ac.category_name,
    'sleeves',sr.sleeve_type,
    'sizes',sr.size_family,
    'cuff',sr.sleeve_finish
  ) order by r.root_set_no,r.profile_label),'[]'::jsonb)
  into rows_json
  from public.rr_cb_derived_requirement_v1 r
  left join public.rr_cb_art_assignments ca on ca.cb_id=r.cb_unit_id
  left join public.rr_art_master am on am.id=ca.art_id
  left join public.rr_art_categories ac on ac.id=am.art_category_id
  left join public.rr_cb_set_requirement_v1 sr on sr.cb_unit_id=r.cb_unit_id
  where r.cb_id=p_cb_id and r.active and r.requirement_type=typ
    and r.source_id=p_source_id and r.required_qty>0;

  select count(*),coalesce(max(revision_no),0)
  into n,last_rev
  from public.rr_cb_requirement_send_log_v1
  where cb_id=p_cb_id and requirement_type=typ and source_id=p_source_id;

  d:=d||jsonb_build_object(
    'rows',rows_json,
    'receipt_no','CB'||(d->>'cb_no')||'-'||case typ
      when 'MATERIAL' then 'MAT' when 'STICKER' then 'STK' else 'MID' end||
      '-'||left(p_source_id::text,8)||'-R'||(d->>'revision_no'),
    'send_kind',case
      when n=0 then 'FIRST'
      when last_rev<coalesce((d->>'revision_no')::integer,1) then 'REVISED'
      else 'RESEND'
    end,
    'send_count',n,
    'generated_at',now(),
    'version','RECEIPT_V3_LIVE_UPDATE'
  );

  return d||jsonb_build_object(
    'snapshot_token',md5((d-'generated_at'-'send_kind'-'send_count')::text)
  );
end
$function$;

revoke all on function public.rr_cb_requirement_receipt_context_v2(uuid,text,uuid)
from public,anon,authenticated;
grant execute on function public.rr_cb_requirement_receipt_context_v2(uuid,text,uuid)
to authenticated,service_role;

create or replace function public.rr_cb_requirement_receipt_record_v2(
  p_cb_id uuid,
  p_requirement_type text,
  p_source_id uuid,
  p_share_event_id uuid,
  p_snapshot_token text,
  p_format text,
  p_caption text,
  p_files jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  d jsonb;
  n integer;
  typ text:=upper(trim(coalesce(p_requirement_type,'')));
  fmt text:=upper(trim(coalesce(p_format,'')));
  old_log public.rr_cb_requirement_send_log_v1%rowtype;
begin
  perform public.rr_cb_department_assert_authority_v600();
  if p_share_event_id is null or fmt not in('JPG','PDF') then
    raise exception 'Valid single-file receipt share required.';
  end if;
  if nullif(trim(coalesce(p_snapshot_token,'')),'') is null then
    raise exception 'Receipt snapshot token required.';
  end if;
  if jsonb_typeof(p_files) is distinct from 'array'
     or jsonb_array_length(p_files)<>1
     or length(coalesce(p_caption,''))>8000 then
    raise exception 'Exactly one receipt attachment is required.';
  end if;
  if exists(
    select 1 from jsonb_array_elements(p_files) f
    where coalesce(f->>'type','') not in('image/jpeg','application/pdf')
       or coalesce((f->>'size')::bigint,0)<=0
       or (fmt='JPG' and coalesce(f->>'type','')<>'image/jpeg')
       or (fmt='PDF' and coalesce(f->>'type','')<>'application/pdf')
  ) then
    raise exception 'Valid JPG/PDF receipt attachment required.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'CB_RECEIPT:'||p_cb_id::text||':'||typ||':'||p_source_id::text,2
  ));

  select * into old_log
  from public.rr_cb_requirement_send_log_v1
  where share_event_id=p_share_event_id;
  if found then
    if old_log.cb_id<>p_cb_id or old_log.source_id<>p_source_id
       or old_log.requirement_type<>typ then
      raise exception 'Share event does not match this receipt.';
    end if;
    return jsonb_build_object(
      'ok',true,'duplicate',true,'recorded',true,
      'receipt_no',old_log.receipt_no
    );
  end if;

  d:=public.rr_cb_requirement_receipt_context_v2(p_cb_id,typ,p_source_id);
  if d->>'snapshot_token' is distinct from p_snapshot_token then
    return jsonb_build_object(
      'ok',true,'recorded',false,'reason','REQUIREMENT_CHANGED'
    );
  end if;

  n:=coalesce((d->>'send_count')::integer,0)+1;
  insert into public.rr_cb_requirement_send_log_v1(
    cb_id,requirement_type,source_id,revision_no,send_sequence,
    template_kind,message_text,supplier_name,share_event_id,share_channel,
    receipt_no,attachment_manifest,receipt_snapshot
  ) values(
    p_cb_id,typ,p_source_id,(d->>'revision_no')::integer,n,
    d->>'send_kind',p_caption,d->>'supplier_name',p_share_event_id,
    'NATIVE_CONTACT_PICKER_'||fmt,d->>'receipt_no',p_files,d
  );

  update public.rr_cb_derived_requirement_v1 r
  set status=case when d->>'send_kind'='RESEND' then 'RESENT' else 'SENT' end,
      last_sent_at=now(),last_sent_revision=r.revision_no,updated_at=now()
  where r.cb_id=p_cb_id and r.requirement_type=typ
    and r.source_id=p_source_id and r.active and r.required_qty>0;

  return jsonb_build_object(
    'ok',true,
    'recorded',true,
    'receipt_no',d->>'receipt_no',
    'template_kind',d->>'send_kind',
    'send_sequence',n,
    'handoff_only',true
  );
end
$function$;

revoke all on function public.rr_cb_requirement_receipt_record_v2(
  uuid,text,uuid,uuid,text,text,text,jsonb
) from public,anon,authenticated;
grant execute on function public.rr_cb_requirement_receipt_record_v2(
  uuid,text,uuid,uuid,text,text,text,jsonb
) to authenticated,service_role;

comment on function public.rr_cb_requirement_share_context_v1(uuid,text,uuid)
is 'Authorized V3 CB requirement receipt context with colour projection and numbered linked media.';

notify pgrst,'reload schema';
commit;
