-- TEST70 V182: reconcile the login-linked role source used by the unified directory.
begin;

insert into public.rr_roles(
  code,name,department_code,can_view_cost,can_edit_cost,
  can_view_sales,can_edit_sales,can_manage_users,is_active
)
values
  ('worker','Worker',null,false,false,false,false,false,true),
  ('manager','Manager',null,false,false,false,false,false,true)
on conflict(code) do update set name=excluded.name,is_active=true;

update public.rr_user_profiles
set role_code = 'manager', updated_at = now()
where lower(trim(full_name)) = 'nasim'
  and upper(coalesce(department_code, '')) = 'FABRICATION'
  and is_active;

update public.rr_user_profiles
set role_code = 'worker', updated_at = now()
where upper(coalesce(role_code, '')) = 'LINE_MANAGER'
  and upper(coalesce(department_code, '')) <> 'FABRICATION'
  and is_active;

-- Keep the directory copy aligned with the login-linked authoritative record.
update public.rr_worker_directory_v1 w
set role_code = p.role_code,
    department_code = p.department_code,
    updated_at = now()
from public.rr_user_profiles p
where w.id = p.auth_user_id
  and p.is_active;

-- Ordinary workers have worker-side access to their home department only.
update public.rr_real_chat_department_membership_v70 m
set is_active = false,
    source_rule = 'ROLE_SCOPE_RECONCILE_V182',
    updated_at = now()
from public.rr_worker_directory_unified_v1 w
where m.worker_id = w.worker_id
  and upper(coalesce(w.role_code, '')) = 'WORKER'
  and m.membership_side = 'STAFF'
  and m.manual_lock = false;

update public.rr_real_chat_department_membership_v70 m
set is_active = (replace(upper(m.department_code),'KAAJ_','KAJ_') = replace(upper(w.department_code),'KAAJ_','KAJ_')),
    membership_scope = 'DEPARTMENT',
    source_rule = 'HOME_DEPARTMENT_WORKER_V182',
    updated_at = now()
from public.rr_worker_directory_unified_v1 w
where m.worker_id = w.worker_id
  and upper(coalesce(w.role_code, '')) = 'WORKER'
  and m.membership_side = 'WORKER'
  and m.manual_lock = false;

update public.rr_worker_department_map_v1 dm
set is_active = (replace(upper(dm.department_code),'KAAJ_','KAJ_') = replace(upper(w.department_code),'KAAJ_','KAJ_')),
    is_primary = (replace(upper(dm.department_code),'KAAJ_','KAJ_') = replace(upper(w.department_code),'KAAJ_','KAJ_')),
    updated_at = now()
from public.rr_worker_directory_unified_v1 w
where dm.worker_id = w.worker_id
  and upper(coalesce(w.role_code, '')) = 'WORKER'
  and w.is_active;

commit;
