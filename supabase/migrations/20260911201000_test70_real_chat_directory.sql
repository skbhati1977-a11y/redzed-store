-- TEST70 canonical directory. Read-only: no workflow/chat/business rows are created.
create or replace function public.rr_real_chat_directory_v70()
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare
  v_uid uuid:=auth.uid(); v_profile public.rr_user_profiles%rowtype;
  v_role text; v_worker uuid; v_global boolean; v_dept text;
  v_departments jsonb; v_people jsonb; v_staff jsonb;
begin
  if v_uid is null then raise exception 'Login required.'; end if;
  perform public.rr_assert_active_user_v1();
  select * into v_profile from public.rr_user_profiles p
   where p.auth_user_id=v_uid and coalesce(p.is_active,false)
     and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE'
   order by p.updated_at desc nulls last limit 1;
  if not found then raise exception 'Active User Directory profile required.'; end if;
  v_role:=upper(coalesce(v_profile.role_code,'WORKER'));
  v_worker:=public.rr_upm_current_worker_id_v9112();
  v_global:=v_role in ('SUPER_ADMIN','OWNER','ADMIN');
  v_dept:=public.rr_upm_core_department_v9077(v_profile.department_code);

  with canonical(code,name,sort_order) as (values
    ('CUTTING','Cutting',10),('PRINTING','Print',20),('STICKER','Sticker',30),
    ('METAL_ID','Metal ID',40),('STITCHING','Karigar / Stitching',50),
    ('OVERLOCK','Overlock',60),('FOLDING','Folding',70),
    ('KAJ_BUTTON','Kaaj / Button',80),('TEAK_TANKI','Teak / Tanki',90),
    ('THREAD_CUT','Thread Cut',100),('QC','QC',110),('PRESS','Press',120),
    ('PACKING','Packing',130),('DISPATCH','Dispatch',140)
  ), counts as (
    select public.rr_upm_core_department_v9077(a.department_code) code,
      count(*) filter(where a.status in('ASSIGNED','IN_PROGRESS')) working_count,
      count(*) filter(where a.status='RELEASED') open_count,
      count(*) filter(where a.status in('COMPLETED','CANCELLED')) close_count,
      max(coalesce(a.updated_at,a.assigned_at)) last_at
    from public.rr_upm_work_assignments_v8 a group by 1
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'department_code',c.code,'department_name',c.name,'sort_order',c.sort_order,
    'open_count',coalesce(k.open_count,0),'working_count',coalesce(k.working_count,0),
    'close_count',coalesce(k.close_count,0),'last_at',k.last_at,'unread_count',0
  ) order by c.sort_order),'[]') into v_departments
  from canonical c left join counts k using(code)
  where v_global or c.code=v_dept;

  with base as (
    select d.worker_id,d.worker_code,d.worker_name,
      public.rr_upm_core_department_v9077(coalesce(m.department_code,d.department_code)) department_code,
      d.role_code,d.linked_auth_user_id,
      coalesce(pp.worker_category,'NOT_CONFIGURED') payroll_category,
      coalesce(pp.attendance_required,false) attendance_required,
      (upper(coalesce(d.role_code,'')) in ('SUPER_ADMIN','OWNER','ADMIN','MANAGER','ACCOUNT','ACCOUNTS')
       or (upper(coalesce(d.role_code,''))='LINE_MANAGER' and upper(coalesce(d.department_code,''))='FABRICATION')
       or lower(d.worker_name) in ('badsha','sanju','kartik')) is_global_staff
    from public.rr_worker_directory_unified_v1 d
    left join lateral (
      select dm.department_code from public.rr_worker_department_map_v1 dm
      where dm.worker_id=d.worker_id and coalesce(dm.is_active,false)
      order by coalesce(dm.is_primary,false) desc,dm.updated_at desc nulls last limit 1
    ) m on true
    left join lateral (
      select p.worker_category,p.attendance_required from public.rr_worker_payroll_profile_v777_2 p
      where p.worker_id=d.worker_id and p.status='ACTIVE'
      order by p.effective_from desc nulls last,p.configured_at desc nulls last limit 1
    ) pp on true
    where coalesce(d.is_active,false) and upper(coalesce(d.access_status,'ACTIVE'))='ACTIVE'
  ), activity as (
    select worker_id,count(*) filter(where status in('ASSIGNED','IN_PROGRESS')) working_count,
      count(*) filter(where status='RELEASED') open_count,
      count(*) filter(where status in('COMPLETED','CANCELLED')) close_count,
      max(coalesce(updated_at,assigned_at)) last_at
    from public.rr_upm_work_assignments_v8 group by worker_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'worker_id',b.worker_id,'worker_code',b.worker_code,'worker_name',b.worker_name,
    'department_code',b.department_code,'role_code',b.role_code,
    'linked_login',b.linked_auth_user_id is not null,'payroll_category',b.payroll_category,
    'attendance_eligible',b.payroll_category='SALARIED' and b.attendance_required,
    'is_global_staff',b.is_global_staff,'open_count',coalesce(a.open_count,0),
    'working_count',coalesce(a.working_count,0),'close_count',coalesce(a.close_count,0),
    'last_at',a.last_at,'unread_count',0
  ) order by a.last_at desc nulls last,b.worker_name),'[]') into v_people
  from base b left join activity a using(worker_id)
  where (not b.is_global_staff or lower(b.worker_name) in ('badsha','sanju','kartik'))
    and (v_global or b.worker_id=v_worker or b.department_code=v_dept);

  select coalesce(jsonb_agg(jsonb_build_object(
    'worker_id',d.worker_id,'worker_name',d.worker_name,'role_code',d.role_code,
    'home_department_code',public.rr_upm_core_department_v9077(d.department_code),
    'fixed',true,'active',d.is_active
  ) order by d.worker_name),'[]') into v_staff
  from public.rr_worker_directory_unified_v1 d
  where coalesce(d.is_active,false) and (
    upper(coalesce(d.role_code,'')) in ('SUPER_ADMIN','OWNER','ADMIN','MANAGER','ACCOUNT','ACCOUNTS')
    or (upper(coalesce(d.role_code,''))='LINE_MANAGER' and upper(coalesce(d.department_code,''))='FABRICATION')
    or lower(d.worker_name) in ('badsha','sanju','kartik')
  );

  return jsonb_build_object('version','TEST70_REAL_CHAT_DIRECTORY_V70',
    'actor',jsonb_build_object('name',v_profile.full_name,'role',v_role,'worker_id',v_worker,'is_global',v_global),
    'departments',v_departments,'people',v_people,'global_staff',v_staff,
    'read_only_directory',true);
end $function$;
revoke all on function public.rr_real_chat_directory_v70() from public,anon;
grant execute on function public.rr_real_chat_directory_v70() to authenticated;
