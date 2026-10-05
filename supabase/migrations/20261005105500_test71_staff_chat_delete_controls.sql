-- TEST71 endpoints only. Existing production functions remain unchanged.
create or replace function public.rr_chat_staff_messages_test71(p_chat_id uuid,p_channel text default 'GROUP',p_limit integer default 150)
returns table(id uuid,channel text,sender_name text,message_type text,body text,payload jsonb,reply_to_message_id uuid,created_at timestamptz,own boolean)
language plpgsql stable security definer set search_path='' as $$
declare a public.rr_user_profiles%rowtype; chn text:=upper(coalesce(p_channel,'GROUP'));
begin
 perform public.rr_assert_active_user_v1(); a:=public.rr_chat_actor_profile_v9433();
 if a.id is null then raise exception 'Active staff profile required'; end if;
 if not exists(select 1 from public.rr_customer_chat_v9433 c where c.id=p_chat_id and upper(c.data_mode)='TEST') then raise exception 'TEST chat required'; end if;
 if chn='SUPERADMIN_PRIVATE' and upper(coalesce(a.role_code,'')) not in ('SUPER_ADMIN','OWNER') then raise exception 'Private chat is only available to Super Admin.'; end if;
 if not exists(select 1 from public.rr_customer_chat_members_v9433 x where x.chat_id=p_chat_id and x.profile_id=a.id and x.is_active) then raise exception 'Active group membership required.'; end if;
 return query select m.id,m.channel,m.sender_name,m.message_type,m.body,m.payload,m.reply_to_message_id,m.created_at,
 (m.sender_profile_id=a.id and upper(coalesce(m.sender_kind,'')) in ('STAFF','SYSTEM'))
 from public.rr_customer_chat_messages_v9433 m where m.chat_id=p_chat_id and m.channel=chn and m.archived_at is null
 and not exists(select 1 from public.rr_chat_message_hidden_v9712 h where h.message_id=m.id and h.viewer_kind='STAFF' and h.viewer_id=a.id)
 order by m.created_at desc limit least(greatest(coalesce(p_limit,150),1),250);
end $$;
create or replace function public.rr_chat_staff_delete_test71(p_chat_id uuid,p_message_id uuid,p_scope text default 'ME')
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform public.rr_assert_active_user_v1();
 if not exists(select 1 from public.rr_customer_chat_v9433 c where c.id=p_chat_id and upper(c.data_mode)='TEST') then raise exception 'TEST chat required'; end if;
 return public.rr_chat_staff_delete_v9712(p_chat_id,p_message_id,p_scope);
end $$;
create or replace function public.rr_chat_staff_archive_test71(p_chat_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform public.rr_chat_assert_superadmin_v9433();
 if not exists(select 1 from public.rr_customer_chat_v9433 c where c.id=p_chat_id and upper(c.data_mode)='TEST') then raise exception 'TEST chat required'; end if;
 return public.rr_chat_archive_v9433(p_chat_id,'ARCHIVE',p_reason);
end $$;
revoke all on function public.rr_chat_staff_messages_test71(uuid,text,integer),public.rr_chat_staff_delete_test71(uuid,uuid,text),public.rr_chat_staff_archive_test71(uuid,text) from public,anon;
grant execute on function public.rr_chat_staff_messages_test71(uuid,text,integer),public.rr_chat_staff_delete_test71(uuid,uuid,text),public.rr_chat_staff_archive_test71(uuid,text) to authenticated;
notify pgrst,'reload schema';
