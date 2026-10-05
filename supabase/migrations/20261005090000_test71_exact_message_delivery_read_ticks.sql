-- Reuse existing receipt ledger; device fetch is delivery, visible message is read.
create or replace function public.rr_chat_staff_receipts_test71(p_chat_id uuid,p_message_ids uuid[],p_read_ids uuid[] default '{}') returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare ch uuid; cust uuid; actor uuid; mode text; a public.rr_user_profiles%rowtype; x jsonb;
begin
 perform public.rr_assert_active_user_v1();a:=public.rr_chat_actor_profile_v9433();ch:=p_chat_id;actor:=a.id;mode:='STAFF';
  if not exists(select 1 from public.rr_customer_chat_members_v9433 where chat_id=ch and profile_id=actor and is_active) then raise exception 'Active group membership required.'; end if;
  select customer_id into cust from public.rr_customer_chat_v9433 where id=ch;
 if cardinality(p_message_ids)>200 or cardinality(p_read_ids)>200 then raise exception 'Maximum 200 messages.'; end if;
 if not exists(select 1 from public.rr_customer_chat_v9433 where id=ch and data_mode='TEST') then raise exception 'TEST chat required.'; end if;
 -- ACK only messages actually fetched by this device, never the entire chat history.
 insert into public.rr_chat_member_receipts_v61(message_id,member_kind,member_id,delivered_at,read_at)
 select m.id,mode,actor,now(),case when m.id=any(p_read_ids) then now() end from public.rr_customer_chat_messages_v9433 m
 where m.id=any(p_message_ids) and m.chat_id=ch and m.archived_at is null
 and (m.channel='GROUP' or lower(a.role_code) in ('owner','super_admin','superadmin'))
 and case when mode='CUSTOMER' then m.sender_kind<>'CUSTOMER' else m.sender_kind='CUSTOMER' end
 on conflict(message_id,member_kind,member_id) do update set delivered_at=coalesce(rr_chat_member_receipts_v61.delivered_at,excluded.delivered_at),read_at=coalesce(rr_chat_member_receipts_v61.read_at,excluded.read_at);
 return (select coalesce(jsonb_agg(jsonb_build_object('message_id',m.id,'own',
 case when mode='CUSTOMER' then m.sender_kind='CUSTOMER' and coalesce(m.sender_customer_id,cust)=cust else m.sender_kind='STAFF' and m.sender_profile_id=actor end,
 'delivered',exists(select 1 from public.rr_chat_member_receipts_v61 r where r.message_id=m.id and r.delivered_at is not null and case when m.sender_kind='CUSTOMER' then r.member_kind='STAFF' and exists(select 1 from public.rr_customer_chat_members_v9433 cm join public.rr_user_profiles p on p.id=cm.profile_id where cm.chat_id=ch and cm.profile_id=r.member_id and cm.is_active and p.is_active and (m.channel='GROUP' or lower(p.role_code) in ('owner','super_admin','superadmin'))) else r.member_kind='CUSTOMER' and r.member_id=cust end),
 'read',exists(select 1 from public.rr_chat_member_receipts_v61 r where r.message_id=m.id and r.read_at is not null and case when m.sender_kind='CUSTOMER' then r.member_kind='STAFF' and exists(select 1 from public.rr_customer_chat_members_v9433 cm join public.rr_user_profiles p on p.id=cm.profile_id where cm.chat_id=ch and cm.profile_id=r.member_id and cm.is_active and p.is_active and (m.channel='GROUP' or lower(p.role_code) in ('owner','super_admin','superadmin'))) else r.member_kind='CUSTOMER' and r.member_id=cust end))), '[]'::jsonb)
 from public.rr_customer_chat_messages_v9433 m where m.id=any(p_message_ids) and m.chat_id=ch and m.archived_at is null and (m.channel='GROUP' or lower(a.role_code) in ('owner','super_admin','superadmin')));
end
$fn$;
revoke all on function public.rr_chat_staff_receipts_test71(uuid,uuid[],uuid[]) from public,anon;
grant execute on function public.rr_chat_staff_receipts_test71(uuid,uuid[],uuid[]) to authenticated,service_role;
create or replace function public.rr_chat_customer_receipts_test71(p_session_token text,p_device_id text,p_message_ids uuid[],p_read_ids uuid[] default '{}') returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare ch uuid; cust uuid; actor uuid; mode text; a public.rr_user_profiles%rowtype; x jsonb;
begin
 x:=public.rr_customer_session_validate_v9590(p_session_token,p_device_id);ch:=(x->>'chat_id')::uuid;cust:=(x->>'customer_id')::uuid;actor:=cust;mode:='CUSTOMER';
 if cardinality(p_message_ids)>200 or cardinality(p_read_ids)>200 then raise exception 'Maximum 200 messages.'; end if;
 if not exists(select 1 from public.rr_customer_chat_v9433 where id=ch and data_mode='TEST') then raise exception 'TEST chat required.'; end if;
 -- ACK only messages actually fetched by this device, never the entire chat history.
 insert into public.rr_chat_member_receipts_v61(message_id,member_kind,member_id,delivered_at,read_at)
 select m.id,mode,actor,now(),case when m.id=any(p_read_ids) then now() end from public.rr_customer_chat_messages_v9433 m
 where m.id=any(p_message_ids) and m.chat_id=ch and m.archived_at is null
 and (m.channel='GROUP' or true)
 and case when mode='CUSTOMER' then m.sender_kind<>'CUSTOMER' else m.sender_kind='CUSTOMER' end
 on conflict(message_id,member_kind,member_id) do update set delivered_at=coalesce(rr_chat_member_receipts_v61.delivered_at,excluded.delivered_at),read_at=coalesce(rr_chat_member_receipts_v61.read_at,excluded.read_at);
 return (select coalesce(jsonb_agg(jsonb_build_object('message_id',m.id,'own',
 case when mode='CUSTOMER' then m.sender_kind='CUSTOMER' and coalesce(m.sender_customer_id,cust)=cust else m.sender_kind='STAFF' and m.sender_profile_id=actor end,
 'delivered',exists(select 1 from public.rr_chat_member_receipts_v61 r where r.message_id=m.id and r.delivered_at is not null and case when m.sender_kind='CUSTOMER' then r.member_kind='STAFF' and exists(select 1 from public.rr_customer_chat_members_v9433 cm join public.rr_user_profiles p on p.id=cm.profile_id where cm.chat_id=ch and cm.profile_id=r.member_id and cm.is_active and p.is_active and (m.channel='GROUP' or lower(p.role_code) in ('owner','super_admin','superadmin'))) else r.member_kind='CUSTOMER' and r.member_id=cust end),
 'read',exists(select 1 from public.rr_chat_member_receipts_v61 r where r.message_id=m.id and r.read_at is not null and case when m.sender_kind='CUSTOMER' then r.member_kind='STAFF' and exists(select 1 from public.rr_customer_chat_members_v9433 cm join public.rr_user_profiles p on p.id=cm.profile_id where cm.chat_id=ch and cm.profile_id=r.member_id and cm.is_active and p.is_active and (m.channel='GROUP' or lower(p.role_code) in ('owner','super_admin','superadmin'))) else r.member_kind='CUSTOMER' and r.member_id=cust end))), '[]'::jsonb)
 from public.rr_customer_chat_messages_v9433 m where m.id=any(p_message_ids) and m.chat_id=ch and m.archived_at is null and (m.channel='GROUP' or true));
end
$fn$;
revoke all on function public.rr_chat_customer_receipts_test71(text,text,uuid[],uuid[]) from public,anon;
grant execute on function public.rr_chat_customer_receipts_test71(text,text,uuid[],uuid[]) to anon,authenticated,service_role;
