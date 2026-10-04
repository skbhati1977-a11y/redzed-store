-- Shared read model; all authorization remains in the existing callers.
create or replace function public.rr_direct_cycle_history_test71(p_cycle_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(x.event order by x.at,x.kind,x.seq),'[]'::jsonb)
 from (
   select cs.sent_at at,'COLLECTION' kind,cs.send_seq seq,
     jsonb_build_object('kind','COLLECTION','update_no',greatest(cs.send_seq-1,0),
       'created_at',cs.sent_at,'lot_count',(select count(*) from public.rr_market_share_lots_v9420 l where l.share_id=cs.share_id),
       'lots',(select coalesce(jsonb_agg(l.lot_no order by l.lot_no),'[]'::jsonb) from public.rr_market_share_lots_v9420 l where l.share_id=cs.share_id),
       'requirement_update_no',(select coalesce(max(r.requirement_update_no),0) from public.rr_market_requirements_v9420 r where r.collection_cycle_id=p_cycle_id and r.submitted_at<=cs.sent_at)
     ) event
   from public.rr_collection_send_v9586 cs where cs.collection_cycle_id=p_cycle_id
   union all
   select a.created_at,'REQUIREMENT',a.update_no,
     jsonb_build_object('kind','REQUIREMENT',
       'update_no',(row_number() over(order by a.created_at,a.update_no,a.id)-1),
       'created_at',a.created_at,'requirement_id',a.reference_id,
       'lot_count',a.payload->'lot_count','total_qty',a.payload->'total_qty',
       'collection_update_no',greatest(coalesce((select max(cs.send_seq) from public.rr_collection_send_v9586 cs where cs.collection_cycle_id=p_cycle_id and cs.sent_at<=a.created_at),1)-1,0)
     )
   from public.rr_collection_activity_v9633 a where a.collection_cycle_id=p_cycle_id and a.activity_kind in ('REQUIREMENT','REQUIREMENT_UPDATE')
 ) x
$$;
revoke all on function public.rr_direct_cycle_history_test71(uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.rr_collection_current_state_v9633(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cyid uuid; cy public.rr_collection_cycle_v9586%rowtype; n integer; cn integer; rn integer;
begin
  cyid:=public.rr_collection_cycle_for_share_v9631(p_token);
  select * into cy from public.rr_collection_cycle_v9586 where id=cyid;
  select greatest(
    coalesce((select max(update_no) from public.rr_collection_activity_v9633 where collection_cycle_id=cyid),0),
    coalesce((select max(update_no) from public.rr_collection_update_request_v9630 where collection_cycle_id=cyid),0)
  ) into n;
  select greatest(coalesce(max(send_seq),1)-1,0) into cn
  from public.rr_collection_send_v9586 where collection_cycle_id=cyid;
  select coalesce(max(r.requirement_update_no),0) into rn
  from public.rr_market_requirements_v9420 r where r.collection_cycle_id=cyid;
  return jsonb_build_object('collection_cycle_id',cy.id,'collection_display_no',cy.display_no,
    'collection_status',cy.status,'update_no',n,'collection_update_no',cn,'requirement_update_no',rn,'update_history',public.rr_direct_cycle_history_test71(cy.id));
end $function$;

CREATE OR REPLACE FUNCTION public.rr_chat_requirement_detail_v9508(p_chat_id uuid, p_requirement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.rr_market_requirements_v9420%rowtype; outj jsonb; pi jsonb;
begin
 perform public.rr_chat_internal_assert_v9495();
 if not exists(select 1 from public.rr_customer_chat_members_v9433 m join public.rr_user_profiles p on p.id=m.profile_id where m.chat_id=p_chat_id and m.is_active and p.auth_user_id=auth.uid()) then raise exception 'CHAT ACCESS DENIED'; end if;
 select q.* into r from public.rr_market_requirements_v9420 q join public.rr_customer_chat_v9433 c on c.customer_id=q.customer_id where q.id=p_requirement_id and c.id=p_chat_id;
 if not found then raise exception 'REQUIREMENT NOT FOUND IN THIS CHAT'; end if;
 select jsonb_build_object('id',p.id,'pi_no',p.pi_no,'ci_no',p.cpi_no,'status',p.status,'version_no',p.version_no) into pi
 from public.rr_fg_pi_v787 p where p.market_requirement_id=r.id order by p.created_at desc limit 1;
 select jsonb_build_object(
   'id',r.id,'requirement_no',coalesce(r.requirement_display_no,r.requirement_no),
   'requirement_display_no',coalesce(r.requirement_display_no,r.requirement_no),
   'requirement_update_no',coalesce(r.requirement_update_no,0),
   'collection_cycle_id',r.collection_cycle_id,'collection_no',r.collection_no,
   'collection_display_no',coalesce(r.collection_display_no,'COLLECTION'),
   'collection_update_no',coalesce(r.collection_update_no,0),
   'customer_name',r.customer_name,'mobile',r.mobile,'message',r.message,
   'status',coalesce(r.lifecycle_stage,r.status),'submitted_at',r.submitted_at,'share_id',r.share_id,
   'pi',pi,'can_prepare_pi',(pi is null and coalesce(r.lifecycle_stage,r.status) not in('SUPERSEDED','CI_FINAL')),
   'can_add_update',(pi is null and coalesce(r.lifecycle_stage,r.status) not in('SUPERSEDED','CI_FINAL')),
   'lines',coalesce(jsonb_agg(jsonb_build_object('lot_no',l.lot_no,'requested_qty',l.requested_qty,'accepted_qty',l.accepted_qty,'max_available',l.max_available_at_submit,'card',to_jsonb(ca)) order by l.created_at),'[]'::jsonb)
 ) into outj
 from public.rr_market_requirement_lines_v9420 l
 left join lateral public.rr_web_window_cards_v9329(l.lot_no,null,null,'TEST',1,0) ca on true
 where l.requirement_id=r.id;
 return outj||jsonb_build_object('update_history',public.rr_direct_cycle_history_test71(r.collection_cycle_id),
 'current_collection_update_no',greatest(coalesce((select max(cs.send_seq) from public.rr_collection_send_v9586 cs where cs.collection_cycle_id=r.collection_cycle_id),1)-1,0));
end $function$;

create or replace function public.rr_chat_direct_cycle_state_test71(p_chat_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare cy public.rr_collection_cycle_v9586%rowtype;
begin
 perform public.rr_chat_internal_assert_v9495();
 if not exists(select 1 from public.rr_customer_chat_members_v9433 m join public.rr_user_profiles p on p.id=m.profile_id where m.chat_id=p_chat_id and m.is_active and p.auth_user_id=auth.uid()) then raise exception 'CHAT ACCESS DENIED'; end if;
 select * into cy from public.rr_collection_cycle_v9586 where chat_id=p_chat_id and data_mode='TEST' order by created_at desc limit 1;
 if cy.id is null then return '{}'::jsonb; end if;
 return jsonb_build_object('collection_cycle_id',cy.id,'collection_display_no',cy.display_no,'collection_status',cy.status,'update_history',public.rr_direct_cycle_history_test71(cy.id));
end $$;
revoke all on function public.rr_chat_direct_cycle_state_test71(uuid) from public,anon;
grant execute on function public.rr_chat_direct_cycle_state_test71(uuid) to authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rr_collection_current_state_v9633(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cyid uuid; cy public.rr_collection_cycle_v9586%rowtype; n integer; cn integer; rn integer;
begin
  cyid:=public.rr_collection_cycle_for_share_v9631(p_token);
  select * into cy from public.rr_collection_cycle_v9586 where id=cyid;
  select greatest(
    coalesce((select max(update_no) from public.rr_collection_activity_v9633 where collection_cycle_id=cyid),0),
    coalesce((select max(update_no) from public.rr_collection_update_request_v9630 where collection_cycle_id=cyid),0)
  ) into n;
  select greatest(coalesce(max(send_seq),1)-1,0) into cn
  from public.rr_collection_send_v9586 where collection_cycle_id=cyid;
  select coalesce(max(r.requirement_update_no),0) into rn
  from public.rr_market_requirements_v9420 r where r.collection_cycle_id=cyid;
  return jsonb_build_object('collection_cycle_id',cy.id,'collection_display_no',cy.display_no,
    'collection_status',cy.status,'update_no',n,'collection_update_no',cn,'requirement_update_no',rn,'requirement_response_collection_update_no',coalesce((select greatest(coalesce((select max(cs.send_seq) from public.rr_collection_send_v9586 cs where cs.collection_cycle_id=cy.id and cs.sent_at<=a.created_at),1)-1,0) from public.rr_collection_activity_v9633 a where a.collection_cycle_id=cy.id and a.activity_kind in('REQUIREMENT','REQUIREMENT_UPDATE') order by a.created_at desc,a.update_no desc limit 1),-1),'update_history',public.rr_direct_cycle_history_test71(cy.id));
end $function$
;
CREATE OR REPLACE FUNCTION public.rr_direct_collection_send_v9684(p_chat_id uuid, p_customer_id uuid, p_lots text[], p_requirement_id uuid DEFAULT NULL::uuid, p_origin text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_cycle public.rr_collection_cycle_v9586%rowtype;
  v_result jsonb;
  v_message uuid;
  v_profile public.rr_user_profiles%rowtype;
  v_url text;
  v_body text;
  v_update integer;
begin
  perform public.rr_market_assert_sales_actor_v9420();
  select * into v_profile from public.rr_user_profiles
  where auth_user_id=auth.uid() and is_active limit 1;
  if v_profile.id is null then raise exception 'Active staff profile required.'; end if;
  if p_customer_id is null then
    select c.customer_id into p_customer_id from public.rr_customer_chat_v9433 c
    where c.id=p_chat_id and c.data_mode='TEST' and c.status='OPEN' and c.relation_kind='DIRECT_CUSTOMER';
  end if;
  if not exists(
    select 1 from public.rr_customer_chat_v9433 c
    where c.id=p_chat_id and c.customer_id=p_customer_id
      and c.data_mode='TEST' and c.status='OPEN'
  ) then raise exception 'Customer chat identity mismatch.'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_chat_id::text||'|DIRECT_COLLECTION',9684));
  if p_requirement_id is not null then
    select c.* into v_cycle
    from public.rr_market_requirements_v9420 r
    join public.rr_collection_cycle_v9586 c on c.id=r.collection_cycle_id
    where r.id=p_requirement_id and r.customer_id=p_customer_id
      and c.chat_id=p_chat_id and c.data_mode='TEST';
    if v_cycle.id is null then raise exception 'Requirement Collection cycle not found.'; end if;
  else
    select * into v_cycle from public.rr_collection_cycle_v9586 c
    where c.chat_id=p_chat_id and c.customer_id=p_customer_id and c.data_mode='TEST'
      and c.status in('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED')
    order by c.created_at desc limit 1 for update;
  end if;

  if v_cycle.id is null then
    v_result:=public.rr_collection_create_first_v67(p_customer_id,p_lots,'TEST');
  else
    v_result:=public.rr_collection_add_update_v9587(v_cycle.id,p_lots);
  end if;
  select * into v_cycle from public.rr_collection_cycle_v9586
  where id=(v_result->>'collection_cycle_id')::uuid;
  v_update:=greatest(coalesce((v_result->>'send_seq')::integer,1)-1,0);

  if p_origin is distinct from 'https://redzed-customer-collection.jggfab2011.chatgpt.site'
     and coalesce(p_origin,'') !~ '^https://([a-z0-9-]+\.)*(vercel\.app|github\.io)$' then
    raise exception 'Approved application origin required.';
  end if;
  v_url:=rtrim(p_origin,'/')||'/s.html?t='||(v_result->>'token')||
    case when nullif(v_result->>'short_code','') is null then ''
         else '&c='||(v_result->>'short_code') end||
    case when p_requirement_id is null then '' else '&r='||p_requirement_id::text end||'&v=9684';
  v_body:=coalesce(v_cycle.display_no,'RZ COLLECTION')||
    case when v_update>0 then ' · UPDATE '||v_update else '' end||
    ' · '||coalesce(v_result->>'lot_count','0')||' styles\nOpen collection: '||v_url;

  select m.id into v_message
  from public.rr_customer_chat_messages_v9433 m
  where m.chat_id=p_chat_id and m.channel='GROUP' and m.archived_at is null and m.message_type<>'REQUIREMENT' and not (coalesce(m.payload,'{}'::jsonb) ? 'direct_requirement_root_id')
    and (
      m.payload->>'direct_collection_cycle_id'=v_cycle.id::text
      or exists(
        select 1 from public.rr_collection_send_v9586 cs
        join public.rr_market_share_v9420 s on s.id=cs.share_id
        where cs.collection_cycle_id=v_cycle.id
          and (position(s.token in coalesce(m.body,''))>0
            or position(coalesce(s.short_code,'#NO-CODE#') in coalesce(m.body,''))>0)
      )
    )
  order by m.created_at desc,m.id desc limit 1 for update;

  if v_message is null then
    insert into public.rr_customer_chat_messages_v9433(
      chat_id,channel,sender_kind,sender_profile_id,sender_name,message_type,body,payload
    ) values(
      p_chat_id,'GROUP','STAFF',v_profile.id,coalesce(nullif(trim(v_profile.full_name),''),'REDZED Staff'),
      'LINK',v_body,jsonb_build_object(
        'source','DIRECT_MARKET_WINDOW','url',v_url,'market_share_id',v_result->>'share_id',
        'direct_collection_cycle_id',v_cycle.id,'collection_no',v_cycle.collection_no,
        'collection_display_no',v_cycle.display_no,'collection_update_no',v_update,
        'lot_count',(v_result->>'lot_count')::integer
      )
    ) returning id into v_message;
  else
    update public.rr_customer_chat_messages_v9433 set
      sender_kind='STAFF',sender_profile_id=v_profile.id,
      sender_name=coalesce(nullif(trim(v_profile.full_name),''),'REDZED Staff'),
      message_type='LINK',body=v_body,
      payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object(
        'source','DIRECT_MARKET_WINDOW','url',v_url,'market_share_id',v_result->>'share_id',
        'direct_collection_cycle_id',v_cycle.id,'collection_no',v_cycle.collection_no,
        'collection_display_no',v_cycle.display_no,'collection_update_no',v_update,
        'lot_count',(v_result->>'lot_count')::integer
      ),created_at=clock_timestamp(),archived_at=null,archived_by=null,
      archive_reason=null,archive_meta='{}'::jsonb
    where id=v_message;
  end if;

  update public.rr_customer_chat_messages_v9433 m set
    archived_at=clock_timestamp(),archive_reason='DIRECT_COLLECTION_SUPERSEDED_SINGLE_CARD',
    archive_meta=coalesce(m.archive_meta,'{}'::jsonb)||jsonb_build_object('canonical_message_id',v_message,'collection_cycle_id',v_cycle.id)
  where m.chat_id=p_chat_id and m.id<>v_message and m.archived_at is null and m.message_type<>'REQUIREMENT' and not (coalesce(m.payload,'{}'::jsonb) ? 'direct_requirement_root_id') and (
    m.payload->>'direct_collection_cycle_id'=v_cycle.id::text or exists(
      select 1 from public.rr_collection_send_v9586 cs
      join public.rr_market_share_v9420 s on s.id=cs.share_id
      where cs.collection_cycle_id=v_cycle.id
        and (position(s.token in coalesce(m.body,''))>0
          or position(coalesce(s.short_code,'#NO-CODE#') in coalesce(m.body,''))>0)
    )
  );
  return v_result||jsonb_build_object('chat_message_id',v_message,'url',v_url,'collection_update_no',v_update);
end
$function$
;
-- Repair only TEST direct requirement cards overwritten by Collection updates.
update public.rr_customer_chat_messages_v9433 m set
 archive_meta=coalesce(m.archive_meta,'{}'::jsonb)||jsonb_build_object('test71_previous_collection_body',m.body,'test71_previous_collection_payload',m.payload),
 message_type='REQUIREMENT',sender_kind='CUSTOMER',sender_customer_id=r.customer_id,
 sender_name=r.customer_name,
 body='[REQ:'||r.id::text||'] '||coalesce(r.requirement_display_no,r.requirement_no,'REQUIREMENT')||' · '||(select count(*) from public.rr_market_requirement_lines_v9420 l where l.requirement_id=r.id)||' styles · '||coalesce((select sum(l.requested_qty) from public.rr_market_requirement_lines_v9420 l where l.requirement_id=r.id),0)||' pcs',
 payload=m.payload||jsonb_build_object('source','DIRECT_MARKET_REQUIREMENT','collection_update_no',coalesce(r.collection_update_no,0))
from public.rr_market_requirements_v9420 r join public.rr_collection_cycle_v9586 c on c.id=r.collection_cycle_id
where c.data_mode='TEST' and m.chat_id=c.chat_id and m.archived_at is null and m.message_type='LINK'
 and m.payload->>'source'='DIRECT_MARKET_WINDOW'
 and m.payload->>'direct_requirement_root_id'=coalesce(r.root_requirement_id,r.id)::text
 and m.payload->>'requirement_id'=r.id::text;
