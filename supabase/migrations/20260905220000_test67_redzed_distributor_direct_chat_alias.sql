-- TEST67 only: REDZED <-> Distributor is not a second chat architecture.
-- A distributor is already a direct REDZED customer, so the partner relation
-- aliases the existing direct rr_customer_chat_v9433 row. Distributor/customer
-- chats remain separate private relation rows.

do $migration$
declare
  v_row record;
  v_direct_chat uuid;
  v_old_chat uuid;
begin
  for v_row in
    select r.id,r.owner_customer_id,r.chat_id,c.customer_name,c.mobile
    from public.rr_market_partner_relation_chat_v67 r
    join public.rr_customers c on c.id=r.owner_customer_id
    where r.relation_kind='DISTRIBUTOR_REDZED'
  loop
    v_old_chat:=v_row.chat_id;
    select ch.id into v_direct_chat
    from public.rr_customer_chat_v9433 ch
    where ch.customer_id=v_row.owner_customer_id
      and ch.data_mode='TEST'
    order by (ch.status='OPEN') desc,ch.updated_at desc,ch.created_at desc
    limit 1;

    if v_direct_chat is null then
      insert into public.rr_customer_chat_v9433(
        customer_id,customer_name,mobile,data_mode,status
      ) values(
        v_row.owner_customer_id,v_row.customer_name,v_row.mobile,'TEST','OPEN'
      )
      on conflict(customer_id,data_mode) do update
        set customer_name=excluded.customer_name,
            mobile=excluded.mobile,
            status='OPEN',
            updated_at=now()
      returning id into v_direct_chat;
    end if;

    if v_old_chat<>v_direct_chat then
      update public.rr_customer_chat_messages_v9433
      set chat_id=v_direct_chat
      where chat_id=v_old_chat;

      update public.rr_customer_chat_attachments_v9434
      set chat_id=v_direct_chat
      where chat_id=v_old_chat;

      update public.rr_customer_chat_archive_v59
      set chat_id=v_direct_chat
      where chat_id=v_old_chat;

      update public.rr_market_partner_relation_chat_v67
      set chat_id=v_direct_chat,updated_at=now()
      where id=v_row.id;

      update public.rr_customer_chat_v9433
      set status='ARCHIVED',updated_at=now()
      where id=v_old_chat;
    end if;
  end loop;
end
$migration$;

insert into public.rr_customer_chat_members_v9433(
  chat_id,profile_id,is_active,added_by
)
select r.chat_id,p.id,true,p.id
from public.rr_market_partner_relation_chat_v67 r
cross join public.rr_user_profiles p
where r.relation_kind='DISTRIBUTOR_REDZED'
  and r.status='ACTIVE'
  and p.is_active
  and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE'
  and upper(coalesce(p.role_code,'')) in(
    'SUPER_ADMIN','OWNER','ADMIN','ACCOUNTANT','ACCOUNTS','ACCOUNT','SALES','SALESMAN'
  )
on conflict(chat_id,profile_id) do update
  set is_active=true,removed_at=null,removed_by=null;

create or replace function public.rr_market_partner_relation_chat_resolve_v67(
  p_owner_customer_id uuid,
  p_partner_customer_id uuid default null,
  p_relation_kind text default 'DISTRIBUTOR_CUSTOMER'
) returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_kind text:=upper(trim(coalesce(p_relation_kind,'')));
  v_chat uuid;
  v_name text;
  v_mobile text;
  v_created boolean:=false;
begin
  if v_kind not in('DISTRIBUTOR_CUSTOMER','DISTRIBUTOR_REDZED') then
    raise exception 'Invalid distributor chat relation.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      p_owner_customer_id::text||'|'||coalesce(p_partner_customer_id::text,'REDZED')||'|'||v_kind,
      83
    )
  );

  if v_kind='DISTRIBUTOR_CUSTOMER' then
    select r.chat_id into v_chat
    from public.rr_market_partner_relation_chat_v67 r
    where r.owner_customer_id=p_owner_customer_id
      and r.partner_customer_id=p_partner_customer_id
      and r.relation_kind=v_kind
      and r.status='ACTIVE'
    limit 1;
    if v_chat is not null then return v_chat; end if;

    select c.private_name,c.private_mobile into v_name,v_mobile
    from public.rr_market_partner_customer_v67 c
    where c.id=p_partner_customer_id
      and c.owner_customer_id=p_owner_customer_id
      and c.status='ACTIVE'
      and c.data_mode='TEST';
    if v_name is null then
      raise exception 'Distributor customer relation is unavailable.';
    end if;

    insert into public.rr_customer_chat_v9433(
      customer_id,customer_name,mobile,data_mode,status
    ) values(null,v_name,v_mobile,'TEST','OPEN')
    returning id into v_chat;
    v_created:=true;
  else
    select r.chat_id into v_chat
    from public.rr_market_partner_relation_chat_v67 r
    join public.rr_customer_chat_v9433 ch on ch.id=r.chat_id
    where r.owner_customer_id=p_owner_customer_id
      and r.relation_kind=v_kind
      and r.status='ACTIVE'
      and ch.customer_id=p_owner_customer_id
    limit 1;
    if v_chat is not null then return v_chat; end if;

    select c.customer_name,c.mobile into v_name,v_mobile
    from public.rr_customers c
    where c.id=p_owner_customer_id and c.is_active;
    if v_name is null then raise exception 'Distributor relation is unavailable.'; end if;

    insert into public.rr_customer_chat_v9433(
      customer_id,customer_name,mobile,data_mode,status
    ) values(p_owner_customer_id,v_name,v_mobile,'TEST','OPEN')
    on conflict(customer_id,data_mode) do update
      set customer_name=excluded.customer_name,
          mobile=excluded.mobile,
          status='OPEN',
          updated_at=now()
    returning id into v_chat;

    insert into public.rr_customer_chat_members_v9433(
      chat_id,profile_id,is_active,added_by
    )
    select v_chat,p.id,true,p.id
    from public.rr_user_profiles p
    where p.is_active
      and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE'
      and upper(coalesce(p.role_code,'')) in(
        'SUPER_ADMIN','OWNER','ADMIN','ACCOUNTANT','ACCOUNTS','ACCOUNT','SALES','SALESMAN'
      )
    on conflict(chat_id,profile_id) do update
      set is_active=true,removed_at=null,removed_by=null;
  end if;

  begin
    insert into public.rr_market_partner_relation_chat_v67(
      relation_kind,owner_customer_id,partner_customer_id,chat_id
    ) values(
      v_kind,p_owner_customer_id,
      case when v_kind='DISTRIBUTOR_CUSTOMER' then p_partner_customer_id else null end,
      v_chat
    );
  exception when unique_violation then
    if v_created then
      delete from public.rr_customer_chat_v9433 where id=v_chat;
    end if;
    if v_kind='DISTRIBUTOR_CUSTOMER' then
      select r.chat_id into v_chat
      from public.rr_market_partner_relation_chat_v67 r
      where r.owner_customer_id=p_owner_customer_id
        and r.partner_customer_id=p_partner_customer_id
        and r.relation_kind=v_kind
      limit 1;
    else
      select r.chat_id into v_chat
      from public.rr_market_partner_relation_chat_v67 r
      where r.owner_customer_id=p_owner_customer_id
        and r.relation_kind=v_kind
      limit 1;
    end if;
  end;
  return v_chat;
end
$function$;

-- REDZED staff uses this only to recognise which ordinary direct-customer
-- inbox rows are distributors and to render their TEST67 batch journey.
create or replace function public.rr_market_redzed_staff_distributor_relations_v83()
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
begin
  perform public.rr_market_assert_sales_actor_v9420();
  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'chat_id',r.chat_id,
        'owner_customer_id',r.owner_customer_id,
        'distributor_name',c.customer_name,
        'batches',coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id',b.id,
              'batch_ref',b.batch_ref,
              'status',b.status,
              'pi_ref',b.pi_ref,
              'ci_ref',b.ci_ref,
              'order_count',(select count(*) from public.rr_market_partner_batch_member_v67 bm where bm.batch_id=b.id),
              'submitted_at',b.submitted_at
            ) order by b.submitted_at desc
          )
          from public.rr_market_partner_batch_v67 b
          where b.owner_customer_id=r.owner_customer_id
            and b.data_mode='TEST'
        ),'[]'::jsonb)
      ) order by c.customer_name
    )
    from public.rr_market_partner_relation_chat_v67 r
    join public.rr_customers c on c.id=r.owner_customer_id
    where r.relation_kind='DISTRIBUTOR_REDZED'
      and r.status='ACTIVE'
      and c.is_active
  ),'[]'::jsonb);
end
$function$;

-- In the REDZED lane, messages written through the distributor's normal
-- direct-customer session are still distributor messages, never a downstream
-- distributor-customer identity.
create or replace function public.rr_market_partner_chat_messages_v67(
  p_session_token text,
  p_device_id text,
  p_lane text,
  p_partner_customer_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_ctx jsonb;
  v_owner uuid;
  v_lane text:=upper(trim(coalesce(p_lane,'')));
  v_chat uuid;
  v_channel text;
begin
  v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
  v_owner:=(v_ctx->>'owner_customer_id')::uuid;
  if v_lane not in('CUSTOMER_GROUP','CUSTOMER_DIRECT','REDZED') then
    raise exception 'Invalid private chat lane.';
  end if;
  if v_lane='REDZED' then
    v_chat:=public.rr_market_partner_relation_chat_resolve_v67(
      v_owner,null,'DISTRIBUTOR_REDZED'
    );
    v_channel:='GROUP';
  else
    v_chat:=public.rr_market_partner_relation_chat_resolve_v67(
      v_owner,p_partner_customer_id,'DISTRIBUTOR_CUSTOMER'
    );
    v_channel:=case when v_lane='CUSTOMER_DIRECT'
      then 'SUPERADMIN_PRIVATE' else 'GROUP' end;
  end if;
  return coalesce((
    select jsonb_agg(x order by (x->>'created_at')::timestamptz)
    from(
      select jsonb_build_object(
        'id',m.id,
        'actor',case
          when v_lane='REDZED' and m.sender_kind in('STAFF','SYSTEM') then 'REDZED'
          when v_lane='REDZED' then 'DISTRIBUTOR'
          when m.sender_kind='CUSTOMER' then 'CUSTOMER'
          else 'DISTRIBUTOR'
        end,
        'message',m.body,
        'created_at',m.created_at,
        'attachment',(
          select jsonb_build_object(
            'attachment_id',a.id,'name',a.file_name,'type',a.mime_type,
            'byte_size',a.byte_size,
            'data_url','data:'||a.mime_type||';base64,'||encode(a.file_data,'base64')
          )
          from public.rr_customer_chat_attachments_v9434 a
          where a.message_id=m.id
          limit 1
        )
      ) x
      from public.rr_customer_chat_messages_v9433 m
      where m.chat_id=v_chat
        and m.channel=v_channel
        and m.archived_at is null
      order by m.created_at desc
      limit 200
    ) q
  ),'[]'::jsonb);
end
$function$;

revoke all on function public.rr_market_partner_relation_chat_resolve_v67(
  uuid,uuid,text
) from public,anon,authenticated;
revoke all on function public.rr_market_redzed_staff_distributor_relations_v83()
  from public,anon;
revoke all on function public.rr_market_partner_chat_messages_v67(
  text,text,text,uuid
) from public;

grant execute on function public.rr_market_redzed_staff_distributor_relations_v83()
  to authenticated,service_role;
grant execute on function public.rr_market_partner_chat_messages_v67(
  text,text,text,uuid
) to anon,authenticated,service_role;

comment on function public.rr_market_redzed_staff_distributor_relations_v83()
is 'TEST67: maps distributor batch journeys onto existing REDZED direct-customer chat rows without exposing downstream customer identity.';
