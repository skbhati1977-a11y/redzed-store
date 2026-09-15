-- TEST70 V162: reconcile legacy UPM worker UUIDs with the active canonical
-- directory row only when the worker name has exactly one active match.

with unique_active_worker as (
  select lower(trim(worker_name)) worker_key,
         min(worker_id::text)::uuid worker_id,
         min(worker_code) worker_code
  from public.rr_worker_directory_unified_v1
  where coalesce(is_active,false)
    and nullif(trim(worker_name),'') is not null
  group by lower(trim(worker_name))
  having count(*)=1
)
update public.rr_upm_work_assignments_v8 a
set worker_id=u.worker_id,
    worker_code=coalesce(u.worker_code,a.worker_code),
    updated_at=now()
from unique_active_worker u
where lower(trim(a.worker_name_snapshot))=u.worker_key
  and not exists (
    select 1
    from public.rr_worker_directory_unified_v1 d
    where d.worker_id=a.worker_id
      and coalesce(d.is_active,false)
  );

with unique_active_worker as (
  select lower(trim(worker_name)) worker_key,
         min(worker_id::text)::uuid worker_id
  from public.rr_worker_directory_unified_v1
  where coalesce(is_active,false)
    and nullif(trim(worker_name),'') is not null
  group by lower(trim(worker_name))
  having count(*)=1
)
update public.rr_upm_dynamic_submit_history_v741 h
set worker_id=u.worker_id
from unique_active_worker u
where lower(trim(h.worker_name))=u.worker_key
  and not exists (
    select 1
    from public.rr_worker_directory_unified_v1 d
    where d.worker_id=h.worker_id
      and coalesce(d.is_active,false)
  );

select pg_notify('pgrst','reload schema');
