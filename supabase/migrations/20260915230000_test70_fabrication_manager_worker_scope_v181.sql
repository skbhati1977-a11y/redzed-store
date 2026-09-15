-- TEST70 V181: canonical Fabrication leadership and department-only worker scope.
begin;

-- Nasim is the Fabrication Manager. Fabrication line men retain LINE_MANAGER.
update public.rr_worker_directory_v1
set role_code = 'manager', updated_at = now()
where lower(trim(worker_name)) = 'nasim'
  and upper(coalesce(department_code, '')) = 'FABRICATION'
  and is_active;

-- Karigars/operators outside Fabrication are department workers, not line managers.
with corrected as (
  update public.rr_worker_directory_v1
  set role_code = 'worker', updated_at = now()
  where upper(coalesce(role_code, '')) = 'LINE_MANAGER'
    and upper(coalesce(department_code, '')) <> 'FABRICATION'
    and is_active
  returning id
)
update public.rr_real_chat_department_membership_v70 m
set is_active = false,
    source_rule = 'ROLE_SCOPE_RECONCILE_V181',
    updated_at = now()
where m.worker_id in (select id from corrected)
  and m.membership_side = 'STAFF'
  and m.manual_lock = false;

-- A corrected worker remains active only on the worker side of the home department.
update public.rr_real_chat_department_membership_v70 m
set is_active = true,
    membership_scope = 'DEPARTMENT',
    source_rule = 'HOME_DEPARTMENT_WORKER_V181',
    updated_at = now()
from public.rr_worker_directory_v1 w
where m.worker_id = w.id
  and upper(coalesce(w.role_code, '')) = 'WORKER'
  and upper(m.department_code) = upper(w.department_code)
  and m.membership_side = 'WORKER'
  and m.manual_lock = false;

-- Remove stale auxiliary department mappings for ordinary department workers.
update public.rr_worker_department_map_v1 dm
set is_active = (upper(dm.department_code) = upper(w.department_code)),
    is_primary = (upper(dm.department_code) = upper(w.department_code)),
    updated_at = now()
from public.rr_worker_directory_v1 w
where dm.worker_id = w.id
  and upper(coalesce(w.role_code, '')) = 'WORKER'
  and w.is_active;

commit;
