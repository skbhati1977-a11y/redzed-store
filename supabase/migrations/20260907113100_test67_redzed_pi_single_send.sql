-- TEST67: one canonical REDZED <-> distributor journey card and one-shot PI send.

create or replace function public.rr_market_staff_propose_batch_v67(
  p_batch_id uuid,
  p_line_proposals jsonb,
  p_pi_ref text
) returns jsonb
language plpgsql
security definer
set search_path=public
as $function$
declare
  v_line jsonb;
  v_line_id uuid;
  v_qty integer;
  v_owner uuid;
  v_ref text;
  v_seq integer;
  v_kind text;
begin
  perform public.rr_market_assert_sales_actor_v9420();

  select owner_customer_id,sequence_no,batch_kind,pi_ref
    into v_owner,v_seq,v_kind,v_ref
  from public.rr_market_partner_batch_v67
  where id=p_batch_id
    and data_mode='TEST'
    and status in ('SUBMITTED','PI_PROPOSED','WAITING_CONFIRMATION')
  for update;

  if v_owner is null then
    raise exception 'Requirement cannot receive a PI proposal.';
  end if;

  -- A stale tab, double tap, or a second device must not create another PI
  -- event or mutate the already-delivered allocation.
  if nullif(trim(coalesce(v_ref,'')),'') is not null then
    return public.rr_market_staff_batch_detail_v67(p_batch_id)
      || jsonb_build_object('already_sent',true);
  end if;

  v_ref:=coalesce(
    nullif(trim(p_pi_ref),''),
    case when v_kind='CONSOLIDATED' then 'CONSOLIDATED PI ' else 'REDZED PI ' end||v_seq
  );

  for v_line in select value from jsonb_array_elements(p_line_proposals)
  loop
    v_line_id:=(v_line->>'line_id')::uuid;
    v_qty:=(v_line->>'proposed_qty')::integer;
    if v_qty<0 then
      raise exception 'Proposed quantity cannot be negative.';
    end if;

    update public.rr_market_partner_order_line_v67 l
    set proposed_qty=v_qty,
        confirmed_qty=null,
        confirmation_status='WAITING',
        customer_pi_decision='WAITING',
        customer_pi_qty=null,
        customer_pi_note=null,
        updated_at=now()
    where l.id=v_line_id
      and exists (
        select 1
        from public.rr_market_partner_batch_member_v67 m
        where m.batch_id=p_batch_id and m.order_id=l.order_id
      );
    if not found then
      raise exception 'Proposal line does not belong to requirement.';
    end if;
  end loop;

  update public.rr_market_partner_order_v67 o
  set status='PI_PROPOSED',
      pi_ref=v_ref,
      customer_pi_visible=false,
      customer_pi_pushed_at=null,
      customer_pi_status='WAITING',
      customer_pi_note=null,
      customer_pi_responded_at=null,
      updated_at=now()
  where exists (
    select 1
    from public.rr_market_partner_batch_member_v67 m
    where m.batch_id=p_batch_id and m.order_id=o.id
  );

  update public.rr_market_partner_batch_v67
  set status='WAITING_CONFIRMATION',pi_ref=v_ref,updated_at=now()
  where id=p_batch_id;

  insert into public.rr_market_partner_event_v67(
    owner_customer_id,batch_id,event_type,actor_kind,actor_id,payload
  ) values (
    v_owner,p_batch_id,'REDZED_PI_SENT_TO_DISTRIBUTOR','STAFF',auth.uid(),
    jsonb_build_object('pi_ref',v_ref,'batch_kind',v_kind)
  );

  return public.rr_market_staff_batch_detail_v67(p_batch_id)
    || jsonb_build_object('already_sent',false);
end
$function$;

create or replace function public.rr_market_staff_batch_chat_upsert_v67(
  p_chat_id uuid,
  p_batch_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $function$
declare
  v_actor public.rr_user_profiles%rowtype;
  v_batch public.rr_market_partner_batch_v67%rowtype;
  v_message uuid;
  v_body text;
  v_stage text;
  v_ref text;
  v_payload jsonb;
  v_reused boolean:=false;
begin
  perform public.rr_market_assert_sales_actor_v9420();
  v_actor:=public.rr_chat_actor_profile_v9433();
  if v_actor.id is null then
    raise exception 'Active staff profile required.';
  end if;
  if not exists (
    select 1 from public.rr_customer_chat_members_v9433 m
    where m.chat_id=p_chat_id and m.profile_id=v_actor.id and m.is_active
  ) then
    raise exception 'Active group membership required.';
  end if;

  select b.* into v_batch
  from public.rr_market_partner_batch_v67 b
  join public.rr_market_partner_relation_chat_v67 r
    on r.owner_customer_id=b.owner_customer_id
   and r.chat_id=p_chat_id
   and r.relation_kind='DISTRIBUTOR_REDZED'
   and r.status='ACTIVE'
  where b.id=p_batch_id and b.data_mode='TEST';

  if v_batch.id is null then
    raise exception 'Mapped REDZED distributor batch is unavailable.';
  end if;

  if nullif(trim(coalesce(v_batch.ci_ref,'')),'') is not null then
    v_stage:='CI';
    v_ref:=v_batch.ci_ref;
  elsif nullif(trim(coalesce(v_batch.pi_ref,'')),'') is not null then
    v_stage:='PI';
    v_ref:=v_batch.pi_ref;
  else
    raise exception 'PI is not ready to send.';
  end if;

  v_body:='[PBATCH:'||v_batch.id::text||'] '
    ||coalesce(v_batch.requirement_display_no,v_batch.batch_ref)
    ||' · '||v_stage||' '||v_ref||' SENT TO DISTRIBUTOR';
  v_payload:=jsonb_build_object(
    'relation_scope','DISTRIBUTOR_REDZED',
    'partner_batch_id',v_batch.id,
    'stage',v_stage,
    'document_ref',v_ref,
    'ui','TEST67_CANONICAL_BATCH_CARD'
  );

  select m.id into v_message
  from public.rr_customer_chat_messages_v9433 m
  where m.chat_id=p_chat_id
    and m.channel='GROUP'
    and m.archived_at is null
    and (
      m.payload->>'partner_batch_id'=v_batch.id::text
      or position('[PBATCH:'||v_batch.id::text||']' in coalesce(m.body,''))>0
    )
  order by m.created_at desc,m.id desc
  limit 1
  for update;

  v_reused:=v_message is not null;
  if v_message is null then
    insert into public.rr_customer_chat_messages_v9433(
      chat_id,channel,sender_kind,sender_profile_id,sender_customer_id,
      sender_name,message_type,body,payload
    ) values (
      p_chat_id,'GROUP','STAFF',v_actor.id,null,
      coalesce(nullif(trim(v_actor.full_name),''),'REDZED Staff'),
      'TEXT',v_body,v_payload
    ) returning id into v_message;
  else
    update public.rr_customer_chat_messages_v9433
    set sender_kind='STAFF',
        sender_profile_id=v_actor.id,
        sender_customer_id=null,
        sender_name=coalesce(nullif(trim(v_actor.full_name),''),'REDZED Staff'),
        message_type='TEXT',
        body=v_body,
        payload=coalesce(payload,'{}'::jsonb)||v_payload,
        reply_to_message_id=null,
        created_at=clock_timestamp(),
        archived_at=null,
        archived_by=null,
        archive_reason=null,
        archive_meta='{}'::jsonb
    where id=v_message;
  end if;

  update public.rr_customer_chat_messages_v9433 m
  set archived_at=clock_timestamp(),
      archive_reason='PBATCH_SUPERSEDED_SINGLE_CARD',
      archive_meta=coalesce(m.archive_meta,'{}'::jsonb)
        ||jsonb_build_object('canonical_message_id',v_message,'partner_batch_id',v_batch.id)
  where m.chat_id=p_chat_id
    and m.channel='GROUP'
    and m.id<>v_message
    and m.archived_at is null
    and (
      m.payload->>'partner_batch_id'=v_batch.id::text
      or position('[PBATCH:'||v_batch.id::text||']' in coalesce(m.body,''))>0
    );

  return jsonb_build_object(
    'ok',true,
    'message_id',v_message,
    'batch_id',v_batch.id,
    'stage',v_stage,
    'document_ref',v_ref,
    'reused',v_reused
  );
end
$function$;

revoke all on function public.rr_market_staff_batch_chat_upsert_v67(uuid,uuid)
  from public,anon;
grant execute on function public.rr_market_staff_batch_chat_upsert_v67(uuid,uuid)
  to authenticated,service_role;

-- Existing duplicate PBATCH messages remain as recoverable audit rows, but only
-- the newest message per mapped batch stays visible in live chat.
with ranked as (
  select m.id,
         substring(coalesce(m.body,'') from '\[PBATCH:([0-9a-fA-F-]{36})\]') as batch_token,
         row_number() over (
           partition by m.chat_id,
             substring(coalesce(m.body,'') from '\[PBATCH:([0-9a-fA-F-]{36})\]')
           order by m.created_at desc,m.id desc
         ) as rn,
         first_value(m.id) over (
           partition by m.chat_id,
             substring(coalesce(m.body,'') from '\[PBATCH:([0-9a-fA-F-]{36})\]')
           order by m.created_at desc,m.id desc
         ) as canonical_message_id
  from public.rr_customer_chat_messages_v9433 m
  where m.archived_at is null
    and m.payload->>'relation_scope'='DISTRIBUTOR_REDZED'
    and coalesce(m.body,'') ~ '\[PBATCH:[0-9a-fA-F-]{36}\]'
)
update public.rr_customer_chat_messages_v9433 m
set archived_at=clock_timestamp(),
    archive_reason='PBATCH_SUPERSEDED_SINGLE_CARD',
    archive_meta=coalesce(m.archive_meta,'{}'::jsonb)
      ||jsonb_build_object(
        'canonical_message_id',r.canonical_message_id,
        'partner_batch_id',r.batch_token
      )
from ranked r
where r.id=m.id and r.rn>1;

comment on function public.rr_market_staff_batch_chat_upsert_v67(uuid,uuid) is
  'TEST67 authenticated staff-only canonical REDZED-distributor PI/CI chat-card upsert.';
