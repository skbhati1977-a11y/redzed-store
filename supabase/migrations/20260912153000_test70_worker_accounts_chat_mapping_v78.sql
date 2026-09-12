-- TEST70 V78: expose the canonical worker-to-salary-ledger binding to Real Chat staff.
begin;

create or replace function public.rr_test70_worker_accounts_map_v78()
returns table(
  worker_id uuid,
  salary_ledger_id uuid,
  worker_name text,
  department_code text,
  payroll_category text,
  linked_login boolean,
  chat_id uuid
)
language plpgsql stable security definer set search_path=public,pg_temp as $function$
declare v_uid uuid:=auth.uid();
begin
  if v_uid is null or not public.rr_real_chat_is_global_staff_v70(v_uid) then
    raise exception 'STAFF_ACCESS_REQUIRED';
  end if;
  return query
  select m.worker_id,m.salary_ledger_id,m.worker_name,m.department_code,m.payroll_category,
    m.linked_auth_user_id is not null,
    c.chat_id
  from public.rr_worker_accounts_map_v9785 m
  left join public.rr_worker_real_chat_map_v9787 c
    on c.worker_id=m.worker_id and c.is_active
  where m.is_active
  order by m.department_code,m.worker_name,m.worker_id;
end $function$;

revoke all on function public.rr_test70_worker_accounts_map_v78() from public,anon;
grant execute on function public.rr_test70_worker_accounts_map_v78() to authenticated,service_role;
comment on function public.rr_test70_worker_accounts_map_v78() is
'TEST70 staff-only canonical Worker ID to Salary & Wages ledger mapping; no name-based resolution.';

commit;
