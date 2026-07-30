-- REDZED UPM V721.00 — Lot-Centric Core
-- Run after existing V720.40 + Assignment V8 + Alter V4/V5 migrations.
-- Additive only: no production table is dropped.
begin;
create extension if not exists pgcrypto;

-- 1) Lot is the hard product identity. Art/Print/CB and media stay bound to the lot.
alter table public.rr_upm_lot_registry
  add column if not exists cb_no text,
  add column if not exists art_id text,
  add column if not exists print_id text,
  add column if not exists print_no text,
  add column if not exists style_name text,
  add column if not exists art_image_urls jsonb not null default '[]'::jsonb,
  add column if not exists print_image_urls jsonb not null default '[]'::jsonb,
  add column if not exists original_cut_qty numeric(14,3),
  add column if not exists verified_cut_qty numeric(14,3),
  add column if not exists quantity_verified_at timestamptz,
  add column if not exists quantity_verified_by uuid;

create unique index if not exists rr_upm_lot_registry_lot_no_uq
  on public.rr_upm_lot_registry(upper(trim(lot_no)));

-- 2) Actual rate remains the existing authoritative rr_upm_department_rates_v2 (Lot + Department).

-- 3) Immutable physical quantity verification / adjustment history.
create table if not exists public.rr_upm_quantity_adjustments_v721 (
  id uuid primary key default gen_random_uuid(),
  canonical_lot_id text not null references public.rr_upm_lot_registry(canonical_lot_id) on delete restrict,
  lot_no text not null,
  colour_code text not null default 'GENERAL',
  size_code text not null default 'ALL',
  system_qty numeric(14,3) not null,
  verified_qty numeric(14,3) not null check(verified_qty >= 0),
  difference_qty numeric(14,3) generated always as (verified_qty-system_qty) stored,
  reason text not null,
  remarks text,
  evidence_paths jsonb not null default '[]'::jsonb,
  verified_by uuid default auth.uid(),
  verified_by_name text,
  created_at timestamptz not null default now()
);
create index if not exists rr_upm_qty_adj_lot_v721 on public.rr_upm_quantity_adjustments_v721(canonical_lot_id,created_at desc);

-- 4) Universal automatic worker ledger. No update/delete API is granted.
create table if not exists public.rr_upm_worker_ledger_v721 (
  id bigserial primary key,
  canonical_lot_id text not null,
  lot_no text not null,
  department_code text not null,
  colour_code text not null default 'GENERAL',
  size_code text not null default 'ALL',
  worker_id uuid,
  worker_name text,
  event_code text not null check(event_code in ('ISSUE','GOOD','ALTER','RETURN','TRANSFER_IN','TRANSFER_OUT','REMAKE_ISSUE','REMAKE_COMPLETE','DAMAGE','SHORT','EXCESS','DEBIT','QTY_ADJUSTMENT')),
  qty numeric(14,3) not null check(qty > 0),
  rate numeric(14,4),
  source_entity_type text not null,
  source_entity_id text not null,
  counterparty_worker_id uuid,
  remarks text,
  actor_user_id uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists rr_upm_worker_ledger_balance_v721 on public.rr_upm_worker_ledger_v721(canonical_lot_id,department_code,colour_code,size_code,worker_id,created_at);
create unique index if not exists rr_upm_worker_ledger_source_uq_v721 on public.rr_upm_worker_ledger_v721(event_code,source_entity_type,source_entity_id,colour_code,size_code,coalesce(worker_id,'00000000-0000-0000-0000-000000000000'::uuid));

-- 5) Pending-only worker reassignment history.
create table if not exists public.rr_upm_worker_transfers_v721 (
  id uuid primary key default gen_random_uuid(),
  canonical_lot_id text not null,
  lot_no text not null,
  department_code text not null,
  colour_code text not null,
  size_code text not null,
  from_worker_id uuid,
  from_worker_name text,
  to_worker_id uuid,
  to_worker_name text,
  transfer_qty numeric(14,3) not null check(transfer_qty > 0),
  transfer_mode text not null check(transfer_mode in ('RETURN_TO_DEPARTMENT','DIRECT_WORKER_HANDOVER','PHYSICAL_COUNT_ADJUSTMENT')),
  reason text not null,
  remarks text,
  transferred_by uuid default auth.uid(),
  transferred_at timestamptz not null default now()
);

-- RLS/read policies. Writes happen only through security-definer RPCs.
do $$
declare t text;
begin
  foreach t in array array['rr_upm_quantity_adjustments_v721','rr_upm_worker_ledger_v721','rr_upm_worker_transfers_v721'] loop
    execute format('alter table public.%I enable row level security',t);
    begin execute format('create policy %I on public.%I for select to authenticated using (true)',t||'_read',t); exception when duplicate_object then null; end;
    execute format('grant select on public.%I to authenticated',t);
  end loop;
end $$;

-- Bind/update universal product identity without duplicating images in movements.
create or replace function public.rr_upm_bind_lot_identity_v721(
  p_canonical_lot_id text,
  p_lot_no text,
  p_cb_no text default null,
  p_art_id text default null,
  p_art_no text default null,
  p_print_id text default null,
  p_print_no text default null,
  p_item_name text default null,
  p_style_name text default null,
  p_art_image_urls jsonb default '[]'::jsonb,
  p_print_image_urls jsonb default '[]'::jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v public.rr_upm_lot_registry;
begin
  update public.rr_upm_lot_registry set
    lot_no=coalesce(nullif(trim(p_lot_no),''),lot_no),
    cb_no=coalesce(nullif(trim(p_cb_no),''),cb_no),
    art_id=coalesce(nullif(trim(p_art_id),''),art_id),
    art_no=coalesce(nullif(trim(p_art_no),''),art_no),
    print_id=coalesce(nullif(trim(p_print_id),''),print_id),
    print_no=coalesce(nullif(trim(p_print_no),''),print_no),
    item_name=coalesce(nullif(trim(p_item_name),''),item_name),
    style_name=coalesce(nullif(trim(p_style_name),''),style_name),
    art_image_urls=case when jsonb_typeof(p_art_image_urls)='array' and jsonb_array_length(p_art_image_urls)>0 then p_art_image_urls else art_image_urls end,
    print_image_urls=case when jsonb_typeof(p_print_image_urls)='array' and jsonb_array_length(p_print_image_urls)>0 then p_print_image_urls else print_image_urls end,
    updated_at=now()
  where canonical_lot_id=p_canonical_lot_id returning * into v;
  if not found then raise exception 'UPM Lot % not registered.',p_canonical_lot_id; end if;
  insert into public.rr_upm_audit(action_code,canonical_lot_id,entity_type,entity_id,new_data)
  values('BIND_LOT_IDENTITY',p_canonical_lot_id,'LOT',v.id::text,to_jsonb(v));
  return to_jsonb(v);
end $$;

-- Resolve one universal Colour×Size source. Priority: verified adjustment -> assignment size breakup -> saved map -> cutting breakup.
create or replace function public.rr_upm_resolve_colour_size_v721(p_canonical_lot_id text default null,p_lot_no text default null)
returns table(colour_code text,colour_name text,size_code text,cut_qty numeric,verified_qty numeric,registered_alter_qty numeric,available_alter_qty numeric,source_code text)
language plpgsql security definer set search_path=public as $$
declare v_lot text; v_id text;
begin
  select l.lot_no,l.canonical_lot_id into v_lot,v_id from public.rr_upm_lot_registry l
  where l.canonical_lot_id=nullif(trim(p_canonical_lot_id),'') or upper(trim(l.lot_no))=upper(trim(p_lot_no))
  order by (l.canonical_lot_id=nullif(trim(p_canonical_lot_id),'')) desc limit 1;
  if v_lot is null then raise exception 'Lot not found.'; end if;

  return query
  with assign_rows as (
    select upper(a.colour_code) cc,coalesce(a.colour_name,a.colour_code) cn,upper(coalesce(s->>'size_code','ALL')) sz,
           coalesce((s->>'qty')::numeric,0) qty
    from public.rr_upm_work_assignments_v8 a cross join lateral jsonb_array_elements(coalesce(a.size_breakup,'[]'::jsonb)) s
    where (a.canonical_lot_id=v_id or upper(a.lot_no)=upper(v_lot)) and coalesce(a.is_active,true)
  ), mapped as (
    select upper(m.colour_code) cc,coalesce(m.colour_name,m.colour_code) cn,upper(m.size_code) sz,m.cut_qty qty
    from public.rr_upm_lot_cut_size_map_v5 m where upper(m.lot_no)=upper(v_lot)
  ), base as (
    select * from assign_rows where qty>0
    union all
    select * from mapped m where m.qty>0 and not exists(select 1 from assign_rows a where a.cc=m.cc and a.sz=m.sz)
  ), latest_adj as (
    select distinct on (upper(colour_code),upper(size_code)) upper(colour_code) cc,upper(size_code) sz,verified_qty
    from public.rr_upm_quantity_adjustments_v721 where canonical_lot_id=v_id order by upper(colour_code),upper(size_code),created_at desc
  ), used as (
    select upper(coalesce(x.colour_code,'GENERAL')) cc,upper(coalesce(x.size_code,'ALL')) sz,coalesce(sum(x.qty),0) qty
    from public.rr_upm_entries x where x.canonical_lot_id=v_id and x.entry_type='ALTER_OUT' group by 1,2
  )
  select b.cc,b.cn,b.sz,b.qty,coalesce(a.verified_qty,b.qty),coalesce(u.qty,0),greatest(coalesce(a.verified_qty,b.qty)-coalesce(u.qty,0),0),
         case when a.verified_qty is not null then 'VERIFIED' when exists(select 1 from assign_rows z where z.cc=b.cc and z.sz=b.sz) then 'ASSIGNMENT' else 'CUTTING_MAP' end
  from base b left join latest_adj a on a.cc=b.cc and a.sz=b.sz left join used u on u.cc=b.cc and u.sz=b.sz;
end $$;

create or replace function public.rr_upm_get_universal_lot_context_v721(p_canonical_lot_id text default null,p_lot_no text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v public.rr_upm_lot_registry; v_matrix jsonb; v_rates jsonb; v_open_alters jsonb;
begin
  select * into v from public.rr_upm_lot_registry l where l.canonical_lot_id=nullif(trim(p_canonical_lot_id),'') or upper(trim(l.lot_no))=upper(trim(p_lot_no)) order by (l.canonical_lot_id=nullif(trim(p_canonical_lot_id),'')) desc limit 1;
  if not found then raise exception 'Lot not found.'; end if;
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_matrix from public.rr_upm_resolve_colour_size_v721(v.canonical_lot_id,v.lot_no) x;
  select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) into v_rates from public.rr_upm_department_rates_v2 r where r.canonical_lot_id=v.canonical_lot_id;
  begin select coalesce(jsonb_agg(to_jsonb(a)),'[]'::jsonb) into v_open_alters from public.rr_up_alter_card_v1 a where upper(a.lot_no)=upper(v.lot_no) and upper(a.status) not in ('CLOSED','CANCELLED'); exception when undefined_table then v_open_alters='[]'::jsonb; end;
  return jsonb_build_object('lot',to_jsonb(v),'colour_size_matrix',v_matrix,'department_rates',v_rates,'open_alters',v_open_alters);
end $$;

-- Physical verification never overwrites original history.
create or replace function public.rr_upm_verify_quantity_v721(
 p_canonical_lot_id text,p_colour_code text,p_size_code text,p_system_qty numeric,p_verified_qty numeric,p_reason text,p_remarks text default null,p_evidence_paths jsonb default '[]'::jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_lot text; v_name text; v_row public.rr_upm_quantity_adjustments_v721;
begin
 if nullif(trim(p_reason),'') is null then raise exception 'Verification reason is mandatory.'; end if;
 if p_verified_qty is null or p_verified_qty<0 then raise exception 'Verified quantity cannot be negative.'; end if;
 select lot_no into v_lot from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id;
 if v_lot is null then raise exception 'Lot not found.'; end if;
 select coalesce(full_name,email) into v_name from public.rr_user_profiles where auth_user_id=auth.uid() limit 1;
 insert into public.rr_upm_quantity_adjustments_v721(canonical_lot_id,lot_no,colour_code,size_code,system_qty,verified_qty,reason,remarks,evidence_paths,verified_by_name)
 values(p_canonical_lot_id,v_lot,upper(coalesce(nullif(trim(p_colour_code),''),'GENERAL')),upper(coalesce(nullif(trim(p_size_code),''),'ALL')),p_system_qty,p_verified_qty,trim(p_reason),p_remarks,coalesce(p_evidence_paths,'[]'::jsonb),v_name) returning * into v_row;
 insert into public.rr_upm_worker_ledger_v721(canonical_lot_id,lot_no,department_code,colour_code,size_code,event_code,qty,source_entity_type,source_entity_id,remarks)
 values(p_canonical_lot_id,v_lot,'CUTTING',v_row.colour_code,v_row.size_code,case when v_row.difference_qty<0 then 'SHORT' else 'EXCESS' end,abs(v_row.difference_qty),'QTY_ADJUSTMENT',v_row.id::text,p_reason)
 on conflict do nothing;
 return to_jsonb(v_row);
end $$;

grant execute on function public.rr_upm_bind_lot_identity_v721(text,text,text,text,text,text,text,text,text,jsonb,jsonb) to authenticated;
grant execute on function public.rr_upm_resolve_colour_size_v721(text,text) to authenticated;
grant execute on function public.rr_upm_get_universal_lot_context_v721(text,text) to authenticated;
grant execute on function public.rr_upm_verify_quantity_v721(text,text,text,numeric,numeric,text,text,jsonb) to authenticated;

commit;
