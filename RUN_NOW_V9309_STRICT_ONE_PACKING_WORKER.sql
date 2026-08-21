-- V9309: Strictly allow only one active Packing worker per lot.
-- If one colour of a lot is assigned to a Packing worker, all remaining
-- active Packing colours for that lot must use the same worker.

with owner_rows as (
  select distinct on (canonical_lot_id)
    canonical_lot_id,
    worker_id,
    worker_code,
    worker_name_snapshot
  from public.rr_upm_work_assignments_v8
  where public.rr_upm_core_department_v9077(department_code)='PACKING'
    and status in ('ASSIGNED','IN_PROGRESS')
  order by canonical_lot_id, assigned_at asc nulls last, created_at asc nulls last, id asc
), mixed_lots as (
  select canonical_lot_id
  from public.rr_upm_work_assignments_v8
  where public.rr_upm_core_department_v9077(department_code)='PACKING'
    and status in ('ASSIGNED','IN_PROGRESS')
  group by canonical_lot_id
  having count(distinct worker_id)>1
)
update public.rr_upm_work_assignments_v8 a
   set worker_id=o.worker_id,
       worker_code=o.worker_code,
       worker_name_snapshot=o.worker_name_snapshot,
       remarks=concat_ws(' · ', nullif(a.remarks,''), 'V9309 PACKING one-worker lot alignment'),
       updated_at=now()
  from owner_rows o
  join mixed_lots m on m.canonical_lot_id=o.canonical_lot_id
 where a.canonical_lot_id=o.canonical_lot_id
   and public.rr_upm_core_department_v9077(a.department_code)='PACKING'
   and a.status in ('ASSIGNED','IN_PROGRESS')
   and a.worker_id is distinct from o.worker_id;

create or replace function public.rr_upm_guard_one_packing_worker_per_lot_v9309()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_existing record;
begin
  if public.rr_upm_core_department_v9077(new.department_code)='PACKING'
     and new.status in ('ASSIGNED','IN_PROGRESS') then
    select worker_id,worker_name_snapshot,worker_code
      into v_existing
      from public.rr_upm_work_assignments_v8 a
     where a.canonical_lot_id=new.canonical_lot_id
       and public.rr_upm_core_department_v9077(a.department_code)='PACKING'
       and a.status in ('ASSIGNED','IN_PROGRESS')
       and a.id<>new.id
     order by a.assigned_at asc nulls last, a.created_at asc nulls last, a.id asc
     limit 1;
    if v_existing.worker_id is not null and v_existing.worker_id<>new.worker_id then
      raise exception 'Lot already assigned to % in PACKING. Same lot ke sabhi colours ek hi packing worker ko assign honge.', coalesce(v_existing.worker_name_snapshot,v_existing.worker_code,'selected worker');
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists rr_upm_one_packing_worker_per_lot_v9309 on public.rr_upm_work_assignments_v8;
create trigger rr_upm_one_packing_worker_per_lot_v9309
before insert or update of worker_id,status,department_code,canonical_lot_id
on public.rr_upm_work_assignments_v8
for each row
execute function public.rr_upm_guard_one_packing_worker_per_lot_v9309();
