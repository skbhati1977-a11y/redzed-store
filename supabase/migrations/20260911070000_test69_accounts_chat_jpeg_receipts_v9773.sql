-- TEST69 V9773: truthful Accounts JPG sharing and customer delivery/read receipts.

create or replace function public.rr_chat_customer_ack_v9773(
  p_token text,
  p_mobile text,
  p_mark_read boolean default true
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cx record;
  touched integer := 0;
begin
  select * into cx
  from public.rr_chat_customer_context_v9434(p_token,p_mobile)
  limit 1;

  update public.rr_chat_member_receipts_v61 r
     set delivered_at = coalesce(r.delivered_at,clock_timestamp()),
         read_at = case when p_mark_read then coalesce(r.read_at,clock_timestamp()) else r.read_at end
    from public.rr_customer_chat_messages_v9433 m
   where r.message_id=m.id
     and m.chat_id=cx.chat_id
     and m.channel='GROUP'
     and r.member_kind='CUSTOMER'
     and r.member_id=cx.customer_id
     and (r.delivered_at is null or (p_mark_read and r.read_at is null));
  get diagnostics touched = row_count;
  return jsonb_build_object('chat_id',cx.chat_id,'updated',touched,'read',p_mark_read);
end;
$$;

revoke all on function public.rr_chat_customer_ack_v9773(text,text,boolean) from public;
grant execute on function public.rr_chat_customer_ack_v9773(text,text,boolean) to anon,authenticated,service_role;

create or replace function public.rr_chat_customer_ack_session_v9773(
  p_session_token text,
  p_device_id text,
  p_mark_read boolean default true
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  x jsonb;
  ch uuid;
  cust uuid;
  touched integer := 0;
begin
  x := public.rr_customer_session_validate_v9590(p_session_token,p_device_id);
  ch := (x->>'chat_id')::uuid;
  cust := (x->>'customer_id')::uuid;
  update public.rr_chat_member_receipts_v61 r
     set delivered_at=coalesce(r.delivered_at,clock_timestamp()),
         read_at=case when p_mark_read then coalesce(r.read_at,clock_timestamp()) else r.read_at end
    from public.rr_customer_chat_messages_v9433 m
   where r.message_id=m.id and m.chat_id=ch and m.channel='GROUP'
     and r.member_kind='CUSTOMER' and r.member_id=cust
     and (r.delivered_at is null or (p_mark_read and r.read_at is null));
  get diagnostics touched=row_count;
  return jsonb_build_object('chat_id',ch,'updated',touched,'read',p_mark_read);
end;
$$;

revoke all on function public.rr_chat_customer_ack_session_v9773(text,text,boolean) from public;
grant execute on function public.rr_chat_customer_ack_session_v9773(text,text,boolean) to anon,authenticated,service_role;

create or replace function public.rr_accounts_chat_delivery_v9773(p_message_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  a public.rr_user_profiles%rowtype;
  out_row record;
begin
  perform public.rr_assert_active_user_v1();
  a := public.rr_chat_actor_profile_v9433();

  select m.id message_id,m.created_at sent_at,c.customer_name,
         r.delivered_at,r.read_at,
         coalesce(att.file_name,m.payload->>'file_name') file_name
    into out_row
    from public.rr_customer_chat_messages_v9433 m
    join public.rr_customer_chat_v9433 c on c.id=m.chat_id
    left join public.rr_chat_member_receipts_v61 r
      on r.message_id=m.id and r.member_kind='CUSTOMER' and r.member_id=c.customer_id
    left join public.rr_customer_chat_attachments_v9434 att on att.message_id=m.id
   where m.id=p_message_id
     and m.sender_kind='STAFF'
     and m.sender_profile_id=a.id
   limit 1;

  if out_row.message_id is null then raise exception 'Shared message not found or not owned by current user.'; end if;
  return jsonb_build_object(
    'message_id',out_row.message_id,
    'customer_name',out_row.customer_name,
    'file_name',out_row.file_name,
    'sent_at',out_row.sent_at,
    'delivered_at',out_row.delivered_at,
    'read_at',out_row.read_at,
    'status',case when out_row.read_at is not null then 'READ' when out_row.delivered_at is not null then 'DELIVERED' else 'SENT' end
  );
end;
$$;

revoke all on function public.rr_accounts_chat_delivery_v9773(uuid) from public,anon;
grant execute on function public.rr_accounts_chat_delivery_v9773(uuid) to authenticated,service_role;

comment on function public.rr_chat_customer_ack_v9773(text,text,boolean) is
  'Token-scoped customer delivery/read acknowledgement. Never manufactures a receipt before the customer client loads the chat.';
comment on function public.rr_chat_customer_ack_session_v9773(text,text,boolean) is
  'Secure-session customer delivery/read acknowledgement used by the production customer chat.';
comment on function public.rr_accounts_chat_delivery_v9773(uuid) is
  'Sender-scoped status for an Accounts attachment shared to Real Chat.';
