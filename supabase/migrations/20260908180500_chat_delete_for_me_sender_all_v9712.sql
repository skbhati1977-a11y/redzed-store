-- Chat deletion v9712: per-view hide, plus sender-only global archive.
create table if not exists public.rr_chat_message_hidden_v9712(
  message_id uuid not null references public.rr_customer_chat_messages_v9433(id) on delete cascade,
  viewer_kind text not null check(viewer_kind in('STAFF','CUSTOMER','PARTNER_CUSTOMER','DISTRIBUTOR')),
  viewer_id uuid not null,
  hidden_at timestamptz not null default clock_timestamp(),
  primary key(message_id,viewer_kind,viewer_id)
);
alter table public.rr_chat_message_hidden_v9712 enable row level security;
revoke all on public.rr_chat_message_hidden_v9712 from public,anon,authenticated;

create or replace function public.rr_chat_staff_delete_v9712(p_chat_id uuid,p_message_id uuid,p_scope text default 'ME') returns jsonb
language plpgsql security definer set search_path='public' as $function$
declare a public.rr_user_profiles%rowtype; m public.rr_customer_chat_messages_v9433%rowtype; s text:=upper(trim(coalesce(p_scope,'ME')));
begin
  perform public.rr_assert_active_user_v1(); a:=public.rr_chat_actor_profile_v9433();
  if not exists(select 1 from public.rr_customer_chat_members_v9433 x where x.chat_id=p_chat_id and x.profile_id=a.id and x.is_active) then raise exception 'Active group membership required.'; end if;
  select * into m from public.rr_customer_chat_messages_v9433 where id=p_message_id and chat_id=p_chat_id;
  if m.id is null then raise exception 'Message not found.'; end if;
  if s='ME' then
    insert into public.rr_chat_message_hidden_v9712 values(m.id,'STAFF',a.id,clock_timestamp()) on conflict do nothing;
  elsif s='ALL' then
    if m.sender_profile_id is distinct from a.id or upper(coalesce(m.sender_kind,'')) not in('STAFF','SYSTEM') then raise exception 'Only the original sender can delete for everyone.'; end if;
    update public.rr_customer_chat_messages_v9433 set archived_at=coalesce(archived_at,clock_timestamp()),archived_by=a.id,archive_reason='SENDER_DELETE_FOR_ALL' where id=m.id;
  else raise exception 'Delete scope must be ME or ALL.'; end if;
  return jsonb_build_object('ok',true,'scope',s);
end $function$;

create or replace function public.rr_chat_customer_delete_v9712(p_session_token text,p_device_id text,p_message_id uuid,p_scope text default 'ME') returns jsonb
language plpgsql security definer set search_path='public' as $function$
declare x jsonb; ch uuid; cust uuid; m public.rr_customer_chat_messages_v9433%rowtype; s text:=upper(trim(coalesce(p_scope,'ME')));
begin
  x:=public.rr_customer_session_validate_v9590(p_session_token,p_device_id); ch:=(x->>'chat_id')::uuid; cust:=(x->>'customer_id')::uuid;
  select * into m from public.rr_customer_chat_messages_v9433 where id=p_message_id and chat_id=ch;
  if m.id is null then raise exception 'Message not found.'; end if;
  if s='ME' then insert into public.rr_chat_message_hidden_v9712 values(m.id,'CUSTOMER',cust,clock_timestamp()) on conflict do nothing;
  elsif s='ALL' then
    if upper(coalesce(m.sender_kind,''))<>'CUSTOMER' or m.sender_customer_id is distinct from cust then raise exception 'Only the original sender can delete for everyone.'; end if;
    update public.rr_customer_chat_messages_v9433 set archived_at=coalesce(archived_at,clock_timestamp()),archive_reason='SENDER_DELETE_FOR_ALL',archive_meta=jsonb_build_object('customer_id',cust) where id=m.id;
  else raise exception 'Delete scope must be ME or ALL.'; end if;
  return jsonb_build_object('ok',true,'scope',s);
end $function$;

create or replace function public.rr_market_partner_customer_chat_delete_v9712(p_session_token text,p_device_id text,p_message_id uuid,p_scope text default 'ME') returns jsonb
language plpgsql security definer set search_path='public' as $function$
declare x jsonb; ch uuid; cust uuid; m public.rr_customer_chat_messages_v9433%rowtype; s text:=upper(trim(coalesce(p_scope,'ME')));
begin
  x:=public.rr_market_partner_customer_session_validate_v67(p_session_token,p_device_id); ch:=(x->>'chat_id')::uuid; cust:=(x->>'partner_customer_id')::uuid;
  select * into m from public.rr_customer_chat_messages_v9433 where id=p_message_id and chat_id=ch;
  if m.id is null then raise exception 'Message not found.'; end if;
  if s='ME' then insert into public.rr_chat_message_hidden_v9712 values(m.id,'PARTNER_CUSTOMER',cust,clock_timestamp()) on conflict do nothing;
  elsif s='ALL' then
    if upper(coalesce(m.sender_kind,''))<>'CUSTOMER' or coalesce(m.payload->>'partner_customer_id','')<>cust::text then raise exception 'Only the original sender can delete for everyone.'; end if;
    update public.rr_customer_chat_messages_v9433 set archived_at=coalesce(archived_at,clock_timestamp()),archive_reason='SENDER_DELETE_FOR_ALL',archive_meta=jsonb_build_object('partner_customer_id',cust) where id=m.id;
  else raise exception 'Delete scope must be ME or ALL.'; end if;
  return jsonb_build_object('ok',true,'scope',s);
end $function$;

create or replace function public.rr_market_partner_chat_delete_v9712(p_session_token text,p_device_id text,p_lane text,p_partner_customer_id uuid,p_message_id uuid,p_scope text default 'ME') returns jsonb
language plpgsql security definer set search_path='public' as $function$
declare x jsonb; own uuid; lane text:=upper(trim(coalesce(p_lane,''))); ch uuid; chan text; m public.rr_customer_chat_messages_v9433%rowtype; s text:=upper(trim(coalesce(p_scope,'ME')));
begin
  x:=public.rr_market_partner_context_v67(p_session_token,p_device_id); own:=(x->>'owner_customer_id')::uuid;
  if lane='REDZED' then ch:=public.rr_market_partner_relation_chat_resolve_v67(own,null,'DISTRIBUTOR_REDZED');chan:='GROUP';
  elsif lane in('CUSTOMER_GROUP','CUSTOMER_DIRECT') then ch:=public.rr_market_partner_relation_chat_resolve_v67(own,p_partner_customer_id,'DISTRIBUTOR_CUSTOMER');chan:=case when lane='CUSTOMER_DIRECT' then 'SUPERADMIN_PRIVATE' else 'GROUP' end;
  else raise exception 'Invalid private chat lane.'; end if;
  select * into m from public.rr_customer_chat_messages_v9433 where id=p_message_id and chat_id=ch and channel=chan;
  if m.id is null then raise exception 'Message not found.'; end if;
  if s='ME' then insert into public.rr_chat_message_hidden_v9712 values(m.id,'DISTRIBUTOR',own,clock_timestamp()) on conflict do nothing;
  elsif s='ALL' then
    if upper(coalesce(m.sender_kind,''))<>'DISTRIBUTOR' or m.sender_customer_id is distinct from own then raise exception 'Only the original sender can delete for everyone.'; end if;
    update public.rr_customer_chat_messages_v9433 set archived_at=coalesce(archived_at,clock_timestamp()),archive_reason='SENDER_DELETE_FOR_ALL',archive_meta=jsonb_build_object('distributor_id',own,'lane',lane) where id=m.id;
  else raise exception 'Delete scope must be ME or ALL.'; end if;
  return jsonb_build_object('ok',true,'scope',s);
end $function$;

-- Compatibility: old customer delete calls are now safe Delete For Me.
create or replace function public.rr_chat_customer_delete_message_session_v59(p_session_token text,p_device_id text,p_message_id uuid) returns jsonb
language sql security definer set search_path='public' as $$select public.rr_chat_customer_delete_v9712(p_session_token,p_device_id,p_message_id,'ME')$$;
create or replace function public.rr_market_partner_customer_chat_delete_message_session_v67(p_session_token text,p_device_id text,p_message_id uuid) returns jsonb
language sql security definer set search_path='public' as $$select public.rr_market_partner_customer_chat_delete_v9712(p_session_token,p_device_id,p_message_id,'ME')$$;
create or replace function public.rr_market_partner_chat_delete_v67(p_session_token text,p_device_id text,p_lane text,p_partner_customer_id uuid,p_message_id uuid) returns jsonb
language sql security definer set search_path='public' as $$select public.rr_market_partner_chat_delete_v9712(p_session_token,p_device_id,p_lane,p_partner_customer_id,p_message_id,'ME')$$;

-- Hide-for-me is applied in every relevant message feed.
create or replace function public.rr_chat_staff_messages_v9479(p_chat_id uuid,p_channel text default 'GROUP',p_limit integer default 150)
returns table(id uuid,channel text,sender_kind text,sender_profile_id uuid,sender_customer_id uuid,sender_name text,message_type text,body text,payload jsonb,reply_to_message_id uuid,created_at timestamptz)
language plpgsql stable security definer set search_path='public' as $function$
declare a public.rr_user_profiles%rowtype; chn text:=upper(coalesce(p_channel,'GROUP')); r text;
begin perform public.rr_assert_active_user_v1();a:=public.rr_chat_actor_profile_v9433();r:=upper(coalesce(a.role_code,''));
 if not exists(select 1 from public.rr_customer_chat_members_v9433 x where x.chat_id=p_chat_id and x.profile_id=a.id and x.is_active) then raise exception 'Active group membership required.';end if;
 return query select m.id,m.channel,m.sender_kind,m.sender_profile_id,m.sender_customer_id,m.sender_name,m.message_type,m.body,m.payload,m.reply_to_message_id,m.created_at from public.rr_customer_chat_messages_v9433 m
 where m.chat_id=p_chat_id and m.channel=chn and m.archived_at is null and not exists(select 1 from public.rr_chat_message_hidden_v9712 h where h.message_id=m.id and h.viewer_kind='STAFF' and h.viewer_id=a.id)
 and (chn='GROUP' or r in('SUPER_ADMIN','OWNER') or (coalesce(m.payload->>'private_scope','')='STAFF' and(m.sender_profile_id=a.id or m.payload->>'private_thread_profile_id'=a.id::text))) order by m.created_at desc limit least(greatest(coalesce(p_limit,150),1),250);end $function$;

create or replace function public.rr_chat_customer_messages_session_v9593(p_session_token text,p_device_id text,p_channel text default 'GROUP',p_limit integer default 100)
returns table(id uuid,channel text,sender_name text,message_type text,body text,payload jsonb,reply_to_message_id uuid,created_at timestamptz)
language plpgsql security definer set search_path='public' as $function$
declare x jsonb; chn text:=upper(coalesce(p_channel,'GROUP'));ch uuid;cust uuid;begin x:=public.rr_customer_session_validate_v9590(p_session_token,p_device_id);ch:=(x->>'chat_id')::uuid;cust:=(x->>'customer_id')::uuid;
 return query select m.id,m.channel,m.sender_name,m.message_type,m.body,coalesce(m.payload,'{}'::jsonb)-'thumb_base64',m.reply_to_message_id,m.created_at from public.rr_customer_chat_messages_v9433 m where m.chat_id=ch and m.channel=chn and m.archived_at is null
 and not exists(select 1 from public.rr_chat_message_hidden_v9712 h where h.message_id=m.id and h.viewer_kind='CUSTOMER' and h.viewer_id=cust) order by m.created_at desc limit least(greatest(coalesce(p_limit,100),1),200);end $function$;

create or replace function public.rr_market_partner_customer_chat_messages_session_v67(p_session_token text,p_device_id text,p_channel text default 'GROUP',p_limit integer default 100)
returns table(id uuid,channel text,sender_name text,message_type text,body text,payload jsonb,reply_to_message_id uuid,created_at timestamptz)
language plpgsql security definer set search_path='public' as $function$
declare x jsonb;ch uuid;cust uuid;chn text:=upper(coalesce(p_channel,'GROUP'));begin x:=public.rr_market_partner_customer_session_validate_v67(p_session_token,p_device_id);ch:=(x->>'chat_id')::uuid;cust:=(x->>'partner_customer_id')::uuid;
 return query select m.id,m.channel,m.sender_name,m.message_type,m.body,coalesce(m.payload,'{}'::jsonb)-'thumb_base64',m.reply_to_message_id,m.created_at from public.rr_customer_chat_messages_v9433 m where m.chat_id=ch and m.channel=chn and m.archived_at is null
 and not exists(select 1 from public.rr_chat_message_hidden_v9712 h where h.message_id=m.id and h.viewer_kind='PARTNER_CUSTOMER' and h.viewer_id=cust) order by m.created_at desc limit least(greatest(coalesce(p_limit,100),1),200);end $function$;

create or replace function public.rr_market_partner_chat_messages_v67(p_session_token text,p_device_id text,p_lane text,p_partner_customer_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $function$
declare x jsonb;own uuid;lane text:=upper(trim(coalesce(p_lane,'')));ch uuid;chan text;begin x:=public.rr_market_partner_context_v67(p_session_token,p_device_id);own:=(x->>'owner_customer_id')::uuid;
 if lane='REDZED' then ch:=public.rr_market_partner_relation_chat_resolve_v67(own,null,'DISTRIBUTOR_REDZED');chan:='GROUP';elsif lane in('CUSTOMER_GROUP','CUSTOMER_DIRECT') then ch:=public.rr_market_partner_relation_chat_resolve_v67(own,p_partner_customer_id,'DISTRIBUTOR_CUSTOMER');chan:=case when lane='CUSTOMER_DIRECT' then 'SUPERADMIN_PRIVATE' else 'GROUP' end;else raise exception 'Invalid private chat lane.';end if;
 return coalesce((select jsonb_agg(z order by(z->>'created_at')::timestamptz) from(select jsonb_build_object('id',m.id,'actor',case when lane='REDZED' and m.sender_kind in('STAFF','SYSTEM') then 'REDZED' when lane='REDZED' then 'DISTRIBUTOR' when m.sender_kind='CUSTOMER' then 'CUSTOMER' else 'DISTRIBUTOR' end,'message',m.body,'created_at',m.created_at,'attachment',(select jsonb_build_object('attachment_id',a.id,'name',a.file_name,'type',a.mime_type,'byte_size',a.byte_size) from public.rr_customer_chat_attachments_v9434 a where a.message_id=m.id limit 1))z from public.rr_customer_chat_messages_v9433 m where m.chat_id=ch and m.channel=chan and m.archived_at is null and not exists(select 1 from public.rr_chat_message_hidden_v9712 h where h.message_id=m.id and h.viewer_kind='DISTRIBUTOR' and h.viewer_id=own) order by m.created_at desc limit 200)q),'[]'::jsonb);end $function$;

revoke all on function public.rr_chat_staff_delete_v9712(uuid,uuid,text) from public,anon;
grant execute on function public.rr_chat_staff_delete_v9712(uuid,uuid,text) to authenticated,service_role;
revoke all on function public.rr_chat_customer_delete_v9712(text,text,uuid,text) from public;
grant execute on function public.rr_chat_customer_delete_v9712(text,text,uuid,text) to anon,authenticated,service_role;
revoke all on function public.rr_market_partner_customer_chat_delete_v9712(text,text,uuid,text) from public;
grant execute on function public.rr_market_partner_customer_chat_delete_v9712(text,text,uuid,text) to anon,authenticated,service_role;
revoke all on function public.rr_market_partner_chat_delete_v9712(text,text,text,uuid,uuid,text) from public,anon;
grant execute on function public.rr_market_partner_chat_delete_v9712(text,text,text,uuid,uuid,text) to authenticated,service_role;
