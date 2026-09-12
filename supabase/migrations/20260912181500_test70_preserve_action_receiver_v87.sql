-- TEST70 V87: legacy participant enrichment must not erase canonical action routing.
begin;
create or replace function public.rr_real_chat_two_way_participants_v74()
returns trigger language plpgsql security definer set search_path='public','pg_temp' as $$
declare v_sender_name text:=nullif(trim(new.personal_payload->>'sender_name'),'');
 v_receiver_name text:=nullif(trim(new.personal_payload->>'receiver_name'),'');
 v_count integer; v_worker uuid; v_user uuid; v_target text;
begin
 if v_sender_name is not null and new.sender_worker_id is null then
  select count(*) into v_count from public.rr_worker_directory_unified_v1 d
   where coalesce(d.is_active,false) and lower(trim(d.worker_name))=lower(v_sender_name);
  if v_count=1 then select d.worker_id into v_worker from public.rr_worker_directory_unified_v1 d
   where coalesce(d.is_active,false) and lower(trim(d.worker_name))=lower(v_sender_name) limit 1;
   new.sender_worker_id:=v_worker; end if;
 end if;
 if v_receiver_name is not null and new.receiver_worker_id is null then
  select count(*) into v_count from public.rr_worker_directory_unified_v1 d
   where coalesce(d.is_active,false) and lower(trim(d.worker_name))=lower(v_receiver_name);
  if v_count=1 then select d.worker_id,d.linked_auth_user_id into v_worker,v_user
   from public.rr_worker_directory_unified_v1 d where coalesce(d.is_active,false)
    and lower(trim(d.worker_name))=lower(v_receiver_name) limit 1;
   new.receiver_worker_id:=v_worker;new.receiver_user_id:=v_user;end if;
 end if;
 v_target:=coalesce(nullif(new.personal_payload->>'target_department_code',''),
  nullif(new.personal_payload->>'receiver_department_code',''),new.department_code);
 new.personal_payload:=coalesce(new.personal_payload,'{}'::jsonb)||jsonb_build_object(
  'sender_department_code',new.department_code,
  'receiver_department_code',public.rr_real_chat_canonical_department_v83(v_target));
 new.group_payload:=coalesce(new.group_payload,'{}'::jsonb)||jsonb_build_object(
  'sender_department_code',new.department_code,
  'receiver_department_code',public.rr_real_chat_canonical_department_v83(v_target));
 if new.receiver_worker_id is not null then
  new.deep_link:='test70-cb-purchase-real-chat-pilot.html?chat=personal&worker_id='||
   new.receiver_worker_id::text||'&department='||new.department_code||
   '&message_key='||encode(convert_to(new.canonical_key,'UTF8'),'base64');
 end if;
 return new;
end $$;
revoke all on function public.rr_real_chat_two_way_participants_v74() from public,anon,authenticated;

update public.rr_real_chat_message_bridge_v70 b set
 receiver_worker_id=r.worker_id,receiver_user_id=r.receiver_user_id,
 personal_payload=coalesce(b.personal_payload,'{}'::jsonb)||jsonb_build_object('receiver_name',d.worker_name),
 group_payload=coalesce(b.group_payload,'{}'::jsonb)||jsonb_build_object('receiver_name',d.worker_name)
from public.rr_real_chat_department_receiver_v86 r
join public.rr_worker_directory_unified_v1 d on d.worker_id=r.worker_id
where b.archived_at is null and b.department_code='PURCHASE' and r.department_code='PURCHASE' and r.is_active;

insert into public.rr_real_chat_receipts_v70(message_id,receiver_key,receiver_user_id,receiver_worker_id)
select b.id,'WORKER:'||b.receiver_worker_id::text,b.receiver_user_id,b.receiver_worker_id
from public.rr_real_chat_message_bridge_v70 b where b.archived_at is null
 and b.department_code='PURCHASE' and b.receiver_worker_id is not null
on conflict(message_id,receiver_key) do update set receiver_user_id=excluded.receiver_user_id;
commit;
