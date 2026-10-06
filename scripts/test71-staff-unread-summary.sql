create or replace function public.rr_chat_staff_unread_test71()
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare actor public.rr_user_profiles%rowtype;
begin
 perform public.rr_assert_active_user_v1();
 actor:=public.rr_chat_actor_profile_v9433();
 return (select coalesce(jsonb_agg(jsonb_build_object('chat_id',base.chat_id,'unread_count',u.cnt,'first_unread',u.first_message)),'[]'::jsonb)
 from public.rr_chat_staff_inbox_v9434() base
 join public.rr_customer_chat_v9433 ch on ch.id=base.chat_id and ch.data_mode='TEST'
 left join lateral (
  select count(*) cnt,(jsonb_agg(jsonb_build_object('id',m.id,'channel',m.channel,'sender_name',m.sender_name,'message_type',m.message_type,'body',m.body,'payload',m.payload,'reply_to_message_id',m.reply_to_message_id,'created_at',m.created_at) order by m.created_at,m.id)->0) first_message
  from public.rr_customer_chat_messages_v9433 m
  where m.chat_id=base.chat_id and m.channel='GROUP' and m.archived_at is null and m.sender_kind='CUSTOMER'
  and not exists(select 1 from public.rr_chat_member_receipts_v61 r where r.message_id=m.id and r.member_kind='STAFF' and r.member_id=actor.id and r.read_at is not null)
  and not exists(select 1 from public.rr_chat_member_hidden_v61 h where h.message_id=m.id and h.member_kind='STAFF' and h.member_id=actor.id)
  and not exists(select 1 from public.rr_chat_message_redaction_v61 r where r.message_id=m.id)
 ) u on true);
end $$;
revoke all on function public.rr_chat_staff_unread_test71() from public,anon;
grant execute on function public.rr_chat_staff_unread_test71() to authenticated;
