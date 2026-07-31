-- REDZED UPM V741 — Dynamic Colour Queue / First Assignment Wins
-- Run AFTER the currently working V740 SQL.
-- Identity/Alter/WhatsApp tables and functions are not changed.

begin;

create extension if not exists pgcrypto;

create table if not exists public.rr_upm_colour_queue_v741(
  canonical_lot_id text not null,
  colour_id uuid,
  colour_code text not null,
  colour_name text,
  queue_state text not null default 'OPEN' check(queue_state in('OPEN','RUNNING')),
  owner_department_code text,
  owner_assignment_id uuid,
  opened_at timestamptz not null default now(),
  claimed_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key(canonical_lot_id,colour_code)
);

create table if not exists public.rr_upm_dynamic_submit_history_v741(
  id uuid primary key default gen_random_uuid(),
  canonical_lot_id text not null,
  lot_no text not null,
  department_code text not null,
  colour_id uuid,
  colour_code text not null,
  colour_name text,
  size_code text not null,
  good_qty numeric not null check(good_qty>=0),
  assignment_id uuid,
  worker_id uuid,
  worker_name text,
  submitted_by uuid default auth.uid(),
  submitted_at timestamptz not null default now(),
  remarks text
);

create index if not exists rr_upm_dynamic_submit_history_v741_lot_idx
on public.rr_upm_dynamic_submit_history_v741(canonical_lot_id,upper(department_code),upper(colour_code),submitted_at);

alter table public.rr_upm_colour_queue_v741 enable row level security;
alter table public.rr_upm_dynamic_submit_history_v741 enable row level security;

drop policy if exists rr_upm_colour_queue_v741_read on public.rr_upm_colour_queue_v741;
create policy rr_upm_colour_queue_v741_read on public.rr_upm_colour_queue_v741 for select to authenticated using(true);
drop policy if exists rr_upm_dynamic_submit_history_v741_read on public.rr_upm_dynamic_submit_history_v741;
create policy rr_upm_dynamic_submit_history_v741_read on public.rr_upm_dynamic_submit_history_v741 for select to authenticated using(true);

grant select on public.rr_upm_colour_queue_v741,public.rr_upm_dynamic_submit_history_v741 to authenticated;

create or replace function public.rr_upm_sync_colour_queue_v741(p_canonical_lot_id text)
returns void language plpgsql security definer set search_path=public as $$
declare v_lot text;v_q record;v_a record;
begin
  select lot_no into v_lot from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id limit 1;
  if v_lot is null then raise exception 'Lot not registered.'; end if;

  insert into public.rr_upm_colour_queue_v741(canonical_lot_id,colour_id,colour_code,colour_name,queue_state)
  select p_canonical_lot_id,c.colour_id,upper(c.colour_code),max(c.colour_name),'OPEN'
  from public.rr_upm_cut_size_rows_v726(v_lot)c
  group by c.colour_id,upper(c.colour_code)
  on conflict(canonical_lot_id,colour_code) do update
  set colour_id=coalesce(excluded.colour_id,rr_upm_colour_queue_v741.colour_id),
      colour_name=coalesce(excluded.colour_name,rr_upm_colour_queue_v741.colour_name),
      updated_at=now();

  for v_q in select * from public.rr_upm_colour_queue_v741 where canonical_lot_id=p_canonical_lot_id loop
    select * into v_a from public.rr_upm_work_assignments_v8 x
    where x.canonical_lot_id=p_canonical_lot_id and upper(x.colour_code)=upper(v_q.colour_code)
      and x.status in('ASSIGNED','IN_PROGRESS') order by x.assigned_at desc limit 1;
    if v_a.id is not null then
      update public.rr_upm_colour_queue_v741 set queue_state='RUNNING',owner_department_code=upper(v_a.department_code),owner_assignment_id=v_a.id,claimed_at=coalesce(claimed_at,v_a.assigned_at),updated_at=now()
      where canonical_lot_id=p_canonical_lot_id and upper(colour_code)=upper(v_q.colour_code);
    else
      update public.rr_upm_colour_queue_v741 set queue_state='OPEN',owner_department_code=null,owner_assignment_id=null,opened_at=now(),updated_at=now()
      where canonical_lot_id=p_canonical_lot_id and upper(colour_code)=upper(v_q.colour_code);
    end if;
  end loop;
end;$$;
grant execute on function public.rr_upm_sync_colour_queue_v741(text) to authenticated;

-- One-time migration: if older tests left the same Colour active in multiple departments,
-- keep the latest assignment and release the older duplicates.
with ranked as(
  select id,row_number() over(partition by canonical_lot_id,upper(colour_code) order by assigned_at desc,id desc) rn
  from public.rr_upm_work_assignments_v8 where status in('ASSIGNED','IN_PROGRESS')
)
update public.rr_upm_work_assignments_v8 a
set status='RELEASED',cancel_reason=coalesce(cancel_reason,'V741 single-owner migration'),updated_at=now()
from ranked r where a.id=r.id and r.rn>1;

create or replace function public.rr_upm_guard_single_colour_owner_v741()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.status in('ASSIGNED','IN_PROGRESS') then
    perform pg_advisory_xact_lock(hashtextextended(new.canonical_lot_id||'|'||upper(new.colour_code),0));
    if exists(
      select 1 from public.rr_upm_work_assignments_v8 x
      where x.canonical_lot_id=new.canonical_lot_id
        and upper(x.colour_code)=upper(new.colour_code)
        and x.status in('ASSIGNED','IN_PROGRESS')
        and x.id<>coalesce(new.id,gen_random_uuid())
    ) then
      raise exception 'Colour % is already running in another department. Submit it there before reassignment.',new.colour_code;
    end if;
  end if;
  return new;
end;$$;

drop trigger if exists rr_upm_guard_single_colour_owner_v741 on public.rr_upm_work_assignments_v8;
create trigger rr_upm_guard_single_colour_owner_v741
before insert or update of status,department_code,colour_code on public.rr_upm_work_assignments_v8
for each row execute function public.rr_upm_guard_single_colour_owner_v741();

create or replace function public.rr_upm_assignment_queue_sync_v741()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.status in('ASSIGNED','IN_PROGRESS') then
    insert into public.rr_upm_colour_queue_v741(canonical_lot_id,colour_id,colour_code,colour_name,queue_state,owner_department_code,owner_assignment_id,claimed_at,updated_at)
    values(new.canonical_lot_id,new.colour_id,upper(new.colour_code),new.colour_name,'RUNNING',upper(new.department_code),new.id,now(),now())
    on conflict(canonical_lot_id,colour_code) do update set
      queue_state='RUNNING',owner_department_code=excluded.owner_department_code,
      owner_assignment_id=excluded.owner_assignment_id,claimed_at=now(),updated_at=now();
  elsif tg_op='UPDATE' and old.status in('ASSIGNED','IN_PROGRESS') and new.status not in('ASSIGNED','IN_PROGRESS') then
    if not exists(select 1 from public.rr_upm_work_assignments_v8 x where x.canonical_lot_id=new.canonical_lot_id and upper(x.colour_code)=upper(new.colour_code) and x.status in('ASSIGNED','IN_PROGRESS') and x.id<>new.id) then
      insert into public.rr_upm_colour_queue_v741(canonical_lot_id,colour_id,colour_code,colour_name,queue_state,opened_at,updated_at)
      values(new.canonical_lot_id,new.colour_id,upper(new.colour_code),new.colour_name,'OPEN',now(),now())
      on conflict(canonical_lot_id,colour_code) do update set queue_state='OPEN',owner_department_code=null,owner_assignment_id=null,opened_at=now(),updated_at=now();
    end if;
  end if;
  return new;
end;$$;

drop trigger if exists rr_upm_assignment_queue_sync_v741 on public.rr_upm_work_assignments_v8;
create trigger rr_upm_assignment_queue_sync_v741
after insert or update of status on public.rr_upm_work_assignments_v8
for each row execute function public.rr_upm_assignment_queue_sync_v741();

create or replace function public.rr_upm_department_status_v741(p_canonical_lot_id text)
returns table(
  department_code text,department_name text,status_colour text,
  active_colour_codes text[],completed_colour_codes text[],display_colour_codes text[],
  active_count integer,completed_count integer,total_colours integer,display_label text
) language sql stable security definer set search_path=public as $$
with allc as(
  select array_agg(upper(q.colour_code) order by upper(q.colour_code)) all_codes,count(*)::int total
  from public.rr_upm_colour_queue_v741 q where q.canonical_lot_id=p_canonical_lot_id
),deps as(
  select d.department_code,d.department_name
  from public.rr_upm_departments d
  where d.is_active and coalesce(d.colour_assignment_enabled,true)
    and coalesce(d.worker_assignment_enabled,true)
    and upper(coalesce(d.department_type,'PRODUCTION'))='PRODUCTION'
    and not coalesce(d.is_start_department,false)
    and not exists(select 1 from public.rr_upm_departments ch where ch.is_active and upper(coalesce(ch.parent_department_code,''))=upper(d.department_code))
),x as(
 select d.department_code,d.department_name,
  coalesce((select array_agg(distinct upper(a.colour_code) order by upper(a.colour_code)) from public.rr_upm_work_assignments_v8 a where a.canonical_lot_id=p_canonical_lot_id and upper(a.department_code)=upper(d.department_code) and a.status in('ASSIGNED','IN_PROGRESS')),array[]::text[]) active_codes,
  coalesce((select array_agg(distinct upper(a.colour_code) order by upper(a.colour_code)) from public.rr_upm_work_assignments_v8 a where a.canonical_lot_id=p_canonical_lot_id and upper(a.department_code)=upper(d.department_code) and a.status='COMPLETED'),array[]::text[]) completed_codes
 from deps d
),s as(
 select x.*,array(select distinct z from unnest(x.active_codes||x.completed_codes)z order by z) display_codes,
 cardinality(x.active_codes)::int ac,cardinality(x.completed_codes)::int cc,(select total from allc) tc
 from x
)
select s.department_code,s.department_name,
 case when s.cc=s.tc and s.tc>0 then 'RED' when s.ac=s.tc and s.tc>0 then 'GREEN' when cardinality(s.display_codes)>0 then 'ORANGE' else 'BASE' end,
 s.active_codes,s.completed_codes,s.display_codes,s.ac,s.cc,s.tc,
 case
  when s.cc=s.tc and s.tc>0 then s.department_name||' · '||s.cc||'/'||s.tc||' SUBMITTED'
  when s.ac=s.tc and s.tc>0 then s.department_name||' · ALL RUNNING '||s.ac||'/'||s.tc
  when cardinality(s.display_codes)>0 then s.department_name||' · '||array_to_string(s.display_codes,' ')
  else s.department_name
 end
from s order by s.department_name;
$$;
grant execute on function public.rr_upm_department_status_v741(text) to authenticated;

create or replace function public.rr_upm_claim_colours_v741(
  p_canonical_lot_id text,p_lot_no text,p_department_code text,p_rows jsonb,p_remarks text default null
) returns setof public.rr_upm_work_assignments_v8
language plpgsql security definer set search_path=public as $$
declare
 v_profile public.rr_user_profiles%rowtype;v_row jsonb;v_lot_no text;v_colour text;v_colour_id uuid;v_worker uuid;v_qty integer;v_rate numeric;
 v_expected integer;v_sizes jsonb;v_cname text;v_source text;v_source_lot uuid;v_wname text;v_wcode text;v_out public.rr_upm_work_assignments_v8;v_dep record;
begin
 select * into v_profile from public.rr_user_profiles where auth_user_id=auth.uid() and coalesce(is_active,false) and upper(coalesce(access_status,'ACTIVE'))='ACTIVE' limit 1;
 if not found then raise exception 'Active User Directory profile required.';end if;
 if not public.rr_upm_action_permission_v727('ASSIGN',p_department_code) and lower(coalesce(v_profile.role_code,'')) not in('owner','admin','manager','line_manager','line_man','department_head','production','cutting_master') then raise exception 'Assign Work permission denied.';end if;
 select * into v_dep from public.rr_upm_departments d where upper(d.department_code)=upper(p_department_code) and d.is_active and coalesce(d.colour_assignment_enabled,true) and coalesce(d.worker_assignment_enabled,true) and upper(coalesce(d.department_type,'PRODUCTION'))='PRODUCTION' and not coalesce(d.is_start_department,false) and not exists(select 1 from public.rr_upm_departments ch where ch.is_active and upper(coalesce(ch.parent_department_code,''))=upper(d.department_code));
 if v_dep.id is null then raise exception 'Department is not eligible for random Colour assignment.';end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0 then raise exception 'Select at least one colour.';end if;
 select coalesce((select lot_no from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id limit 1),nullif(trim(p_lot_no),'')) into v_lot_no;
 if v_lot_no is null then raise exception 'Lot No is required.';end if;
 perform public.rr_upm_sync_colour_queue_v741(p_canonical_lot_id);
 for v_row in select value from jsonb_array_elements(p_rows) loop
  v_colour:=upper(trim(v_row->>'colour_code'));v_colour_id:=nullif(v_row->>'colour_id','')::uuid;v_worker:=nullif(v_row->>'worker_id','')::uuid;v_qty:=coalesce((v_row->>'assigned_qty')::int,0);v_rate:=coalesce((v_row->>'actual_rate')::numeric,0);
  perform pg_advisory_xact_lock(hashtextextended(p_canonical_lot_id||'|'||v_colour,0));
  if exists(select 1 from public.rr_upm_work_assignments_v8 a where a.canonical_lot_id=p_canonical_lot_id and upper(a.colour_code)=v_colour and a.status in('ASSIGNED','IN_PROGRESS')) then raise exception 'Colour % is already assigned. Submit it first.',v_colour;end if;
  if exists(select 1 from public.rr_upm_work_assignments_v8 a where a.canonical_lot_id=p_canonical_lot_id and upper(a.department_code)=upper(p_department_code) and upper(a.colour_code)=v_colour and a.status='COMPLETED') then raise exception 'Colour % already completed in department %.',v_colour,upper(p_department_code);end if;
  select max(c.colour_name),sum(c.cutting_qty)::int,jsonb_agg(jsonb_build_object('size_code',upper(c.size_code),'qty',c.cutting_qty) order by upper(c.size_code)),max(c.source_type),(array_agg(c.source_lot_id))[1]
  into v_cname,v_expected,v_sizes,v_source,v_source_lot from public.rr_upm_cut_size_rows_v726(v_lot_no)c where (v_colour_id is not null and c.colour_id=v_colour_id) or (v_colour_id is null and upper(c.colour_code)=v_colour);
  if v_expected is null then raise exception 'Cutting mapping missing for Colour %.',v_colour;end if;
  if v_qty<>v_expected then raise exception 'Colour % must be assigned full mapped Qty %.',v_colour,v_expected;end if;
  select worker_name,worker_code into v_wname,v_wcode from public.rr_upm_worker_list_v8_3(p_department_code) where worker_id=v_worker limit 1;
  if v_wname is null then raise exception 'Selected worker is not actively mapped to department %.',upper(p_department_code);end if;
  insert into public.rr_upm_work_assignments_v8(canonical_lot_id,lot_no,department_code,colour_id,colour_code,colour_name,source_type,source_lot_id,worker_id,worker_code,worker_name_snapshot,assigned_qty,size_breakup,inbound_qty,inbound_breakup,actual_rate,rate_filled_by,rate_filled_by_name,rate_filled_at,assigned_by,assigned_by_name,remarks,status)
  values(p_canonical_lot_id,v_lot_no,upper(p_department_code),v_colour_id,v_colour,coalesce(v_cname,v_colour),v_source,v_source_lot,v_worker,v_wcode,v_wname,v_expected,coalesce(v_sizes,'[]'::jsonb),v_expected,coalesce(v_sizes,'[]'::jsonb),round(v_rate,4),auth.uid(),coalesce(v_profile.full_name,v_profile.email),now(),auth.uid(),coalesce(v_profile.full_name,v_profile.email),p_remarks,'ASSIGNED') returning * into v_out;
  return next v_out;
 end loop;
end;$$;
grant execute on function public.rr_upm_claim_colours_v741(text,text,text,jsonb,text) to authenticated;

create or replace function public.rr_upm_submit_colours_v741(
 p_canonical_lot_id text,p_department_code text,p_rows jsonb,p_remarks text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_lot text;v_row jsonb;v_assign public.rr_upm_work_assignments_v8%rowtype;v_base jsonb;v_size jsonb;v_qty numeric;v_count int:=0;v_total numeric:=0;
begin
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0 then raise exception 'Select at least one assigned Colour.';end if;
 select lot_no into v_lot from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id limit 1;
 for v_row in select value from jsonb_array_elements(p_rows) loop
  select * into v_assign from public.rr_upm_work_assignments_v8 a where a.canonical_lot_id=p_canonical_lot_id and upper(a.department_code)=upper(p_department_code) and a.status in('ASSIGNED','IN_PROGRESS') and ((nullif(v_row->>'colour_id','') is not null and a.colour_id=(v_row->>'colour_id')::uuid) or upper(a.colour_code)=upper(v_row->>'colour_code')) order by a.assigned_at desc limit 1 for update;
  if v_assign.id is null then raise exception 'Active assignment missing for Colour %.',v_row->>'colour_code';end if;
  v_base:=public.rr_upm_universal_form_v740(p_canonical_lot_id,p_department_code);
  for v_size in select value from jsonb_array_elements(coalesce(v_base->'rows','[]'::jsonb)) where upper(value->>'colour_code')=upper(v_assign.colour_code) loop
    v_qty:=greatest(coalesce((v_size->>'good_qty')::numeric,0),0);
    insert into public.rr_upm_dynamic_submit_history_v741(canonical_lot_id,lot_no,department_code,colour_id,colour_code,colour_name,size_code,good_qty,assignment_id,worker_id,worker_name,remarks)
    values(p_canonical_lot_id,v_lot,upper(p_department_code),v_assign.colour_id,v_assign.colour_code,v_assign.colour_name,upper(v_size->>'size_code'),v_qty,v_assign.id,v_assign.worker_id,v_assign.worker_name_snapshot,p_remarks);
    v_total:=v_total+v_qty;
  end loop;
  update public.rr_upm_work_assignments_v8 set status='COMPLETED',completed_at=now(),updated_at=now() where id=v_assign.id;
  v_count:=v_count+1;
 end loop;
 perform public.rr_upm_sync_colour_queue_v741(p_canonical_lot_id);
 return jsonb_build_object('ok',true,'colours_submitted',v_count,'qty_submitted',v_total,'queue_status','OPEN_FOR_RANDOM_ASSIGNMENT');
end;$$;
grant execute on function public.rr_upm_submit_colours_v741(text,text,jsonb,text) to authenticated;

create or replace function public.rr_upm_universal_form_v741(p_canonical_lot_id text,p_department_code text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare base jsonb;outrows jsonb:='[]'::jsonb;r jsonb;a record;q record;eligible boolean;completed_here boolean;statuses jsonb;
begin
 perform public.rr_upm_sync_colour_queue_v741(p_canonical_lot_id);
 base:=public.rr_upm_universal_form_v740(p_canonical_lot_id,p_department_code);
 select exists(select 1 from public.rr_upm_departments d where upper(d.department_code)=upper(p_department_code) and d.is_active and coalesce(d.colour_assignment_enabled,true) and coalesce(d.worker_assignment_enabled,true) and upper(coalesce(d.department_type,'PRODUCTION'))='PRODUCTION' and not coalesce(d.is_start_department,false)
    and not exists(select 1 from public.rr_upm_departments ch where ch.is_active and upper(coalesce(ch.parent_department_code,''))=upper(d.department_code))) into eligible;
 for r in select value from jsonb_array_elements(coalesce(base->'rows','[]'::jsonb)) loop
  select * into q from public.rr_upm_colour_queue_v741 where canonical_lot_id=p_canonical_lot_id and upper(colour_code)=upper(r->>'colour_code');
  select * into a from public.rr_upm_work_assignments_v8 x where x.canonical_lot_id=p_canonical_lot_id and upper(x.colour_code)=upper(r->>'colour_code') and x.status in('ASSIGNED','IN_PROGRESS') order by x.assigned_at desc limit 1;
  select exists(select 1 from public.rr_upm_work_assignments_v8 x where x.canonical_lot_id=p_canonical_lot_id and upper(x.department_code)=upper(p_department_code) and upper(x.colour_code)=upper(r->>'colour_code') and x.status='COMPLETED') into completed_here;
  if q.queue_state='OPEN' or (a.id is not null and upper(a.department_code)=upper(p_department_code)) then
    r:=r||jsonb_build_object(
      'is_locked',(a.id is not null and upper(a.department_code)=upper(p_department_code)),
      'can_assign',(q.queue_state='OPEN' and eligible and not completed_here),
      'assignment_id',case when a.id is not null and upper(a.department_code)=upper(p_department_code) then a.id else null end,
      'worker_id',case when a.id is not null and upper(a.department_code)=upper(p_department_code) then a.worker_id else null end,
      'worker_name',case when a.id is not null and upper(a.department_code)=upper(p_department_code) then a.worker_name_snapshot else null end,
      'worker_code',case when a.id is not null and upper(a.department_code)=upper(p_department_code) then a.worker_code else null end,
      'assigned_qty',case when a.id is not null and upper(a.department_code)=upper(p_department_code) then (r->>'main_qty')::numeric else 0 end,
      'assignment_status',case when a.id is not null and upper(a.department_code)=upper(p_department_code) then a.status else null end,
      'status',case when a.id is not null and upper(a.department_code)=upper(p_department_code) then 'ASSIGNED / IN PROGRESS' when completed_here then 'COMPLETED HERE' else 'OPEN FOR ASSIGNMENT' end,
      'queue_state',q.queue_state,
      'owner_department_code',q.owner_department_code
    );
    outrows:=outrows||jsonb_build_array(r);
  end if;
 end loop;
 select coalesce(jsonb_agg(to_jsonb(s) order by s.department_name),'[]'::jsonb) into statuses from public.rr_upm_department_status_v741(p_canonical_lot_id)s;
 base:=jsonb_set(base,'{rows}',outrows,true);
 base:=base||jsonb_build_object('department_statuses',statuses,'dynamic_queue','FIRST_ASSIGNMENT_WINS','route_locked_to',null,'next_department_code',null,'versions',coalesce(base->'versions','{}'::jsonb)||jsonb_build_object('dynamic_queue','V741_RANDOM_ASSIGN'));
 return base;
end;$$;
grant execute on function public.rr_upm_universal_form_v741(text,text) to authenticated;

commit;
