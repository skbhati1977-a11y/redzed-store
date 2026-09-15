-- TEST70 V183: Fabrication Manager and line men remain Fabrication-scoped.
begin;

update public.rr_real_chat_department_membership_v70 m
set is_active = (
      upper(m.department_code) = 'FABRICATION'
      and m.membership_side in ('WORKER','STAFF')
    ),
    membership_scope = 'DEPARTMENT',
    source_rule = 'FABRICATION_LEADERSHIP_SCOPE_V183',
    updated_at = now()
from public.rr_worker_directory_unified_v1 w
where m.worker_id = w.worker_id
  and upper(w.department_code) = 'FABRICATION'
  and upper(w.role_code) in ('MANAGER','LINE_MANAGER')
  and m.manual_lock = false;

update public.rr_worker_department_map_v1 dm
set is_active = (upper(dm.department_code) = 'FABRICATION'),
    is_primary = (upper(dm.department_code) = 'FABRICATION'),
    updated_at = now()
from public.rr_worker_directory_unified_v1 w
where dm.worker_id = w.worker_id
  and upper(w.department_code) = 'FABRICATION'
  and upper(w.role_code) in ('MANAGER','LINE_MANAGER');

commit;
