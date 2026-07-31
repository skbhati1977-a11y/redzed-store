-- REDZED STORE — Dynamic Department Master + Multi-Skill Workers + UPM Flow Fix
-- Web filenames remain unchanged. Put release/version only in the Git commit message.
-- Requires existing Role & Permission, Unified Worker Directory and UPM foundations.

begin;
create extension if not exists pgcrypto;

-- ============================================================================
-- A. DYNAMIC DEPARTMENT CAPABILITIES
-- ============================================================================
alter table public.rr_departments_v1
  add column if not exists department_type text not null default 'PRODUCTION',
  add column if not exists production_enabled boolean not null default true,
  add column if not exists worker_assignment_enabled boolean not null default true,
  add column if not exists rate_enabled boolean not null default true,
  add column if not exists colour_assignment_enabled boolean not null default true,
  add column if not exists allow_alter boolean not null default true,
  add column if not exists code_locked boolean not null default true,
  add column if not exists archived_at timestamptz,
  add column if not exists archive_reason text;

alter table public.rr_upm_departments
  add column if not exists parent_department_code text,
  add column if not exists department_type text not null default 'PRODUCTION',
  add column if not exists worker_assignment_enabled boolean not null default true,
  add column if not exists rate_enabled boolean not null default true,
  add column if not exists colour_assignment_enabled boolean not null default true;

-- Kaaj and Button stay separate processes. The same worker may be enabled for both.
insert into public.rr_departments_v1(
  department_code,department_name,display_order,parent_department_code,is_external,is_active,
  department_type,production_enabled,worker_assignment_enabled,rate_enabled,
  colour_assignment_enabled,allow_alter,code_locked,updated_at
)
values
  ('kaaj','Kaaj',52,'fabrication',false,true,'FABRICATION',true,true,true,true,true,true,now()),
  ('button','Button / BTN',53,'fabrication',false,true,'FABRICATION',true,true,true,true,true,true,now())
on conflict(department_code) do update set
  department_name=excluded.department_name,
  parent_department_code=excluded.parent_department_code,
  is_active=true,
  department_type=excluded.department_type,
  production_enabled=true,
  worker_assignment_enabled=true,
  rate_enabled=true,
  colour_assignment_enabled=true,
  allow_alter=true,
  updated_at=now();

update public.rr_departments_v1
set display_order=case department_code
  when 'overlock' then 54 when 'folding' then 55 when 'thread_cut' then 56
  when 'qc' then 57 when 'press' then 58 when 'packing' then 59 else display_order end,
  updated_at=now()
where department_code in('overlock','folding','thread_cut','qc','press','packing');

insert into public.rr_upm_departments(
  department_code,department_name,sequence_no,entry_mode,is_start_department,is_final_department,
  auto_forward,allow_partial,allow_alter,is_active,parent_department_code,department_type,
  worker_assignment_enabled,rate_enabled,colour_assignment_enabled,updated_at
)
values
  ('KAAJ','Kaaj',52,'COLOUR_SIZE',false,false,true,true,true,true,'fabrication','FABRICATION',true,true,true,now()),
  ('BUTTON','Button / BTN',53,'COLOUR_SIZE',false,false,true,true,true,true,'fabrication','FABRICATION',true,true,true,now())
on conflict(department_code) do update set
  department_name=excluded.department_name,
  sequence_no=excluded.sequence_no,
  entry_mode=excluded.entry_mode,
  allow_alter=excluded.allow_alter,
  is_active=true,
  parent_department_code=excluded.parent_department_code,
  department_type=excluded.department_type,
  worker_assignment_enabled=true,
  rate_enabled=true,
  colour_assignment_enabled=true,
  updated_at=now();

insert into public.rr_role_department_map_v1(role_code,role_name,department_code,is_owner_master,is_active,updated_at)
values
  ('kaaj','Kaaj','kaaj',false,true,now()),
  ('kaaj_operator','Kaaj Operator','kaaj',false,true,now()),
  ('button','Button / BTN','button',false,true,now()),
  ('btn','Button / BTN','button',false,true,now()),
  ('button_operator','Button Operator','button',false,true,now())
on conflict(role_code) do update set
  role_name=excluded.role_name,
  department_code=excluded.department_code,
  is_active=true,
  updated_at=now();

-- One worker can have one primary department plus any number of additional skills.
create table if not exists public.rr_worker_department_map_v1(
  worker_id uuid not null,
  department_code text not null references public.rr_departments_v1(department_code),
  is_primary boolean not null default false,
  is_active boolean not null default true,
  assigned_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(worker_id,department_code)
);
create unique index if not exists rr_worker_department_map_v1_primary_uq
on public.rr_worker_department_map_v1(worker_id)
where is_primary and is_active;
create index if not exists rr_worker_department_map_v1_department_idx
on public.rr_worker_department_map_v1(department_code,worker_id)
where is_active;

alter table public.rr_worker_department_map_v1 enable row level security;
drop policy if exists rr_worker_department_map_v1_read on public.rr_worker_department_map_v1;
create policy rr_worker_department_map_v1_read on public.rr_worker_department_map_v1
for select to authenticated using(true);
grant select on public.rr_worker_department_map_v1 to authenticated;

do $backfill$
begin
  if to_regclass('public.rr_worker_directory_unified_v1') is not null then
    insert into public.rr_worker_department_map_v1(worker_id,department_code,is_primary,is_active)
    select u.worker_id,lower(u.department_code),true,true
    from public.rr_worker_directory_unified_v1 u
    join public.rr_departments_v1 d on d.department_code=lower(u.department_code)
    where u.worker_id is not null and nullif(trim(u.department_code),'') is not null
    on conflict(worker_id,department_code) do nothing;
  end if;
end
$backfill$;

-- UPM action keys become visible in Role & Permission Action Matrix.
insert into public.rr_action_master_v1(action_key,display_name,module_code,is_sensitive,display_order,is_active)
values
  ('upm.assign_work','UPM · Assign Work','production',false,210,true),
  ('upm.submit_work','UPM · Submit Good Work','production',false,220,true),
  ('upm.register_alter','UPM · Register Alter','production',false,230,true),
  ('upm.remake_issue','UPM · Issue Remake','production',false,240,true),
  ('upm.remake_complete','UPM · Complete Remake','production',false,250,true),
  ('upm.damage','UPM · Save Damage','production',true,260,true),
  ('upm.reassign_pending','UPM · Reassign Pending','production',true,270,true)
on conflict(action_key) do update set
  display_name=excluded.display_name,module_code=excluded.module_code,
  is_sensitive=excluded.is_sensitive,display_order=excluded.display_order,is_active=true;

-- Existing production departments get working defaults. Owner can still deny or override.
insert into public.rr_department_action_permissions_v1(action_key,department_code,is_allowed,updated_at)
select a.action_key,d.department_code,true,now()
from public.rr_action_master_v1 a
cross join public.rr_departments_v1 d
where a.action_key like 'upm.%'
  and d.is_active and coalesce(d.production_enabled,false)
on conflict(action_key,department_code) do nothing;

create or replace function public.rr_owner_department_console_v2()
returns jsonb
language plpgsql stable security definer set search_path=public as $function$
declare v_role text;
begin
  select lower(role_code) into v_role from public.rr_user_profiles
  where auth_user_id=auth.uid() and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE' limit 1;
  if coalesce(v_role,'') not in('owner','admin') then raise exception 'Owner/Admin permission required.'; end if;

  return jsonb_build_object(
    'departments',coalesce((
      select jsonb_agg(to_jsonb(d)||jsonb_build_object(
        'upm_department_code',u.department_code,
        'upm_entry_mode',u.entry_mode,
        'upm_is_active',u.is_active
      ) order by d.display_order,d.department_name)
      from public.rr_departments_v1 d
      left join public.rr_upm_departments u on lower(u.department_code)=d.department_code
    ),'[]'::jsonb),
    'roles',coalesce((
      select jsonb_agg(to_jsonb(r) order by r.role_name,r.role_code)
      from public.rr_role_department_map_v1 r
    ),'[]'::jsonb),
    'worker_skills',coalesce((
      select jsonb_agg(to_jsonb(m)||jsonb_build_object('department_name',d.department_name)
        order by m.worker_id,m.is_primary desc,d.display_order)
      from public.rr_worker_department_map_v1 m
      join public.rr_departments_v1 d on d.department_code=m.department_code
    ),'[]'::jsonb)
  );
end
$function$;
grant execute on function public.rr_owner_department_console_v2() to authenticated;

create or replace function public.rr_owner_save_department_v2(
  p_department_code text,
  p_department_name text,
  p_parent_department_code text default null,
  p_department_type text default 'PRODUCTION',
  p_display_order integer default 100,
  p_is_active boolean default true,
  p_production_enabled boolean default true,
  p_worker_assignment_enabled boolean default true,
  p_rate_enabled boolean default true,
  p_colour_assignment_enabled boolean default true,
  p_allow_alter boolean default true,
  p_copy_permissions_from text default null,
  p_copy_permissions boolean default false,
  p_create_role boolean default true
)
returns jsonb
language plpgsql security definer set search_path=public as $function$
declare
  v_role text;
  v_code text:=lower(trim(p_department_code));
  v_parent text:=nullif(lower(trim(p_parent_department_code)),'');
  v_copy text:=nullif(lower(trim(p_copy_permissions_from)),'');
  v_type text:=upper(trim(coalesce(p_department_type,'PRODUCTION')));
  v_existing boolean;
begin
  select lower(role_code) into v_role from public.rr_user_profiles
  where auth_user_id=auth.uid() and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE' limit 1;
  if coalesce(v_role,'') not in('owner','admin') then raise exception 'Owner/Admin permission required.'; end if;
  if v_code !~ '^[a-z][a-z0-9_]{1,39}$' then raise exception 'Department code must use lowercase letters, numbers and underscore; minimum 2 characters.'; end if;
  if nullif(trim(p_department_name),'') is null then raise exception 'Department name is required.'; end if;
  if v_parent=v_code then raise exception 'A department cannot be its own parent.'; end if;
  if v_parent is not null and not exists(select 1 from public.rr_departments_v1 where department_code=v_parent) then raise exception 'Parent department not found.'; end if;
  if v_copy is not null and not exists(select 1 from public.rr_departments_v1 where department_code=v_copy) then raise exception 'Permission template department not found.'; end if;
  select exists(select 1 from public.rr_departments_v1 where department_code=v_code) into v_existing;

  insert into public.rr_departments_v1(
    department_code,department_name,display_order,parent_department_code,is_external,is_active,
    department_type,production_enabled,worker_assignment_enabled,rate_enabled,
    colour_assignment_enabled,allow_alter,code_locked,archived_at,archive_reason,updated_at
  ) values(
    v_code,trim(p_department_name),coalesce(p_display_order,100),v_parent,false,coalesce(p_is_active,true),
    v_type,coalesce(p_production_enabled,true),coalesce(p_worker_assignment_enabled,true),coalesce(p_rate_enabled,true),
    coalesce(p_colour_assignment_enabled,true),coalesce(p_allow_alter,true),true,
    case when coalesce(p_is_active,true) then null else now() end,null,now()
  )
  on conflict(department_code) do update set
    department_name=excluded.department_name,
    display_order=excluded.display_order,
    parent_department_code=excluded.parent_department_code,
    is_active=excluded.is_active,
    department_type=excluded.department_type,
    production_enabled=excluded.production_enabled,
    worker_assignment_enabled=excluded.worker_assignment_enabled,
    rate_enabled=excluded.rate_enabled,
    colour_assignment_enabled=excluded.colour_assignment_enabled,
    allow_alter=excluded.allow_alter,
    archived_at=excluded.archived_at,
    updated_at=now();

  if coalesce(p_production_enabled,true) then
    insert into public.rr_upm_departments(
      department_code,department_name,sequence_no,entry_mode,is_start_department,is_final_department,
      auto_forward,allow_partial,allow_alter,is_active,parent_department_code,department_type,
      worker_assignment_enabled,rate_enabled,colour_assignment_enabled,updated_at
    ) values(
      upper(v_code),trim(p_department_name),coalesce(p_display_order,100),'COLOUR_SIZE',false,false,
      true,true,coalesce(p_allow_alter,true),coalesce(p_is_active,true),v_parent,v_type,
      coalesce(p_worker_assignment_enabled,true),coalesce(p_rate_enabled,true),coalesce(p_colour_assignment_enabled,true),now()
    ) on conflict(department_code) do update set
      department_name=excluded.department_name,
      sequence_no=excluded.sequence_no,
      entry_mode=excluded.entry_mode,
      allow_alter=excluded.allow_alter,
      is_active=excluded.is_active,
      parent_department_code=excluded.parent_department_code,
      department_type=excluded.department_type,
      worker_assignment_enabled=excluded.worker_assignment_enabled,
      rate_enabled=excluded.rate_enabled,
      colour_assignment_enabled=excluded.colour_assignment_enabled,
      updated_at=now();
  else
    update public.rr_upm_departments set is_active=false,updated_at=now() where department_code=upper(v_code);
  end if;

  if coalesce(p_create_role,true) then
    insert into public.rr_role_department_map_v1(role_code,role_name,department_code,is_owner_master,is_active,updated_at)
    values(v_code,trim(p_department_name),v_code,false,coalesce(p_is_active,true),now())
    on conflict(role_code) do update set role_name=excluded.role_name,department_code=excluded.department_code,is_active=excluded.is_active,updated_at=now();
  end if;

  if coalesce(p_copy_permissions,false) and v_copy is not null then
    delete from public.rr_department_field_permissions_v1 where department_code=v_code;
    insert into public.rr_department_field_permissions_v1(field_id,department_code,access_mode,updated_by,updated_at)
    select field_id,v_code,access_mode,auth.uid(),now()
    from public.rr_department_field_permissions_v1 where department_code=v_copy;

    delete from public.rr_department_action_permissions_v1 where department_code=v_code;
    insert into public.rr_department_action_permissions_v1(action_key,department_code,is_allowed,updated_by,updated_at)
    select action_key,v_code,is_allowed,auth.uid(),now()
    from public.rr_department_action_permissions_v1 where department_code=v_copy;
  else
    insert into public.rr_department_field_permissions_v1(field_id,department_code,access_mode,updated_by,updated_at)
    select f.id,v_code,'HIDE',auth.uid(),now() from public.rr_field_master_v1 f
    on conflict(field_id,department_code) do nothing;

    insert into public.rr_department_action_permissions_v1(action_key,department_code,is_allowed,updated_by,updated_at)
    select a.action_key,v_code,(a.action_key like 'upm.%' and coalesce(p_production_enabled,true)),auth.uid(),now()
    from public.rr_action_master_v1 a
    on conflict(action_key,department_code) do nothing;
  end if;

  return jsonb_build_object('ok',true,'department_code',v_code,'created',not v_existing,'mapped_to_upm',coalesce(p_production_enabled,true));
end
$function$;
grant execute on function public.rr_owner_save_department_v2(text,text,text,text,integer,boolean,boolean,boolean,boolean,boolean,boolean,text,boolean,boolean) to authenticated;

create or replace function public.rr_owner_set_department_status_v2(
  p_department_code text,p_action text,p_reason text default null
)
returns jsonb
language plpgsql security definer set search_path=public as $function$
declare v_role text;v_code text:=lower(trim(p_department_code));v_action text:=upper(trim(p_action));
begin
  select lower(role_code) into v_role from public.rr_user_profiles
  where auth_user_id=auth.uid() and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE' limit 1;
  if coalesce(v_role,'') not in('owner','admin') then raise exception 'Owner/Admin permission required.'; end if;
  if v_action not in('ACTIVATE','ARCHIVE') then raise exception 'Invalid department action.'; end if;
  if not exists(select 1 from public.rr_departments_v1 where department_code=v_code) then raise exception 'Department not found.'; end if;
  if v_action='ARCHIVE' and exists(
    select 1 from public.rr_upm_work_assignments_v8 a
    where upper(a.department_code)=upper(v_code) and a.status in('ASSIGNED','IN_PROGRESS')
  ) then raise exception 'Department % has active production assignments. Complete or reassign them before Archive.',v_code; end if;

  update public.rr_departments_v1 set
    is_active=(v_action='ACTIVATE'),
    archived_at=case when v_action='ARCHIVE' then now() else null end,
    archive_reason=case when v_action='ARCHIVE' then nullif(trim(p_reason),'') else null end,
    updated_at=now()
  where department_code=v_code;
  update public.rr_upm_departments set is_active=(v_action='ACTIVATE'),updated_at=now() where department_code=upper(v_code);
  update public.rr_role_department_map_v1 set is_active=(v_action='ACTIVATE'),updated_at=now() where department_code=v_code;
  if v_action='ARCHIVE' then update public.rr_worker_department_map_v1 set is_active=false,updated_at=now() where department_code=v_code; end if;
  return jsonb_build_object('ok',true,'department_code',v_code,'status',v_action);
end
$function$;
grant execute on function public.rr_owner_set_department_status_v2(text,text,text) to authenticated;

create or replace function public.rr_owner_set_worker_departments_v1(p_worker_id uuid,p_rows jsonb)
returns jsonb
language plpgsql security definer set search_path=public as $function$
declare
  v_role text;v_row jsonb;v_count integer:=0;v_primary_count integer:=0;v_primary text;
  v_source text;v_auth uuid;
begin
  select lower(role_code) into v_role from public.rr_user_profiles
  where auth_user_id=auth.uid() and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE' limit 1;
  if coalesce(v_role,'') not in('owner','admin') then raise exception 'Owner/Admin permission required.'; end if;
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0 then raise exception 'Select at least one department.'; end if;
  if not exists(select 1 from public.rr_worker_directory_unified_v1 where worker_id=p_worker_id) then raise exception 'Worker not found in Unified Worker Directory.'; end if;

  for v_row in select value from jsonb_array_elements(p_rows) loop
    if not exists(select 1 from public.rr_departments_v1 d where d.department_code=lower(trim(v_row->>'department_code')) and d.is_active and d.worker_assignment_enabled) then
      raise exception 'Department % is inactive or worker assignment is disabled.',v_row->>'department_code';
    end if;
    v_count:=v_count+1;
    if coalesce((v_row->>'is_primary')::boolean,false) then v_primary_count:=v_primary_count+1;v_primary:=lower(trim(v_row->>'department_code')); end if;
  end loop;
  if v_primary_count<>1 then raise exception 'Exactly one Primary department required.'; end if;

  delete from public.rr_worker_department_map_v1 where worker_id=p_worker_id;
  insert into public.rr_worker_department_map_v1(worker_id,department_code,is_primary,is_active,assigned_by,updated_at)
  select p_worker_id,lower(trim(x->>'department_code')),coalesce((x->>'is_primary')::boolean,false),true,auth.uid(),now()
  from jsonb_array_elements(p_rows) x;

  select u.source,u.linked_auth_user_id into v_source,v_auth
  from public.rr_worker_directory_unified_v1 u where u.worker_id=p_worker_id limit 1;
  if upper(coalesce(v_source,''))='ROLE_DIRECTORY' and v_auth is not null then
    update public.rr_user_profiles set department_code=v_primary,updated_at=now() where auth_user_id=v_auth;
  else
    update public.rr_worker_directory_v1 set department_code=v_primary,updated_at=now(),updated_by=auth.uid() where id=p_worker_id;
  end if;

  return jsonb_build_object('ok',true,'worker_id',p_worker_id,'primary_department',v_primary,'department_count',v_count);
end
$function$;
grant execute on function public.rr_owner_set_worker_departments_v1(uuid,jsonb) to authenticated;

-- Worker selector now accepts primary department OR additional skill.
drop function if exists public.rr_upm_worker_list_v8_3(text);
create function public.rr_upm_worker_list_v8_3(p_department_code text default null)
returns table(
  worker_id uuid,worker_code text,worker_name text,department_code text,role_code text,
  is_active boolean,access_status text,source text,linked_auth_user_id uuid
)
language sql stable security definer set search_path=public as $function$
  select distinct
    u.worker_id,u.worker_code,u.worker_name,u.department_code,u.role_code,
    u.is_active,u.access_status,u.source,u.linked_auth_user_id
  from public.rr_worker_directory_unified_v1 u
  where coalesce(u.is_active,false)
    and upper(coalesce(u.access_status,'ACTIVE'))='ACTIVE'
    and (
      nullif(trim(p_department_code),'') is null
      or lower(u.department_code)=lower(trim(p_department_code))
      or exists(
        select 1 from public.rr_worker_department_map_v1 m
        where m.worker_id=u.worker_id and m.is_active
          and m.department_code=lower(trim(p_department_code))
      )
    )
  order by u.worker_name,u.worker_code;
$function$;
grant execute on function public.rr_upm_worker_list_v8_3(text) to authenticated;

-- ============================================================================
-- B. VERIFIED SINGLE/MULTI CUTTING MAPPING + WORKFLOW ACTION ENGINE
-- ============================================================================
alter table public.rr_upm_work_assignments_v8
  add column if not exists colour_id uuid,
  add column if not exists source_type text,
  add column if not exists source_lot_id uuid,
  add column if not exists actual_rate numeric(12,4),
  add column if not exists rate_filled_by uuid,
  add column if not exists rate_filled_by_name text,
  add column if not exists rate_filled_at timestamptz;

create index if not exists rr_upm_work_assignments_v8_colour_id_idx
on public.rr_upm_work_assignments_v8(canonical_lot_id,upper(department_code),colour_id)
where colour_id is not null;

create table if not exists public.rr_upm_actions_v726(
  id uuid primary key default gen_random_uuid(),
  request_id uuid unique,
  canonical_lot_id text not null,
  lot_no text not null,
  department_code text not null,
  colour_id uuid,
  colour_code text not null,
  colour_name text,
  size_code text not null,
  assignment_id uuid,
  worker_id uuid,
  worker_name text,
  worker_code text,
  action_type text not null check(action_type in('GOOD','ALTER','REMAKE_ISSUE','REMAKE_COMPLETE','DAMAGE','REASSIGN_OUT','REASSIGN_IN','ADJUSTMENT')),
  source_bucket text not null default 'PENDING' check(source_bucket in('PENDING','ALTER','REMAKE','SYSTEM')),
  qty numeric(14,3) not null check(qty>0),
  actual_rate numeric(14,4) not null default 0,
  standard_rate numeric(14,4),
  remarks text,
  reference_id uuid,
  actor_user_id uuid default auth.uid(),
  actor_name text,
  created_at timestamptz not null default now()
);
alter table public.rr_upm_actions_v726
  add column if not exists request_id uuid,
  add column if not exists colour_id uuid,
  add column if not exists assignment_id uuid,
  add column if not exists source_bucket text not null default 'PENDING';
create unique index if not exists rr_upm_actions_v726_request_uq on public.rr_upm_actions_v726(request_id) where request_id is not null;
create index if not exists rr_upm_actions_v726_lookup_idx
on public.rr_upm_actions_v726(canonical_lot_id,upper(department_code),colour_id,upper(colour_code),upper(size_code),created_at);
alter table public.rr_upm_actions_v726 enable row level security;
drop policy if exists rr_upm_actions_read_v726 on public.rr_upm_actions_v726;
create policy rr_upm_actions_read_v726 on public.rr_upm_actions_v726 for select to authenticated using(true);
grant select on public.rr_upm_actions_v726 to authenticated;

drop function if exists public.rr_upm_cut_size_rows_v726(text);
create function public.rr_upm_cut_size_rows_v726(p_lot_no text)
returns table(source_type text,source_lot_id uuid,colour_id uuid,colour_code text,colour_name text,size_code text,cutting_qty numeric)
language sql stable security definer set search_path=public as $function$
with single_rows as(
  select 1 source_priority,'SINGLE'::text source_type,l.id source_lot_id,b.cb_colour_id colour_id,
    case when c.col_no is not null then upper('C'||c.col_no::text)
         when b.cb_colour_id is not null then 'CID:'||b.cb_colour_id::text
         else upper(coalesce(nullif(trim(b.colour_name_snapshot),''),'COLOUR')) end colour_code,
    coalesce(nullif(trim(b.colour_name_snapshot),''),nullif(trim(c.colour_name),''),'Colour') colour_name,
    upper(trim(b.size_code)) size_code,sum(coalesce(b.planned_qty,0))::numeric cutting_qty
  from public.rr_cutting_lots_v3 l
  join public.rr_cutting_breakup_v3 b on b.cutting_lot_id=l.id
  left join public.rr_cb_colours c on c.id=b.cb_colour_id
  where upper(trim(l.lot_no))=upper(trim(p_lot_no)) and coalesce(b.planned_qty,0)>0
  group by l.id,b.cb_colour_id,c.col_no,
    coalesce(nullif(trim(b.colour_name_snapshot),''),nullif(trim(c.colour_name),''),'Colour'),upper(trim(b.size_code)),
    case when c.col_no is not null then upper('C'||c.col_no::text)
         when b.cb_colour_id is not null then 'CID:'||b.cb_colour_id::text
         else upper(coalesce(nullif(trim(b.colour_name_snapshot),''),'COLOUR')) end
),multi_rows as(
  select 2 source_priority,'MULTI'::text source_type,l.id source_lot_id,b.cb_colour_id colour_id,
    case when c.col_no is not null then upper('C'||c.col_no::text)
         when b.cb_colour_id is not null then 'CID:'||b.cb_colour_id::text
         else upper(coalesce(nullif(trim(b.colour_name_snapshot),''),'COLOUR')) end colour_code,
    coalesce(nullif(trim(b.colour_name_snapshot),''),nullif(trim(c.colour_name),''),'Colour') colour_name,
    upper(trim(b.size_code)) size_code,sum(coalesce(b.planned_qty,0))::numeric cutting_qty
  from public.rr_production_lots l
  join public.rr_production_lot_breakup_v3 b on b.production_lot_id=l.id
  left join public.rr_cb_colours c on c.id=b.cb_colour_id
  where upper(trim(l.lot_no))=upper(trim(p_lot_no)) and coalesce(b.planned_qty,0)>0
  group by l.id,b.cb_colour_id,c.col_no,
    coalesce(nullif(trim(b.colour_name_snapshot),''),nullif(trim(c.colour_name),''),'Colour'),upper(trim(b.size_code)),
    case when c.col_no is not null then upper('C'||c.col_no::text)
         when b.cb_colour_id is not null then 'CID:'||b.cb_colour_id::text
         else upper(coalesce(nullif(trim(b.colour_name_snapshot),''),'COLOUR')) end
),all_rows as(
  select * from single_rows union all select * from multi_rows
),chosen as(select min(source_priority) source_priority from all_rows)
select a.source_type,a.source_lot_id,a.colour_id,a.colour_code,a.colour_name,a.size_code,a.cutting_qty
from all_rows a cross join chosen c where a.source_priority=c.source_priority
order by case when a.colour_code~'^C[0-9]+$' then regexp_replace(a.colour_code,'[^0-9]','','g')::integer else 999999 end,
  a.colour_name,
  case a.size_code when 'XS' then 1 when 'S' then 2 when 'M' then 3 when 'L' then 4 when 'XL' then 5 when 'XXL' then 6 when '2XL' then 6 when '3XL' then 7 when '4XL' then 8 when '5XL' then 9 else 99 end,
  a.size_code;
$function$;
grant execute on function public.rr_upm_cut_size_rows_v726(text) to authenticated;

create or replace function public.rr_upm_worker_eligible_v726(p_worker_id uuid,p_department_code text)
returns boolean
language sql stable security definer set search_path=public as $function$
  select exists(
    select 1 from public.rr_worker_directory_unified_v1 u
    where u.worker_id=p_worker_id and coalesce(u.is_active,false)
      and upper(coalesce(u.access_status,'ACTIVE'))='ACTIVE'
      and (
        lower(u.department_code)=lower(trim(p_department_code))
        or exists(select 1 from public.rr_worker_department_map_v1 m where m.worker_id=u.worker_id and m.is_active and m.department_code=lower(trim(p_department_code)))
      )
  );
$function$;
grant execute on function public.rr_upm_worker_eligible_v726(uuid,text) to authenticated;

create or replace function public.rr_upm_action_permission_v726(p_action_type text)
returns boolean
language plpgsql stable security definer set search_path=public as $function$
declare v_role text;v_key text;v_allowed boolean:=false;
begin
  select lower(role_code) into v_role from public.rr_user_profiles
  where auth_user_id=auth.uid() and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE' limit 1;
  if v_role is null then return false; end if;
  if v_role in('owner','admin') then return true; end if;
  v_key:=case upper(trim(p_action_type))
    when 'GOOD' then 'upm.submit_work' when 'ALTER' then 'upm.register_alter'
    when 'REMAKE_ISSUE' then 'upm.remake_issue' when 'REMAKE_COMPLETE' then 'upm.remake_complete'
    when 'DAMAGE' then 'upm.damage' when 'REASSIGN' then 'upm.reassign_pending'
    else 'upm.submit_work' end;
  if to_regprocedure('public.rr_has_action_permission_v1(text)') is not null then
    begin v_allowed:=public.rr_has_action_permission_v1(v_key); exception when others then v_allowed:=false; end;
  else
    v_allowed:=v_role in('manager','line_manager','line_man','department_head','production','worker','karigar','overlock','kaaj','button','folding','thread_cut','qc','press','packing');
  end if;
  return coalesce(v_allowed,false);
end
$function$;

drop function if exists public.rr_upm_action_balance_v726(text,text,uuid,text,text);
create function public.rr_upm_action_balance_v726(
  p_canonical_lot_id text,p_department_code text,p_colour_id uuid,p_colour_code text,p_size_code text
)
returns table(
  cutting_qty numeric,direct_good_qty numeric,alter_registered_qty numeric,remake_issued_qty numeric,
  remake_completed_qty numeric,damage_pending_qty numeric,damage_alter_qty numeric,damage_remake_qty numeric,
  pending_qty numeric,alter_open_qty numeric,remake_open_qty numeric,good_total_qty numeric,damage_total_qty numeric
)
language sql stable security definer set search_path=public as $function$
with lot as(
  select lot_no from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id limit 1
),cut as(
  select coalesce(sum(c.cutting_qty),0)::numeric cutting_qty
  from lot l cross join lateral public.rr_upm_cut_size_rows_v726(l.lot_no) c
  where upper(c.size_code)=upper(trim(p_size_code))
    and ((p_colour_id is not null and c.colour_id=p_colour_id) or (p_colour_id is null and upper(c.colour_code)=upper(trim(p_colour_code))))
),act as(
  select
    coalesce(sum(qty) filter(where action_type='GOOD'),0)::numeric direct_good,
    coalesce(sum(qty) filter(where action_type='ALTER'),0)::numeric alter_registered,
    coalesce(sum(qty) filter(where action_type='REMAKE_ISSUE'),0)::numeric remake_issued,
    coalesce(sum(qty) filter(where action_type='REMAKE_COMPLETE'),0)::numeric remake_completed,
    coalesce(sum(qty) filter(where action_type='DAMAGE' and coalesce(source_bucket,'PENDING')='PENDING'),0)::numeric damage_pending,
    coalesce(sum(qty) filter(where action_type='DAMAGE' and source_bucket='ALTER'),0)::numeric damage_alter,
    coalesce(sum(qty) filter(where action_type='DAMAGE' and source_bucket='REMAKE'),0)::numeric damage_remake
  from public.rr_upm_actions_v726 a
  where a.canonical_lot_id=p_canonical_lot_id
    and upper(a.department_code)=upper(trim(p_department_code))
    and upper(a.size_code)=upper(trim(p_size_code))
    and ((p_colour_id is not null and a.colour_id=p_colour_id) or (p_colour_id is null and upper(a.colour_code)=upper(trim(p_colour_code))))
)
select c.cutting_qty,a.direct_good,a.alter_registered,a.remake_issued,a.remake_completed,
  a.damage_pending,a.damage_alter,a.damage_remake,
  greatest(c.cutting_qty-a.direct_good-a.alter_registered-a.damage_pending,0),
  greatest(a.alter_registered-a.remake_issued-a.damage_alter,0),
  greatest(a.remake_issued-a.remake_completed-a.damage_remake,0),
  a.direct_good+a.remake_completed,
  a.damage_pending+a.damage_alter+a.damage_remake
from cut c cross join act a;
$function$;
grant execute on function public.rr_upm_action_balance_v726(text,text,uuid,text,text) to authenticated;

-- Assignment remains one full Colour + all Sizes. Worker can qualify by primary or skill.
create or replace function public.rr_upm_assign_colours_v8_3(
  p_canonical_lot_id text,p_lot_no text,p_department_code text,p_rows jsonb,p_remarks text default null
)
returns setof public.rr_upm_work_assignments_v8
language plpgsql security definer set search_path=public as $function$
declare
  v_profile public.rr_user_profiles%rowtype;v_allowed boolean:=false;v_lot_no text;v_row jsonb;
  v_colour_id uuid;v_colour text;v_worker uuid;v_qty integer;v_rate numeric(12,4);
  v_expected integer;v_sizes jsonb;v_cname text;v_source text;v_source_lot uuid;
  v_wname text;v_wcode text;v_existing public.rr_upm_work_assignments_v8%rowtype;v_out public.rr_upm_work_assignments_v8;
begin
  select * into v_profile from public.rr_user_profiles
  where auth_user_id=auth.uid() and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE' limit 1;
  if not found then raise exception 'Active User Directory profile required.'; end if;
  v_allowed:=lower(coalesce(v_profile.role_code,'')) in('owner','admin','manager','line_manager','line_man','department_head','production','cutting_master');
  if to_regprocedure('public.rr_has_action_permission_v1(text)') is not null then
    begin v_allowed:=v_allowed or public.rr_has_action_permission_v1('upm.assign_work'); exception when others then null; end;
  end if;
  if not v_allowed then raise exception 'Assign Work permission denied by Role & Permission Directory.'; end if;
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0 then raise exception 'Select at least one colour.'; end if;
  select coalesce((select lot_no from public.rr_upm_lot_board_v1 where canonical_lot_id=nullif(trim(p_canonical_lot_id),'') limit 1),nullif(trim(p_lot_no),'')) into v_lot_no;
  if v_lot_no is null then raise exception 'Lot No is required.'; end if;

  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_colour_id:=nullif(v_row->>'colour_id','')::uuid;
    v_colour:=upper(trim(v_row->>'colour_code'));
    v_worker:=nullif(v_row->>'worker_id','')::uuid;
    v_qty:=coalesce(nullif(v_row->>'assigned_qty','')::integer,0);
    v_rate:=coalesce(nullif(v_row->>'actual_rate','')::numeric,0);
    if v_worker is null then raise exception 'Worker is required for colour %.',v_colour; end if;
    if not public.rr_upm_worker_eligible_v726(v_worker,p_department_code) then raise exception 'Selected worker is not enabled for department %.',p_department_code; end if;

    select max(r.colour_name),sum(r.cutting_qty)::integer,
      jsonb_agg(jsonb_build_object('size_code',r.size_code,'qty',r.cutting_qty) order by upper(r.size_code)),
      max(r.source_type),(array_agg(r.source_lot_id))[1],(array_agg(r.colour_id))[1]
    into v_cname,v_expected,v_sizes,v_source,v_source_lot,v_colour_id
    from public.rr_upm_cut_size_rows_v726(v_lot_no) r
    where (v_colour_id is not null and r.colour_id=v_colour_id) or (v_colour_id is null and upper(r.colour_code)=v_colour);
    if v_expected is null then raise exception 'Mapped Cutting colour-size quantity missing for colour %.',v_colour; end if;
    if v_qty<>v_expected then raise exception 'Colour % qty must equal complete Cutting mapped qty %.',v_colour,v_expected; end if;

    select * into v_existing from public.rr_upm_work_assignments_v8 x
    where x.canonical_lot_id=p_canonical_lot_id and upper(x.department_code)=upper(p_department_code)
      and x.status in('ASSIGNED','IN_PROGRESS','COMPLETED')
      and ((v_colour_id is not null and x.colour_id=v_colour_id) or upper(x.colour_code)=v_colour)
    order by x.assigned_at desc limit 1;
    if v_existing.id is not null then raise exception 'Colour % is already assigned to %.',v_colour,v_existing.worker_name_snapshot; end if;

    select worker_name,worker_code into v_wname,v_wcode from public.rr_worker_directory_unified_v1 where worker_id=v_worker limit 1;
    insert into public.rr_upm_work_assignments_v8(
      canonical_lot_id,lot_no,department_code,colour_id,colour_code,colour_name,source_type,source_lot_id,
      worker_id,worker_code,worker_name_snapshot,assigned_qty,size_breakup,actual_rate,
      rate_filled_by,rate_filled_by_name,rate_filled_at,assigned_by,assigned_by_name,remarks,status
    ) values(
      nullif(trim(p_canonical_lot_id),''),v_lot_no,upper(trim(p_department_code)),v_colour_id,v_colour,coalesce(v_cname,v_colour),v_source,v_source_lot,
      v_worker,v_wcode,v_wname,v_expected,coalesce(v_sizes,'[]'::jsonb),round(v_rate,4),
      auth.uid(),coalesce(v_profile.full_name,v_profile.email),now(),auth.uid(),coalesce(v_profile.full_name,v_profile.email),p_remarks,'ASSIGNED'
    ) returning * into v_out;
    return next v_out;
  end loop;
end
$function$;
grant execute on function public.rr_upm_assign_colours_v8_3(text,text,text,jsonb,text) to authenticated;

create or replace function public.rr_upm_apply_actions_batch_v726(
  p_canonical_lot_id text,p_department_code text,p_actions jsonb,p_rate numeric default 0,p_remarks text default null
)
returns jsonb
language plpgsql security definer set search_path=public as $function$
declare
  v_lot public.rr_upm_lot_registry%rowtype;v_row jsonb;v_type text;v_bucket text;v_qty numeric;
  v_colour_id uuid;v_colour text;v_cname text;v_size text;v_request uuid;v_assign public.rr_upm_work_assignments_v8%rowtype;
  v_balance record;v_std numeric;v_actor text;v_entry_type text;v_count integer:=0;
begin
  if jsonb_typeof(p_actions)<>'array' or jsonb_array_length(p_actions)=0 then raise exception 'No action rows supplied.'; end if;
  select * into v_lot from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id;
  if not found then raise exception 'Lot is not registered.'; end if;
  begin v_actor:=coalesce(public.rr_up_user_context_v2()->>'display_name',auth.uid()::text); exception when others then v_actor:=auth.uid()::text; end;
  begin select standard_rate into v_std from public.rr_upm_standard_rates_v723 where canonical_lot_id=p_canonical_lot_id and upper(department_code)=upper(p_department_code) limit 1; exception when others then v_std:=null; end;

  for v_row in select value from jsonb_array_elements(p_actions) loop
    v_type:=upper(trim(v_row->>'action_type'));
    v_bucket:=upper(trim(coalesce(v_row->>'source_bucket','PENDING')));
    v_qty:=coalesce(nullif(v_row->>'qty','')::numeric,0);
    v_colour_id:=nullif(v_row->>'colour_id','')::uuid;
    v_colour:=upper(trim(v_row->>'colour_code'));
    v_cname:=nullif(trim(v_row->>'colour_name'),'');
    v_size:=upper(trim(v_row->>'size_code'));
    v_request:=nullif(v_row->>'request_id','')::uuid;

    if v_type not in('GOOD','ALTER','REMAKE_ISSUE','REMAKE_COMPLETE','DAMAGE') then raise exception 'Invalid action type %.',v_type; end if;
    if not public.rr_upm_action_permission_v726(v_type) then raise exception 'Permission denied for %.',v_type; end if;
    if v_qty<=0 then raise exception '% quantity must be greater than zero.',v_type; end if;
    if v_bucket not in('PENDING','ALTER','REMAKE') then raise exception 'Invalid source bucket %.',v_bucket; end if;
    if v_type<>'DAMAGE' then v_bucket:=case when v_type in('REMAKE_ISSUE') then 'ALTER' when v_type='REMAKE_COMPLETE' then 'REMAKE' else 'PENDING' end; end if;
    if v_request is not null and exists(select 1 from public.rr_upm_actions_v726 where request_id=v_request) then continue; end if;

    select * into v_assign from public.rr_upm_work_assignments_v8 x
    where x.canonical_lot_id=p_canonical_lot_id and upper(x.department_code)=upper(p_department_code)
      and x.status in('ASSIGNED','IN_PROGRESS','COMPLETED')
      and ((v_colour_id is not null and x.colour_id=v_colour_id) or upper(x.colour_code)=v_colour)
    order by case when v_colour_id is not null and x.colour_id=v_colour_id then 0 else 1 end,x.assigned_at desc limit 1;
    if v_assign.id is null then raise exception 'Complete colour % is not actively assigned in %.',v_colour,p_department_code; end if;
    if not public.rr_upm_worker_eligible_v726(v_assign.worker_id,p_department_code) then raise exception 'Assigned worker is inactive or no longer enabled for %.',p_department_code; end if;

    select * into v_balance from public.rr_upm_action_balance_v726(p_canonical_lot_id,p_department_code,v_colour_id,v_colour,v_size);
    if v_balance.cutting_qty is null or v_balance.cutting_qty<=0 then raise exception 'Cutting mapping missing for % / %.',v_colour,v_size; end if;
    if v_type in('GOOD','ALTER') and v_qty>v_balance.pending_qty then raise exception '% / %: Qty % exceeds Pending %.',v_colour,v_size,v_qty,v_balance.pending_qty; end if;
    if v_type='REMAKE_ISSUE' and v_qty>v_balance.alter_open_qty then raise exception '% / %: Remake Issue % exceeds Alter Open %.',v_colour,v_size,v_qty,v_balance.alter_open_qty; end if;
    if v_type='REMAKE_COMPLETE' and v_qty>v_balance.remake_open_qty then raise exception '% / %: Remake Complete % exceeds Remake Open %.',v_colour,v_size,v_qty,v_balance.remake_open_qty; end if;
    if v_type='DAMAGE' then
      if v_bucket='PENDING' and v_qty>v_balance.pending_qty then raise exception '% / %: Damage % exceeds Pending %.',v_colour,v_size,v_qty,v_balance.pending_qty; end if;
      if v_bucket='ALTER' and v_qty>v_balance.alter_open_qty then raise exception '% / %: Damage % exceeds Alter Open %.',v_colour,v_size,v_qty,v_balance.alter_open_qty; end if;
      if v_bucket='REMAKE' and v_qty>v_balance.remake_open_qty then raise exception '% / %: Damage % exceeds Remake Open %.',v_colour,v_size,v_qty,v_balance.remake_open_qty; end if;
    end if;

    insert into public.rr_upm_actions_v726(
      request_id,canonical_lot_id,lot_no,department_code,colour_id,colour_code,colour_name,size_code,
      assignment_id,worker_id,worker_name,worker_code,action_type,source_bucket,qty,actual_rate,standard_rate,remarks,actor_name
    ) values(
      v_request,p_canonical_lot_id,v_lot.lot_no,upper(p_department_code),v_colour_id,v_colour,coalesce(v_cname,v_assign.colour_name),v_size,
      v_assign.id,v_assign.worker_id,v_assign.worker_name_snapshot,v_assign.worker_code,v_type,v_bucket,v_qty,coalesce(v_assign.actual_rate,p_rate,0),v_std,
      coalesce(nullif(trim(p_remarks),''),'Universal Lot Form'),v_actor
    );

    v_entry_type:=case v_type when 'GOOD' then 'GOOD' when 'ALTER' then 'ALTER_OUT' when 'REMAKE_COMPLETE' then 'REMAKE' when 'DAMAGE' then 'REJECT' else null end;
    if v_entry_type is not null then
      insert into public.rr_upm_entries(canonical_lot_id,lot_no,department_code,colour_code,size_code,entry_type,qty,rate,remarks,operator_name)
      values(p_canonical_lot_id,v_lot.lot_no,upper(p_department_code),v_colour,v_size,v_entry_type,v_qty,coalesce(v_assign.actual_rate,p_rate,0),
        concat_ws(' · ',p_remarks,'Source '||v_bucket),v_actor);
    end if;
    update public.rr_upm_work_assignments_v8 set status='IN_PROGRESS',completed_at=null,updated_at=now() where id=v_assign.id;
    v_count:=v_count+1;
  end loop;

  -- Complete assignment only when every size has no Pending, Alter Open or Remake Open.
  update public.rr_upm_work_assignments_v8 a set status='COMPLETED',completed_at=now(),updated_at=now()
  where a.canonical_lot_id=p_canonical_lot_id and upper(a.department_code)=upper(p_department_code)
    and a.status in('ASSIGNED','IN_PROGRESS')
    and not exists(
      select 1 from public.rr_upm_cut_size_rows_v726(v_lot.lot_no) c
      cross join lateral public.rr_upm_action_balance_v726(p_canonical_lot_id,p_department_code,c.colour_id,c.colour_code,c.size_code) b
      where ((a.colour_id is not null and c.colour_id=a.colour_id) or (a.colour_id is null and upper(c.colour_code)=upper(a.colour_code)))
        and (b.pending_qty>0 or b.alter_open_qty>0 or b.remake_open_qty>0)
    );

  return jsonb_build_object('ok',true,'actions_saved',v_count,'context',public.rr_upm_universal_form_v726(p_canonical_lot_id,p_department_code));
end
$function$;
grant execute on function public.rr_upm_apply_actions_batch_v726(text,text,jsonb,numeric,text) to authenticated;

create or replace function public.rr_upm_reassign_colours_v726(
  p_canonical_lot_id text,p_department_code text,p_rows jsonb,p_remarks text default null
)
returns jsonb
language plpgsql security definer set search_path=public as $function$
declare
  v_lot public.rr_upm_lot_registry%rowtype;v_row jsonb;v_colour_id uuid;v_colour text;v_new_worker uuid;
  v_old public.rr_upm_work_assignments_v8%rowtype;v_wname text;v_wcode text;v_profile public.rr_user_profiles%rowtype;
  v_cut record;v_bal record;v_pending_total numeric;v_alter_total numeric;v_remake_total numeric;v_new_id uuid;v_count integer:=0;
begin
  if not public.rr_upm_action_permission_v726('REASSIGN') then raise exception 'Reassign Pending permission denied.'; end if;
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0 then raise exception 'Select assigned colours to reassign.'; end if;
  select * into v_lot from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id;
  if not found then raise exception 'Lot is not registered.'; end if;
  select * into v_profile from public.rr_user_profiles where auth_user_id=auth.uid() limit 1;

  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_colour_id:=nullif(v_row->>'colour_id','')::uuid;
    v_colour:=upper(trim(v_row->>'colour_code'));
    v_new_worker:=nullif(v_row->>'new_worker_id','')::uuid;
    if v_new_worker is null then raise exception 'New worker is required for colour %.',v_colour; end if;
    if not public.rr_upm_worker_eligible_v726(v_new_worker,p_department_code) then raise exception 'New worker is not enabled for department %.',p_department_code; end if;

    select * into v_old from public.rr_upm_work_assignments_v8 a
    where a.canonical_lot_id=p_canonical_lot_id and upper(a.department_code)=upper(p_department_code)
      and a.status in('ASSIGNED','IN_PROGRESS','COMPLETED')
      and ((v_colour_id is not null and a.colour_id=v_colour_id) or upper(a.colour_code)=v_colour)
    order by a.assigned_at desc limit 1;
    if v_old.id is null then raise exception 'Active assignment not found for colour %.',v_colour; end if;
    if v_old.worker_id=v_new_worker then raise exception 'New worker is same as current worker for colour %.',v_colour; end if;

    v_pending_total:=0;v_alter_total:=0;v_remake_total:=0;
    for v_cut in select * from public.rr_upm_cut_size_rows_v726(v_lot.lot_no) c
      where ((v_old.colour_id is not null and c.colour_id=v_old.colour_id) or upper(c.colour_code)=upper(v_old.colour_code))
    loop
      select * into v_bal from public.rr_upm_action_balance_v726(p_canonical_lot_id,p_department_code,v_cut.colour_id,v_cut.colour_code,v_cut.size_code);
      v_pending_total:=v_pending_total+coalesce(v_bal.pending_qty,0);
      v_alter_total:=v_alter_total+coalesce(v_bal.alter_open_qty,0);
      v_remake_total:=v_remake_total+coalesce(v_bal.remake_open_qty,0);
    end loop;
    if v_pending_total<=0 then raise exception 'No direct Pending work remains for colour %.',v_colour; end if;
    if v_alter_total>0 or v_remake_total>0 then raise exception 'Resolve Alter/Remake before reassigning colour %. Alter Open %, Remake Open %.',v_colour,v_alter_total,v_remake_total; end if;

    select worker_name,worker_code into v_wname,v_wcode from public.rr_worker_directory_unified_v1 where worker_id=v_new_worker limit 1;
    update public.rr_upm_work_assignments_v8 set status='CANCELLED',cancelled_at=now(),cancel_reason=coalesce(p_remarks,'Pending reassigned'),updated_at=now() where id=v_old.id;
    insert into public.rr_upm_work_assignments_v8(
      canonical_lot_id,lot_no,department_code,colour_id,colour_code,colour_name,source_type,source_lot_id,
      worker_id,worker_code,worker_name_snapshot,assigned_qty,size_breakup,actual_rate,
      rate_filled_by,rate_filled_by_name,rate_filled_at,assigned_by,assigned_by_name,remarks,status
    ) values(
      v_old.canonical_lot_id,v_old.lot_no,v_old.department_code,v_old.colour_id,v_old.colour_code,v_old.colour_name,v_old.source_type,v_old.source_lot_id,
      v_new_worker,v_wcode,v_wname,v_old.assigned_qty,v_old.size_breakup,v_old.actual_rate,
      auth.uid(),coalesce(v_profile.full_name,v_profile.email),now(),auth.uid(),coalesce(v_profile.full_name,v_profile.email),
      concat_ws(' · ',p_remarks,'Reassigned from '||v_old.worker_name_snapshot),'ASSIGNED'
    ) returning id into v_new_id;

    for v_cut in select * from public.rr_upm_cut_size_rows_v726(v_lot.lot_no) c
      where ((v_old.colour_id is not null and c.colour_id=v_old.colour_id) or upper(c.colour_code)=upper(v_old.colour_code))
    loop
      select * into v_bal from public.rr_upm_action_balance_v726(p_canonical_lot_id,p_department_code,v_cut.colour_id,v_cut.colour_code,v_cut.size_code);
      if coalesce(v_bal.pending_qty,0)>0 then
        insert into public.rr_upm_actions_v726(canonical_lot_id,lot_no,department_code,colour_id,colour_code,colour_name,size_code,assignment_id,worker_id,worker_name,worker_code,action_type,source_bucket,qty,actual_rate,remarks,actor_name)
        values(p_canonical_lot_id,v_lot.lot_no,upper(p_department_code),v_cut.colour_id,v_cut.colour_code,v_cut.colour_name,v_cut.size_code,v_old.id,v_old.worker_id,v_old.worker_name_snapshot,v_old.worker_code,'REASSIGN_OUT','SYSTEM',v_bal.pending_qty,coalesce(v_old.actual_rate,0),p_remarks,coalesce(v_profile.full_name,v_profile.email));
        insert into public.rr_upm_actions_v726(canonical_lot_id,lot_no,department_code,colour_id,colour_code,colour_name,size_code,assignment_id,worker_id,worker_name,worker_code,action_type,source_bucket,qty,actual_rate,remarks,actor_name)
        values(p_canonical_lot_id,v_lot.lot_no,upper(p_department_code),v_cut.colour_id,v_cut.colour_code,v_cut.colour_name,v_cut.size_code,v_new_id,v_new_worker,v_wname,v_wcode,'REASSIGN_IN','SYSTEM',v_bal.pending_qty,coalesce(v_old.actual_rate,0),p_remarks,coalesce(v_profile.full_name,v_profile.email));
      end if;
    end loop;
    v_count:=v_count+1;
  end loop;
  return jsonb_build_object('ok',true,'colours_reassigned',v_count,'context',public.rr_upm_universal_form_v726(p_canonical_lot_id,p_department_code));
end
$function$;
grant execute on function public.rr_upm_reassign_colours_v726(text,text,jsonb,text) to authenticated;

create or replace function public.rr_upm_universal_form_v726(p_canonical_lot_id text,p_department_code text)
returns jsonb
language plpgsql stable security definer set search_path=public as $function$
declare
  v_lot jsonb;v_rows jsonb;v_workers jsonb;v_rate numeric:=0;v_std numeric;v_margin numeric:=0;v_owner boolean:=false;v_summary jsonb;v_cb text;
begin
  select to_jsonb(x) into v_lot from public.rr_upm_lot_board_v1 x where x.canonical_lot_id=p_canonical_lot_id limit 1;
  if v_lot is null then raise exception 'Lot not found.'; end if;
  v_cb:=coalesce(v_lot->>'cb_no',v_lot->>'cb_number',v_lot->>'cb_base_no');
  if nullif(trim(v_cb),'') is null then
    begin select coalesce(to_jsonb(c)->>'cb_no',to_jsonb(c)->>'cb_number',to_jsonb(c)->>'cb_code') into v_cb from public.rr_cutting_lots_v3 c where upper(trim(c.lot_no))=upper(trim(v_lot->>'lot_no')) order by c.created_at desc limit 1; exception when others then v_cb:=null; end;
  end if;
  v_lot:=jsonb_set(v_lot,'{cb_no}',to_jsonb(coalesce(nullif(trim(v_cb),''),'—')),true);
  begin v_owner:=public.rr_upm_is_owner_admin_v723(); exception when others then v_owner:=false; end;
  select coalesce(actual_rate,0) into v_rate from public.rr_upm_department_rates_v2 where canonical_lot_id=p_canonical_lot_id and upper(department_code)=upper(p_department_code) limit 1;
  if v_owner then
    begin select standard_rate into v_std from public.rr_upm_standard_rates_v723 where canonical_lot_id=p_canonical_lot_id and upper(department_code)=upper(p_department_code) limit 1; exception when others then v_std:=null; end;
    begin select flat_amount_per_piece into v_margin from public.rr_upm_owner_margin_v723 where is_active order by effective_from desc limit 1; exception when others then v_margin:=0; end;
  end if;

  with cuts as(select * from public.rr_upm_cut_size_rows_v726(v_lot->>'lot_no')),
  colour_map as(
    select colour_id,colour_code,max(colour_name) colour_name,sum(cutting_qty)::numeric total_qty,
      jsonb_agg(jsonb_build_object('size_code',size_code,'qty',cutting_qty) order by upper(size_code)) size_breakup,
      max(source_type) source_type,(array_agg(source_lot_id))[1] source_lot_id
    from cuts group by colour_id,colour_code
  ),assignment as(
    select c.*,a.id assignment_id,a.worker_id,a.worker_code,a.worker_name_snapshot,a.assigned_qty,a.actual_rate,a.status assignment_status,
      (a.id is not null and a.assigned_qty=c.total_qty and public.rr_upm_worker_eligible_v726(a.worker_id,p_department_code)
       and coalesce((select jsonb_agg(jsonb_build_object('size_code',upper(trim(z->>'size_code')),'qty',coalesce((z->>'qty')::numeric,0)) order by upper(trim(z->>'size_code'))) from jsonb_array_elements(coalesce(a.size_breakup,'[]'::jsonb)) z),'[]'::jsonb)=c.size_breakup) is_locked
    from colour_map c
    left join lateral(
      select x.* from public.rr_upm_work_assignments_v8 x
      where x.canonical_lot_id=p_canonical_lot_id and upper(x.department_code)=upper(p_department_code)
        and x.status in('ASSIGNED','IN_PROGRESS','COMPLETED')
        and ((c.colour_id is not null and x.colour_id=c.colour_id) or upper(x.colour_code)=upper(c.colour_code))
      order by case when c.colour_id is not null and x.colour_id=c.colour_id then 0 else 1 end,x.assigned_at desc limit 1
    ) a on true
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'source_type',c.source_type,'source_lot_id',c.source_lot_id,'colour_id',c.colour_id,'colour_code',c.colour_code,'colour_name',c.colour_name,
    'size_code',c.size_code,'cutting_qty',c.cutting_qty,
    'assignment_id',a.assignment_id,'worker_id',a.worker_id,'worker_name',a.worker_name_snapshot,'worker_code',a.worker_code,
    'colour_total_qty',a.total_qty,'colour_assigned_qty',coalesce(a.assigned_qty,0),'assigned_qty',case when a.is_locked then c.cutting_qty else 0 end,
    'is_locked',coalesce(a.is_locked,false),'assignment_status',a.assignment_status,
    'good_qty',case when a.is_locked then b.good_total_qty else 0 end,
    'direct_good_qty',case when a.is_locked then b.direct_good_qty else 0 end,
    'alter_registered_qty',case when a.is_locked then b.alter_registered_qty else 0 end,
    'alter_open_qty',case when a.is_locked then b.alter_open_qty else 0 end,
    'alter_qty',case when a.is_locked then b.alter_open_qty else 0 end,
    'remake_issued_qty',case when a.is_locked then b.remake_issued_qty else 0 end,
    'remake_completed_qty',case when a.is_locked then b.remake_completed_qty else 0 end,
    'remake_open_qty',case when a.is_locked then b.remake_open_qty else 0 end,
    'remake_qty',case when a.is_locked then b.remake_open_qty else 0 end,
    'damage_qty',case when a.is_locked then b.damage_total_qty else 0 end,
    'pending_qty',case when a.is_locked then b.pending_qty else 0 end,
    'actual_rate',coalesce(a.actual_rate,v_rate,0),'standard_rate',case when v_owner then v_std else null end,
    'status',case when not coalesce(a.is_locked,false) then 'NOT ASSIGNED'
      when b.pending_qty=0 and b.alter_open_qty=0 and b.remake_open_qty=0 then 'DONE'
      else 'RUNNING' end
  ) order by c.colour_name,
    case c.size_code when 'XS' then 1 when 'S' then 2 when 'M' then 3 when 'L' then 4 when 'XL' then 5 when 'XXL' then 6 when '2XL' then 6 when '3XL' then 7 when '4XL' then 8 when '5XL' then 9 else 99 end,c.size_code),'[]'::jsonb)
  into v_rows
  from cuts c
  join assignment a on a.colour_id is not distinct from c.colour_id and a.colour_code=c.colour_code
  cross join lateral public.rr_upm_action_balance_v726(p_canonical_lot_id,p_department_code,c.colour_id,c.colour_code,c.size_code) b;

  select coalesce(jsonb_agg(to_jsonb(w) order by w.worker_name),'[]'::jsonb) into v_workers
  from public.rr_upm_worker_list_v8_3(p_department_code) w;

  select jsonb_build_object(
    'assigned',coalesce(sum((r->>'assigned_qty')::numeric),0),
    'good',coalesce(sum((r->>'good_qty')::numeric),0),
    'alter',coalesce(sum((r->>'alter_open_qty')::numeric),0),
    'remake',coalesce(sum((r->>'remake_open_qty')::numeric),0),
    'damage',coalesce(sum((r->>'damage_qty')::numeric),0),
    'pending',coalesce(sum((r->>'pending_qty')::numeric),0)
  ) into v_summary from jsonb_array_elements(v_rows) r;

  return jsonb_build_object(
    'lot',v_lot,'department_code',upper(p_department_code),'rows',v_rows,'workers',v_workers,'summary',v_summary,
    'actual_rate',v_rate,'standard_rate',case when v_owner then v_std else null end,
    'owner_margin',case when v_owner then coalesce(v_margin,0) else null end,
    'can_view_standard',v_owner,'can_change_standard',v_owner,'can_change_margin',v_owner,
    'assignment_level','COLOUR_ALL_SIZES','action_model','PENDING_TO_GOOD_OR_ALTER; ALTER_TO_REMAKE; REMAKE_TO_GOOD'
  );
end
$function$;
grant execute on function public.rr_upm_universal_form_v726(text,text) to authenticated;

create or replace function public.rr_upm_debug_lot_flow_v726(p_canonical_lot_id text,p_department_code text)
returns jsonb
language plpgsql stable security definer set search_path=public as $function$
declare v_lot text;v_map jsonb;v_context jsonb;v_issues jsonb:='[]'::jsonb;v_department boolean;v_workers integer;v_assignments integer;
begin
  select lot_no into v_lot from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id limit 1;
  if v_lot is null then v_issues:=v_issues||jsonb_build_array('Lot missing from rr_upm_lot_registry'); end if;
  select exists(select 1 from public.rr_upm_departments where upper(department_code)=upper(p_department_code) and is_active) into v_department;
  if not v_department then v_issues:=v_issues||jsonb_build_array('Department missing or inactive in rr_upm_departments'); end if;
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_map from public.rr_upm_cut_size_rows_v726(v_lot) x;
  if jsonb_array_length(v_map)=0 then v_issues:=v_issues||jsonb_build_array('No Single/Multi Cutting breakup rows found'); end if;
  select count(*) into v_workers from public.rr_upm_worker_list_v8_3(p_department_code);
  if v_workers=0 then v_issues:=v_issues||jsonb_build_array('No active primary/skill workers for selected department'); end if;
  select count(*) into v_assignments from public.rr_upm_work_assignments_v8 where canonical_lot_id=p_canonical_lot_id and upper(department_code)=upper(p_department_code) and status in('ASSIGNED','IN_PROGRESS','COMPLETED');
  begin v_context:=public.rr_upm_universal_form_v726(p_canonical_lot_id,p_department_code); exception when others then v_issues:=v_issues||jsonb_build_array('Universal form error: '||sqlerrm);v_context:=null; end;
  return jsonb_build_object(
    'ok',jsonb_array_length(v_issues)=0,'lot_no',v_lot,'department_code',upper(p_department_code),
    'checks',jsonb_build_object('department_active',v_department,'cutting_rows',jsonb_array_length(v_map),'eligible_workers',v_workers,'assignments',v_assignments),
    'issues',v_issues,'cutting_map',v_map,'context',v_context,
    'functions',jsonb_build_object(
      'universal_form',to_regprocedure('public.rr_upm_universal_form_v726(text,text)'),
      'assign',to_regprocedure('public.rr_upm_assign_colours_v8_3(text,text,text,jsonb,text)'),
      'batch_actions',to_regprocedure('public.rr_upm_apply_actions_batch_v726(text,text,jsonb,numeric,text)'),
      'reassign',to_regprocedure('public.rr_upm_reassign_colours_v726(text,text,jsonb,text)'),
      'worker_list',to_regprocedure('public.rr_upm_worker_list_v8_3(text)')
    )
  );
end
$function$;
grant execute on function public.rr_upm_debug_lot_flow_v726(text,text) to authenticated;

create or replace function public.rr_upm_verify_cutting_map_v726(p_lot_no text)
returns table(source_type text,source_lot_id uuid,colour_id uuid,colour_code text,colour_name text,size_code text,cutting_qty numeric)
language sql stable security definer set search_path=public as $function$
  select * from public.rr_upm_cut_size_rows_v726(p_lot_no);
$function$;
grant execute on function public.rr_upm_verify_cutting_map_v726(text) to authenticated;

create or replace view public.rr_upm_worker_ledger_v726 as
select canonical_lot_id,lot_no,department_code,worker_id,worker_name,worker_code,colour_id,colour_code,size_code,
  action_type,source_bucket,qty,actual_rate,round(qty*actual_rate,2) amount,remarks,created_at
from public.rr_upm_actions_v726;

create or replace view public.rr_upm_department_ledger_v726 as
select canonical_lot_id,lot_no,department_code,action_type,source_bucket,
  sum(qty) qty,sum(round(qty*actual_rate,2)) actual_amount,sum(round(qty*coalesce(standard_rate,0),2)) standard_amount,
  min(created_at) first_entry,max(created_at) last_entry
from public.rr_upm_actions_v726
group by canonical_lot_id,lot_no,department_code,action_type,source_bucket;

grant select on public.rr_upm_worker_ledger_v726,public.rr_upm_department_ledger_v726 to authenticated;

-- ============================================================================
-- C. COLOUR-BOUND DEPARTMENT HANDOFF FLOW
-- Version is intentionally kept out of web filenames. Use the supplied commit message.
-- Rules:
--   1) One assignment = one complete Colour + every Cutting size.
--   2) One, many or all open Colours may be assigned together.
--   3) A downstream department cannot assign a Colour before upstream Submit.
--   4) Submit is Colour-level: every size's remaining direct Pending becomes Good;
--      open Alter/Remake stays in the current department and is not forwarded.
--   5) Submitted Good opens the Colour in the next active department.
-- ============================================================================

alter table public.rr_upm_work_assignments_v8
  add column if not exists inbound_qty numeric(14,3) not null default 0,
  add column if not exists inbound_breakup jsonb not null default '[]'::jsonb;

-- Legacy assignments were already full-colour assignments. Preserve them as the
-- initial inbound snapshot so they continue to work after this migration.
update public.rr_upm_work_assignments_v8
set inbound_qty=case when coalesce(inbound_qty,0)>0 then inbound_qty else coalesce(assigned_qty,0) end,
    inbound_breakup=case when jsonb_array_length(coalesce(inbound_breakup,'[]'::jsonb))>0 then inbound_breakup else coalesce(size_breakup,'[]'::jsonb) end,
    updated_at=now()
where status in('ASSIGNED','IN_PROGRESS','COMPLETED');

create table if not exists public.rr_upm_department_handoffs_v727(
  id uuid primary key default gen_random_uuid(),
  request_id uuid unique default gen_random_uuid(),
  canonical_lot_id text not null,
  lot_no text not null,
  from_department_code text not null,
  to_department_code text not null,
  colour_id uuid,
  colour_code text not null,
  colour_name text,
  size_code text not null,
  qty numeric(14,3) not null check(qty>0),
  assignment_id uuid,
  worker_id uuid,
  worker_name text,
  remarks text,
  actor_user_id uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists rr_upm_department_handoffs_v727_in_idx
on public.rr_upm_department_handoffs_v727(canonical_lot_id,upper(to_department_code),colour_id,upper(colour_code),upper(size_code));
create index if not exists rr_upm_department_handoffs_v727_out_idx
on public.rr_upm_department_handoffs_v727(canonical_lot_id,upper(from_department_code),colour_id,upper(colour_code),upper(size_code));
alter table public.rr_upm_department_handoffs_v727 enable row level security;
drop policy if exists rr_upm_department_handoffs_v727_read on public.rr_upm_department_handoffs_v727;
create policy rr_upm_department_handoffs_v727_read on public.rr_upm_department_handoffs_v727 for select to authenticated using(true);
grant select on public.rr_upm_department_handoffs_v727 to authenticated;

create or replace function public.rr_upm_access_context_v727()
returns jsonb
language plpgsql stable security definer set search_path=public as $function$
declare v_profile public.rr_user_profiles%rowtype;v_allowed boolean:=false;v_department text;
begin
  select * into v_profile from public.rr_user_profiles
  where auth_user_id=auth.uid() and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE' limit 1;
  if not found then return jsonb_build_object('allowed',false,'reason','Active ERP profile required'); end if;
  if lower(coalesce(v_profile.role_code,'')) in('owner','admin','manager','line_manager','line_man','department_head','production','cutting_master') then
    v_allowed:=true;
  else
    select r.department_code into v_department
    from public.rr_role_department_map_v1 r
    join public.rr_departments_v1 d on d.department_code=r.department_code
    where lower(r.role_code)=lower(v_profile.role_code) and r.is_active and d.is_active and coalesce(d.production_enabled,false)
    limit 1;
    v_allowed:=v_department is not null;
  end if;
  return jsonb_build_object('allowed',v_allowed,'role_code',lower(v_profile.role_code),'department_code',coalesce(v_department,v_profile.department_code),'profile_id',v_profile.id,'full_name',v_profile.full_name);
end
$function$;
grant execute on function public.rr_upm_access_context_v727() to authenticated;

create or replace function public.rr_upm_next_department_v727(p_department_code text)
returns text
language sql stable security definer set search_path=public as $function$
  select d.department_code
  from public.rr_upm_departments d
  where d.is_active
    and coalesce(d.worker_assignment_enabled,true)
    and d.sequence_no>(select sequence_no from public.rr_upm_departments where upper(department_code)=upper(trim(p_department_code)) limit 1)
  order by d.sequence_no,d.department_code
  limit 1;
$function$;
grant execute on function public.rr_upm_next_department_v727(text) to authenticated;

create or replace function public.rr_upm_department_inbound_v727(
  p_canonical_lot_id text,p_department_code text,p_colour_id uuid,p_colour_code text,p_size_code text
)
returns table(cutting_qty numeric,inbound_qty numeric,handed_in_qty numeric,assignment_snapshot_qty numeric,inbound_source text)
language sql stable security definer set search_path=public as $function$
with lot as(
  select lot_no from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id limit 1
),cut as(
  select coalesce(sum(c.cutting_qty),0)::numeric cutting_qty
  from lot l cross join lateral public.rr_upm_cut_size_rows_v726(l.lot_no) c
  where upper(c.size_code)=upper(trim(p_size_code))
    and ((p_colour_id is not null and c.colour_id=p_colour_id) or (p_colour_id is null and upper(c.colour_code)=upper(trim(p_colour_code))))
),handed as(
  select coalesce(sum(h.qty),0)::numeric handed_in_qty
  from public.rr_upm_department_handoffs_v727 h
  where h.canonical_lot_id=p_canonical_lot_id
    and upper(h.to_department_code)=upper(trim(p_department_code))
    and upper(h.size_code)=upper(trim(p_size_code))
    and ((p_colour_id is not null and h.colour_id=p_colour_id) or (p_colour_id is null and upper(h.colour_code)=upper(trim(p_colour_code))))
),assignment as(
  select a.id,
    coalesce((select sum(coalesce((z->>'qty')::numeric,0))
      from jsonb_array_elements(coalesce(a.inbound_breakup,'[]'::jsonb)) z
      where upper(trim(z->>'size_code'))=upper(trim(p_size_code))),0)::numeric snapshot_qty
  from public.rr_upm_work_assignments_v8 a
  where a.canonical_lot_id=p_canonical_lot_id
    and upper(a.department_code)=upper(trim(p_department_code))
    and a.status in('ASSIGNED','IN_PROGRESS','COMPLETED')
    and ((p_colour_id is not null and a.colour_id=p_colour_id) or (p_colour_id is null and upper(a.colour_code)=upper(trim(p_colour_code))))
  order by a.assigned_at desc limit 1
),initial_gate as(
  select exists(
    select 1 from public.rr_upm_colour_state s
    where s.canonical_lot_id=p_canonical_lot_id
      and upper(s.colour_code)=upper(trim(p_colour_code))
      and (
        upper(s.current_department_code)=upper(trim(p_department_code))
        or (upper(s.current_department_code)='CUTTING' and upper(public.rr_upm_next_department_v727('CUTTING'))=upper(trim(p_department_code)))
      )
  ) or (
    not exists(select 1 from public.rr_upm_colour_state s where s.canonical_lot_id=p_canonical_lot_id and upper(s.colour_code)=upper(trim(p_colour_code)))
    and upper(public.rr_upm_next_department_v727('CUTTING'))=upper(trim(p_department_code))
  ) is_initial
)
select c.cutting_qty,
  case
    when a.id is not null then greatest(h.handed_in_qty,a.snapshot_qty,case when g.is_initial then c.cutting_qty else 0 end)
    when h.handed_in_qty>0 then h.handed_in_qty
    when g.is_initial then c.cutting_qty
    else 0
  end::numeric inbound_qty,
  h.handed_in_qty,
  coalesce(a.snapshot_qty,0)::numeric,
  case
    when h.handed_in_qty>0 then 'UPSTREAM_SUBMIT'
    when a.id is not null and a.snapshot_qty>0 then 'ASSIGNMENT_SNAPSHOT'
    when g.is_initial then 'INITIAL_ROUTE'
    else 'WAITING_PREVIOUS_SUBMIT'
  end::text inbound_source
from cut c cross join handed h cross join initial_gate g left join assignment a on true;
$function$;
grant execute on function public.rr_upm_department_inbound_v727(text,text,uuid,text,text) to authenticated;

create or replace function public.rr_upm_action_permission_v727(p_action_type text,p_department_code text)
returns boolean
language plpgsql stable security definer set search_path=public as $function$
declare v_profile public.rr_user_profiles%rowtype;v_key text;v_override boolean;v_allowed boolean:=false;v_eligible boolean:=false;
begin
  select * into v_profile from public.rr_user_profiles
  where auth_user_id=auth.uid() and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE' limit 1;
  if not found then return false; end if;
  if lower(coalesce(v_profile.role_code,'')) in('owner','admin') then return true; end if;
  v_key:=case upper(trim(p_action_type))
    when 'GOOD' then 'upm.submit_work' when 'ALTER' then 'upm.register_alter'
    when 'REMAKE_ISSUE' then 'upm.remake_issue' when 'REMAKE_COMPLETE' then 'upm.remake_complete'
    when 'DAMAGE' then 'upm.damage' when 'REASSIGN' then 'upm.reassign_pending'
    when 'ASSIGN' then 'upm.assign_work' else null end;
  if v_key is null then return false; end if;

  select u.is_allowed into v_override from public.rr_user_action_overrides_v1 u
  where u.profile_id=v_profile.id and u.action_key=v_key
    and (u.valid_from is null or u.valid_from<=now()) and (u.valid_until is null or u.valid_until>now())
  limit 1;
  if v_override is not null then return v_override; end if;

  v_eligible:=lower(coalesce(v_profile.role_code,'')) in('manager','line_manager','line_man','department_head','production','cutting_master')
    or lower(coalesce(v_profile.department_code,''))=lower(trim(p_department_code))
    or exists(
      select 1 from public.rr_worker_directory_unified_v1 w
      where w.linked_auth_user_id=auth.uid()
        and public.rr_upm_worker_eligible_v726(w.worker_id,p_department_code)
    );
  if not v_eligible then return false; end if;

  select p.is_allowed into v_allowed from public.rr_department_action_permissions_v1 p
  where p.action_key=v_key and p.department_code=lower(trim(p_department_code)) limit 1;
  return coalesce(v_allowed,false);
end
$function$;
grant execute on function public.rr_upm_action_permission_v727(text,text) to authenticated;

drop function if exists public.rr_upm_action_balance_v727(text,text,uuid,text,text);
create function public.rr_upm_action_balance_v727(
  p_canonical_lot_id text,p_department_code text,p_colour_id uuid,p_colour_code text,p_size_code text
)
returns table(
  cutting_qty numeric,inbound_qty numeric,direct_good_qty numeric,alter_registered_qty numeric,remake_issued_qty numeric,
  remake_completed_qty numeric,damage_pending_qty numeric,damage_alter_qty numeric,damage_remake_qty numeric,
  outbound_qty numeric,pending_qty numeric,alter_open_qty numeric,remake_open_qty numeric,good_total_qty numeric,
  submit_ready_qty numeric,damage_total_qty numeric
)
language sql stable security definer set search_path=public as $function$
with src as(
  select * from public.rr_upm_department_inbound_v727(p_canonical_lot_id,p_department_code,p_colour_id,p_colour_code,p_size_code)
),act as(
  select
    coalesce(sum(qty) filter(where action_type='GOOD'),0)::numeric direct_good,
    coalesce(sum(qty) filter(where action_type='ALTER'),0)::numeric alter_registered,
    coalesce(sum(qty) filter(where action_type='REMAKE_ISSUE'),0)::numeric remake_issued,
    coalesce(sum(qty) filter(where action_type='REMAKE_COMPLETE'),0)::numeric remake_completed,
    coalesce(sum(qty) filter(where action_type='DAMAGE' and coalesce(source_bucket,'PENDING')='PENDING'),0)::numeric damage_pending,
    coalesce(sum(qty) filter(where action_type='DAMAGE' and source_bucket='ALTER'),0)::numeric damage_alter,
    coalesce(sum(qty) filter(where action_type='DAMAGE' and source_bucket='REMAKE'),0)::numeric damage_remake
  from public.rr_upm_actions_v726 a
  where a.canonical_lot_id=p_canonical_lot_id
    and upper(a.department_code)=upper(trim(p_department_code))
    and upper(a.size_code)=upper(trim(p_size_code))
    and ((p_colour_id is not null and a.colour_id=p_colour_id) or (p_colour_id is null and upper(a.colour_code)=upper(trim(p_colour_code))))
),outbound as(
  select coalesce(sum(h.qty),0)::numeric outbound_qty
  from public.rr_upm_department_handoffs_v727 h
  where h.canonical_lot_id=p_canonical_lot_id
    and upper(h.from_department_code)=upper(trim(p_department_code))
    and upper(h.size_code)=upper(trim(p_size_code))
    and ((p_colour_id is not null and h.colour_id=p_colour_id) or (p_colour_id is null and upper(h.colour_code)=upper(trim(p_colour_code))))
)
select s.cutting_qty,s.inbound_qty,a.direct_good,a.alter_registered,a.remake_issued,a.remake_completed,
  a.damage_pending,a.damage_alter,a.damage_remake,o.outbound_qty,
  greatest(s.inbound_qty-a.direct_good-a.alter_registered-a.damage_pending,0),
  greatest(a.alter_registered-a.remake_issued-a.damage_alter,0),
  greatest(a.remake_issued-a.remake_completed-a.damage_remake,0),
  a.direct_good+a.remake_completed,
  greatest(a.direct_good+a.remake_completed-o.outbound_qty,0),
  a.damage_pending+a.damage_alter+a.damage_remake
from src s cross join act a cross join outbound o;
$function$;
grant execute on function public.rr_upm_action_balance_v727(text,text,uuid,text,text) to authenticated;

create or replace function public.rr_upm_assign_colours_v8_3(
  p_canonical_lot_id text,p_lot_no text,p_department_code text,p_rows jsonb,p_remarks text default null
)
returns setof public.rr_upm_work_assignments_v8
language plpgsql security definer set search_path=public as $function$
declare
  v_profile public.rr_user_profiles%rowtype;v_allowed boolean:=false;v_lot_no text;v_row jsonb;
  v_colour_id uuid;v_colour text;v_worker uuid;v_qty integer;v_rate numeric(12,4);
  v_expected integer;v_sizes jsonb;v_cname text;v_source text;v_source_lot uuid;
  v_wname text;v_wcode text;v_existing public.rr_upm_work_assignments_v8%rowtype;v_out public.rr_upm_work_assignments_v8;
  v_inbound numeric;v_inbound_sizes jsonb;
begin
  select * into v_profile from public.rr_user_profiles
  where auth_user_id=auth.uid() and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE' limit 1;
  if not found then raise exception 'Active User Directory profile required.'; end if;
  v_allowed:=lower(coalesce(v_profile.role_code,'')) in('owner','admin','manager','line_manager','line_man','department_head','production','cutting_master')
    or public.rr_upm_action_permission_v727('ASSIGN',p_department_code);
  if not v_allowed then raise exception 'Assign Work permission denied by Role & Permission Directory.'; end if;
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0 then raise exception 'Select at least one colour.'; end if;
  select coalesce((select lot_no from public.rr_upm_lot_board_v1 where canonical_lot_id=nullif(trim(p_canonical_lot_id),'') limit 1),nullif(trim(p_lot_no),'')) into v_lot_no;
  if v_lot_no is null then raise exception 'Lot No is required.'; end if;

  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_colour_id:=nullif(v_row->>'colour_id','')::uuid;
    v_colour:=upper(trim(v_row->>'colour_code'));
    v_worker:=nullif(v_row->>'worker_id','')::uuid;
    v_qty:=coalesce(nullif(v_row->>'assigned_qty','')::integer,0);
    v_rate:=coalesce(nullif(v_row->>'actual_rate','')::numeric,0);
    if v_worker is null then raise exception 'Worker is required for colour %.',v_colour; end if;
    if not public.rr_upm_worker_eligible_v726(v_worker,p_department_code) then raise exception 'Selected worker is not enabled for department %.',p_department_code; end if;

    select max(r.colour_name),sum(r.cutting_qty)::integer,
      jsonb_agg(jsonb_build_object('size_code',r.size_code,'qty',r.cutting_qty) order by upper(r.size_code)),
      max(r.source_type),(array_agg(r.source_lot_id))[1],(array_agg(r.colour_id))[1]
    into v_cname,v_expected,v_sizes,v_source,v_source_lot,v_colour_id
    from public.rr_upm_cut_size_rows_v726(v_lot_no) r
    where (v_colour_id is not null and r.colour_id=v_colour_id) or (v_colour_id is null and upper(r.colour_code)=v_colour);
    if v_expected is null then raise exception 'Mapped Cutting colour-size quantity missing for colour %.',v_colour; end if;
    if v_qty<>v_expected then raise exception 'Colour % qty must equal complete Cutting mapped qty %.',v_colour,v_expected; end if;

    select coalesce(sum(i.inbound_qty),0),
      coalesce(jsonb_agg(jsonb_build_object('size_code',r.size_code,'qty',i.inbound_qty) order by upper(r.size_code)),'[]'::jsonb)
    into v_inbound,v_inbound_sizes
    from public.rr_upm_cut_size_rows_v726(v_lot_no) r
    cross join lateral public.rr_upm_department_inbound_v727(p_canonical_lot_id,p_department_code,r.colour_id,r.colour_code,r.size_code) i
    where (v_colour_id is not null and r.colour_id=v_colour_id) or (v_colour_id is null and upper(r.colour_code)=v_colour);
    if coalesce(v_inbound,0)<=0 then raise exception 'Colour % is waiting for previous department Submit.',v_colour; end if;

    select * into v_existing from public.rr_upm_work_assignments_v8 x
    where x.canonical_lot_id=p_canonical_lot_id and upper(x.department_code)=upper(p_department_code)
      and x.status in('ASSIGNED','IN_PROGRESS','COMPLETED')
      and ((v_colour_id is not null and x.colour_id=v_colour_id) or upper(x.colour_code)=v_colour)
    order by x.assigned_at desc limit 1;
    if v_existing.id is not null then raise exception 'Colour % is already assigned to % in %.',v_colour,v_existing.worker_name_snapshot,p_department_code; end if;

    select worker_name,worker_code into v_wname,v_wcode from public.rr_worker_directory_unified_v1 where worker_id=v_worker limit 1;
    insert into public.rr_upm_work_assignments_v8(
      canonical_lot_id,lot_no,department_code,colour_id,colour_code,colour_name,source_type,source_lot_id,
      worker_id,worker_code,worker_name_snapshot,assigned_qty,size_breakup,inbound_qty,inbound_breakup,actual_rate,
      rate_filled_by,rate_filled_by_name,rate_filled_at,assigned_by,assigned_by_name,remarks,status
    ) values(
      nullif(trim(p_canonical_lot_id),''),v_lot_no,upper(trim(p_department_code)),v_colour_id,v_colour,coalesce(v_cname,v_colour),v_source,v_source_lot,
      v_worker,v_wcode,v_wname,v_expected,coalesce(v_sizes,'[]'::jsonb),v_inbound,coalesce(v_inbound_sizes,'[]'::jsonb),round(v_rate,4),
      auth.uid(),coalesce(v_profile.full_name,v_profile.email),now(),auth.uid(),coalesce(v_profile.full_name,v_profile.email),p_remarks,'ASSIGNED'
    ) returning * into v_out;
    return next v_out;
  end loop;
end
$function$;
grant execute on function public.rr_upm_assign_colours_v8_3(text,text,text,jsonb,text) to authenticated;

create or replace function public.rr_upm_apply_actions_batch_v726(
  p_canonical_lot_id text,p_department_code text,p_actions jsonb,p_rate numeric default 0,p_remarks text default null
)
returns jsonb
language plpgsql security definer set search_path=public as $function$
declare
  v_lot public.rr_upm_lot_registry%rowtype;v_row jsonb;v_type text;v_bucket text;v_qty numeric;
  v_colour_id uuid;v_colour text;v_cname text;v_size text;v_request uuid;v_assign public.rr_upm_work_assignments_v8%rowtype;
  v_balance record;v_std numeric;v_actor text;v_entry_type text;v_count integer:=0;
begin
  if jsonb_typeof(p_actions)<>'array' or jsonb_array_length(p_actions)=0 then raise exception 'No action rows supplied.'; end if;
  select * into v_lot from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id;
  if not found then raise exception 'Lot is not registered.'; end if;
  begin v_actor:=coalesce(public.rr_up_user_context_v2()->>'display_name',auth.uid()::text); exception when others then v_actor:=auth.uid()::text; end;
  begin select standard_rate into v_std from public.rr_upm_standard_rates_v723 where canonical_lot_id=p_canonical_lot_id and upper(department_code)=upper(p_department_code) limit 1; exception when others then v_std:=null; end;

  for v_row in select value from jsonb_array_elements(p_actions) loop
    v_type:=upper(trim(v_row->>'action_type'));v_bucket:=upper(trim(coalesce(v_row->>'source_bucket','PENDING')));
    v_qty:=coalesce(nullif(v_row->>'qty','')::numeric,0);v_colour_id:=nullif(v_row->>'colour_id','')::uuid;
    v_colour:=upper(trim(v_row->>'colour_code'));v_cname:=nullif(trim(v_row->>'colour_name'),'');v_size:=upper(trim(v_row->>'size_code'));
    v_request:=nullif(v_row->>'request_id','')::uuid;
    if v_type not in('GOOD','ALTER','REMAKE_ISSUE','REMAKE_COMPLETE','DAMAGE') then raise exception 'Invalid action type %.',v_type; end if;
    if not public.rr_upm_action_permission_v727(v_type,p_department_code) then raise exception 'Permission denied for %.',v_type; end if;
    if v_qty<=0 then raise exception '% quantity must be greater than zero.',v_type; end if;
    if v_bucket not in('PENDING','ALTER','REMAKE') then raise exception 'Invalid source bucket %.',v_bucket; end if;
    if v_type<>'DAMAGE' then v_bucket:=case when v_type='REMAKE_ISSUE' then 'ALTER' when v_type='REMAKE_COMPLETE' then 'REMAKE' else 'PENDING' end; end if;
    if v_request is not null and exists(select 1 from public.rr_upm_actions_v726 where request_id=v_request) then continue; end if;

    select * into v_assign from public.rr_upm_work_assignments_v8 x
    where x.canonical_lot_id=p_canonical_lot_id and upper(x.department_code)=upper(p_department_code)
      and x.status in('ASSIGNED','IN_PROGRESS')
      and ((v_colour_id is not null and x.colour_id=v_colour_id) or upper(x.colour_code)=v_colour)
    order by case when v_colour_id is not null and x.colour_id=v_colour_id then 0 else 1 end,x.assigned_at desc limit 1;
    if v_assign.id is null then raise exception 'Complete colour % is not actively assigned in %.',v_colour,p_department_code; end if;
    if not public.rr_upm_worker_eligible_v726(v_assign.worker_id,p_department_code) then raise exception 'Assigned worker is inactive or no longer enabled for %.',p_department_code; end if;

    select * into v_balance from public.rr_upm_action_balance_v727(p_canonical_lot_id,p_department_code,v_colour_id,v_colour,v_size);
    if v_balance.inbound_qty is null or v_balance.inbound_qty<=0 then raise exception '% / % is waiting for previous department Submit.',v_colour,v_size; end if;
    if v_type in('GOOD','ALTER') and v_qty>v_balance.pending_qty then raise exception '% / %: Qty % exceeds Pending %.',v_colour,v_size,v_qty,v_balance.pending_qty; end if;
    if v_type='REMAKE_ISSUE' and v_qty>v_balance.alter_open_qty then raise exception '% / %: Remake Issue % exceeds Alter Open %.',v_colour,v_size,v_qty,v_balance.alter_open_qty; end if;
    if v_type='REMAKE_COMPLETE' and v_qty>v_balance.remake_open_qty then raise exception '% / %: Remake Complete % exceeds Remake Open %.',v_colour,v_size,v_qty,v_balance.remake_open_qty; end if;
    if v_type='DAMAGE' then
      if v_bucket='PENDING' and v_qty>v_balance.pending_qty then raise exception '% / %: Damage % exceeds Pending %.',v_colour,v_size,v_qty,v_balance.pending_qty; end if;
      if v_bucket='ALTER' and v_qty>v_balance.alter_open_qty then raise exception '% / %: Damage % exceeds Alter Open %.',v_colour,v_size,v_qty,v_balance.alter_open_qty; end if;
      if v_bucket='REMAKE' and v_qty>v_balance.remake_open_qty then raise exception '% / %: Damage % exceeds Remake Open %.',v_colour,v_size,v_qty,v_balance.remake_open_qty; end if;
    end if;

    insert into public.rr_upm_actions_v726(request_id,canonical_lot_id,lot_no,department_code,colour_id,colour_code,colour_name,size_code,assignment_id,worker_id,worker_name,worker_code,action_type,source_bucket,qty,actual_rate,standard_rate,remarks,actor_name)
    values(v_request,p_canonical_lot_id,v_lot.lot_no,upper(p_department_code),v_colour_id,v_colour,coalesce(v_cname,v_assign.colour_name),v_size,v_assign.id,v_assign.worker_id,v_assign.worker_name_snapshot,v_assign.worker_code,v_type,v_bucket,v_qty,coalesce(v_assign.actual_rate,p_rate,0),v_std,coalesce(nullif(trim(p_remarks),''),'Universal Lot Form'),v_actor);

    v_entry_type:=case v_type when 'GOOD' then 'GOOD' when 'ALTER' then 'ALTER_OUT' when 'REMAKE_COMPLETE' then 'REMAKE' when 'DAMAGE' then 'REJECT' else null end;
    if v_entry_type is not null then
      insert into public.rr_upm_entries(canonical_lot_id,lot_no,department_code,colour_code,size_code,entry_type,qty,rate,remarks,operator_name)
      values(p_canonical_lot_id,v_lot.lot_no,upper(p_department_code),v_colour,v_size,v_entry_type,v_qty,coalesce(v_assign.actual_rate,p_rate,0),concat_ws(' · ',p_remarks,'Source '||v_bucket),v_actor);
    end if;
    update public.rr_upm_work_assignments_v8 set status='IN_PROGRESS',updated_at=now() where id=v_assign.id and status='ASSIGNED';
    v_count:=v_count+1;
  end loop;
  return jsonb_build_object('ok',true,'actions_saved',v_count);
end
$function$;
grant execute on function public.rr_upm_apply_actions_batch_v726(text,text,jsonb,numeric,text) to authenticated;

create or replace function public.rr_upm_submit_colours_v727(
  p_canonical_lot_id text,p_department_code text,p_rows jsonb,p_rate numeric default 0,p_remarks text default null
)
returns jsonb
language plpgsql security definer set search_path=public as $function$
declare
  v_lot public.rr_upm_lot_registry%rowtype;v_row jsonb;v_colour_id uuid;v_colour text;v_assign public.rr_upm_work_assignments_v8%rowtype;
  v_cut record;v_bal record;v_actions jsonb;v_next text;v_handoff numeric;v_colour_name text;v_submitted numeric:=0;v_colours integer:=0;
  v_pending_total numeric;v_alter_total numeric;v_remake_total numeric;v_ready_total numeric;v_actor text;
begin
  if not public.rr_upm_action_permission_v727('GOOD',p_department_code) then raise exception 'Submit Work permission denied.'; end if;
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0 then raise exception 'Select at least one assigned colour.'; end if;
  select * into v_lot from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id;
  if not found then raise exception 'Lot is not registered.'; end if;
  begin v_actor:=coalesce(public.rr_up_user_context_v2()->>'display_name',auth.uid()::text); exception when others then v_actor:=auth.uid()::text; end;
  v_next:=public.rr_upm_next_department_v727(p_department_code);

  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_colour_id:=nullif(v_row->>'colour_id','')::uuid;v_colour:=upper(trim(v_row->>'colour_code'));
    select * into v_assign from public.rr_upm_work_assignments_v8 a
    where a.canonical_lot_id=p_canonical_lot_id and upper(a.department_code)=upper(p_department_code)
      and a.status in('ASSIGNED','IN_PROGRESS')
      and ((v_colour_id is not null and a.colour_id=v_colour_id) or upper(a.colour_code)=v_colour)
    order by a.assigned_at desc limit 1;
    if v_assign.id is null then raise exception 'Active assignment not found for colour % in %.',v_colour,p_department_code; end if;
    v_colour_name:=coalesce(v_assign.colour_name,v_colour);v_actions:='[]'::jsonb;

    -- Every size travels together. All remaining direct Pending becomes Good.
    for v_cut in select * from public.rr_upm_cut_size_rows_v726(v_lot.lot_no) c
      where ((v_assign.colour_id is not null and c.colour_id=v_assign.colour_id) or (v_assign.colour_id is null and upper(c.colour_code)=upper(v_assign.colour_code)))
    loop
      select * into v_bal from public.rr_upm_action_balance_v727(p_canonical_lot_id,p_department_code,v_cut.colour_id,v_cut.colour_code,v_cut.size_code);
      if coalesce(v_bal.pending_qty,0)>0 then
        v_actions:=v_actions||jsonb_build_array(jsonb_build_object(
          'request_id',gen_random_uuid(),'colour_id',v_cut.colour_id,'colour_code',v_cut.colour_code,'colour_name',v_cut.colour_name,
          'size_code',v_cut.size_code,'action_type','GOOD','source_bucket','PENDING','qty',v_bal.pending_qty));
      end if;
    end loop;
    if jsonb_array_length(v_actions)>0 then
      perform public.rr_upm_apply_actions_batch_v726(p_canonical_lot_id,p_department_code,v_actions,p_rate,coalesce(p_remarks,'Colour Submit'));
    end if;

    v_handoff:=0;
    for v_cut in select * from public.rr_upm_cut_size_rows_v726(v_lot.lot_no) c
      where ((v_assign.colour_id is not null and c.colour_id=v_assign.colour_id) or (v_assign.colour_id is null and upper(c.colour_code)=upper(v_assign.colour_code)))
    loop
      select * into v_bal from public.rr_upm_action_balance_v727(p_canonical_lot_id,p_department_code,v_cut.colour_id,v_cut.colour_code,v_cut.size_code);
      if coalesce(v_bal.submit_ready_qty,0)>0 then
        insert into public.rr_upm_department_handoffs_v727(canonical_lot_id,lot_no,from_department_code,to_department_code,colour_id,colour_code,colour_name,size_code,qty,assignment_id,worker_id,worker_name,remarks,actor_user_id)
        values(p_canonical_lot_id,v_lot.lot_no,upper(p_department_code),coalesce(v_next,'FINAL'),v_cut.colour_id,v_cut.colour_code,v_cut.colour_name,v_cut.size_code,v_bal.submit_ready_qty,v_assign.id,v_assign.worker_id,v_assign.worker_name_snapshot,coalesce(p_remarks,'Colour Submit'),auth.uid());
        v_handoff:=v_handoff+v_bal.submit_ready_qty;
        -- A downstream worker may have finished an earlier partial handoff.
        -- New repaired/remade pieces reopen the same full-colour assignment.
        if v_next is not null then
          update public.rr_upm_work_assignments_v8 n set status='IN_PROGRESS',completed_at=null,updated_at=now()
          where n.canonical_lot_id=p_canonical_lot_id and upper(n.department_code)=upper(v_next)
            and n.status='COMPLETED'
            and ((v_cut.colour_id is not null and n.colour_id=v_cut.colour_id) or (v_cut.colour_id is null and upper(n.colour_code)=upper(v_cut.colour_code)));
        end if;
      end if;
    end loop;
    if v_handoff<=0 then raise exception 'Colour % has no new non-Alter balance to Submit.',v_colour; end if;

    if v_next is not null then
      update public.rr_upm_colour_state set current_department_code=v_next,status='PENDING',updated_at=now()
      where canonical_lot_id=p_canonical_lot_id and upper(colour_code)=upper(v_assign.colour_code);
    end if;

    select coalesce(sum(b.pending_qty),0),coalesce(sum(b.alter_open_qty),0),coalesce(sum(b.remake_open_qty),0),coalesce(sum(b.submit_ready_qty),0)
    into v_pending_total,v_alter_total,v_remake_total,v_ready_total
    from public.rr_upm_cut_size_rows_v726(v_lot.lot_no) c
    cross join lateral public.rr_upm_action_balance_v727(p_canonical_lot_id,p_department_code,c.colour_id,c.colour_code,c.size_code) b
    where ((v_assign.colour_id is not null and c.colour_id=v_assign.colour_id) or (v_assign.colour_id is null and upper(c.colour_code)=upper(v_assign.colour_code)));

    update public.rr_upm_work_assignments_v8 set
      status=case when coalesce(v_pending_total,0)=0 and coalesce(v_alter_total,0)=0 and coalesce(v_remake_total,0)=0 and coalesce(v_ready_total,0)=0 then 'COMPLETED' else 'IN_PROGRESS' end,
      completed_at=case when coalesce(v_pending_total,0)=0 and coalesce(v_alter_total,0)=0 and coalesce(v_remake_total,0)=0 and coalesce(v_ready_total,0)=0 then now() else completed_at end,
      updated_at=now()
    where id=v_assign.id;
    v_submitted:=v_submitted+v_handoff;v_colours:=v_colours+1;
  end loop;
  return jsonb_build_object('ok',true,'colours_submitted',v_colours,'qty_forwarded',v_submitted,'next_department_code',v_next,'context',public.rr_upm_universal_form_v726(p_canonical_lot_id,p_department_code));
end
$function$;
grant execute on function public.rr_upm_submit_colours_v727(text,text,jsonb,numeric,text) to authenticated;

create or replace function public.rr_upm_reassign_colours_v726(
  p_canonical_lot_id text,p_department_code text,p_rows jsonb,p_remarks text default null
)
returns jsonb
language plpgsql security definer set search_path=public as $function$
declare
  v_lot public.rr_upm_lot_registry%rowtype;v_row jsonb;v_colour_id uuid;v_colour text;v_new_worker uuid;
  v_old public.rr_upm_work_assignments_v8%rowtype;v_wname text;v_wcode text;v_profile public.rr_user_profiles%rowtype;
  v_cut record;v_bal record;v_pending_total numeric;v_alter_total numeric;v_remake_total numeric;v_new_id uuid;v_count integer:=0;
begin
  if not public.rr_upm_action_permission_v727('REASSIGN',p_department_code) then raise exception 'Reassign Pending permission denied.'; end if;
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0 then raise exception 'Select assigned colours to reassign.'; end if;
  select * into v_lot from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id;
  if not found then raise exception 'Lot is not registered.'; end if;
  select * into v_profile from public.rr_user_profiles where auth_user_id=auth.uid() limit 1;

  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_colour_id:=nullif(v_row->>'colour_id','')::uuid;v_colour:=upper(trim(v_row->>'colour_code'));v_new_worker:=nullif(v_row->>'new_worker_id','')::uuid;
    if v_new_worker is null then raise exception 'New worker is required for colour %.',v_colour; end if;
    if not public.rr_upm_worker_eligible_v726(v_new_worker,p_department_code) then raise exception 'New worker is not enabled for department %.',p_department_code; end if;
    select * into v_old from public.rr_upm_work_assignments_v8 a
    where a.canonical_lot_id=p_canonical_lot_id and upper(a.department_code)=upper(p_department_code) and a.status in('ASSIGNED','IN_PROGRESS')
      and ((v_colour_id is not null and a.colour_id=v_colour_id) or upper(a.colour_code)=v_colour)
    order by a.assigned_at desc limit 1;
    if v_old.id is null then raise exception 'Active assignment not found for colour %.',v_colour; end if;
    if v_old.worker_id=v_new_worker then raise exception 'New worker is same as current worker for colour %.',v_colour; end if;

    select coalesce(sum(b.pending_qty),0),coalesce(sum(b.alter_open_qty),0),coalesce(sum(b.remake_open_qty),0)
    into v_pending_total,v_alter_total,v_remake_total
    from public.rr_upm_cut_size_rows_v726(v_lot.lot_no) c
    cross join lateral public.rr_upm_action_balance_v727(p_canonical_lot_id,p_department_code,c.colour_id,c.colour_code,c.size_code) b
    where ((v_old.colour_id is not null and c.colour_id=v_old.colour_id) or (v_old.colour_id is null and upper(c.colour_code)=upper(v_old.colour_code)));
    if v_pending_total<=0 then raise exception 'No direct Pending work remains for colour %.',v_colour; end if;
    if v_alter_total>0 or v_remake_total>0 then raise exception 'Resolve Alter/Remake before reassigning colour %.',v_colour; end if;

    select worker_name,worker_code into v_wname,v_wcode from public.rr_worker_directory_unified_v1 where worker_id=v_new_worker limit 1;
    update public.rr_upm_work_assignments_v8 set status='CANCELLED',cancelled_at=now(),cancel_reason=coalesce(p_remarks,'Pending reassigned'),updated_at=now() where id=v_old.id;
    insert into public.rr_upm_work_assignments_v8(canonical_lot_id,lot_no,department_code,colour_id,colour_code,colour_name,source_type,source_lot_id,worker_id,worker_code,worker_name_snapshot,assigned_qty,size_breakup,inbound_qty,inbound_breakup,actual_rate,rate_filled_by,rate_filled_by_name,rate_filled_at,assigned_by,assigned_by_name,remarks,status)
    values(v_old.canonical_lot_id,v_old.lot_no,v_old.department_code,v_old.colour_id,v_old.colour_code,v_old.colour_name,v_old.source_type,v_old.source_lot_id,v_new_worker,v_wcode,v_wname,v_old.assigned_qty,v_old.size_breakup,v_old.inbound_qty,v_old.inbound_breakup,v_old.actual_rate,auth.uid(),coalesce(v_profile.full_name,v_profile.email),now(),auth.uid(),coalesce(v_profile.full_name,v_profile.email),concat_ws(' · ',p_remarks,'Reassigned from '||v_old.worker_name_snapshot),'ASSIGNED') returning id into v_new_id;

    for v_cut in select * from public.rr_upm_cut_size_rows_v726(v_lot.lot_no) c where ((v_old.colour_id is not null and c.colour_id=v_old.colour_id) or upper(c.colour_code)=upper(v_old.colour_code)) loop
      select * into v_bal from public.rr_upm_action_balance_v727(p_canonical_lot_id,p_department_code,v_cut.colour_id,v_cut.colour_code,v_cut.size_code);
      if coalesce(v_bal.pending_qty,0)>0 then
        insert into public.rr_upm_actions_v726(canonical_lot_id,lot_no,department_code,colour_id,colour_code,colour_name,size_code,assignment_id,worker_id,worker_name,worker_code,action_type,source_bucket,qty,actual_rate,remarks,actor_name)
        values(p_canonical_lot_id,v_lot.lot_no,upper(p_department_code),v_cut.colour_id,v_cut.colour_code,v_cut.colour_name,v_cut.size_code,v_old.id,v_old.worker_id,v_old.worker_name_snapshot,v_old.worker_code,'REASSIGN_OUT','SYSTEM',v_bal.pending_qty,coalesce(v_old.actual_rate,0),p_remarks,coalesce(v_profile.full_name,v_profile.email));
        insert into public.rr_upm_actions_v726(canonical_lot_id,lot_no,department_code,colour_id,colour_code,colour_name,size_code,assignment_id,worker_id,worker_name,worker_code,action_type,source_bucket,qty,actual_rate,remarks,actor_name)
        values(p_canonical_lot_id,v_lot.lot_no,upper(p_department_code),v_cut.colour_id,v_cut.colour_code,v_cut.colour_name,v_cut.size_code,v_new_id,v_new_worker,v_wname,v_wcode,'REASSIGN_IN','SYSTEM',v_bal.pending_qty,coalesce(v_old.actual_rate,0),p_remarks,coalesce(v_profile.full_name,v_profile.email));
      end if;
    end loop;
    v_count:=v_count+1;
  end loop;
  return jsonb_build_object('ok',true,'colours_reassigned',v_count,'context',public.rr_upm_universal_form_v726(p_canonical_lot_id,p_department_code));
end
$function$;
grant execute on function public.rr_upm_reassign_colours_v726(text,text,jsonb,text) to authenticated;

create or replace function public.rr_upm_universal_form_v726(p_canonical_lot_id text,p_department_code text)
returns jsonb
language plpgsql stable security definer set search_path=public as $function$
declare
  v_lot jsonb;v_rows jsonb;v_workers jsonb;v_rate numeric:=0;v_std numeric;v_margin numeric:=0;v_owner boolean:=false;v_summary jsonb;v_cb text;v_next text;
begin
  select to_jsonb(x) into v_lot from public.rr_upm_lot_board_v1 x where x.canonical_lot_id=p_canonical_lot_id limit 1;
  if v_lot is null then raise exception 'Lot not found.'; end if;
  v_cb:=coalesce(v_lot->>'cb_no',v_lot->>'cb_number',v_lot->>'cb_base_no');
  if nullif(trim(v_cb),'') is null then begin select coalesce(to_jsonb(c)->>'cb_no',to_jsonb(c)->>'cb_number',to_jsonb(c)->>'cb_code') into v_cb from public.rr_cutting_lots_v3 c where upper(trim(c.lot_no))=upper(trim(v_lot->>'lot_no')) order by c.created_at desc limit 1; exception when others then v_cb:=null; end; end if;
  v_lot:=jsonb_set(v_lot,'{cb_no}',to_jsonb(coalesce(nullif(trim(v_cb),''),'—')),true);
  begin v_owner:=public.rr_upm_is_owner_admin_v723(); exception when others then v_owner:=false; end;
  select coalesce(actual_rate,0) into v_rate from public.rr_upm_department_rates_v2 where canonical_lot_id=p_canonical_lot_id and upper(department_code)=upper(p_department_code) limit 1;
  if v_owner then
    begin select standard_rate into v_std from public.rr_upm_standard_rates_v723 where canonical_lot_id=p_canonical_lot_id and upper(department_code)=upper(p_department_code) limit 1; exception when others then v_std:=null; end;
    begin select flat_amount_per_piece into v_margin from public.rr_upm_owner_margin_v723 where is_active order by effective_from desc limit 1; exception when others then v_margin:=0; end;
  end if;
  v_next:=public.rr_upm_next_department_v727(p_department_code);

  with cuts as(select * from public.rr_upm_cut_size_rows_v726(v_lot->>'lot_no')),
  colour_map as(
    select colour_id,colour_code,max(colour_name) colour_name,sum(cutting_qty)::numeric total_qty,
      jsonb_agg(jsonb_build_object('size_code',size_code,'qty',cutting_qty) order by upper(size_code)) size_breakup,
      max(source_type) source_type,(array_agg(source_lot_id))[1] source_lot_id
    from cuts group by colour_id,colour_code
  ),assignment as(
    select c.*,a.id assignment_id,a.worker_id,a.worker_code,a.worker_name_snapshot,a.assigned_qty,a.actual_rate,a.status assignment_status,
      (a.id is not null and a.assigned_qty=c.total_qty and public.rr_upm_worker_eligible_v726(a.worker_id,p_department_code)
       and coalesce((select jsonb_agg(jsonb_build_object('size_code',upper(trim(z->>'size_code')),'qty',coalesce((z->>'qty')::numeric,0)) order by upper(trim(z->>'size_code'))) from jsonb_array_elements(coalesce(a.size_breakup,'[]'::jsonb)) z),'[]'::jsonb)=c.size_breakup) is_locked
    from colour_map c
    left join lateral(
      select x.* from public.rr_upm_work_assignments_v8 x
      where x.canonical_lot_id=p_canonical_lot_id and upper(x.department_code)=upper(p_department_code)
        and x.status in('ASSIGNED','IN_PROGRESS','COMPLETED')
        and ((c.colour_id is not null and x.colour_id=c.colour_id) or upper(x.colour_code)=upper(c.colour_code))
      order by case when c.colour_id is not null and x.colour_id=c.colour_id then 0 else 1 end,x.assigned_at desc limit 1
    ) a on true
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'source_type',c.source_type,'source_lot_id',c.source_lot_id,'colour_id',c.colour_id,'colour_code',c.colour_code,'colour_name',c.colour_name,
    'size_code',c.size_code,'cutting_qty',c.cutting_qty,'inbound_qty',b.inbound_qty,'outbound_qty',b.outbound_qty,'submit_ready_qty',b.submit_ready_qty,
    'inbound_source',i.inbound_source,'assignment_id',a.assignment_id,'worker_id',a.worker_id,'worker_name',a.worker_name_snapshot,'worker_code',a.worker_code,
    'colour_total_qty',a.total_qty,'colour_assigned_qty',coalesce(a.assigned_qty,0),'assigned_qty',case when a.is_locked then c.cutting_qty else 0 end,
    'is_locked',coalesce(a.is_locked,false),'can_assign',(a.assignment_id is null and b.inbound_qty>0),'assignment_status',a.assignment_status,
    'good_qty',case when a.is_locked then b.good_total_qty else 0 end,'direct_good_qty',case when a.is_locked then b.direct_good_qty else 0 end,
    'alter_registered_qty',case when a.is_locked then b.alter_registered_qty else 0 end,'alter_open_qty',case when a.is_locked then b.alter_open_qty else 0 end,'alter_qty',case when a.is_locked then b.alter_open_qty else 0 end,
    'remake_issued_qty',case when a.is_locked then b.remake_issued_qty else 0 end,'remake_completed_qty',case when a.is_locked then b.remake_completed_qty else 0 end,
    'remake_open_qty',case when a.is_locked then b.remake_open_qty else 0 end,'remake_qty',case when a.is_locked then b.remake_open_qty else 0 end,
    'damage_qty',case when a.is_locked then b.damage_total_qty else 0 end,'pending_qty',case when a.is_locked then b.pending_qty else b.inbound_qty end,
    'actual_rate',coalesce(a.actual_rate,v_rate,0),'standard_rate',case when v_owner then v_std else null end,
    'status',case when a.assignment_id is null and b.inbound_qty<=0 then 'WAITING PREVIOUS SUBMIT'
      when a.assignment_id is null then 'OPEN FOR ASSIGNMENT'
      when b.pending_qty=0 and b.alter_open_qty=0 and b.remake_open_qty=0 and b.submit_ready_qty=0 then 'SUBMITTED'
      else 'RUNNING' end
  ) order by c.colour_name,case c.size_code when 'XS' then 1 when 'S' then 2 when 'M' then 3 when 'L' then 4 when 'XL' then 5 when 'XXL' then 6 when '2XL' then 6 when '3XL' then 7 when '4XL' then 8 when '5XL' then 9 else 99 end,c.size_code),'[]'::jsonb)
  into v_rows
  from cuts c
  join assignment a on a.colour_id is not distinct from c.colour_id and a.colour_code=c.colour_code
  cross join lateral public.rr_upm_department_inbound_v727(p_canonical_lot_id,p_department_code,c.colour_id,c.colour_code,c.size_code) i
  cross join lateral public.rr_upm_action_balance_v727(p_canonical_lot_id,p_department_code,c.colour_id,c.colour_code,c.size_code) b;

  select coalesce(jsonb_agg(to_jsonb(w) order by w.worker_name),'[]'::jsonb) into v_workers from public.rr_upm_worker_list_v8_3(p_department_code) w;
  select jsonb_build_object(
    'assigned',coalesce(sum((r->>'assigned_qty')::numeric),0),'inbound',coalesce(sum((r->>'inbound_qty')::numeric),0),
    'good',coalesce(sum((r->>'good_qty')::numeric),0),'alter',coalesce(sum((r->>'alter_open_qty')::numeric),0),
    'remake',coalesce(sum((r->>'remake_open_qty')::numeric),0),'damage',coalesce(sum((r->>'damage_qty')::numeric),0),
    'pending',coalesce(sum((r->>'pending_qty')::numeric),0),'ready_to_submit',coalesce(sum((r->>'submit_ready_qty')::numeric),0),
    'outbound',coalesce(sum((r->>'outbound_qty')::numeric),0)
  ) into v_summary from jsonb_array_elements(v_rows) r;

  return jsonb_build_object('lot',v_lot,'department_code',upper(p_department_code),'next_department_code',v_next,'rows',v_rows,'workers',v_workers,'summary',v_summary,
    'actual_rate',v_rate,'standard_rate',case when v_owner then v_std else null end,'owner_margin',case when v_owner then coalesce(v_margin,0) else null end,
    'can_view_standard',v_owner,'can_change_standard',v_owner,'can_change_margin',v_owner,
    'assignment_level','COLOUR_ALL_CUTTING_SIZES_LOCKED','submit_model','COLOUR_ALL_SIZES_AUTO_GOOD_EXCLUDING_ALTER','route_gate','NEXT_DEPARTMENT_OPENS_ONLY_AFTER_SUBMIT');
end
$function$;
grant execute on function public.rr_upm_universal_form_v726(text,text) to authenticated;

create or replace function public.rr_upm_debug_lot_flow_v726(p_canonical_lot_id text,p_department_code text)
returns jsonb
language plpgsql stable security definer set search_path=public as $function$
declare v_lot text;v_map jsonb;v_context jsonb;v_issues jsonb:='[]'::jsonb;v_department boolean;v_workers integer;v_assignments integer;v_handoffs integer;v_waiting integer;
begin
  select lot_no into v_lot from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id limit 1;
  if v_lot is null then v_issues:=v_issues||jsonb_build_array('Lot missing from rr_upm_lot_registry'); end if;
  select exists(select 1 from public.rr_upm_departments where upper(department_code)=upper(p_department_code) and is_active) into v_department;
  if not v_department then v_issues:=v_issues||jsonb_build_array('Department missing or inactive in rr_upm_departments'); end if;
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_map from public.rr_upm_cut_size_rows_v726(v_lot) x;
  if jsonb_array_length(v_map)=0 then v_issues:=v_issues||jsonb_build_array('No Single/Multi Cutting breakup rows found'); end if;
  select count(*) into v_workers from public.rr_upm_worker_list_v8_3(p_department_code);
  if v_workers=0 then v_issues:=v_issues||jsonb_build_array('No active primary/skill workers for selected department'); end if;
  select count(*) into v_assignments from public.rr_upm_work_assignments_v8 where canonical_lot_id=p_canonical_lot_id and upper(department_code)=upper(p_department_code) and status in('ASSIGNED','IN_PROGRESS','COMPLETED');
  select count(*) into v_handoffs from public.rr_upm_department_handoffs_v727 where canonical_lot_id=p_canonical_lot_id and (upper(from_department_code)=upper(p_department_code) or upper(to_department_code)=upper(p_department_code));
  begin v_context:=public.rr_upm_universal_form_v726(p_canonical_lot_id,p_department_code); exception when others then v_issues:=v_issues||jsonb_build_array('Universal form error: '||sqlerrm);v_context:=null; end;
  select count(*) into v_waiting from jsonb_array_elements(coalesce(v_context->'rows','[]'::jsonb)) r where r->>'status'='WAITING PREVIOUS SUBMIT';
  return jsonb_build_object('ok',jsonb_array_length(v_issues)=0,'lot_no',v_lot,'department_code',upper(p_department_code),'next_department_code',public.rr_upm_next_department_v727(p_department_code),
    'checks',jsonb_build_object('department_active',v_department,'cutting_rows',jsonb_array_length(v_map),'eligible_workers',v_workers,'assignments',v_assignments,'handoffs',v_handoffs,'waiting_rows',v_waiting),
    'issues',v_issues,'cutting_map',v_map,'context',v_context,
    'functions',jsonb_build_object('universal_form',to_regprocedure('public.rr_upm_universal_form_v726(text,text)'),'assign',to_regprocedure('public.rr_upm_assign_colours_v8_3(text,text,text,jsonb,text)'),
      'actions',to_regprocedure('public.rr_upm_apply_actions_batch_v726(text,text,jsonb,numeric,text)'),'submit',to_regprocedure('public.rr_upm_submit_colours_v727(text,text,jsonb,numeric,text)'),
      'reassign',to_regprocedure('public.rr_upm_reassign_colours_v726(text,text,jsonb,text)'),'inbound',to_regprocedure('public.rr_upm_department_inbound_v727(text,text,uuid,text,text)')));
end
$function$;
grant execute on function public.rr_upm_debug_lot_flow_v726(text,text) to authenticated;

create or replace view public.rr_upm_handoff_ledger_v727 as
select canonical_lot_id,lot_no,from_department_code,to_department_code,colour_id,colour_code,colour_name,size_code,qty,assignment_id,worker_id,worker_name,remarks,created_at
from public.rr_upm_department_handoffs_v727;
grant select on public.rr_upm_handoff_ledger_v727 to authenticated;


commit;

-- Verification examples:
-- select public.rr_owner_department_console_v2();
-- select * from public.rr_upm_verify_cutting_map_v726('YOUR-LOT-NO');
-- select public.rr_upm_debug_lot_flow_v726('CANONICAL-LOT-ID','STITCHING');
