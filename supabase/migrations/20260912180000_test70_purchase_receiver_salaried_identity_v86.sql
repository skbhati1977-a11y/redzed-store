-- TEST70 V86: Purchase primary receiver plus truthful salaried identity label.
begin;

create table if not exists public.rr_real_chat_department_receiver_v86(
 department_code text primary key,
 worker_id uuid not null,
 receiver_user_id uuid,
 receiver_kind text not null default 'PRIMARY_ACTION_STAFF'
  check(receiver_kind in ('PRIMARY_ACTION_STAFF','DEPARTMENT_HEAD')),
 is_active boolean not null default true,
 updated_at timestamptz not null default now()
);
alter table public.rr_real_chat_department_receiver_v86 enable row level security;
revoke all on public.rr_real_chat_department_receiver_v86 from public,anon,authenticated;

insert into public.rr_real_chat_department_receiver_v86
 (department_code,worker_id,receiver_user_id,receiver_kind,is_active,updated_at)
select 'PURCHASE',d.worker_id,d.linked_auth_user_id,'PRIMARY_ACTION_STAFF',true,now()
from public.rr_worker_directory_unified_v1 d
where lower(trim(d.worker_name))='shailender' and coalesce(d.is_active,false)
order by (d.linked_auth_user_id is not null) desc,d.worker_id limit 1
on conflict(department_code) do update set worker_id=excluded.worker_id,
 receiver_user_id=excluded.receiver_user_id,receiver_kind=excluded.receiver_kind,
 is_active=true,updated_at=now();

-- Employment classification is corrected without inventing a monthly salary amount.
update public.rr_worker_accounts_map_v9785
set payroll_category='SALARIED',updated_at=now()
where worker_id=(select d.worker_id from public.rr_worker_directory_unified_v1 d
 where lower(trim(d.worker_name))='shailender' and coalesce(d.is_active,false)
 order by (d.linked_auth_user_id is not null) desc,d.worker_id limit 1);

create or replace function public.rr_real_chat_enforce_action_route_v85()
returns trigger language plpgsql security invoker set search_path='' as $$
declare v_source text; v_target text; v_receiver record;
begin
 new.department_code:=public.rr_real_chat_route_department_v85(new.source_module,new.action_code,
  new.department_code,new.personal_payload,new.group_payload);
 v_source:=new.department_code;
 v_target:=coalesce(nullif(new.personal_payload->>'target_department_code',''),
  nullif(new.personal_payload->>'receiver_department_code',''),
  nullif(new.group_payload->>'target_department_code',''),
  nullif(new.group_payload->>'receiver_department_code',''));
 if v_target is not null then v_target:=public.rr_real_chat_canonical_department_v83(v_target); end if;
 if new.receiver_worker_id is null and new.receiver_user_id is null then
  select r.worker_id,r.receiver_user_id into v_receiver
  from public.rr_real_chat_department_receiver_v86 r
  where r.department_code=v_source and r.is_active limit 1;
  if found then new.receiver_worker_id:=v_receiver.worker_id;new.receiver_user_id:=v_receiver.receiver_user_id;end if;
 end if;
 new.personal_payload:=coalesce(new.personal_payload,'{}'::jsonb)
  ||jsonb_build_object('source_department_code',v_source,'performed_by_user_id',new.sender_user_id)
  ||case when v_target is null then '{}'::jsonb else jsonb_build_object('target_department_code',v_target) end;
 new.group_payload:=coalesce(new.group_payload,'{}'::jsonb)
  ||jsonb_build_object('source_department_code',v_source)
  ||case when v_target is null then '{}'::jsonb else jsonb_build_object('target_department_code',v_target) end;
 return new;
end $$;
revoke all on function public.rr_real_chat_enforce_action_route_v85() from public,anon,authenticated;

-- Attach existing Purchase history to the primary Purchase staff identity.
update public.rr_real_chat_message_bridge_v70 b set
 receiver_worker_id=r.worker_id,receiver_user_id=r.receiver_user_id
from public.rr_real_chat_department_receiver_v86 r
where b.archived_at is null and b.department_code='PURCHASE' and r.department_code='PURCHASE'
 and r.is_active and b.receiver_worker_id is null and b.receiver_user_id is null;

insert into public.rr_real_chat_receipts_v70(message_id,receiver_key,receiver_user_id,receiver_worker_id)
select b.id,'WORKER:'||b.receiver_worker_id::text,b.receiver_user_id,b.receiver_worker_id
from public.rr_real_chat_message_bridge_v70 b
where b.archived_at is null and b.department_code='PURCHASE' and b.receiver_worker_id is not null
on conflict(message_id,receiver_key) do update set receiver_user_id=excluded.receiver_user_id;

insert into public.rr_real_chat_notification_links_v70
 (message_id,receiver_key,receiver_user_id,receiver_worker_id,deep_link)
select b.id,'WORKER:'||b.receiver_worker_id::text,b.receiver_user_id,b.receiver_worker_id,b.deep_link
from public.rr_real_chat_message_bridge_v70 b
where b.archived_at is null and b.department_code='PURCHASE' and b.receiver_worker_id is not null
on conflict(message_id,receiver_key) do update
 set receiver_user_id=excluded.receiver_user_id,deep_link=excluded.deep_link;

commit;
