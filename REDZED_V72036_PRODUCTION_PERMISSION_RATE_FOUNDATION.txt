-- REDZED REAL — V720.36 OPTIONAL FOUNDATION
-- Module permissions + one actual-rate ledger for Cutting and downstream production.
-- This SQL creates the backend foundation only. Downstream HTML/JS module files are
-- still required before their screens can show these columns.

begin;

create extension if not exists pgcrypto;

create table if not exists public.rr_module_role_permissions_v1 (
  id uuid primary key default gen_random_uuid(),
  role_code text not null,
  module_code text not null,
  can_view boolean not null default false,
  can_create boolean not null default false,
  can_edit boolean not null default false,
  can_delete boolean not null default false,
  can_verify boolean not null default false,
  can_approve boolean not null default false,
  can_view_bill boolean not null default false,
  can_view_actual_rate boolean not null default true,
  can_view_amount boolean not null default false,
  can_view_costing boolean not null default false,
  can_view_margin boolean not null default false,
  can_whatsapp boolean not null default false,
  can_export boolean not null default false,
  updated_at timestamptz not null default now(),
  unique(role_code,module_code)
);

-- Owner defaults.
insert into public.rr_module_role_permissions_v1(
  role_code,module_code,can_view,can_create,can_edit,can_delete,can_verify,can_approve,
  can_view_bill,can_view_actual_rate,can_view_amount,can_view_costing,can_view_margin,can_whatsapp,can_export
)
select 'owner',m,true,true,true,true,true,true,true,true,true,true,true,true,true
from unnest(array['product_master','cutting','printing','karigar','overlock','folding','thread_cut','qc','press','packing']) m
on conflict(role_code,module_code) do nothing;

-- Admin defaults.
insert into public.rr_module_role_permissions_v1(
  role_code,module_code,can_view,can_create,can_edit,can_delete,can_verify,can_approve,
  can_view_bill,can_view_actual_rate,can_view_amount,can_view_costing,can_view_margin,can_whatsapp,can_export
)
select 'admin',m,true,true,true,false,true,false,true,true,true,true,false,true,true
from unnest(array['product_master','cutting','printing','karigar','overlock','folding','thread_cut','qc','press','packing']) m
on conflict(role_code,module_code) do nothing;

-- Accounts defaults: financial visibility, no production posting by default.
insert into public.rr_module_role_permissions_v1(
  role_code,module_code,can_view,can_create,can_edit,can_delete,can_verify,can_approve,
  can_view_bill,can_view_actual_rate,can_view_amount,can_view_costing,can_view_margin,can_whatsapp,can_export
)
select r,m,true,false,false,false,false,false,true,true,true,true,false,false,true
from unnest(array['account','accounts']) r
cross join unnest(array['product_master','cutting','printing','karigar','overlock','folding','thread_cut','qc','press','packing']) m
on conflict(role_code,module_code) do nothing;

-- Production default: operational columns + Actual Rate, but no bill/amount/costing.
insert into public.rr_module_role_permissions_v1(
  role_code,module_code,can_view,can_create,can_edit,can_delete,can_verify,can_approve,
  can_view_bill,can_view_actual_rate,can_view_amount,can_view_costing,can_view_margin,can_whatsapp,can_export
)
select 'production',m,true,true,true,false,false,false,false,true,false,false,false,false,false
from unnest(array['cutting','printing','karigar','overlock','folding','thread_cut','qc','press','packing']) m
on conflict(role_code,module_code) do nothing;

create or replace function public.rr_has_module_permission_v1(
  p_module_code text,
  p_permission text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role text:=lower(coalesce(public.rr_current_role(),''));
  v_row public.rr_module_role_permissions_v1%rowtype;
  v_permission text:=lower(trim(coalesce(p_permission,'')));
begin
  select * into v_row
  from public.rr_module_role_permissions_v1
  where lower(role_code)=v_role and lower(module_code)=lower(trim(p_module_code));
  if not found then return false; end if;

  return case v_permission
    when 'view' then v_row.can_view
    when 'create' then v_row.can_create
    when 'edit' then v_row.can_edit
    when 'delete' then v_row.can_delete
    when 'verify' then v_row.can_verify
    when 'approve' then v_row.can_approve
    when 'view_bill' then v_row.can_view_bill
    when 'view_actual_rate' then v_row.can_view_actual_rate
    when 'view_amount' then v_row.can_view_amount
    when 'view_costing' then v_row.can_view_costing
    when 'view_margin' then v_row.can_view_margin
    when 'whatsapp' then v_row.can_whatsapp
    when 'export' then v_row.can_export
    else false end;
end;
$$;

create table if not exists public.rr_lot_process_actuals_v1 (
  id uuid primary key default gen_random_uuid(),
  lot_no text not null,
  process_code text not null check (process_code in (
    'CUTTING','PRINTING','KARIGAR','OVERLOCK','FOLDING','THREAD_CUT','QC','PRESS','PACKING'
  )),
  art_no text,
  print_no text,
  colour_id uuid,
  colour_name text,
  size_code text,
  colour_key text generated always as (coalesce(colour_id::text,lower(trim(coalesce(colour_name,''))))) stored,
  size_key text generated always as (lower(trim(coalesce(size_code,'')))) stored,
  in_pcs integer not null default 0 check (in_pcs >= 0),
  out_pcs integer not null default 0 check (out_pcs >= 0),
  short_pcs integer not null default 0 check (short_pcs >= 0),
  reject_pcs integer not null default 0 check (reject_pcs >= 0),
  actual_rate numeric(18,4) not null default 0 check (actual_rate >= 0),
  actual_amount numeric(18,2) generated always as (round(out_pcs * actual_rate,2)) stored,
  process_status text not null default 'PENDING',
  remarks text,
  is_frozen boolean not null default false,
  frozen_at timestamptz,
  frozen_by uuid,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  unique(lot_no,process_code,colour_key,size_key)
);

create index if not exists rr_lot_process_actuals_lot_idx
  on public.rr_lot_process_actuals_v1(lower(lot_no),process_code);

create or replace function public.rr_upsert_lot_process_actual_v1(
  p_lot_no text,
  p_process_code text,
  p_art_no text default null,
  p_print_no text default null,
  p_colour_id uuid default null,
  p_colour_name text default null,
  p_size_code text default null,
  p_in_pcs integer default 0,
  p_out_pcs integer default 0,
  p_short_pcs integer default 0,
  p_reject_pcs integer default 0,
  p_actual_rate numeric default 0,
  p_process_status text default 'PENDING',
  p_remarks text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_row public.rr_lot_process_actuals_v1%rowtype;
begin
  if not public.rr_has_module_permission_v1(lower(trim(p_process_code)),'edit')
     and not public.rr_has_module_permission_v1(lower(trim(p_process_code)),'create') then
    raise exception 'Permission denied for %.',p_process_code;
  end if;

  select * into v_row
  from public.rr_lot_process_actuals_v1
  where lower(lot_no)=lower(trim(p_lot_no))
    and process_code=upper(trim(p_process_code))
    and colour_key=coalesce(p_colour_id::text,lower(trim(coalesce(p_colour_name,''))))
    and size_key=lower(trim(coalesce(p_size_code,'')))
  for update;

  if found and v_row.is_frozen then raise exception 'This process rate/quantity is frozen.'; end if;

  insert into public.rr_lot_process_actuals_v1(
    lot_no,process_code,art_no,print_no,colour_id,colour_name,size_code,
    in_pcs,out_pcs,short_pcs,reject_pcs,actual_rate,process_status,remarks,updated_at,updated_by
  ) values(
    upper(trim(p_lot_no)),upper(trim(p_process_code)),nullif(trim(p_art_no),''),nullif(trim(p_print_no),''),
    p_colour_id,nullif(trim(p_colour_name),''),nullif(trim(p_size_code),''),
    greatest(0,coalesce(p_in_pcs,0)),greatest(0,coalesce(p_out_pcs,0)),
    greatest(0,coalesce(p_short_pcs,0)),greatest(0,coalesce(p_reject_pcs,0)),
    greatest(0,coalesce(p_actual_rate,0)),upper(trim(coalesce(p_process_status,'PENDING'))),
    nullif(trim(p_remarks),''),now(),auth.uid()
  )
  on conflict(lot_no,process_code,colour_key,size_key)
  do update set
    art_no=excluded.art_no,print_no=excluded.print_no,colour_name=excluded.colour_name,
    in_pcs=excluded.in_pcs,out_pcs=excluded.out_pcs,short_pcs=excluded.short_pcs,reject_pcs=excluded.reject_pcs,
    actual_rate=excluded.actual_rate,process_status=excluded.process_status,remarks=excluded.remarks,
    updated_at=now(),updated_by=auth.uid()
  returning * into v_row;

  return to_jsonb(v_row);
end;
$$;

create or replace function public.rr_freeze_lot_process_actual_v1(
  p_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_row public.rr_lot_process_actuals_v1%rowtype;
begin
  if lower(coalesce(public.rr_current_role(),'')) not in ('owner','admin') then
    raise exception 'Owner/Admin permission required.';
  end if;
  update public.rr_lot_process_actuals_v1
  set is_frozen=true,frozen_at=now(),frozen_by=auth.uid(),updated_at=now(),updated_by=auth.uid()
  where id=p_id returning * into v_row;
  if not found then raise exception 'Process record not found.'; end if;
  return to_jsonb(v_row);
end;
$$;

-- Operational read: Actual Rate visible; Actual Amount and costing are omitted.
create or replace view public.rr_lot_process_operational_v1 as
select id,lot_no,process_code,art_no,print_no,colour_id,colour_name,size_code,
       in_pcs,out_pcs,short_pcs,reject_pcs,actual_rate,process_status,remarks,
       is_frozen,created_at,updated_at
from public.rr_lot_process_actuals_v1;

create or replace function public.rr_get_lot_process_actuals_v1(p_lot_no text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return coalesce((
    select jsonb_agg(
      case
        when public.rr_has_module_permission_v1(lower(r.process_code),'view_amount')
          or public.rr_has_module_permission_v1(lower(r.process_code),'view_costing')
        then to_jsonb(r)
        else jsonb_build_object(
          'id',r.id,
          'lot_no',r.lot_no,
          'process_code',r.process_code,
          'art_no',r.art_no,
          'print_no',r.print_no,
          'colour_id',r.colour_id,
          'colour_name',r.colour_name,
          'size_code',r.size_code,
          'in_pcs',r.in_pcs,
          'out_pcs',r.out_pcs,
          'short_pcs',r.short_pcs,
          'reject_pcs',r.reject_pcs,
          'actual_rate',case
            when public.rr_has_module_permission_v1(lower(r.process_code),'view_actual_rate')
            then r.actual_rate else null end,
          'process_status',r.process_status,
          'remarks',r.remarks,
          'is_frozen',r.is_frozen,
          'created_at',r.created_at,
          'updated_at',r.updated_at
        )
      end
      order by r.process_code,r.colour_name,r.size_code
    )
    from public.rr_lot_process_actuals_v1 r
    where lower(r.lot_no)=lower(trim(p_lot_no))
      and public.rr_has_module_permission_v1(lower(r.process_code),'view')
  ),'[]'::jsonb);
end;
$$;

alter table public.rr_module_role_permissions_v1 enable row level security;
alter table public.rr_lot_process_actuals_v1 enable row level security;

drop policy if exists rr_module_permissions_read on public.rr_module_role_permissions_v1;
create policy rr_module_permissions_read on public.rr_module_role_permissions_v1
for select to authenticated using(true);

drop policy if exists rr_lot_process_actuals_read on public.rr_lot_process_actuals_v1;
create policy rr_lot_process_actuals_read on public.rr_lot_process_actuals_v1
for select to authenticated using(true);

revoke all on public.rr_lot_process_actuals_v1 from anon,authenticated;
revoke all on public.rr_lot_process_operational_v1 from anon,authenticated;
grant select on public.rr_module_role_permissions_v1 to authenticated;
grant execute on function public.rr_has_module_permission_v1(text,text) to authenticated;
grant execute on function public.rr_upsert_lot_process_actual_v1(text,text,text,text,uuid,text,text,integer,integer,integer,integer,numeric,text,text) to authenticated;
grant execute on function public.rr_freeze_lot_process_actual_v1(uuid) to authenticated;
grant execute on function public.rr_get_lot_process_actuals_v1(text) to authenticated;

commit;
