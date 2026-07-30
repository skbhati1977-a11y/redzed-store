-- REDZED UPM V723 — Unified Lot Form + Costing foundation
-- Run after existing V720.55/V721 SQL. Additive only.
begin;
create extension if not exists pgcrypto;

create table if not exists public.rr_upm_standard_rates_v723 (
  id uuid primary key default gen_random_uuid(),
  canonical_lot_id text not null,
  lot_no text not null,
  department_code text not null,
  standard_rate numeric(14,4) not null check (standard_rate >= 0),
  currency_code text not null default 'INR',
  effective_from timestamptz not null default now(),
  changed_by uuid default auth.uid(),
  changed_by_name text,
  reason text,
  created_at timestamptz not null default now(),
  unique(canonical_lot_id, department_code)
);

create table if not exists public.rr_upm_owner_margin_v723 (
  id uuid primary key default gen_random_uuid(),
  margin_name text not null default 'DEFAULT',
  flat_amount_per_piece numeric(14,4) not null check (flat_amount_per_piece >= 0),
  is_active boolean not null default true,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  reason text not null,
  changed_by uuid default auth.uid(),
  changed_by_name text,
  created_at timestamptz not null default now()
);
create unique index if not exists rr_upm_owner_margin_one_active_v723
on public.rr_upm_owner_margin_v723(is_active) where is_active;

create table if not exists public.rr_upm_worker_ledger_v723 (
  id bigint generated always as identity primary key,
  canonical_lot_id text not null,
  lot_no text not null,
  department_code text not null,
  colour_code text not null,
  size_code text not null,
  worker_id uuid,
  worker_name text,
  event_type text not null check(event_type in
    ('ISSUE','GOOD','ALTER','RETURN','TRANSFER_IN','TRANSFER_OUT','REMAKE_ISSUE','REMAKE_COMPLETE','DAMAGE','SHORT','EXCESS','ADJUSTMENT')),
  qty numeric(14,3) not null check(qty > 0),
  actual_rate numeric(14,4) not null default 0,
  amount numeric(14,2) generated always as (round(qty*actual_rate,2)) stored,
  source_table text,
  source_id text,
  remarks text,
  actor_user_id uuid default auth.uid(),
  actor_name text,
  created_at timestamptz not null default now()
);
create index if not exists rr_upm_worker_ledger_lookup_v723
on public.rr_upm_worker_ledger_v723(canonical_lot_id,department_code,worker_id,created_at desc);

create table if not exists public.rr_upm_dispatch_cost_snapshot_v723 (
  id uuid primary key default gen_random_uuid(),
  canonical_lot_id text not null,
  lot_no text not null,
  dispatch_qty numeric(14,3) not null check(dispatch_qty > 0),
  actual_material_cost_total numeric(14,2) not null default 0,
  actual_production_cost_total numeric(14,2) not null default 0,
  actual_cost_total numeric(14,2) not null default 0,
  actual_cost_per_piece numeric(14,4) not null default 0,
  standard_material_cost_total numeric(14,2) not null default 0,
  standard_production_cost_total numeric(14,2) not null default 0,
  standard_cost_total numeric(14,2) not null default 0,
  standard_cost_per_piece numeric(14,4) not null default 0,
  owner_margin_per_piece numeric(14,4) not null default 0,
  owner_margin_total numeric(14,2) not null default 0,
  final_cost_total numeric(14,2) not null default 0,
  final_cost_per_piece numeric(14,4) not null default 0,
  snapshot_data jsonb not null default '{}'::jsonb,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  unique(canonical_lot_id)
);

alter table public.rr_upm_standard_rates_v723 enable row level security;
alter table public.rr_upm_owner_margin_v723 enable row level security;
alter table public.rr_upm_worker_ledger_v723 enable row level security;
alter table public.rr_upm_dispatch_cost_snapshot_v723 enable row level security;

do $$ begin create policy rr_upm_standard_rate_read_v723 on public.rr_upm_standard_rates_v723 for select to authenticated using (true); exception when duplicate_object then null; end $$;
do $$ begin create policy rr_upm_margin_read_v723 on public.rr_upm_owner_margin_v723 for select to authenticated using (true); exception when duplicate_object then null; end $$;
do $$ begin create policy rr_upm_worker_ledger_read_v723 on public.rr_upm_worker_ledger_v723 for select to authenticated using (true); exception when duplicate_object then null; end $$;
do $$ begin create policy rr_upm_cost_snapshot_read_v723 on public.rr_upm_dispatch_cost_snapshot_v723 for select to authenticated using (true); exception when duplicate_object then null; end $$;

grant select on public.rr_upm_standard_rates_v723, public.rr_upm_owner_margin_v723,
 public.rr_upm_worker_ledger_v723, public.rr_upm_dispatch_cost_snapshot_v723 to authenticated;

create or replace function public.rr_upm_is_owner_admin_v723()
returns boolean language sql stable security definer set search_path=public as $$
  select coalesce(upper(public.rr_up_user_context_v2()->>'user_category') in ('OWNER','ADMIN'),false)
$$;

create or replace function public.rr_upm_set_standard_rate_v723(
 p_canonical_lot_id text,p_department_code text,p_standard_rate numeric,p_reason text default null)
returns public.rr_upm_standard_rates_v723 language plpgsql security definer set search_path=public as $$
declare v_lot_no text; v_name text; v public.rr_upm_standard_rates_v723;
begin
 if not public.rr_upm_is_owner_admin_v723() then raise exception 'Only Owner/Admin can view or change Standard Rate'; end if;
 if p_standard_rate is null or p_standard_rate<0 then raise exception 'Invalid standard rate'; end if;
 select lot_no into v_lot_no from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id;
 if v_lot_no is null then raise exception 'Lot not found'; end if;
 v_name:=coalesce(public.rr_up_user_context_v2()->>'display_name',auth.uid()::text);
 insert into public.rr_upm_standard_rates_v723(canonical_lot_id,lot_no,department_code,standard_rate,changed_by_name,reason)
 values(p_canonical_lot_id,v_lot_no,upper(p_department_code),p_standard_rate,v_name,p_reason)
 on conflict(canonical_lot_id,department_code) do update set standard_rate=excluded.standard_rate,effective_from=now(),changed_by=auth.uid(),changed_by_name=v_name,reason=excluded.reason
 returning * into v;
 insert into public.rr_upm_audit(action_code,canonical_lot_id,entity_type,entity_id,new_data)
 values('STANDARD_RATE_CHANGE',p_canonical_lot_id,'STANDARD_RATE',v.id::text,to_jsonb(v));
 return v;
end $$;

create or replace function public.rr_upm_set_owner_margin_v723(p_amount numeric,p_reason text)
returns public.rr_upm_owner_margin_v723 language plpgsql security definer set search_path=public as $$
declare v public.rr_upm_owner_margin_v723; v_name text;
begin
 if not public.rr_upm_is_owner_admin_v723() then raise exception 'Only Owner/Admin can change margin'; end if;
 if p_amount is null or p_amount<0 then raise exception 'Invalid margin'; end if;
 if nullif(trim(p_reason),'') is null then raise exception 'Reason required'; end if;
 v_name:=coalesce(public.rr_up_user_context_v2()->>'display_name',auth.uid()::text);
 update public.rr_upm_owner_margin_v723 set is_active=false,effective_to=now() where is_active;
 insert into public.rr_upm_owner_margin_v723(flat_amount_per_piece,reason,changed_by_name)
 values(p_amount,p_reason,v_name) returning * into v;
 return v;
end $$;

create or replace function public.rr_upm_universal_form_v723(p_canonical_lot_id text,p_department_code text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_lot jsonb; v_rows jsonb; v_workers jsonb; v_rate numeric:=0; v_std numeric:=null; v_owner boolean; v_margin numeric:=0;
begin
 v_owner:=public.rr_upm_is_owner_admin_v723();
 select to_jsonb(x) into v_lot from public.rr_upm_lot_board_v1 x where canonical_lot_id=p_canonical_lot_id limit 1;
 if v_lot is null then raise exception 'Lot not found'; end if;
 select coalesce(actual_rate,0) into v_rate from public.rr_upm_department_rates_v2 where canonical_lot_id=p_canonical_lot_id and upper(department_code)=upper(p_department_code);
 if v_owner then select standard_rate into v_std from public.rr_upm_standard_rates_v723 where canonical_lot_id=p_canonical_lot_id and upper(department_code)=upper(p_department_code); end if;
 if v_owner then select flat_amount_per_piece into v_margin from public.rr_upm_owner_margin_v723 where is_active order by effective_from desc limit 1; end if;
 with sizes as (
  select upper(m.colour_code) colour_code,max(m.colour_name) colour_name,upper(m.size_code) size_code,sum(m.cut_qty)::numeric cutting_qty
  from public.rr_upm_lot_cut_size_map_v5 m
  where m.is_active and upper(m.lot_no)=upper(v_lot->>'lot_no') group by upper(m.colour_code),upper(m.size_code)
 ), assigns as (
  select upper(a.colour_code) colour_code,a.worker_id,max(a.worker_name_snapshot) worker_name,max(a.worker_code) worker_code,
         sum(coalesce((z->>'qty')::numeric,0)) filter(where upper(z->>'size_code')=s.size_code) assigned_qty
  from public.rr_upm_work_assignments_v8 a cross join lateral jsonb_array_elements(a.size_breakup) z
  join sizes s on s.colour_code=upper(a.colour_code)
  where a.canonical_lot_id=p_canonical_lot_id and upper(a.department_code)=upper(p_department_code) and a.status in ('ASSIGNED','IN_PROGRESS','COMPLETED')
  group by upper(a.colour_code),a.worker_id,s.size_code
 ), production as (
  select upper(colour_code) colour_code,upper(size_code) size_code,
   sum(case when entry_type='GOOD' then qty else 0 end) good_qty,
   sum(case when entry_type in ('ALTER_OUT','REJECT') then qty else 0 end) alter_qty,
   sum(case when entry_type='REMAKE' then qty else 0 end) remake_qty
  from public.rr_upm_entries where canonical_lot_id=p_canonical_lot_id and upper(department_code)=upper(p_department_code)
  group by upper(colour_code),upper(size_code)
 )
 select coalesce(jsonb_agg(jsonb_build_object(
  'colour_code',s.colour_code,'colour_name',s.colour_name,'size_code',s.size_code,'cutting_qty',s.cutting_qty,
  'worker_id',a.worker_id,'worker_name',a.worker_name,'worker_code',a.worker_code,
  'assigned_qty',coalesce(a.assigned_qty,0),'good_qty',coalesce(p.good_qty,0),'alter_qty',coalesce(p.alter_qty,0),
  'remake_qty',coalesce(p.remake_qty,0),'damage_qty',0,
  'pending_qty',greatest(coalesce(a.assigned_qty,0)-coalesce(p.good_qty,0)-coalesce(p.alter_qty,0),0),
  'actual_rate',v_rate,'standard_rate',case when v_owner then v_std else null end
 ) order by s.colour_name,s.size_code),'[]'::jsonb) into v_rows
 from sizes s left join assigns a on a.colour_code=s.colour_code
 left join production p on p.colour_code=s.colour_code and (p.size_code=s.size_code or p.size_code='ALL');

 select coalesce(jsonb_agg(to_jsonb(w)),'[]'::jsonb) into v_workers from public.rr_upm_worker_list_v8(p_department_code) w;
 return jsonb_build_object('lot',v_lot,'department_code',upper(p_department_code),'rows',v_rows,'workers',v_workers,
  'actual_rate',v_rate,'standard_rate',case when v_owner then v_std else null end,'owner_margin',case when v_owner then coalesce(v_margin,0) else null end,
  'can_view_standard',v_owner,'can_change_standard',v_owner,'can_change_margin',v_owner);
end $$;

grant execute on function public.rr_upm_is_owner_admin_v723() to authenticated;
grant execute on function public.rr_upm_set_standard_rate_v723(text,text,numeric,text) to authenticated;
grant execute on function public.rr_upm_set_owner_margin_v723(numeric,text) to authenticated;
grant execute on function public.rr_upm_universal_form_v723(text,text) to authenticated;
commit;
