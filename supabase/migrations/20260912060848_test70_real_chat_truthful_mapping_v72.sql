-- TEST70 V72: truthful recipients, canonical terminal states and real department staff membership.
-- Production workflow rows and MAIN are untouched.
begin;

create or replace function public.rr_real_chat_truthful_bridge_v72()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_sender_name text; v_roles jsonb:='[]'::jsonb;
begin
  if new.source_module='CUTTING' then
    select p.full_name into v_sender_name from public.rr_user_profiles p
    where p.auth_user_id=new.sender_user_id and p.is_active
    order by p.updated_at desc nulls last limit 1;
    if upper(new.source_event_type) like '%PENDING_ADMIN%'
       or upper(new.source_event_type) like '%ADMIN_MESSAGE_SENT%'
       or upper(new.source_event_type) like '%RECHECK_REQUIRED%' then
      v_roles:='["ADMIN"]'::jsonb;
    elsif upper(new.source_event_type) like '%ADMIN_VERIFIED%' then
      v_roles:='["OWNER","SUPER_ADMIN"]'::jsonb;
    end if;
    -- Cutting decisions are role queues, never an arbitrary first-admin personal assignment.
    new.receiver_user_id:=null; new.receiver_worker_id:=null;
    new.personal_payload:=(new.personal_payload-'receiver_name')
      ||jsonb_build_object('sender_name',coalesce(v_sender_name,new.personal_payload->>'sender_name','Cutting Master'),'allowed_roles',v_roles);
    new.group_payload:=(new.group_payload-'receiver_name')
      ||jsonb_build_object('sender_name',coalesce(v_sender_name,new.group_payload->>'sender_name','Cutting Master'),'allowed_roles',v_roles);
  elsif new.source_module='PRODUCT_MASTER' then
    -- Product decisions are department/role group events until a real assignee exists.
    new.receiver_user_id:=null; new.receiver_worker_id:=null;
    new.personal_payload:=(new.personal_payload-'receiver_name')||jsonb_build_object('allowed_roles','["OWNER","ADMIN"]'::jsonb);
    new.group_payload:=(new.group_payload-'receiver_name')||jsonb_build_object('allowed_roles','["OWNER","ADMIN"]'::jsonb);
  end if;
  return new;
end $$;
revoke all on function public.rr_real_chat_truthful_bridge_v72() from public,anon,authenticated;

drop trigger if exists rr_real_chat_truthful_bridge_v72 on public.rr_real_chat_message_bridge_v70;
create trigger rr_real_chat_truthful_bridge_v72
before insert or update on public.rr_real_chat_message_bridge_v70
for each row execute function public.rr_real_chat_truthful_bridge_v72();

-- Reconcile already-projected rows through the same truthful trigger.
update public.rr_real_chat_message_bridge_v70
set source_event_type=source_event_type
where source_module in ('CUTTING','PRODUCT_MASTER');

delete from public.rr_real_chat_receipts_v70 r
using public.rr_real_chat_message_bridge_v70 b
where b.id=r.message_id and b.source_module in ('CUTTING','PRODUCT_MASTER')
  and b.receiver_user_id is null and b.receiver_worker_id is null;

-- Remove generated universal staff fan-out. Preserve workers and rebuild staff from role truth.
update public.rr_real_chat_department_membership_v70
set is_active=false,updated_at=now(),updated_by=auth.uid()
where membership_side='STAFF' and is_active;

with departments(code) as (values
 ('CUTTING'),('PRINTING'),('STICKER'),('METAL_ID'),('STITCHING'),('OVERLOCK'),('FOLDING'),
 ('KAAJ_BUTTON'),('TEAK_TANKI'),('THREAD_CUT'),('QC'),('PRESS'),('PACKING'),('DISPATCH'),
 ('FABRICATION'),('SALES'),('ACCOUNTS'),('ADMIN')
), active_directory as (
 select d.worker_id,lower(trim(d.worker_name)) worker_name,upper(coalesce(d.role_code,'')) role_code,
   public.rr_upm_core_department_v9077(d.department_code) home_department
 from public.rr_worker_directory_unified_v1 d
 where coalesce(d.is_active,false) and upper(coalesce(d.access_status,'ACTIVE'))='ACTIVE'
), truthful_staff as (
 select x.code department_code,d.worker_id,'GLOBAL_OWNER_STAFF' source_rule
 from departments x join active_directory d on d.role_code in ('OWNER','SUPER_ADMIN')
 union
 select d.home_department,d.worker_id,'HOME_DEPARTMENT_STAFF'
 from active_directory d
 where d.role_code in ('ADMIN','MANAGER','ACCOUNT','ACCOUNTS','ACCOUNTANT','LINE_MANAGER','LINE_MAN','DEPARTMENT_HEAD')
   and nullif(d.home_department,'') is not null
 union
 select x.code,d.worker_id,'NAMED_CROSS_DEPARTMENT_STAFF'
 from departments x join active_directory d on d.worker_name in ('badsha','sanju','kartik')
)
insert into public.rr_real_chat_department_membership_v70
 (department_code,worker_id,membership_side,source_rule,is_active,updated_at,updated_by)
select department_code,worker_id,'STAFF',source_rule,true,now(),auth.uid() from truthful_staff
on conflict(department_code,worker_id,membership_side) do update
set is_active=true,source_rule=excluded.source_rule,updated_at=now(),updated_by=excluded.updated_by;

commit;
