-- TEST70 V83 identity-first Real Chat repair.
-- Existing operational forms/RPCs remain the source of truth.
begin;

create table if not exists public.rr_real_chat_department_alias_v83 (
  alias_code text primary key,
  canonical_code text not null,
  display_name text not null,
  is_active boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.rr_real_chat_department_alias_v83 enable row level security;
revoke all on public.rr_real_chat_department_alias_v83 from public,anon,authenticated;

insert into public.rr_real_chat_department_alias_v83(alias_code,canonical_code,display_name) values
 ('DESPATCH','DESPATCH','Despatch'),('DISPATCH','DESPATCH','Despatch'),
 ('KAAJ_BUTTON','KAAJ_BUTTON','Kaaj / Button'),('KAJ_BUTTON','KAAJ_BUTTON','Kaaj / Button'),
 ('KAAJ','KAAJ_BUTTON','Kaaj / Button'),('KAJ','KAAJ_BUTTON','Kaaj / Button'),
 ('BUTTON','KAAJ_BUTTON','Kaaj / Button'),('BTN','KAAJ_BUTTON','Kaaj / Button'),
 ('PURCHASE','PURCHASE','Purchase')
on conflict(alias_code) do update set canonical_code=excluded.canonical_code,
 display_name=excluded.display_name,is_active=true,updated_at=now();

create or replace function public.rr_real_chat_canonical_department_v83(p_code text)
returns text language sql immutable security invoker set search_path='' as $$
 select case upper(regexp_replace(trim(coalesce(p_code,'')),'[ -]+','_','g'))
  when 'DISPATCH' then 'DESPATCH'
  when 'DESPATCH' then 'DESPATCH'
  when 'KAJ_BUTTON' then 'KAAJ_BUTTON'
  when 'KAAJ_BUTTON' then 'KAAJ_BUTTON'
  when 'KAJ' then 'KAAJ_BUTTON'
  when 'KAAJ' then 'KAAJ_BUTTON'
  when 'BUTTON' then 'KAAJ_BUTTON'
  when 'BTN' then 'KAAJ_BUTTON'
  else upper(regexp_replace(trim(coalesce(p_code,'')),'[ -]+','_','g')) end
$$;
revoke all on function public.rr_real_chat_canonical_department_v83(text) from public,anon;
grant execute on function public.rr_real_chat_canonical_department_v83(text) to authenticated;

insert into public.rr_departments_v1
 (department_code,department_name,display_order,is_external,is_active,department_type,
  production_enabled,worker_assignment_enabled,rate_enabled,colour_assignment_enabled,
  allow_alter,code_locked)
values ('PURCHASE','Purchase',5,false,true,'CONTROL',false,false,false,false,false,true)
on conflict(department_code) do update set department_name='Purchase',is_active=true,
 department_type='CONTROL',production_enabled=false,worker_assignment_enabled=false,
 rate_enabled=false,colour_assignment_enabled=false,allow_alter=false,code_locked=true,
 updated_at=now();

-- One verified Worker ID is reused; no duplicate Shailender identity is created.
insert into public.rr_real_chat_department_membership_v70
 (department_code,worker_id,membership_side,source_rule,is_active,updated_at)
select 'PURCHASE',d.worker_id,'STAFF','PURCHASE_AUTHORIZED_SHAILENDER',true,now()
from public.rr_worker_directory_unified_v1 d
where lower(trim(d.worker_name))='shailender' and coalesce(d.is_active,false)
order by (d.linked_auth_user_id is not null) desc,d.worker_id limit 1
on conflict(department_code,worker_id,membership_side) do update
 set source_rule=excluded.source_rule,is_active=true,updated_at=now();

-- Owner/Super Admin is visible on Purchase, using the existing linked worker identity.
insert into public.rr_real_chat_department_membership_v70
 (department_code,worker_id,membership_side,source_rule,is_active,updated_at)
select 'PURCHASE',d.worker_id,'STAFF','UNIVERSAL_REDZED_STAFF',true,now()
from public.rr_worker_directory_unified_v1 d
join public.rr_user_profiles p on p.auth_user_id=d.linked_auth_user_id
where coalesce(d.is_active,false) and coalesce(p.is_active,false)
 and upper(coalesce(p.role_code,'')) in ('OWNER','SUPER_ADMIN')
on conflict(department_code,worker_id,membership_side) do update
 set source_rule=excluded.source_rule,is_active=true,updated_at=now();

-- Reconcile aliases without losing an existing canonical membership.
insert into public.rr_real_chat_department_membership_v70
 (department_code,worker_id,membership_side,source_rule,is_active,updated_at,updated_by)
select public.rr_real_chat_canonical_department_v83(m.department_code),m.worker_id,m.membership_side,
 m.source_rule,m.is_active,now(),m.updated_by
from public.rr_real_chat_department_membership_v70 m
where m.department_code<>public.rr_real_chat_canonical_department_v83(m.department_code)
on conflict(department_code,worker_id,membership_side) do update
 set is_active=excluded.is_active,source_rule=excluded.source_rule,updated_at=now();
delete from public.rr_real_chat_department_membership_v70 m
where m.department_code<>public.rr_real_chat_canonical_department_v83(m.department_code);

create or replace function public.rr_real_chat_canonical_state_v83(
 p_source_module text,p_event_type text,p_action_code text,p_payload jsonb default '{}'::jsonb)
returns text language sql immutable security invoker set search_path='' as $$
 with x as (select upper(coalesce(p_source_module,'')) m,upper(coalesce(p_event_type,'')) e,
  upper(coalesce(p_action_code,'')) a,
  upper(coalesce(p_payload->>'message_status',p_payload->>'status','')) s)
 select case
  when s in ('COMPLETED','CANCELLED','CLOSED','APPROVED','REJECTED','VERIFIED','FINALIZED','POSTED','RECEIVED','REVERSED','SELECTED')
    or e in ('ASSIGNMENT_COMPLETED','ASSIGNMENT_CANCELLED','WORK_SUBMITTED','PAYMENT_POSTED','ORDER_CLOSED','COLLECTION_CLOSED')
    or e like '%_COMPLETED' or e like '%_CLOSED' or e like '%_CANCELLED' or e like '%_APPROVED'
    or e like '%_REJECTED' or e like '%_SELECTED' or e like '%_NA'
   then 'CLOSE'
  when e in ('LOT_OPEN','READY_TO_ASSIGN','ART_DECIDE_PENDING','REQUIREMENT_OPEN','COLLECTION_OPEN')
    or s in ('OPEN','RELEASED','READY_TO_ASSIGN') then 'OPEN'
  else 'WORKING' end from x
$$;
revoke all on function public.rr_real_chat_canonical_state_v83(text,text,text,jsonb) from public,anon;
grant execute on function public.rr_real_chat_canonical_state_v83(text,text,text,jsonb) to authenticated;

create or replace function public.rr_real_chat_directory_v83()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_base jsonb; v_profile public.rr_user_profiles%rowtype;
 v_worker uuid; v_role text; v_global boolean; v_members jsonb; v_purchase jsonb;
begin
 if v_uid is null then raise exception 'Login required.'; end if;
 perform public.rr_assert_active_user_v1();
 select * into v_profile from public.rr_user_profiles p where p.auth_user_id=v_uid
  and coalesce(p.is_active,false) order by p.updated_at desc nulls last limit 1;
 if not found then raise exception 'Active User Directory profile required.'; end if;
 v_worker:=public.rr_upm_current_worker_id_v9112();
 v_role:=upper(coalesce(v_profile.role_code,'WORKER'));
 v_global:=v_role in ('OWNER','SUPER_ADMIN','ADMIN');
 v_base:=public.rr_real_chat_directory_v71();
 if v_global or exists(select 1 from public.rr_real_chat_department_membership_v70 m
   where m.department_code='PURCHASE' and m.worker_id=v_worker and m.is_active) then
  select coalesce(jsonb_agg(jsonb_build_object('worker_id',d.worker_id,'worker_code',d.worker_code,
   'worker_name',d.worker_name,'role_code',d.role_code,'home_department_code',d.department_code,
   'linked_login',d.linked_auth_user_id is not null,'membership_side',m.membership_side,
   'source_rule',m.source_rule) order by d.worker_name),'[]'::jsonb)
  into v_members
  from public.rr_real_chat_department_membership_v70 m
  join public.rr_worker_directory_unified_v1 d on d.worker_id=m.worker_id
  where m.department_code='PURCHASE' and m.is_active and coalesce(d.is_active,false);
  v_purchase:=jsonb_build_object('department_code','PURCHASE','department_name','Purchase',
   'sort_order',5,'open_count',0,'working_count',0,'close_count',0,'last_at',null,
   'worker_count',0,'staff_count',jsonb_array_length(v_members),'workers','[]'::jsonb,'staff',v_members);
  v_base:=jsonb_set(v_base,'{departments}',jsonb_build_array(v_purchase)||coalesce(v_base->'departments','[]'::jsonb));
 end if;
 return jsonb_set(v_base,'{version}','"TEST70_REAL_CHAT_DIRECTORY_V83_IDENTITY_FIRST"'::jsonb);
end $$;
revoke all on function public.rr_real_chat_directory_v83() from public,anon;
grant execute on function public.rr_real_chat_directory_v83() to authenticated;

-- Privacy boundary: browser no longer reads the bridge table directly.
create or replace function public.rr_real_chat_conversation_history_v83(p_limit integer default 2000)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_profile public.rr_user_profiles%rowtype; v_worker uuid;
 v_role text; v_global boolean; v_rows jsonb;
begin
 if v_uid is null then raise exception 'Login required.'; end if;
 perform public.rr_assert_active_user_v1();
 select * into v_profile from public.rr_user_profiles p where p.auth_user_id=v_uid
  and coalesce(p.is_active,false) and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE'
  order by p.updated_at desc nulls last limit 1;
 if not found then raise exception 'Active User Directory profile required.'; end if;
 v_worker:=public.rr_upm_current_worker_id_v9112();
 v_role:=upper(coalesce(v_profile.role_code,'WORKER'));
 v_global:=v_role in ('OWNER','SUPER_ADMIN','ADMIN');
 select coalesce(jsonb_agg(to_jsonb(q) order by q.sent_at desc),'[]'::jsonb) into v_rows
 from (
  select b.id,b.canonical_key,b.source_module,b.source_record_id,b.source_event_type,
   public.rr_real_chat_canonical_department_v83(b.department_code) department_code,
   b.sender_worker_id,b.receiver_user_id,b.receiver_worker_id,
   case when public.rr_real_chat_canonical_state_v83(b.source_module,b.source_event_type,b.action_code,b.personal_payload)='CLOSE'
     then null else b.action_code end action_code,
   case when public.rr_real_chat_canonical_state_v83(b.source_module,b.source_event_type,b.action_code,b.personal_payload)='CLOSE'
     then null else b.action_label end action_label,
   public.rr_real_chat_canonical_state_v83(b.source_module,b.source_event_type,b.action_code,b.personal_payload) canonical_state,
   case when v_global or b.receiver_user_id=v_uid or b.receiver_worker_id=v_worker
     then b.personal_payload else '{}'::jsonb end personal_payload,
   b.group_payload,b.deep_link,b.sent_at,
   (select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) from public.rr_real_chat_receipts_v70 r
     where r.message_id=b.id and (v_global or r.receiver_user_id=v_uid)) rr_real_chat_receipts_v70
  from public.rr_real_chat_message_bridge_v70 b
  where b.archived_at is null and (
   v_global or b.receiver_user_id=v_uid or b.receiver_worker_id=v_worker
   or (
    upper(coalesce(b.source_module,'')) not in ('ACCOUNTS','WORKER_PAYROLL','PAYROLL','SALARY','SALARY_WAGES')
    and exists(
     select 1 from public.rr_real_chat_department_membership_v70 m
     where m.worker_id=v_worker and m.is_active
       and public.rr_real_chat_canonical_department_v83(m.department_code)=public.rr_real_chat_canonical_department_v83(b.department_code)
    )
   )
  )
  order by b.sent_at desc limit least(greatest(coalesce(p_limit,2000),1),5000)
 ) q;
 return v_rows;
end $$;
revoke all on function public.rr_real_chat_conversation_history_v83(integer) from public,anon;
grant execute on function public.rr_real_chat_conversation_history_v83(integer) to authenticated;

commit;
