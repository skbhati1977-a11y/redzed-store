-- TEST67: map distributor relations onto the mature direct-customer chat core.
-- Ordinary chat lives in rr_customer_chat_*; rr_market_partner_event_v67 remains
-- reserved for collection / requirement / PI / CI system artifacts.

alter table public.rr_customer_chat_messages_v9433
  drop constraint if exists rr_customer_chat_messages_v9433_sender_kind_check;
alter table public.rr_customer_chat_messages_v9433
  add constraint rr_customer_chat_messages_v9433_sender_kind_check
  check(sender_kind in('STAFF','CUSTOMER','SYSTEM','DISTRIBUTOR','DISTRIBUTOR_STAFF'));

create table if not exists public.rr_market_partner_relation_chat_v67(
  id uuid primary key default gen_random_uuid(),
  relation_kind text not null check(relation_kind in('DISTRIBUTOR_CUSTOMER','DISTRIBUTOR_REDZED')),
  owner_customer_id uuid not null references public.rr_customers(id) on delete cascade,
  partner_customer_id uuid references public.rr_market_partner_customer_v67(id) on delete cascade,
  chat_id uuid not null unique references public.rr_customer_chat_v9433(id) on delete cascade,
  status text not null default 'ACTIVE' check(status in('ACTIVE','INACTIVE')),
  data_mode text not null default 'TEST' check(data_mode='TEST'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(
    (relation_kind='DISTRIBUTOR_CUSTOMER' and partner_customer_id is not null)
    or (relation_kind='DISTRIBUTOR_REDZED' and partner_customer_id is null)
  )
);
create unique index if not exists rr_market_partner_relation_chat_customer_v67_uq
  on public.rr_market_partner_relation_chat_v67(owner_customer_id,partner_customer_id)
  where relation_kind='DISTRIBUTOR_CUSTOMER';
create unique index if not exists rr_market_partner_relation_chat_redzed_v67_uq
  on public.rr_market_partner_relation_chat_v67(owner_customer_id)
  where relation_kind='DISTRIBUTOR_REDZED';
create index if not exists rr_market_partner_relation_chat_owner_v67_idx
  on public.rr_market_partner_relation_chat_v67(owner_customer_id,status);
alter table public.rr_market_partner_relation_chat_v67 enable row level security;
revoke all on public.rr_market_partner_relation_chat_v67 from public,anon,authenticated;
grant all on public.rr_market_partner_relation_chat_v67 to service_role;

create table if not exists public.rr_market_partner_customer_session_v67(
  id uuid primary key default gen_random_uuid(),
  session_token_hash text not null unique,
  owner_customer_id uuid not null references public.rr_customers(id) on delete cascade,
  partner_customer_id uuid not null references public.rr_market_partner_customer_v67(id) on delete cascade,
  relation_chat_id uuid not null references public.rr_market_partner_relation_chat_v67(id) on delete cascade,
  chat_id uuid not null references public.rr_customer_chat_v9433(id) on delete cascade,
  share_id uuid not null references public.rr_market_share_v9420(id) on delete cascade,
  device_id_hash text,
  data_mode text not null default 'TEST' check(data_mode='TEST'),
  verified_at timestamptz not null default now(),
  expires_at timestamptz not null default(now()+interval '30 days'),
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists rr_market_partner_customer_session_v67_lookup_idx
  on public.rr_market_partner_customer_session_v67(session_token_hash)
  where revoked_at is null;
alter table public.rr_market_partner_customer_session_v67 enable row level security;
revoke all on public.rr_market_partner_customer_session_v67 from public,anon,authenticated;
grant all on public.rr_market_partner_customer_session_v67 to service_role;

create or replace function public.rr_market_partner_relation_chat_resolve_v67(
  p_owner_customer_id uuid,
  p_partner_customer_id uuid default null,
  p_relation_kind text default 'DISTRIBUTOR_CUSTOMER'
) returns uuid
language plpgsql security definer set search_path=''
as $function$
declare
  v_kind text:=upper(trim(coalesce(p_relation_kind,'')));
  v_chat uuid;
  v_relation uuid;
  v_name text;
  v_mobile text;
begin
  if v_kind not in('DISTRIBUTOR_CUSTOMER','DISTRIBUTOR_REDZED') then
    raise exception 'Invalid distributor chat relation.';
  end if;
  if v_kind='DISTRIBUTOR_CUSTOMER' then
    select r.chat_id into v_chat
    from public.rr_market_partner_relation_chat_v67 r
    where r.owner_customer_id=p_owner_customer_id
      and r.partner_customer_id=p_partner_customer_id
      and r.relation_kind=v_kind limit 1;
    if v_chat is not null then return v_chat; end if;
    select c.private_name,c.private_mobile into v_name,v_mobile
    from public.rr_market_partner_customer_v67 c
    where c.id=p_partner_customer_id and c.owner_customer_id=p_owner_customer_id
      and c.status='ACTIVE' and c.data_mode='TEST';
    if v_name is null then raise exception 'Distributor customer relation is unavailable.'; end if;
  else
    select r.chat_id into v_chat
    from public.rr_market_partner_relation_chat_v67 r
    where r.owner_customer_id=p_owner_customer_id
      and r.relation_kind=v_kind limit 1;
    if v_chat is not null then return v_chat; end if;
    if not exists(select 1 from public.rr_customers c where c.id=p_owner_customer_id and c.is_active) then
      raise exception 'Distributor relation is unavailable.';
    end if;
    v_name:='REDZED'; v_mobile:=null;
  end if;
  insert into public.rr_customer_chat_v9433(customer_id,customer_name,mobile,data_mode,status)
  values(null,v_name,v_mobile,'TEST','OPEN') returning id into v_chat;
  begin
    insert into public.rr_market_partner_relation_chat_v67(
      relation_kind,owner_customer_id,partner_customer_id,chat_id
    ) values(v_kind,p_owner_customer_id,case when v_kind='DISTRIBUTOR_CUSTOMER' then p_partner_customer_id else null end,v_chat)
    returning id into v_relation;
  exception when unique_violation then
    delete from public.rr_customer_chat_v9433 where id=v_chat;
    if v_kind='DISTRIBUTOR_CUSTOMER' then
      select r.chat_id into v_chat from public.rr_market_partner_relation_chat_v67 r
      where r.owner_customer_id=p_owner_customer_id and r.partner_customer_id=p_partner_customer_id
        and r.relation_kind=v_kind limit 1;
    else
      select r.chat_id into v_chat from public.rr_market_partner_relation_chat_v67 r
      where r.owner_customer_id=p_owner_customer_id and r.relation_kind=v_kind limit 1;
    end if;
  end;
  return v_chat;
end
$function$;

create or replace function public.rr_market_partner_customer_session_issue_v67(
  p_token text,
  p_device_id text default null
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare
  v_owner uuid; v_customer uuid; v_share uuid; v_chat uuid; v_relation uuid;
  v_name text; v_group text; v_owner_name text; v_raw text; v_hash text; v_device_hash text;
begin
  select pc.owner_customer_id,pc.partner_customer_id,s.id,c.private_name,g.group_name,o.customer_name
  into v_owner,v_customer,v_share,v_name,v_group,v_owner_name
  from public.rr_market_share_v9420 s
  join public.rr_market_partner_collection_v67 pc on pc.share_id=s.id
  join public.rr_market_partner_customer_v67 c on c.id=pc.partner_customer_id
  join public.rr_customers o on o.id=pc.owner_customer_id
  left join public.rr_market_partner_group_v67 g on g.id=c.group_id
  where (s.token=p_token or s.short_code=upper(p_token))
    and s.status='ACTIVE' and s.data_mode='TEST' and c.status='ACTIVE'
  order by case when s.token=p_token then 0 else 1 end limit 1;
  if v_owner is null or v_customer is null then
    raise exception 'Distributor customer share relation is unavailable.';
  end if;
  v_chat:=public.rr_market_partner_relation_chat_resolve_v67(v_owner,v_customer,'DISTRIBUTOR_CUSTOMER');
  select r.id into v_relation from public.rr_market_partner_relation_chat_v67 r
  where r.chat_id=v_chat and r.status='ACTIVE';
  v_raw:=encode(extensions.gen_random_bytes(32),'hex');
  v_hash:=encode(extensions.digest(v_raw,'sha256'),'hex');
  if nullif(trim(coalesce(p_device_id,'')),'') is not null then
    v_device_hash:=encode(extensions.digest(trim(p_device_id),'sha256'),'hex');
  end if;
  insert into public.rr_market_partner_customer_session_v67(
    session_token_hash,owner_customer_id,partner_customer_id,relation_chat_id,chat_id,share_id,device_id_hash
  ) values(v_hash,v_owner,v_customer,v_relation,v_chat,v_share,v_device_hash);
  return jsonb_build_object(
    'session_token',v_raw,'expires_in_seconds',2592000,'chat_id',v_chat,
    'owner_customer_id',v_owner,'partner_customer_id',v_customer,
    'customer_name',v_name,'group_name',coalesce(v_group,v_name||' GROUP'),
    'owner_name',v_owner_name,'relation_kind','DISTRIBUTOR_CUSTOMER','data_mode','TEST'
  );
end
$function$;

create or replace function public.rr_market_partner_customer_session_validate_v67(
  p_session_token text,
  p_device_id text default null
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare
  v_session public.rr_market_partner_customer_session_v67%rowtype;
  v_hash text; v_device_hash text; v_name text; v_group text; v_owner_name text;
begin
  if nullif(trim(coalesce(p_session_token,'')),'') is null then raise exception 'Customer session required.'; end if;
  v_hash:=encode(extensions.digest(trim(p_session_token),'sha256'),'hex');
  select s.* into v_session
  from public.rr_market_partner_customer_session_v67 s
  join public.rr_market_partner_relation_chat_v67 r on r.id=s.relation_chat_id and r.status='ACTIVE'
  join public.rr_market_partner_customer_v67 c on c.id=s.partner_customer_id and c.status='ACTIVE'
  where s.session_token_hash=v_hash and s.revoked_at is null and s.expires_at>now()
  limit 1;
  if v_session.id is null then raise exception 'Customer session invalid or expired.'; end if;
  if v_session.device_id_hash is not null then
    if nullif(trim(coalesce(p_device_id,'')),'') is null then raise exception 'Trusted device binding required.'; end if;
    v_device_hash:=encode(extensions.digest(trim(p_device_id),'sha256'),'hex');
    if v_device_hash<>v_session.device_id_hash then raise exception 'Trusted device does not match.'; end if;
  end if;
  update public.rr_market_partner_customer_session_v67 set last_seen_at=now() where id=v_session.id;
  select c.private_name,g.group_name,o.customer_name into v_name,v_group,v_owner_name
  from public.rr_market_partner_customer_v67 c
  join public.rr_customers o on o.id=c.owner_customer_id
  left join public.rr_market_partner_group_v67 g on g.id=c.group_id
  where c.id=v_session.partner_customer_id;
  return jsonb_build_object(
    'valid',true,'chat_id',v_session.chat_id,'owner_customer_id',v_session.owner_customer_id,
    'partner_customer_id',v_session.partner_customer_id,'share_id',v_session.share_id,
    'customer_name',v_name,'group_name',coalesce(v_group,v_name||' GROUP'),
    'owner_name',v_owner_name,'relation_kind','DISTRIBUTOR_CUSTOMER',
    'data_mode','TEST','expires_at',v_session.expires_at
  );
end
$function$;

create or replace function public.rr_market_partner_customer_chat_messages_session_v67(
  p_session_token text,p_device_id text,p_channel text default 'GROUP',p_limit integer default 100
) returns table(id uuid,channel text,sender_name text,message_type text,body text,payload jsonb,reply_to_message_id uuid,created_at timestamptz)
language plpgsql security definer set search_path=''
as $function$
declare v_ctx jsonb; v_chat uuid; v_channel text:=upper(coalesce(p_channel,'GROUP'));
begin
  v_ctx:=public.rr_market_partner_customer_session_validate_v67(p_session_token,p_device_id);
  v_chat:=(v_ctx->>'chat_id')::uuid;
  if v_channel not in('GROUP','SUPERADMIN_PRIVATE') then raise exception 'Invalid distributor customer channel.'; end if;
  return query select m.id,m.channel,m.sender_name,m.message_type,m.body,
    coalesce(m.payload,'{}'::jsonb)-'thumb_base64',m.reply_to_message_id,m.created_at
  from public.rr_customer_chat_messages_v9433 m
  where m.chat_id=v_chat and m.channel=v_channel and m.archived_at is null
  order by m.created_at desc limit least(greatest(coalesce(p_limit,100),1),200);
end
$function$;

create or replace function public.rr_market_partner_customer_chat_send_session_v67(
  p_session_token text,p_device_id text,p_channel text,p_message_type text,p_body text,
  p_payload jsonb default '{}'::jsonb,p_reply_to uuid default null
) returns uuid
language plpgsql security definer set search_path=''
as $function$
declare v_ctx jsonb; v_chat uuid; v_customer uuid; v_name text; v_channel text:=upper(coalesce(p_channel,'GROUP')); v_id uuid;
begin
  v_ctx:=public.rr_market_partner_customer_session_validate_v67(p_session_token,p_device_id);
  v_chat:=(v_ctx->>'chat_id')::uuid; v_customer:=(v_ctx->>'partner_customer_id')::uuid; v_name:=v_ctx->>'customer_name';
  if v_channel not in('GROUP','SUPERADMIN_PRIVATE') then raise exception 'Invalid distributor customer channel.'; end if;
  if nullif(trim(coalesce(p_body,'')),'') is null and upper(coalesce(p_message_type,'TEXT'))='TEXT' then raise exception 'Message is required.'; end if;
  if p_reply_to is not null and not exists(select 1 from public.rr_customer_chat_messages_v9433 m where m.id=p_reply_to and m.chat_id=v_chat and m.channel=v_channel and m.archived_at is null) then raise exception 'Reply target is unavailable.'; end if;
  insert into public.rr_customer_chat_messages_v9433(
    chat_id,channel,sender_kind,sender_customer_id,sender_name,message_type,body,payload,reply_to_message_id
  ) values(v_chat,v_channel,'CUSTOMER',null,coalesce(nullif(trim(v_name),''),'Customer'),upper(coalesce(p_message_type,'TEXT')),
    nullif(p_body,''),coalesce(p_payload,'{}'::jsonb)||jsonb_build_object('partner_customer_id',v_customer,'relation_scope','DISTRIBUTOR_CUSTOMER'),p_reply_to)
  returning id into v_id;
  return v_id;
end
$function$;

create or replace function public.rr_market_partner_customer_chat_upload_session_v67(
  p_session_token text,p_device_id text,p_channel text,p_file_name text,p_mime_type text,p_base64 text,
  p_body text default null,p_reply_to uuid default null,p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare v_ctx jsonb; v_chat uuid; v_customer uuid; v_name text; v_channel text:=upper(coalesce(p_channel,'GROUP'));
  v_raw bytea; v_message uuid; v_attachment uuid; v_type text; v_payload jsonb:=coalesce(p_payload,'{}'::jsonb);
begin
  v_ctx:=public.rr_market_partner_customer_session_validate_v67(p_session_token,p_device_id);
  v_chat:=(v_ctx->>'chat_id')::uuid; v_customer:=(v_ctx->>'partner_customer_id')::uuid; v_name:=v_ctx->>'customer_name';
  if v_channel not in('GROUP','SUPERADMIN_PRIVATE') then raise exception 'Invalid distributor customer channel.'; end if;
  v_raw:=decode(coalesce(p_base64,''),'base64');
  if octet_length(v_raw)<1 or octet_length(v_raw)>6291456 then raise exception 'Attachment must be 1 byte to 6 MB.'; end if;
  v_type:=case when lower(coalesce(p_mime_type,'')) like 'audio/%' then 'VOICE' else 'ATTACHMENT' end;
  v_payload:=v_payload||jsonb_build_object(
    'file_name',coalesce(nullif(trim(p_file_name),''),'attachment'),
    'mime_type',coalesce(nullif(trim(p_mime_type),''),'application/octet-stream'),
    'byte_size',octet_length(v_raw),'media_kind',case when v_type='VOICE' then 'VOICE' else 'FILE' end,
    'partner_customer_id',v_customer,'relation_scope','DISTRIBUTOR_CUSTOMER'
  );
  insert into public.rr_customer_chat_messages_v9433(
    chat_id,channel,sender_kind,sender_name,message_type,body,payload,reply_to_message_id
  ) values(v_chat,v_channel,'CUSTOMER',coalesce(nullif(trim(v_name),''),'Customer'),v_type,nullif(p_body,''),v_payload,p_reply_to)
  returning id into v_message;
  insert into public.rr_customer_chat_attachments_v9434(message_id,chat_id,file_name,mime_type,byte_size,file_data)
  values(v_message,v_chat,coalesce(nullif(trim(p_file_name),''),'attachment'),coalesce(nullif(trim(p_mime_type),''),'application/octet-stream'),octet_length(v_raw),v_raw)
  returning id into v_attachment;
  update public.rr_customer_chat_messages_v9433 set payload=payload||jsonb_build_object('attachment_id',v_attachment) where id=v_message;
  return jsonb_build_object('message_id',v_message,'attachment_id',v_attachment,'message_type',v_type,'byte_size',octet_length(v_raw));
end
$function$;

create or replace function public.rr_market_partner_customer_chat_attachment_session_v67(
  p_session_token text,p_device_id text,p_attachment_id uuid
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare v_ctx jsonb; v_chat uuid; v_attachment public.rr_customer_chat_attachments_v9434%rowtype;
begin
  v_ctx:=public.rr_market_partner_customer_session_validate_v67(p_session_token,p_device_id); v_chat:=(v_ctx->>'chat_id')::uuid;
  select a.* into v_attachment from public.rr_customer_chat_attachments_v9434 a where a.id=p_attachment_id and a.chat_id=v_chat;
  if v_attachment.id is null then raise exception 'Attachment not found.'; end if;
  return jsonb_build_object('attachment_id',v_attachment.id,'file_name',v_attachment.file_name,'mime_type',v_attachment.mime_type,'byte_size',v_attachment.byte_size,'base64',encode(v_attachment.file_data,'base64'));
end
$function$;

create or replace function public.rr_market_partner_customer_chat_delete_message_session_v67(
  p_session_token text,p_device_id text,p_message_id uuid
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare v_ctx jsonb; v_chat uuid; v_customer uuid; v_message public.rr_customer_chat_messages_v9433%rowtype;
begin
  v_ctx:=public.rr_market_partner_customer_session_validate_v67(p_session_token,p_device_id);
  v_chat:=(v_ctx->>'chat_id')::uuid; v_customer:=(v_ctx->>'partner_customer_id')::uuid;
  select m.* into v_message from public.rr_customer_chat_messages_v9433 m where m.id=p_message_id and m.chat_id=v_chat and m.channel='GROUP';
  if v_message.id is null then raise exception 'Message not found.'; end if;
  update public.rr_customer_chat_messages_v9433 set archived_at=coalesce(archived_at,clock_timestamp()),archive_reason='PARTNER_CUSTOMER_DELETE',archive_meta=jsonb_build_object('partner_customer_id',v_customer) where id=v_message.id;
  insert into public.rr_customer_chat_archive_v59(message_id,chat_id,archived_at,archived_reason,archived_actor_kind)
  values(v_message.id,v_chat,clock_timestamp(),'PARTNER_CUSTOMER_DELETE','CUSTOMER')
  on conflict(message_id) do update set archived_at=excluded.archived_at,archived_reason=excluded.archived_reason,archived_actor_kind=excluded.archived_actor_kind,restored_at=null,restored_by=null;
  return jsonb_build_object('ok',true,'archived',true);
end
$function$;

create or replace function public.rr_market_partner_customer_chat_disappearing_get_session_v67(
  p_session_token text,p_device_id text
) returns jsonb language plpgsql security definer set search_path=''
as $function$ declare v_ctx jsonb; v_chat uuid; v_days int; begin
  v_ctx:=public.rr_market_partner_customer_session_validate_v67(p_session_token,p_device_id); v_chat:=(v_ctx->>'chat_id')::uuid;
  select d.days into v_days from public.rr_customer_chat_disappearing_v59 d where d.chat_id=v_chat;
  return jsonb_build_object('days',v_days);
end $function$;

create or replace function public.rr_market_partner_customer_chat_disappearing_set_session_v67(
  p_session_token text,p_device_id text,p_days integer
) returns jsonb language plpgsql security definer set search_path=''
as $function$ declare v_ctx jsonb; v_chat uuid; begin
  v_ctx:=public.rr_market_partner_customer_session_validate_v67(p_session_token,p_device_id); v_chat:=(v_ctx->>'chat_id')::uuid;
  if p_days is not null and p_days not in(7,15,30,60,90,180,365) then raise exception 'Invalid disappearing period.'; end if;
  insert into public.rr_customer_chat_disappearing_v59(chat_id,days,updated_at) values(v_chat,p_days,now())
  on conflict(chat_id) do update set days=excluded.days,updated_at=now();
  return jsonb_build_object('ok',true,'days',p_days);
end $function$;

create or replace function public.rr_market_partner_customer_chat_disappearing_cleanup_session_v67(
  p_session_token text,p_device_id text
) returns jsonb language plpgsql security definer set search_path=''
as $function$ declare v_ctx jsonb; v_chat uuid; v_days int; v_row record; v_count int:=0; begin
  v_ctx:=public.rr_market_partner_customer_session_validate_v67(p_session_token,p_device_id); v_chat:=(v_ctx->>'chat_id')::uuid;
  select d.days into v_days from public.rr_customer_chat_disappearing_v59 d where d.chat_id=v_chat;
  if v_days is null then return jsonb_build_object('ok',true,'archived',0); end if;
  for v_row in select m.id from public.rr_customer_chat_messages_v9433 m
    where m.chat_id=v_chat and m.channel='GROUP' and m.archived_at is null and m.created_at<clock_timestamp()-(v_days||' days')::interval
  loop
    update public.rr_customer_chat_messages_v9433 set archived_at=clock_timestamp(),archive_reason='DISAPPEARING_'||v_days||'_DAYS' where id=v_row.id;
    insert into public.rr_customer_chat_archive_v59(message_id,chat_id,archived_at,archived_reason,archived_actor_kind)
    values(v_row.id,v_chat,clock_timestamp(),'DISAPPEARING_'||v_days||'_DAYS','SYSTEM')
    on conflict(message_id) do update set archived_at=excluded.archived_at,archived_reason=excluded.archived_reason,archived_actor_kind='SYSTEM',restored_at=null,restored_by=null;
    v_count:=v_count+1;
  end loop;
  return jsonb_build_object('ok',true,'archived',v_count,'days',v_days);
end $function$;

create or replace function public.rr_market_partner_customer_chat_media_files_session_v67(
  p_session_token text,p_device_id text,p_limit integer default 500,p_offset integer default 0
) returns table(message_id uuid,attachment_id uuid,file_name text,mime_type text,byte_size integer,message_type text,sender_name text,created_at timestamptz,payload jsonb)
language plpgsql security definer set search_path=''
as $function$ declare v_ctx jsonb; v_chat uuid; begin
  v_ctx:=public.rr_market_partner_customer_session_validate_v67(p_session_token,p_device_id); v_chat:=(v_ctx->>'chat_id')::uuid;
  return query select m.id,a.id,a.file_name,a.mime_type,a.byte_size,m.message_type,m.sender_name,m.created_at,coalesce(m.payload,'{}'::jsonb)-'thumb_base64'
  from public.rr_customer_chat_messages_v9433 m join public.rr_customer_chat_attachments_v9434 a on a.message_id=m.id and a.chat_id=m.chat_id
  where m.chat_id=v_chat and m.channel='GROUP' and m.archived_at is null order by m.created_at desc
  limit least(greatest(coalesce(p_limit,500),1),500) offset greatest(coalesce(p_offset,0),0);
end $function$;

create or replace function public.rr_market_partner_customer_chat_resend_session_v67(
  p_session_token text,p_device_id text,p_attachment_ids uuid[]
) returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_ctx jsonb; v_chat uuid; v_name text; v_id uuid; v_aid uuid; v_source uuid; v_attachment public.rr_customer_chat_attachments_v9434%rowtype; v_old public.rr_customer_chat_messages_v9433%rowtype; v_count int:=0;
begin
  v_ctx:=public.rr_market_partner_customer_session_validate_v67(p_session_token,p_device_id); v_chat:=(v_ctx->>'chat_id')::uuid; v_name:=v_ctx->>'customer_name';
  if coalesce(array_length(p_attachment_ids,1),0)<1 or array_length(p_attachment_ids,1)>50 then raise exception 'Select 1 to 50 media files.'; end if;
  foreach v_source in array p_attachment_ids loop
    select a.* into v_attachment from public.rr_customer_chat_attachments_v9434 a where a.id=v_source and a.chat_id=v_chat;
    select m.* into v_old from public.rr_customer_chat_messages_v9433 m where m.id=v_attachment.message_id and m.chat_id=v_chat and m.channel='GROUP' and m.archived_at is null;
    if v_attachment.id is null or v_old.id is null then raise exception 'Group media not available.'; end if;
    v_id:=gen_random_uuid(); v_aid:=gen_random_uuid();
    insert into public.rr_customer_chat_messages_v9433(id,chat_id,channel,sender_kind,sender_name,message_type,payload,created_at)
    values(v_id,v_chat,'GROUP','CUSTOMER',coalesce(nullif(trim(v_name),''),'Customer'),'ATTACHMENT',
      (coalesce(v_old.payload,'{}'::jsonb)-'attachment_id')||jsonb_build_object('attachment_id',v_aid,'media_kind','MEDIA_FILES_RESEND'),clock_timestamp()+(v_count*interval '1 millisecond'));
    insert into public.rr_customer_chat_attachments_v9434(id,message_id,chat_id,file_name,mime_type,byte_size,file_data)
    values(v_aid,v_id,v_chat,v_attachment.file_name,v_attachment.mime_type,v_attachment.byte_size,v_attachment.file_data);
    insert into public.rr_customer_chat_thumbnails_v51(attachment_id,mime_type,byte_size,thumb_data,created_at)
    select v_aid,t.mime_type,t.byte_size,t.thumb_data,clock_timestamp() from public.rr_customer_chat_thumbnails_v51 t where t.attachment_id=v_source
    on conflict(attachment_id) do nothing;
    v_count:=v_count+1;
  end loop;
  return jsonb_build_object('ok',true,'sent',v_count);
end $function$;

create or replace function public.rr_market_partner_customer_chat_thumbnail_get_session_v67(
  p_session_token text,p_device_id text,p_attachment_id uuid
) returns jsonb language plpgsql security definer set search_path=''
as $function$ declare v_ctx jsonb; v_chat uuid; v_thumb public.rr_customer_chat_thumbnails_v51%rowtype; begin
  v_ctx:=public.rr_market_partner_customer_session_validate_v67(p_session_token,p_device_id); v_chat:=(v_ctx->>'chat_id')::uuid;
  if not exists(select 1 from public.rr_customer_chat_attachments_v9434 a where a.id=p_attachment_id and a.chat_id=v_chat) then raise exception 'Attachment not found.'; end if;
  select t.* into v_thumb from public.rr_customer_chat_thumbnails_v51 t where t.attachment_id=p_attachment_id;
  if v_thumb.attachment_id is null then return null; end if;
  return jsonb_build_object('attachment_id',v_thumb.attachment_id,'mime_type',v_thumb.mime_type,'byte_size',v_thumb.byte_size,'base64',encode(v_thumb.thumb_data,'base64'));
end $function$;

create or replace function public.rr_market_partner_customer_chat_thumbnail_put_session_v67(
  p_session_token text,p_device_id text,p_attachment_id uuid,p_mime_type text,p_base64 text
) returns jsonb language plpgsql security definer set search_path=''
as $function$ declare v_ctx jsonb; v_chat uuid; v_raw bytea; begin
  v_ctx:=public.rr_market_partner_customer_session_validate_v67(p_session_token,p_device_id); v_chat:=(v_ctx->>'chat_id')::uuid;
  if not exists(select 1 from public.rr_customer_chat_attachments_v9434 a where a.id=p_attachment_id and a.chat_id=v_chat and lower(coalesce(a.mime_type,'')) like 'image/%') then raise exception 'Image attachment not found.'; end if;
  v_raw:=decode(coalesce(p_base64,''),'base64'); if octet_length(v_raw)<1 or octet_length(v_raw)>90000 then raise exception 'Thumbnail too large.'; end if;
  insert into public.rr_customer_chat_thumbnails_v51(attachment_id,mime_type,byte_size,thumb_data)
  values(p_attachment_id,coalesce(nullif(p_mime_type,''),'image/jpeg'),octet_length(v_raw),v_raw)
  on conflict(attachment_id) do update set mime_type=excluded.mime_type,byte_size=excluded.byte_size,thumb_data=excluded.thumb_data;
  return jsonb_build_object('ok',true,'attachment_id',p_attachment_id,'byte_size',octet_length(v_raw));
end $function$;

create or replace function public.rr_market_partner_customer_chat_thumbnail_batch_session_v67(
  p_session_token text,p_device_id text,p_attachment_ids uuid[]
) returns table(attachment_id uuid,mime_type text,byte_size integer,base64 text)
language plpgsql security definer set search_path=''
as $function$ declare v_ctx jsonb; v_chat uuid; begin
  v_ctx:=public.rr_market_partner_customer_session_validate_v67(p_session_token,p_device_id); v_chat:=(v_ctx->>'chat_id')::uuid;
  return query select t.attachment_id,t.mime_type,t.byte_size,encode(t.thumb_data,'base64')
  from public.rr_customer_chat_thumbnails_v51 t join public.rr_customer_chat_attachments_v9434 a on a.id=t.attachment_id
  where a.chat_id=v_chat and t.attachment_id=any(coalesce(p_attachment_ids,array[]::uuid[])) limit 200;
end $function$;

create or replace function public.rr_market_partner_customer_chat_thumbnail_policy_session_v67(
  p_session_token text,p_device_id text
) returns jsonb language plpgsql security definer set search_path=''
as $function$ declare v_ctx jsonb; begin
  v_ctx:=public.rr_market_partner_customer_session_validate_v67(p_session_token,p_device_id);
  return jsonb_build_object('max_edge_px',480,'jpeg_quality',0.72,'max_bytes',90000,'format','image/jpeg','version',67);
end $function$;

-- Owner/distributor chat endpoints now write/read the shared chat model.
create or replace function public.rr_market_partner_chat_send_v67(
  p_session_token text,p_device_id text,p_lane text,p_partner_customer_id uuid default null,
  p_message text default null,p_attachment jsonb default null
) returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_ctx jsonb; v_owner uuid; v_lane text:=upper(trim(coalesce(p_lane,''))); v_chat uuid; v_channel text; v_name text;
  v_message uuid; v_attachment uuid; v_raw bytea; v_data_url text; v_mime text; v_file text; v_payload jsonb:='{}'::jsonb;
begin
  v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id); v_owner:=(v_ctx->>'owner_customer_id')::uuid;
  if v_lane not in('CUSTOMER_GROUP','CUSTOMER_DIRECT','REDZED') then raise exception 'Invalid private chat lane.'; end if;
  if nullif(trim(coalesce(p_message,'')),'') is null and (p_attachment is null or p_attachment='null'::jsonb) then raise exception 'Message or attachment is required.'; end if;
  if v_lane='REDZED' then
    v_chat:=public.rr_market_partner_relation_chat_resolve_v67(v_owner,null,'DISTRIBUTOR_REDZED'); v_channel:='GROUP';
  else
    v_chat:=public.rr_market_partner_relation_chat_resolve_v67(v_owner,p_partner_customer_id,'DISTRIBUTOR_CUSTOMER');
    v_channel:=case when v_lane='CUSTOMER_DIRECT' then 'SUPERADMIN_PRIVATE' else 'GROUP' end;
  end if;
  select c.customer_name into v_name from public.rr_customers c where c.id=v_owner;
  insert into public.rr_customer_chat_messages_v9433(chat_id,channel,sender_kind,sender_customer_id,sender_name,message_type,body,payload)
  values(v_chat,v_channel,'DISTRIBUTOR',v_owner,coalesce(nullif(trim(v_name),''),'Distributor'),
    case when lower(coalesce(p_attachment->>'type','')) like 'audio/%' then 'VOICE' when p_attachment is not null and p_attachment<>'null'::jsonb then 'ATTACHMENT' else 'TEXT' end,
    nullif(trim(coalesce(p_message,'')),''),jsonb_build_object('relation_scope',case when v_lane='REDZED' then 'DISTRIBUTOR_REDZED' else 'DISTRIBUTOR_CUSTOMER' end,'lane',v_lane))
  returning id into v_message;
  if p_attachment is not null and p_attachment<>'null'::jsonb then
    v_data_url:=p_attachment->>'data_url';
    if v_data_url !~ '^data:[^;]+;base64,' then raise exception 'Attachment data is invalid.'; end if;
    v_raw:=decode(split_part(v_data_url,',',2),'base64');
    if octet_length(v_raw)<1 or octet_length(v_raw)>6291456 then raise exception 'Attachment must be 1 byte to 6 MB.'; end if;
    v_mime:=coalesce(nullif(trim(p_attachment->>'type'),''),split_part(split_part(v_data_url,';',1),':',2),'application/octet-stream');
    v_file:=coalesce(nullif(trim(p_attachment->>'name'),''),'attachment');
    insert into public.rr_customer_chat_attachments_v9434(message_id,chat_id,file_name,mime_type,byte_size,file_data)
    values(v_message,v_chat,v_file,v_mime,octet_length(v_raw),v_raw) returning id into v_attachment;
    update public.rr_customer_chat_messages_v9433 set payload=payload||jsonb_build_object('attachment_id',v_attachment,'file_name',v_file,'mime_type',v_mime,'byte_size',octet_length(v_raw)) where id=v_message;
  end if;
  return jsonb_build_object('ok',true,'id',v_message,'lane',v_lane,'attachment_id',v_attachment);
end $function$;

create or replace function public.rr_market_partner_chat_messages_v67(
  p_session_token text,p_device_id text,p_lane text,p_partner_customer_id uuid default null
) returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_ctx jsonb; v_owner uuid; v_lane text:=upper(trim(coalesce(p_lane,''))); v_chat uuid; v_channel text;
begin
  v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id); v_owner:=(v_ctx->>'owner_customer_id')::uuid;
  if v_lane not in('CUSTOMER_GROUP','CUSTOMER_DIRECT','REDZED') then raise exception 'Invalid private chat lane.'; end if;
  if v_lane='REDZED' then
    v_chat:=public.rr_market_partner_relation_chat_resolve_v67(v_owner,null,'DISTRIBUTOR_REDZED'); v_channel:='GROUP';
  else
    v_chat:=public.rr_market_partner_relation_chat_resolve_v67(v_owner,p_partner_customer_id,'DISTRIBUTOR_CUSTOMER');
    v_channel:=case when v_lane='CUSTOMER_DIRECT' then 'SUPERADMIN_PRIVATE' else 'GROUP' end;
  end if;
  return coalesce((select jsonb_agg(x order by (x->>'created_at')::timestamptz) from(
    select jsonb_build_object(
      'id',m.id,'actor',case when m.sender_kind='CUSTOMER' then 'CUSTOMER' when v_lane='REDZED' and m.sender_kind in('STAFF','SYSTEM') then 'REDZED' else 'DISTRIBUTOR' end,
      'message',m.body,'created_at',m.created_at,
      'attachment',(select jsonb_build_object('attachment_id',a.id,'name',a.file_name,'type',a.mime_type,'byte_size',a.byte_size,
        'data_url','data:'||a.mime_type||';base64,'||encode(a.file_data,'base64')) from public.rr_customer_chat_attachments_v9434 a where a.message_id=m.id limit 1)
    ) x from public.rr_customer_chat_messages_v9433 m
    where m.chat_id=v_chat and m.channel=v_channel and m.archived_at is null order by m.created_at desc limit 200
  ) q),'[]'::jsonb);
end $function$;

create or replace function public.rr_market_partner_chat_delete_v67(
  p_session_token text,p_device_id text,p_lane text,p_partner_customer_id uuid,p_message_id uuid
) returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_ctx jsonb; v_owner uuid; v_lane text:=upper(trim(coalesce(p_lane,''))); v_chat uuid; v_channel text; v_message uuid;
begin
  v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id); v_owner:=(v_ctx->>'owner_customer_id')::uuid;
  if v_lane='REDZED' then v_chat:=public.rr_market_partner_relation_chat_resolve_v67(v_owner,null,'DISTRIBUTOR_REDZED'); v_channel:='GROUP';
  elsif v_lane in('CUSTOMER_GROUP','CUSTOMER_DIRECT') then v_chat:=public.rr_market_partner_relation_chat_resolve_v67(v_owner,p_partner_customer_id,'DISTRIBUTOR_CUSTOMER'); v_channel:=case when v_lane='CUSTOMER_DIRECT' then 'SUPERADMIN_PRIVATE' else 'GROUP' end;
  else raise exception 'Invalid private chat lane.'; end if;
  select m.id into v_message from public.rr_customer_chat_messages_v9433 m where m.id=p_message_id and m.chat_id=v_chat and m.channel=v_channel;
  if v_message is null then raise exception 'Message not found.'; end if;
  update public.rr_customer_chat_messages_v9433 set archived_at=coalesce(archived_at,clock_timestamp()),archived_by=v_owner,archive_reason='DISTRIBUTOR_DELETE',archive_meta=jsonb_build_object('lane',v_lane) where id=v_message;
  insert into public.rr_customer_chat_archive_v59(message_id,chat_id,archived_at,archived_reason,archived_actor_kind,archived_actor_customer_id)
  values(v_message,v_chat,clock_timestamp(),'DISTRIBUTOR_DELETE','DISTRIBUTOR',v_owner)
  on conflict(message_id) do update set archived_at=excluded.archived_at,archived_reason=excluded.archived_reason,archived_actor_kind=excluded.archived_actor_kind,archived_actor_customer_id=excluded.archived_actor_customer_id,restored_at=null,restored_by=null;
  return jsonb_build_object('ok',true,'archived',true);
end $function$;

-- Migrate prior text chat events once, without continuing the parallel event-chat architecture.
do $block$
declare v record; v_chat uuid; v_channel text; v_kind text;
begin
  for v in select e.* from public.rr_market_partner_event_v67 e where e.event_type='CHAT_MESSAGE'
    and not exists(select 1 from public.rr_customer_chat_messages_v9433 m where m.payload->>'source_partner_event_id'=e.id::text)
    order by e.created_at
  loop
    v_kind:=case when v.payload->>'lane'='REDZED' then 'DISTRIBUTOR_REDZED' else 'DISTRIBUTOR_CUSTOMER' end;
    begin
      v_chat:=public.rr_market_partner_relation_chat_resolve_v67(v.owner_customer_id,
        case when v_kind='DISTRIBUTOR_CUSTOMER' then nullif(v.payload->>'customer_id','')::uuid else null end,v_kind);
      v_channel:=case when v.payload->>'lane'='CUSTOMER_DIRECT' then 'SUPERADMIN_PRIVATE' else 'GROUP' end;
      insert into public.rr_customer_chat_messages_v9433(chat_id,channel,sender_kind,sender_name,message_type,body,payload,created_at)
      values(v_chat,v_channel,case when v.actor_kind='CUSTOMER' then 'CUSTOMER' when v.actor_kind='DISTRIBUTOR' then 'DISTRIBUTOR' else 'SYSTEM' end,
        case when v.actor_kind='CUSTOMER' then 'Customer' when v.actor_kind='DISTRIBUTOR' then 'Distributor' else coalesce(v.actor_kind,'System') end,
        'TEXT',v.note,coalesce(v.payload,'{}'::jsonb)||jsonb_build_object('source_partner_event_id',v.id,'legacy_attachment',v.payload->'attachment'),v.created_at);
    exception when others then
      null;
    end;
  end loop;
end
$block$;

revoke all on function public.rr_market_partner_relation_chat_resolve_v67(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.rr_market_partner_customer_session_issue_v67(text,text) from public;
revoke all on function public.rr_market_partner_customer_session_validate_v67(text,text) from public;
revoke all on function public.rr_market_partner_customer_chat_messages_session_v67(text,text,text,integer) from public;
revoke all on function public.rr_market_partner_customer_chat_send_session_v67(text,text,text,text,text,jsonb,uuid) from public;
revoke all on function public.rr_market_partner_customer_chat_upload_session_v67(text,text,text,text,text,text,text,uuid,jsonb) from public;
revoke all on function public.rr_market_partner_customer_chat_attachment_session_v67(text,text,uuid) from public;
revoke all on function public.rr_market_partner_customer_chat_delete_message_session_v67(text,text,uuid) from public;
revoke all on function public.rr_market_partner_customer_chat_disappearing_get_session_v67(text,text) from public;
revoke all on function public.rr_market_partner_customer_chat_disappearing_set_session_v67(text,text,integer) from public;
revoke all on function public.rr_market_partner_customer_chat_disappearing_cleanup_session_v67(text,text) from public;
revoke all on function public.rr_market_partner_customer_chat_media_files_session_v67(text,text,integer,integer) from public;
revoke all on function public.rr_market_partner_customer_chat_resend_session_v67(text,text,uuid[]) from public;
revoke all on function public.rr_market_partner_customer_chat_thumbnail_get_session_v67(text,text,uuid) from public;
revoke all on function public.rr_market_partner_customer_chat_thumbnail_put_session_v67(text,text,uuid,text,text) from public;
revoke all on function public.rr_market_partner_customer_chat_thumbnail_batch_session_v67(text,text,uuid[]) from public;
revoke all on function public.rr_market_partner_customer_chat_thumbnail_policy_session_v67(text,text) from public;
revoke all on function public.rr_market_partner_chat_send_v67(text,text,text,uuid,text,jsonb) from public;
revoke all on function public.rr_market_partner_chat_messages_v67(text,text,text,uuid) from public;
revoke all on function public.rr_market_partner_chat_delete_v67(text,text,text,uuid,uuid) from public;

grant execute on function public.rr_market_partner_customer_session_issue_v67(text,text) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_session_validate_v67(text,text) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_chat_messages_session_v67(text,text,text,integer) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_chat_send_session_v67(text,text,text,text,text,jsonb,uuid) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_chat_upload_session_v67(text,text,text,text,text,text,text,uuid,jsonb) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_chat_attachment_session_v67(text,text,uuid) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_chat_delete_message_session_v67(text,text,uuid) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_chat_disappearing_get_session_v67(text,text) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_chat_disappearing_set_session_v67(text,text,integer) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_chat_disappearing_cleanup_session_v67(text,text) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_chat_media_files_session_v67(text,text,integer,integer) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_chat_resend_session_v67(text,text,uuid[]) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_chat_thumbnail_get_session_v67(text,text,uuid) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_chat_thumbnail_put_session_v67(text,text,uuid,text,text) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_chat_thumbnail_batch_session_v67(text,text,uuid[]) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_chat_thumbnail_policy_session_v67(text,text) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_chat_send_v67(text,text,text,uuid,text,jsonb) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_chat_messages_v67(text,text,text,uuid) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_chat_delete_v67(text,text,text,uuid,uuid) to anon,authenticated,service_role;
