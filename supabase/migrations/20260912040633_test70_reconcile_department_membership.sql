-- Rebuild the TEST70 matrix from current active directory truth.
-- MAIN workflows remain untouched.
begin;

update public.rr_real_chat_department_membership_v70
set is_active=false,updated_at=now(),updated_by=auth.uid()
where is_active;

insert into public.rr_real_chat_department_membership_v70
  (department_code,worker_id,membership_side,source_rule,is_active,updated_at,updated_by)
select public.rr_upm_core_department_v9077(d.department_code),d.worker_id,'WORKER','HOME_DEPARTMENT',true,now(),auth.uid()
from public.rr_worker_directory_unified_v1 d
where coalesce(d.is_active,false)
  and upper(coalesce(d.access_status,'ACTIVE'))='ACTIVE'
on conflict(department_code,worker_id,membership_side) do update
set is_active=true,source_rule=excluded.source_rule,updated_at=now(),updated_by=excluded.updated_by;

with departments(code) as (values
 ('CUTTING'),('PRINTING'),('STICKER'),('METAL_ID'),('STITCHING'),('OVERLOCK'),('FOLDING'),
 ('KAAJ_BUTTON'),('TEAK_TANKI'),('THREAD_CUT'),('QC'),('PRESS'),('PACKING'),('DISPATCH'),
 ('FABRICATION'),('SALES'),('ACCOUNTS'),('ADMIN')
), current_staff as (
 select d.worker_id,public.rr_upm_core_department_v9077(d.department_code) home_department,
   lower(trim(d.worker_name)) worker_name
 from public.rr_worker_directory_unified_v1 d
 where coalesce(d.is_active,false)
   and upper(coalesce(d.access_status,'ACTIVE'))='ACTIVE'
   and (upper(coalesce(d.role_code,'')) in
     ('OWNER','SUPER_ADMIN','ADMIN','MANAGER','ACCOUNT','ACCOUNTS','ACCOUNTANT','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD')
     or lower(trim(d.worker_name)) in ('badsha','sanju','kartik'))
)
insert into public.rr_real_chat_department_membership_v70
  (department_code,worker_id,membership_side,source_rule,is_active,updated_at,updated_by)
select x.code,s.worker_id,'STAFF',
 case when s.worker_name in ('badsha','sanju','kartik') then 'NAMED_CROSS_DEPARTMENT_STAFF' else 'UNIVERSAL_REDZED_STAFF' end,
 true,now(),auth.uid()
from departments x cross join current_staff s
where not (s.worker_name in ('badsha','sanju','kartik') and x.code=s.home_department)
on conflict(department_code,worker_id,membership_side) do update
set is_active=true,source_rule=excluded.source_rule,updated_at=now(),updated_by=excluded.updated_by;

create or replace function public.rr_real_chat_directory_v71()
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare v_uid uuid:=auth.uid(); v_profile public.rr_user_profiles%rowtype; v_role text; v_worker uuid; v_global boolean; v_dept text; v_departments jsonb; v_people jsonb;
begin
 if v_uid is null then raise exception 'Login required.'; end if;
 perform public.rr_assert_active_user_v1();
 select * into v_profile from public.rr_user_profiles p where p.auth_user_id=v_uid and coalesce(p.is_active,false) and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE' order by p.updated_at desc nulls last limit 1;
 if not found then raise exception 'Active User Directory profile required.'; end if;
 v_role:=upper(coalesce(v_profile.role_code,'WORKER')); v_worker:=public.rr_upm_current_worker_id_v9112();
 v_global:=v_role in ('SUPER_ADMIN','OWNER','ADMIN'); v_dept:=public.rr_upm_core_department_v9077(v_profile.department_code);

 with canonical(code,name,sort_order) as (values
  ('CUTTING','Cutting',10),('PRINTING','Print',20),('STICKER','Sticker',30),('METAL_ID','Metal ID',40),
  ('STITCHING','Karigar / Stitching',50),('OVERLOCK','Overlock',60),('FOLDING','Folding',70),
  ('KAAJ_BUTTON','Kaaj / Button',80),('TEAK_TANKI','Teak / Tanki',90),('THREAD_CUT','Thread Cut',100),
  ('QC','QC',110),('PRESS','Press',120),('PACKING','Packing',130),('DISPATCH','Dispatch',140),
  ('FABRICATION','Fabrication / Line Man',150),('SALES','Sales',160),('ACCOUNTS','Accounts',170),('ADMIN','Admin',180)
 ), counts as (
  select public.rr_upm_core_department_v9077(a.department_code) code,
   count(*) filter(where a.status in('ASSIGNED','IN_PROGRESS')) working_count,
   count(*) filter(where a.status='RELEASED') open_count,
   count(*) filter(where a.status in('COMPLETED','CANCELLED')) close_count,max(coalesce(a.updated_at,a.assigned_at)) last_at
  from public.rr_upm_work_assignments_v8 a group by 1
 ), member_rows as (
  select m.department_code,m.membership_side,d.worker_id,d.worker_code,d.worker_name,d.role_code,d.linked_auth_user_id,
   public.rr_upm_core_department_v9077(d.department_code) home_department_code,m.source_rule
  from public.rr_real_chat_department_membership_v70 m join public.rr_worker_directory_unified_v1 d on d.worker_id=m.worker_id
  where m.is_active and coalesce(d.is_active,false) and upper(coalesce(d.access_status,'ACTIVE'))='ACTIVE'
 )
 select coalesce(jsonb_agg(jsonb_build_object(
  'department_code',c.code,'department_name',c.name,'sort_order',c.sort_order,
  'open_count',coalesce(k.open_count,0),'working_count',coalesce(k.working_count,0),'close_count',coalesce(k.close_count,0),'last_at',k.last_at,
  'worker_count',(select count(*) from member_rows z where z.department_code=c.code and z.membership_side='WORKER'),
  'staff_count',(select count(*) from member_rows z where z.department_code=c.code and z.membership_side='STAFF'),
  'workers',coalesce((select jsonb_agg(jsonb_build_object('worker_id',z.worker_id,'worker_code',z.worker_code,'worker_name',z.worker_name,'role_code',z.role_code,'home_department_code',z.home_department_code,'linked_login',z.linked_auth_user_id is not null,'membership_side','WORKER') order by z.worker_name) from member_rows z where z.department_code=c.code and z.membership_side='WORKER'),'[]'::jsonb),
  'staff',coalesce((select jsonb_agg(jsonb_build_object('worker_id',z.worker_id,'worker_code',z.worker_code,'worker_name',z.worker_name,'role_code',z.role_code,'home_department_code',z.home_department_code,'linked_login',z.linked_auth_user_id is not null,'membership_side','STAFF','source_rule',z.source_rule) order by z.worker_name) from member_rows z where z.department_code=c.code and z.membership_side='STAFF'),'[]'::jsonb)
 ) order by c.sort_order),'[]'::jsonb) into v_departments from canonical c left join counts k using(code)
 where v_global or c.code=v_dept or exists(select 1 from member_rows z where z.department_code=c.code and z.worker_id=v_worker);

 with activity as (
  select worker_id,count(*) filter(where status in('ASSIGNED','IN_PROGRESS')) working_count,count(*) filter(where status='RELEASED') open_count,count(*) filter(where status in('COMPLETED','CANCELLED')) close_count,max(coalesce(updated_at,assigned_at)) last_at
  from public.rr_upm_work_assignments_v8 group by worker_id
 )
 select coalesce(jsonb_agg(jsonb_build_object('worker_id',d.worker_id,'worker_code',d.worker_code,'worker_name',d.worker_name,
  'department_code',public.rr_upm_core_department_v9077(d.department_code),'role_code',d.role_code,'linked_login',d.linked_auth_user_id is not null,
  'open_count',coalesce(a.open_count,0),'working_count',coalesce(a.working_count,0),'close_count',coalesce(a.close_count,0),'last_at',a.last_at,'unread_count',0
 ) order by a.last_at desc nulls last,d.worker_name),'[]'::jsonb) into v_people
 from public.rr_worker_directory_unified_v1 d left join activity a using(worker_id)
 where coalesce(d.is_active,false) and upper(coalesce(d.access_status,'ACTIVE'))='ACTIVE'
 and (v_global or d.worker_id=v_worker or public.rr_upm_core_department_v9077(d.department_code)=v_dept);

 return jsonb_build_object('version','TEST70_REAL_CHAT_DIRECTORY_V71_RECONCILED','actor',jsonb_build_object('name',v_profile.full_name,'role',v_role,'worker_id',v_worker,'is_global',v_global),
  'departments',v_departments,'people',v_people,'mapped_worker_count',jsonb_array_length(v_people),'read_only_directory',true);
end $function$;
revoke all on function public.rr_real_chat_directory_v71() from public,anon;
grant execute on function public.rr_real_chat_directory_v71() to authenticated;

commit;
