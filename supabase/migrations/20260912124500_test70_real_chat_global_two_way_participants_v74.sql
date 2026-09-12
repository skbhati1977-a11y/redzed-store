-- TEST70 only: resolve every bridge message to its logical sender, receiver and departments.
-- Existing workflow engines remain authoritative; archived rows stay archived.
begin;

create index if not exists rr_rc_bridge_sender_worker_v70
on public.rr_real_chat_message_bridge_v70(sender_worker_id,sent_at desc);

create or replace function public.rr_real_chat_two_way_participants_v74()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_sender_name text:=nullif(trim(new.personal_payload->>'sender_name'),'');
  v_receiver_name text:=nullif(trim(new.personal_payload->>'receiver_name'),'');
  v_sender_count integer:=0; v_receiver_count integer:=0;
  v_sender_worker uuid; v_receiver_worker uuid;
  v_sender_department text; v_receiver_department text;
  v_receiver_user uuid;
begin
  if v_sender_name is not null then
    select count(*) into v_sender_count from public.rr_worker_directory_unified_v1 d
    where coalesce(d.is_active,false) and lower(trim(d.worker_name))=lower(v_sender_name);
    if v_sender_count=1 then
      select d.worker_id,public.rr_upm_core_department_v9077(d.department_code)
      into v_sender_worker,v_sender_department
      from public.rr_worker_directory_unified_v1 d
      where coalesce(d.is_active,false) and lower(trim(d.worker_name))=lower(v_sender_name) limit 1;
    end if;
  end if;
  if v_receiver_name is not null then
    select count(*) into v_receiver_count from public.rr_worker_directory_unified_v1 d
    where coalesce(d.is_active,false) and lower(trim(d.worker_name))=lower(v_receiver_name);
    if v_receiver_count=1 then
      select d.worker_id,public.rr_upm_core_department_v9077(d.department_code),d.linked_auth_user_id
      into v_receiver_worker,v_receiver_department,v_receiver_user
      from public.rr_worker_directory_unified_v1 d
      where coalesce(d.is_active,false) and lower(trim(d.worker_name))=lower(v_receiver_name) limit 1;
    end if;
  end if;

  new.sender_worker_id:=v_sender_worker;
  new.receiver_worker_id:=v_receiver_worker;
  new.receiver_user_id:=v_receiver_user;
  new.personal_payload:=new.personal_payload||jsonb_build_object(
    'sender_department_code',coalesce(v_sender_department,new.department_code),
    'receiver_department_code',coalesce(v_receiver_department,new.department_code));
  new.group_payload:=new.group_payload||jsonb_build_object(
    'sender_department_code',coalesce(v_sender_department,new.department_code),
    'receiver_department_code',coalesce(v_receiver_department,new.department_code));
  if v_receiver_worker is not null then
    new.deep_link:='test70-cb-purchase-real-chat-pilot.html?chat=personal&worker_id='||v_receiver_worker::text||
      '&message_key='||encode(convert_to(new.canonical_key,'UTF8'),'base64');
  end if;
  return new;
end $$;
revoke all on function public.rr_real_chat_two_way_participants_v74() from public,anon,authenticated;

drop trigger if exists rr_real_chat_two_way_participants_v74 on public.rr_real_chat_message_bridge_v70;
create trigger rr_real_chat_two_way_participants_v74
before insert or update on public.rr_real_chat_message_bridge_v70
for each row execute function public.rr_real_chat_two_way_participants_v74();

-- Legacy reconciliation: V73 first rebuilds truthful names; V74 then resolves both participants.
update public.rr_real_chat_message_bridge_v70 set source_event_type=source_event_type;

delete from public.rr_real_chat_receipts_v70 r using public.rr_real_chat_message_bridge_v70 m
where r.message_id=m.id and r.receiver_key like 'WORKER:%'
  and r.receiver_worker_id is distinct from m.receiver_worker_id;
insert into public.rr_real_chat_receipts_v70(message_id,receiver_key,receiver_user_id,receiver_worker_id)
select m.id,'WORKER:'||m.receiver_worker_id::text,m.receiver_user_id,m.receiver_worker_id
from public.rr_real_chat_message_bridge_v70 m where m.receiver_worker_id is not null
on conflict(message_id,receiver_key) do update set receiver_user_id=excluded.receiver_user_id;

delete from public.rr_real_chat_notification_links_v70 n using public.rr_real_chat_message_bridge_v70 m
where n.message_id=m.id and n.receiver_key like 'WORKER:%'
  and n.receiver_worker_id is distinct from m.receiver_worker_id;
insert into public.rr_real_chat_notification_links_v70(message_id,receiver_key,receiver_user_id,receiver_worker_id,deep_link)
select m.id,'WORKER:'||m.receiver_worker_id::text,m.receiver_user_id,m.receiver_worker_id,m.deep_link
from public.rr_real_chat_message_bridge_v70 m where m.receiver_worker_id is not null
on conflict(message_id,receiver_key) do update set receiver_user_id=excluded.receiver_user_id,deep_link=excluded.deep_link;

drop policy if exists rr_rc_bridge_select_v70 on public.rr_real_chat_message_bridge_v70;
create policy rr_rc_bridge_select_v70 on public.rr_real_chat_message_bridge_v70
for select to authenticated using (
  auth.uid() is not null and (
    auth.uid() in (sender_user_id,receiver_user_id)
    or exists(select 1 from public.rr_worker_directory_unified_v1 d
      where d.linked_auth_user_id=auth.uid() and coalesce(d.is_active,false)
        and d.worker_id in (sender_worker_id,receiver_worker_id))
    or public.rr_real_chat_is_global_staff_v70(auth.uid())
  )
);

comment on function public.rr_real_chat_two_way_participants_v74() is
'TEST70 global legacy/present/future logical sender-receiver and department resolver; never changes source workflow rows.';
commit;
