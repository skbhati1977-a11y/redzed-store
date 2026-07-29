-- REDZED Universal Production Module V720.40
-- Safe additive migration. Existing production/cutting tables are not dropped or renamed.
create extension if not exists pgcrypto;

create table if not exists public.rr_upm_departments (
  id uuid primary key default gen_random_uuid(),
  department_code text not null unique,
  department_name text not null,
  sequence_no integer not null default 100,
  entry_mode text not null default 'COLOUR' check (entry_mode in ('LOT','COLOUR','SIZE','COLOUR_SIZE')),
  is_start_department boolean not null default false,
  is_final_department boolean not null default false,
  auto_forward boolean not null default true,
  allow_partial boolean not null default true,
  allow_alter boolean not null default true,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.rr_upm_departments(department_code,department_name,sequence_no,entry_mode,is_start_department,is_final_department)
values
 ('CUTTING','Cutting',10,'COLOUR_SIZE',true,false),
 ('PRINTING','Printing',20,'COLOUR',false,false),
 ('STICKER','Sticker / Heat Transfer',30,'COLOUR',false,false),
 ('STITCHING','Stitching',40,'COLOUR_SIZE',false,false),
 ('THREAD_CUT','Thread Cutting',50,'COLOUR_SIZE',false,false),
 ('PRESS','Press / Finishing',60,'COLOUR_SIZE',false,false),
 ('PACKING','Packing',70,'COLOUR_SIZE',false,true)
on conflict (department_code) do nothing;

create table if not exists public.rr_upm_lot_registry (
  id uuid primary key default gen_random_uuid(),
  canonical_lot_id text not null unique,
  lot_no text not null,
  source_table text,
  source_id text,
  art_no text,
  item_name text,
  status text not null default 'OPEN',
  total_qty numeric(14,3) not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists rr_upm_lot_registry_source_uq on public.rr_upm_lot_registry(source_table,source_id) where source_id is not null;

create table if not exists public.rr_upm_colour_state (
  id uuid primary key default gen_random_uuid(),
  canonical_lot_id text not null,
  colour_code text not null default 'GENERAL',
  colour_name text not null default 'General',
  planned_qty numeric(14,3) not null default 0,
  current_department_code text not null default 'CUTTING',
  completed_qty numeric(14,3) not null default 0,
  rejected_qty numeric(14,3) not null default 0,
  alter_qty numeric(14,3) not null default 0,
  status text not null default 'PENDING' check(status in ('PENDING','IN_PROGRESS','PARTIAL','COMPLETED','HOLD','CANCELLED')),
  updated_at timestamptz not null default now(),
  unique(canonical_lot_id,colour_code)
);

create table if not exists public.rr_upm_entries (
  id uuid primary key default gen_random_uuid(),
  canonical_lot_id text not null,
  lot_no text not null,
  department_code text not null,
  colour_code text not null default 'GENERAL',
  size_code text not null default 'ALL',
  entry_type text not null default 'GOOD' check(entry_type in ('GOOD','REJECT','ALTER_OUT','ALTER_IN','REMAKE','ADJUSTMENT')),
  qty numeric(14,3) not null check(qty > 0),
  rate numeric(14,4) not null default 0,
  amount numeric(14,2) generated always as (round(qty * rate,2)) stored,
  remarks text,
  reference_entry_id uuid references public.rr_upm_entries(id),
  operator_user_id uuid default auth.uid(),
  operator_name text,
  created_at timestamptz not null default now()
);
create index if not exists rr_upm_entries_lot_idx on public.rr_upm_entries(canonical_lot_id,created_at desc);
create index if not exists rr_upm_entries_dept_idx on public.rr_upm_entries(department_code,created_at desc);

create table if not exists public.rr_upm_alter_requests (
  id uuid primary key default gen_random_uuid(),
  canonical_lot_id text not null,
  lot_no text not null,
  colour_code text not null default 'GENERAL',
  size_code text not null default 'ALL',
  from_department_code text not null,
  return_department_code text not null,
  qty numeric(14,3) not null check(qty > 0),
  reason text not null,
  status text not null default 'OPEN' check(status in ('OPEN','IN_PROGRESS','RETURNED','CLOSED','CANCELLED')),
  created_by uuid default auth.uid(),
  assigned_to uuid,
  created_at timestamptz not null default now(),
  closed_at timestamptz
);

create table if not exists public.rr_upm_audit (
 id bigserial primary key, action_code text not null, canonical_lot_id text, entity_type text,
 entity_id text, old_data jsonb, new_data jsonb, actor_user_id uuid default auth.uid(), created_at timestamptz not null default now()
);

alter table public.rr_upm_departments enable row level security;
alter table public.rr_upm_lot_registry enable row level security;
alter table public.rr_upm_colour_state enable row level security;
alter table public.rr_upm_entries enable row level security;
alter table public.rr_upm_alter_requests enable row level security;
alter table public.rr_upm_audit enable row level security;

do $$ begin
  create policy rr_upm_departments_read on public.rr_upm_departments for select to authenticated using (true);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy rr_upm_registry_read on public.rr_upm_lot_registry for select to authenticated using (true);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy rr_upm_colour_read on public.rr_upm_colour_state for select to authenticated using (true);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy rr_upm_entries_read on public.rr_upm_entries for select to authenticated using (true);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy rr_upm_alter_read on public.rr_upm_alter_requests for select to authenticated using (true);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy rr_upm_audit_read on public.rr_upm_audit for select to authenticated using (true);
exception when duplicate_object then null; end $$;

create or replace function public.rr_upm_is_operator()
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.rr_user_profiles p where p.auth_user_id=auth.uid() and coalesce(p.is_active,true)=true);
$$;

create or replace function public.rr_upm_register_lot_v1(
 p_canonical_lot_id text,p_lot_no text,p_source_table text default null,p_source_id text default null,
 p_art_no text default null,p_item_name text default null,p_total_qty numeric default 0,p_colours jsonb default '[]'::jsonb,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_row public.rr_upm_lot_registry; v_colour jsonb;
begin
 if not public.rr_upm_is_operator() then raise exception 'Active ERP user required'; end if;
 insert into public.rr_upm_lot_registry(canonical_lot_id,lot_no,source_table,source_id,art_no,item_name,total_qty,metadata)
 values(p_canonical_lot_id,p_lot_no,p_source_table,p_source_id,p_art_no,p_item_name,coalesce(p_total_qty,0),coalesce(p_metadata,'{}'))
 on conflict(canonical_lot_id) do update set lot_no=excluded.lot_no,source_table=coalesce(excluded.source_table,rr_upm_lot_registry.source_table),source_id=coalesce(excluded.source_id,rr_upm_lot_registry.source_id),art_no=coalesce(excluded.art_no,rr_upm_lot_registry.art_no),item_name=coalesce(excluded.item_name,rr_upm_lot_registry.item_name),total_qty=greatest(excluded.total_qty,rr_upm_lot_registry.total_qty),metadata=rr_upm_lot_registry.metadata||excluded.metadata,updated_at=now()
 returning * into v_row;
 if jsonb_typeof(p_colours)='array' and jsonb_array_length(p_colours)>0 then
  for v_colour in select * from jsonb_array_elements(p_colours) loop
   insert into public.rr_upm_colour_state(canonical_lot_id,colour_code,colour_name,planned_qty,current_department_code,status)
   values(p_canonical_lot_id,coalesce(v_colour->>'colour_code',v_colour->>'code','GENERAL'),coalesce(v_colour->>'colour_name',v_colour->>'name','General'),coalesce((v_colour->>'qty')::numeric,0),'CUTTING','PENDING')
   on conflict(canonical_lot_id,colour_code) do update set colour_name=excluded.colour_name,planned_qty=greatest(excluded.planned_qty,rr_upm_colour_state.planned_qty),updated_at=now();
  end loop;
 else
  insert into public.rr_upm_colour_state(canonical_lot_id,colour_code,colour_name,planned_qty)
  values(p_canonical_lot_id,'GENERAL','General',coalesce(p_total_qty,0)) on conflict do nothing;
 end if;
 insert into public.rr_upm_audit(action_code,canonical_lot_id,entity_type,entity_id,new_data) values('REGISTER_LOT',p_canonical_lot_id,'LOT',v_row.id::text,to_jsonb(v_row));
 return to_jsonb(v_row);
end $$;

create or replace function public.rr_upm_post_entry_v1(
 p_canonical_lot_id text,p_department_code text,p_colour_code text,p_size_code text,p_entry_type text,p_qty numeric,p_rate numeric default 0,p_remarks text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_lot public.rr_upm_lot_registry; v_entry public.rr_upm_entries; v_state public.rr_upm_colour_state; v_next text; v_good numeric; v_required numeric;
begin
 if not public.rr_upm_is_operator() then raise exception 'Active ERP user required'; end if;
 if p_qty is null or p_qty<=0 then raise exception 'Quantity must be greater than zero'; end if;
 select * into v_lot from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id;
 if not found then raise exception 'Lot is not registered in Universal Production'; end if;
 select * into v_state from public.rr_upm_colour_state where canonical_lot_id=p_canonical_lot_id and colour_code=coalesce(nullif(p_colour_code,''),'GENERAL') for update;
 if not found then
  insert into public.rr_upm_colour_state(canonical_lot_id,colour_code,colour_name,planned_qty,current_department_code)
  values(p_canonical_lot_id,coalesce(nullif(p_colour_code,''),'GENERAL'),coalesce(nullif(p_colour_code,''),'General'),0,p_department_code) returning * into v_state;
 end if;
 insert into public.rr_upm_entries(canonical_lot_id,lot_no,department_code,colour_code,size_code,entry_type,qty,rate,remarks)
 values(p_canonical_lot_id,v_lot.lot_no,p_department_code,coalesce(nullif(p_colour_code,''),'GENERAL'),coalesce(nullif(p_size_code,''),'ALL'),upper(p_entry_type),p_qty,coalesce(p_rate,0),p_remarks) returning * into v_entry;
 select coalesce(sum(qty) filter(where entry_type in ('GOOD','ALTER_IN','REMAKE','ADJUSTMENT')),0) into v_good from public.rr_upm_entries where canonical_lot_id=p_canonical_lot_id and colour_code=v_state.colour_code and department_code=p_department_code;
 v_required:=case when v_state.planned_qty>0 then v_state.planned_qty else v_lot.total_qty end;
 update public.rr_upm_colour_state set completed_qty=v_good,rejected_qty=rejected_qty+case when upper(p_entry_type)='REJECT' then p_qty else 0 end,alter_qty=alter_qty+case when upper(p_entry_type)='ALTER_OUT' then p_qty when upper(p_entry_type)='ALTER_IN' then -least(alter_qty,p_qty) else 0 end,status=case when v_required>0 and v_good>=v_required then 'COMPLETED' when v_good>0 then 'PARTIAL' else 'IN_PROGRESS' end,updated_at=now() where id=v_state.id returning * into v_state;
 if v_state.status='COMPLETED' then
  select department_code into v_next from public.rr_upm_departments where is_active and sequence_no>(select sequence_no from public.rr_upm_departments where department_code=p_department_code) order by sequence_no limit 1;
  if v_next is not null and coalesce((select auto_forward from public.rr_upm_departments where department_code=p_department_code),true) then update public.rr_upm_colour_state set current_department_code=v_next,status='PENDING',completed_qty=0,updated_at=now() where id=v_state.id; end if;
 end if;
 insert into public.rr_upm_audit(action_code,canonical_lot_id,entity_type,entity_id,new_data) values('POST_ENTRY',p_canonical_lot_id,'ENTRY',v_entry.id::text,to_jsonb(v_entry));
 return jsonb_build_object('entry',to_jsonb(v_entry),'state',(select to_jsonb(s) from public.rr_upm_colour_state s where s.id=v_state.id),'forwarded_to',v_next);
end $$;

create or replace function public.rr_upm_create_alter_v1(p_canonical_lot_id text,p_colour_code text,p_size_code text,p_from_department text,p_return_department text,p_qty numeric,p_reason text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_lot public.rr_upm_lot_registry; v_row public.rr_upm_alter_requests;
begin
 if not public.rr_upm_is_operator() then raise exception 'Active ERP user required'; end if;
 select * into v_lot from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id;
 if not found then raise exception 'Lot not found'; end if;
 insert into public.rr_upm_alter_requests(canonical_lot_id,lot_no,colour_code,size_code,from_department_code,return_department_code,qty,reason)
 values(p_canonical_lot_id,v_lot.lot_no,coalesce(nullif(p_colour_code,''),'GENERAL'),coalesce(nullif(p_size_code,''),'ALL'),p_from_department,p_return_department,p_qty,p_reason) returning * into v_row;
 perform public.rr_upm_post_entry_v1(p_canonical_lot_id,p_from_department,p_colour_code,p_size_code,'ALTER_OUT',p_qty,0,p_reason);
 return to_jsonb(v_row);
end $$;

create or replace function public.rr_upm_close_alter_v1(p_alter_id uuid,p_remarks text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v public.rr_upm_alter_requests;
begin
 select * into v from public.rr_upm_alter_requests where id=p_alter_id for update;
 if not found then raise exception 'Alter request not found'; end if;
 perform public.rr_upm_post_entry_v1(v.canonical_lot_id,v.from_department_code,v.colour_code,v.size_code,'ALTER_IN',v.qty,0,p_remarks);
 update public.rr_upm_alter_requests set status='CLOSED',closed_at=now() where id=p_alter_id returning * into v;
 return to_jsonb(v);
end $$;

grant execute on function public.rr_upm_register_lot_v1(text,text,text,text,text,text,numeric,jsonb,jsonb) to authenticated;
grant execute on function public.rr_upm_post_entry_v1(text,text,text,text,text,numeric,numeric,text) to authenticated;
grant execute on function public.rr_upm_create_alter_v1(text,text,text,text,text,numeric,text) to authenticated;
grant execute on function public.rr_upm_close_alter_v1(uuid,text) to authenticated;

create or replace view public.rr_upm_lot_board_v1 as
select l.*, coalesce(jsonb_agg(to_jsonb(c) order by d.sequence_no) filter(where c.id is not null),'[]'::jsonb) colours,
 coalesce(sum(c.planned_qty),0) planned_colour_qty,
 max(l.updated_at) board_updated_at
from public.rr_upm_lot_registry l
left join public.rr_upm_colour_state c on c.canonical_lot_id=l.canonical_lot_id
left join public.rr_upm_departments d on d.department_code=c.current_department_code
group by l.id;

grant select on public.rr_upm_lot_board_v1 to authenticated;
