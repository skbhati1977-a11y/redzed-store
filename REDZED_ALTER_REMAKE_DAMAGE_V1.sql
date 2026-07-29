-- REDZED ERP — Universal Production Alter / Remake / Damage V1
-- Run on a BACKUP / TEST Supabase project first.
-- Assumptions:
--   1) auth.users is used.
--   2) Your app sets user role metadata or provides public profiles.
--   3) Lot identity is the existing lot_no text.

begin;

create extension if not exists pgcrypto;

-- ---------- helpers ----------
create or replace function public.rr_up_current_role_v1()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select upper(coalesce(
    auth.jwt() -> 'app_metadata' ->> 'role',
    auth.jwt() -> 'user_metadata' ->> 'role',
    'WORKER'
  ));
$$;

create or replace function public.rr_up_is_owner_admin_v1()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.rr_up_current_role_v1() in ('OWNER','ADMIN');
$$;

create or replace function public.rr_up_is_department_head_v1()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.rr_up_current_role_v1() in ('DEPARTMENT_HEAD','DEPT_HEAD','HEAD','OWNER','ADMIN');
$$;

create or replace function public.rr_up_is_cutting_master_v1()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.rr_up_current_role_v1() in ('CUTTING_MASTER','MASTER','OWNER','ADMIN');
$$;

-- ---------- master records ----------
create table if not exists public.rr_up_alters (
  id uuid primary key default gen_random_uuid(),
  alter_no bigint generated always as identity unique,
  alter_code text generated always as ('ALT-' || lpad(alter_no::text, 7, '0')) stored,
  lot_no text not null,
  department_id uuid,
  department_name text not null,
  worker_id uuid not null,
  worker_name text not null,
  line_man_id uuid,
  line_man_name text,
  cutting_master_id uuid,
  cutting_master_name text,
  registered_by uuid not null default auth.uid(),
  registered_by_role text not null default public.rr_up_current_role_v1(),
  status text not null default 'OPEN' check (status in ('OPEN','PARTIAL','REMAKE_ISSUED','READY_TO_VERIFY','CLOSED','CANCELLED')),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  closed_at timestamptz,
  closed_by uuid,
  original_locked boolean not null default true
);

create index if not exists rr_up_alters_lot_idx on public.rr_up_alters(lot_no, created_at desc);
create index if not exists rr_up_alters_worker_idx on public.rr_up_alters(worker_id, created_at desc);
create index if not exists rr_up_alters_department_idx on public.rr_up_alters(department_id, created_at desc);

create table if not exists public.rr_up_alter_lines (
  id uuid primary key default gen_random_uuid(),
  alter_id uuid not null references public.rr_up_alters(id) on delete restrict,
  colour_id uuid,
  colour_name text not null,
  size_code text not null,
  alter_qty integer not null check (alter_qty > 0),
  created_at timestamptz not null default now(),
  unique(alter_id, colour_name, size_code)
);

create index if not exists rr_up_alter_lines_alter_idx on public.rr_up_alter_lines(alter_id);

create table if not exists public.rr_up_remakes (
  id uuid primary key default gen_random_uuid(),
  alter_id uuid not null references public.rr_up_alters(id) on delete restrict,
  issued_by uuid not null default auth.uid(),
  issued_by_name text,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists rr_up_remakes_alter_idx on public.rr_up_remakes(alter_id, created_at desc);

create table if not exists public.rr_up_remake_lines (
  id uuid primary key default gen_random_uuid(),
  remake_id uuid not null references public.rr_up_remakes(id) on delete restrict,
  alter_line_id uuid not null references public.rr_up_alter_lines(id) on delete restrict,
  qty integer not null check (qty > 0),
  created_at timestamptz not null default now(),
  unique(remake_id, alter_line_id)
);

create index if not exists rr_up_remake_lines_line_idx on public.rr_up_remake_lines(alter_line_id);

create table if not exists public.rr_up_damages (
  id uuid primary key default gen_random_uuid(),
  alter_id uuid not null references public.rr_up_alters(id) on delete restrict,
  fault_worker_id uuid,
  fault_worker_name text,
  reason text not null,
  note text,
  created_by uuid not null default auth.uid(),
  updated_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists rr_up_damages_alter_idx on public.rr_up_damages(alter_id, created_at desc);

create table if not exists public.rr_up_damage_lines (
  id uuid primary key default gen_random_uuid(),
  damage_id uuid not null references public.rr_up_damages(id) on delete restrict,
  alter_line_id uuid not null references public.rr_up_alter_lines(id) on delete restrict,
  qty integer not null check (qty > 0),
  created_at timestamptz not null default now(),
  unique(damage_id, alter_line_id)
);

create index if not exists rr_up_damage_lines_line_idx on public.rr_up_damage_lines(alter_line_id);

create table if not exists public.rr_up_alter_media (
  id uuid primary key default gen_random_uuid(),
  alter_id uuid not null references public.rr_up_alters(id) on delete restrict,
  entity_type text not null check (entity_type in ('ALTER','REMAKE','DAMAGE','VERIFY')),
  entity_id uuid,
  storage_bucket text not null default 'redzed-alter-evidence',
  storage_path text not null unique,
  mime_type text,
  captured_live boolean not null default true,
  uploaded_by uuid not null default auth.uid(),
  uploaded_by_name text,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  deleted_by uuid
);

create index if not exists rr_up_alter_media_alter_idx on public.rr_up_alter_media(alter_id, created_at);

create table if not exists public.rr_up_alter_status_log (
  id bigint generated always as identity primary key,
  alter_id uuid not null references public.rr_up_alters(id) on delete restrict,
  old_status text,
  new_status text not null,
  note text,
  changed_by uuid not null default auth.uid(),
  changed_by_role text not null default public.rr_up_current_role_v1(),
  created_at timestamptz not null default now()
);

-- ---------- immutable original protection ----------
create or replace function public.rr_up_block_original_change_v1()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.rr_up_is_owner_admin_v1() then
    return new;
  end if;
  raise exception 'Original Alter record is locked after submit.';
end;
$$;

drop trigger if exists rr_up_alters_no_update on public.rr_up_alters;
create trigger rr_up_alters_no_update
before update or delete on public.rr_up_alters
for each row execute function public.rr_up_block_original_change_v1();

drop trigger if exists rr_up_alter_lines_no_update on public.rr_up_alter_lines;
create trigger rr_up_alter_lines_no_update
before update or delete on public.rr_up_alter_lines
for each row execute function public.rr_up_block_original_change_v1();

-- Media can only be soft-deleted by owner/admin; no physical delete.
create or replace function public.rr_up_block_media_delete_v1()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'Evidence cannot be physically deleted. Use owner/admin soft-delete.';
end;
$$;

drop trigger if exists rr_up_media_no_delete on public.rr_up_alter_media;
create trigger rr_up_media_no_delete
before delete on public.rr_up_alter_media
for each row execute function public.rr_up_block_media_delete_v1();

-- ---------- quantity view ----------
create or replace view public.rr_up_alter_line_balance_v1 as
select
  l.id as alter_line_id,
  l.alter_id,
  l.colour_id,
  l.colour_name,
  l.size_code,
  l.alter_qty,
  coalesce(r.remake_qty,0)::integer as remake_qty,
  coalesce(d.damage_qty,0)::integer as damage_qty,
  greatest(l.alter_qty - coalesce(r.remake_qty,0) - coalesce(d.damage_qty,0),0)::integer as pending_qty
from public.rr_up_alter_lines l
left join (
  select rl.alter_line_id, sum(rl.qty)::integer remake_qty
  from public.rr_up_remake_lines rl
  group by rl.alter_line_id
) r on r.alter_line_id=l.id
left join (
  select dl.alter_line_id, sum(dl.qty)::integer damage_qty
  from public.rr_up_damage_lines dl
  group by dl.alter_line_id
) d on d.alter_line_id=l.id;

create or replace view public.rr_up_alter_card_v1 as
select
  a.*,
  coalesce(sum(b.alter_qty),0)::integer as alter_qty,
  coalesce(sum(b.remake_qty),0)::integer as remake_qty,
  coalesce(sum(b.damage_qty),0)::integer as damage_qty,
  coalesce(sum(b.pending_qty),0)::integer as pending_qty
from public.rr_up_alters a
left join public.rr_up_alter_line_balance_v1 b on b.alter_id=a.id
group by a.id;

-- ---------- validation ----------
create or replace function public.rr_up_validate_line_capacity_v1(p_alter_line_id uuid, p_new_qty integer, p_kind text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_line public.rr_up_alter_lines%rowtype;
  v_remake integer;
  v_damage integer;
begin
  select * into v_line from public.rr_up_alter_lines where id=p_alter_line_id for update;
  if not found then raise exception 'Alter colour-size line not found.'; end if;

  select coalesce(sum(rl.qty),0)::integer into v_remake
  from public.rr_up_remake_lines rl where rl.alter_line_id=p_alter_line_id;

  select coalesce(sum(dl.qty),0)::integer into v_damage
  from public.rr_up_damage_lines dl where dl.alter_line_id=p_alter_line_id;

  if upper(p_kind)='REMAKE' then v_remake := v_remake + p_new_qty;
  elsif upper(p_kind)='DAMAGE' then v_damage := v_damage + p_new_qty;
  else raise exception 'Invalid capacity type.';
  end if;

  if v_remake + v_damage > v_line.alter_qty then
    raise exception 'Remake + Damage cannot exceed Alter Qty for % / %.', v_line.colour_name, v_line.size_code;
  end if;
end;
$$;

-- ---------- main RPCs ----------
create or replace function public.rr_up_register_alter_v1(
  p_lot_no text,
  p_department_id uuid,
  p_department_name text,
  p_worker_id uuid,
  p_worker_name text,
  p_line_man_id uuid,
  p_line_man_name text,
  p_cutting_master_id uuid,
  p_cutting_master_name text,
  p_lines jsonb,
  p_note text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_alter public.rr_up_alters%rowtype;
  v_role text := public.rr_up_current_role_v1();
  v_row jsonb;
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  if v_role not in ('WORKER','DEPARTMENT_HEAD','DEPT_HEAD','HEAD','OWNER','ADMIN') then
    raise exception 'Only worker or Department Head can register Alter.';
  end if;
  if v_role='WORKER' and p_worker_id <> auth.uid() then
    raise exception 'Worker can register Alter only against himself.';
  end if;
  if nullif(trim(p_lot_no),'') is null then raise exception 'Lot No is required.'; end if;
  if nullif(trim(p_department_name),'') is null then raise exception 'Department is required.'; end if;
  if p_worker_id is null or nullif(trim(p_worker_name),'') is null then raise exception 'Worker is required.'; end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines)=0 then raise exception 'Colour-size lines are required.'; end if;

  insert into public.rr_up_alters(
    lot_no,department_id,department_name,worker_id,worker_name,
    line_man_id,line_man_name,cutting_master_id,cutting_master_name,note
  ) values (
    trim(p_lot_no),p_department_id,trim(p_department_name),p_worker_id,trim(p_worker_name),
    p_line_man_id,nullif(trim(p_line_man_name),''),p_cutting_master_id,nullif(trim(p_cutting_master_name),''),nullif(trim(p_note),'')
  ) returning * into v_alter;

  for v_row in select value from jsonb_array_elements(p_lines)
  loop
    if coalesce((v_row->>'qty')::integer,0) <= 0 then raise exception 'Every Alter line Qty must be greater than zero.'; end if;
    if nullif(trim(v_row->>'colour_name'),'') is null or nullif(trim(v_row->>'size_code'),'') is null then
      raise exception 'Colour and Size are mandatory.';
    end if;
    insert into public.rr_up_alter_lines(alter_id,colour_id,colour_name,size_code,alter_qty)
    values(v_alter.id,nullif(v_row->>'colour_id','')::uuid,trim(v_row->>'colour_name'),upper(trim(v_row->>'size_code')),(v_row->>'qty')::integer);
  end loop;

  insert into public.rr_up_alter_status_log(alter_id,new_status,note)
  values(v_alter.id,'OPEN','Alter registered');

  return to_jsonb(v_alter);
end;
$$;

create or replace function public.rr_up_issue_remake_v1(
  p_alter_id uuid,
  p_lines jsonb,
  p_issued_by_name text default null,
  p_note text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_remake public.rr_up_remakes%rowtype;
  v_row jsonb;
  v_qty integer;
  v_line_id uuid;
begin
  if not public.rr_up_is_cutting_master_v1() then raise exception 'Only Cutting Master can issue remake.'; end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines)=0 then raise exception 'Remake colour-size lines are required.'; end if;

  insert into public.rr_up_remakes(alter_id,issued_by_name,note)
  values(p_alter_id,nullif(trim(p_issued_by_name),''),nullif(trim(p_note),'')) returning * into v_remake;

  for v_row in select value from jsonb_array_elements(p_lines)
  loop
    v_line_id := (v_row->>'alter_line_id')::uuid;
    v_qty := coalesce((v_row->>'qty')::integer,0);
    if v_qty <= 0 then continue; end if;
    perform public.rr_up_validate_line_capacity_v1(v_line_id,v_qty,'REMAKE');
    insert into public.rr_up_remake_lines(remake_id,alter_line_id,qty) values(v_remake.id,v_line_id,v_qty);
  end loop;

  update public.rr_up_alters set status='REMAKE_ISSUED',updated_at=now() where id=p_alter_id;
  insert into public.rr_up_alter_status_log(alter_id,old_status,new_status,note)
  values(p_alter_id,'OPEN','REMAKE_ISSUED','Colour-size remake issued');
  return to_jsonb(v_remake);
end;
$$;

create or replace function public.rr_up_save_damage_v1(
  p_alter_id uuid,
  p_damage_id uuid,
  p_fault_worker_id uuid,
  p_fault_worker_name text,
  p_reason text,
  p_note text,
  p_lines jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_damage public.rr_up_damages%rowtype;
  v_row jsonb;
  v_qty integer;
  v_line_id uuid;
begin
  if not public.rr_up_is_department_head_v1() then raise exception 'Only Department Head can register/edit Damage.'; end if;
  if nullif(trim(p_reason),'') is null then raise exception 'Damage reason is required.'; end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines)=0 then raise exception 'Damage colour-size lines are required.'; end if;

  if p_damage_id is null then
    insert into public.rr_up_damages(alter_id,fault_worker_id,fault_worker_name,reason,note)
    values(p_alter_id,p_fault_worker_id,nullif(trim(p_fault_worker_name),''),trim(p_reason),nullif(trim(p_note),''))
    returning * into v_damage;
  else
    select * into v_damage from public.rr_up_damages where id=p_damage_id and alter_id=p_alter_id for update;
    if not found then raise exception 'Damage entry not found.'; end if;
    delete from public.rr_up_damage_lines where damage_id=p_damage_id;
    update public.rr_up_damages set
      fault_worker_id=p_fault_worker_id,
      fault_worker_name=nullif(trim(p_fault_worker_name),''),
      reason=trim(p_reason),note=nullif(trim(p_note),''),updated_by=auth.uid(),updated_at=now()
    where id=p_damage_id returning * into v_damage;
  end if;

  for v_row in select value from jsonb_array_elements(p_lines)
  loop
    v_line_id := (v_row->>'alter_line_id')::uuid;
    v_qty := coalesce((v_row->>'qty')::integer,0);
    if v_qty <= 0 then continue; end if;
    perform public.rr_up_validate_line_capacity_v1(v_line_id,v_qty,'DAMAGE');
    insert into public.rr_up_damage_lines(damage_id,alter_line_id,qty) values(v_damage.id,v_line_id,v_qty);
  end loop;

  update public.rr_up_alters set updated_at=now() where id=p_alter_id;
  return to_jsonb(v_damage);
end;
$$;

create or replace function public.rr_up_add_media_v1(
  p_alter_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_storage_path text,
  p_mime_type text,
  p_captured_live boolean,
  p_uploaded_by_name text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_media public.rr_up_alter_media%rowtype;
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  if upper(trim(p_entity_type)) not in ('ALTER','REMAKE','DAMAGE','VERIFY') then raise exception 'Invalid image type.'; end if;
  if upper(trim(p_entity_type))='ALTER' and not p_captured_live then raise exception 'Alter evidence must be captured from live camera.'; end if;
  insert into public.rr_up_alter_media(alter_id,entity_type,entity_id,storage_path,mime_type,captured_live,uploaded_by_name)
  values(p_alter_id,upper(trim(p_entity_type)),p_entity_id,trim(p_storage_path),p_mime_type,p_captured_live,nullif(trim(p_uploaded_by_name),''))
  returning * into v_media;
  return to_jsonb(v_media);
end;
$$;

create or replace function public.rr_up_set_alter_status_v1(p_alter_id uuid,p_status text,p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old text;
  v_new text := upper(trim(p_status));
  v_pending integer;
  v_row public.rr_up_alters%rowtype;
begin
  if not public.rr_up_is_department_head_v1() then raise exception 'Only Department Head/Admin can update Alter status.'; end if;
  if v_new not in ('OPEN','PARTIAL','REMAKE_ISSUED','READY_TO_VERIFY','CLOSED','CANCELLED') then raise exception 'Invalid status.'; end if;
  select status into v_old from public.rr_up_alters where id=p_alter_id for update;
  if not found then raise exception 'Alter not found.'; end if;
  select coalesce(sum(pending_qty),0)::integer into v_pending from public.rr_up_alter_line_balance_v1 where alter_id=p_alter_id;
  if v_new='CLOSED' and v_pending<>0 then raise exception 'Alter cannot close while pending quantity is %.',v_pending; end if;
  update public.rr_up_alters set status=v_new,updated_at=now(),closed_at=case when v_new='CLOSED' then now() else null end,closed_by=case when v_new='CLOSED' then auth.uid() else null end
  where id=p_alter_id returning * into v_row;
  insert into public.rr_up_alter_status_log(alter_id,old_status,new_status,note) values(p_alter_id,v_old,v_new,nullif(trim(p_note),''));
  return to_jsonb(v_row);
end;
$$;

create or replace function public.rr_up_soft_delete_media_v1(p_media_id uuid,p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_media public.rr_up_alter_media%rowtype;
begin
  if not public.rr_up_is_owner_admin_v1() then raise exception 'Only Owner/Admin can hide evidence.'; end if;
  if nullif(trim(p_reason),'') is null then raise exception 'Reason is required.'; end if;
  update public.rr_up_alter_media set deleted_at=now(),deleted_by=auth.uid()
  where id=p_media_id and deleted_at is null returning * into v_media;
  if not found then raise exception 'Evidence not found or already hidden.'; end if;
  return to_jsonb(v_media) || jsonb_build_object('reason',trim(p_reason));
end;
$$;

-- ---------- RLS ----------
alter table public.rr_up_alters enable row level security;
alter table public.rr_up_alter_lines enable row level security;
alter table public.rr_up_remakes enable row level security;
alter table public.rr_up_remake_lines enable row level security;
alter table public.rr_up_damages enable row level security;
alter table public.rr_up_damage_lines enable row level security;
alter table public.rr_up_alter_media enable row level security;
alter table public.rr_up_alter_status_log enable row level security;

-- Related authenticated users can view. Mutations happen through SECURITY DEFINER RPCs.
do $$
declare t text;
begin
  foreach t in array array['rr_up_alters','rr_up_alter_lines','rr_up_remakes','rr_up_remake_lines','rr_up_damages','rr_up_damage_lines','rr_up_alter_media','rr_up_alter_status_log']
  loop
    execute format('drop policy if exists %I on public.%I',t||'_read',t);
    execute format('create policy %I on public.%I for select to authenticated using (true)',t||'_read',t);
  end loop;
end $$;

-- ---------- Storage bucket ----------
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('redzed-alter-evidence','redzed-alter-evidence',false,10485760,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists rr_up_evidence_read on storage.objects;
create policy rr_up_evidence_read on storage.objects for select to authenticated
using (bucket_id='redzed-alter-evidence');

drop policy if exists rr_up_evidence_insert on storage.objects;
create policy rr_up_evidence_insert on storage.objects for insert to authenticated
with check (bucket_id='redzed-alter-evidence' and (storage.foldername(name))[1]=auth.uid()::text);

-- No client update/delete policy: evidence is immutable.

grant select on public.rr_up_alter_card_v1,public.rr_up_alter_line_balance_v1 to authenticated;
grant select on public.rr_up_alters,public.rr_up_alter_lines,public.rr_up_remakes,public.rr_up_remake_lines,public.rr_up_damages,public.rr_up_damage_lines,public.rr_up_alter_media,public.rr_up_alter_status_log to authenticated;
grant execute on function public.rr_up_register_alter_v1(text,uuid,text,uuid,text,uuid,text,uuid,text,jsonb,text) to authenticated;
grant execute on function public.rr_up_issue_remake_v1(uuid,jsonb,text,text) to authenticated;
grant execute on function public.rr_up_save_damage_v1(uuid,uuid,uuid,text,text,text,jsonb) to authenticated;
grant execute on function public.rr_up_add_media_v1(uuid,text,uuid,text,text,boolean,text) to authenticated;
grant execute on function public.rr_up_set_alter_status_v1(uuid,text,text) to authenticated;
grant execute on function public.rr_up_soft_delete_media_v1(uuid,text) to authenticated;

commit;
