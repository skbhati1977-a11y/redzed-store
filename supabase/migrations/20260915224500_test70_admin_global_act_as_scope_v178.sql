-- TEST70 V178: ADMIN is a global role, never a single department.
begin;

-- Restore universal Admin staff membership unless an explicit manual lock exists.
update public.rr_real_chat_department_membership_v70 m
set is_active=true,updated_at=now(),source_rule='ADMIN_GLOBAL_ROLE'
from public.rr_worker_directory_unified_v1 w
where w.worker_id=m.worker_id
  and upper(coalesce(w.role_code,''))='ADMIN'
  and w.is_active
  and m.manual_lock=false
  and m.membership_side='STAFF';

create or replace function public.rr_test_set_on_behalf_context_v176(p_worker_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_operator_role text;v_target record;v_departments text[];
begin
 select upper(role_code) into v_operator_role from public.rr_user_profiles
 where auth_user_id=auth.uid() and is_active order by updated_at desc nulls last limit 1;
 if v_operator_role not in('OWNER','SUPER_ADMIN')then raise exception 'Super Admin test delegation required';end if;
 select worker_id,worker_name,upper(coalesce(role_code,'WORKER')) role_code,upper(coalesce(department_code,'')) department_code
 into v_target from public.rr_worker_directory_unified_v1 where worker_id=p_worker_id and is_active limit 1;
 if not found then raise exception 'Selected mapped person is inactive or unavailable';end if;
 if v_target.role_code='ADMIN' then
  select array_agg(d.department_code order by d.display_order) into v_departments
  from public.rr_departments_v1 d
  where d.is_active
    and not exists(
      select 1 from public.rr_real_chat_department_membership_v70 m
      where m.worker_id=p_worker_id and upper(m.department_code)=upper(d.department_code)
        and m.manual_lock=true and m.is_active=false
    );
 else
  select array_agg(distinct d) into v_departments from(
   select v_target.department_code d where v_target.department_code<>''
   union select upper(department_code) from public.rr_worker_department_map_v1 where worker_id=p_worker_id and is_active
  )s;
 end if;
 insert into public.rr_test_on_behalf_context_v176(operator_user_id,target_worker_id,target_name,target_role,department_codes,is_active,selected_at,expires_at)
 values(auth.uid(),p_worker_id,v_target.worker_name,v_target.role_code,coalesce(v_departments,'{}'),true,now(),now()+interval '8 hours')
 on conflict(operator_user_id)do update set target_worker_id=excluded.target_worker_id,target_name=excluded.target_name,
  target_role=excluded.target_role,department_codes=excluded.department_codes,is_active=true,selected_at=now(),expires_at=now()+interval '8 hours';
 return jsonb_build_object('ok',true,'worker_id',p_worker_id,'name',v_target.worker_name,'role_code',v_target.role_code,'department_codes',coalesce(v_departments,'{}'));
end $$;

revoke all on function public.rr_test_set_on_behalf_context_v176(uuid) from public,anon;
grant execute on function public.rr_test_set_on_behalf_context_v176(uuid) to authenticated;

commit;
