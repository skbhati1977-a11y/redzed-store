CREATE OR REPLACE FUNCTION public.rr_direct_cycle_live_meta_test71(p_cycle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cy public.rr_collection_cycle_v9586%rowtype; req public.rr_market_requirements_v9420%rowtype; pi public.rr_fg_pi_v787%rowtype;
 sent_at timestamptz; request_at timestamptz; cats jsonb; sample_no integer; sample_at timestamptz; ci text; ci_at timestamptz;
begin
 select * into cy from public.rr_collection_cycle_v9586 where id=p_cycle_id;
 if cy.id is null then return '{}'::jsonb; end if;
 select * into req from public.rr_market_requirements_v9420 where collection_cycle_id=cy.id and coalesce(lifecycle_stage,status,'') not in ('SUPERSEDED','CANCELLED') order by submitted_at desc,id desc limit 1;
 select * into pi from public.rr_fg_pi_v787 where market_requirement_id=req.id and data_mode=cy.data_mode order by created_at desc,id desc limit 1;
 select c.ci_no,c.finalized_at into ci,ci_at from public.rr_fg_final_ci_v9632 c where c.ci_id=pi.id and c.data_mode=cy.data_mode;
 select max(sent.sent_at) into sent_at from public.rr_collection_send_v9586 sent where collection_cycle_id=cy.id;
 select max(a.created_at) into request_at from public.rr_collection_activity_v9633 a where collection_cycle_id=cy.id and activity_kind in ('REQUIREMENT','REQUIREMENT_UPDATE');
 select r.update_no,r.created_at,(select coalesce(jsonb_agg(k.category order by k.category),'[]'::jsonb) from public.rr_collection_update_category_v9630 k where k.update_request_id=r.id)
 into sample_no,sample_at,cats from public.rr_collection_update_request_v9630 r where collection_cycle_id=cy.id and request_kind='MORE_SAMPLES' order by created_at desc,update_no desc limit 1;
 return jsonb_build_object('last_collection_at',sent_at,'last_requirement_at',request_at,'last_category_request_at',sample_at,
 'sample_request_update_no',coalesce(sample_no,0),'requested_categories',coalesce(cats,'[]'::jsonb),
 'requirement_id',req.id,'requirement_display_no',coalesce(req.requirement_display_no,req.requirement_no),
 'requirement_update_no',coalesce(req.requirement_update_no,0),
 'collection_update_no',greatest(coalesce((select max(send_seq) from public.rr_collection_send_v9586 where collection_cycle_id=cy.id),1)-1,0),
 'latest_collection_token',(select s.token from public.rr_collection_send_v9586 cs join public.rr_market_share_v9420 s on s.id=cs.share_id where cs.collection_cycle_id=cy.id and s.status='ACTIVE' order by cs.send_seq desc limit 1),
 'pi_id',pi.id,'pi_no',pi.pi_no,'pi_generated_at',coalesce(req.pi_generated_at,pi.created_at),
 'ci_no',ci,'ci_generated_at',ci_at,
 'live_status',case when ci is not null then 'CI GENERATED' when req.pi_generated_at is not null or pi.id is not null then 'PI GENERATED'
 when req.id is not null then 'REQUIREMENT RECEIVED' when sample_no is not null then 'CATEGORIES REQUESTED' else replace(cy.status,'_',' ') end);
end $function$
;
CREATE OR REPLACE FUNCTION public.rr_sales_collection_send_test71(p_chat_id uuid, p_customer_id uuid, p_lots text[], p_requirement_id uuid DEFAULT NULL::uuid, p_origin text DEFAULT NULL::text, p_collection_cycle_id uuid DEFAULT NULL::uuid)
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
  ctx jsonb; lot text; cat text; chosen_cats text[]:=array[]::text[];
begin
  perform public.rr_market_assert_sales_actor_v9420();
  select * into v_profile from public.rr_user_profiles
  where auth_user_id=auth.uid() and is_active limit 1;
  if v_profile.id is null then raise exception 'Active staff profile required.'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_chat_id::text||'|DIRECT_COLLECTION',9684));
  ctx:=public.rr_sales_collection_context_test71(p_chat_id,p_requirement_id,p_collection_cycle_id);
  if p_customer_id is not null and p_customer_id::text is distinct from ctx->>'customer_id'
   then raise exception 'Collection belongs to another party.'; end if;
  p_customer_id:=(ctx->>'customer_id')::uuid;
  if not (ctx->>'can_send')::boolean then raise exception 'This collection is complete. Open a new collection.'; end if;
  p_requirement_id:=(ctx->>'requirement_id')::uuid;
  select * into v_cycle from public.rr_collection_cycle_v9586 where id=(ctx->>'collection_cycle_id')::uuid for update;
  if v_cycle.id is not null then
   perform pg_advisory_xact_lock(hashtextextended(v_cycle.id::text||'|DIRECT_REQUIREMENT',9714));
  end if;
  select array_agg(distinct upper(trim(x))) into p_lots from unnest(p_lots) x where nullif(trim(x),'') is not null;
  if coalesce(cardinality(p_lots),0)=0 then raise exception 'Select at least one design.'; end if;
  foreach lot in array p_lots loop
   if ctx->'sent_lots' ? lot then raise exception 'This design was already sent. Refresh the collection list.'; end if;
   select w.category into cat from public.rr_web_window_cards_v9329(lot,null,null,'TEST',1,0) w where upper(trim(w.lot_no))=lot;
   if not found then raise exception 'Selected design is unavailable. Refresh the collection list.'; end if;
   if jsonb_array_length(ctx->'categories')>0 and not exists(
    select 1 from jsonb_array_elements_text(ctx->'categories') c where lower(trim(c))=lower(trim(cat)))
    then raise exception 'Select designs from the categories requested by this party.'; end if;
   chosen_cats:=array_append(chosen_cats,lower(trim(cat)));
  end loop;

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
  where m.chat_id=p_chat_id and m.channel='GROUP' and m.archived_at is null and m.message_type<>'REQUIREMENT' and coalesce(m.payload->>'source','')<>'DIRECT_CATEGORY_REQUEST_TEST71' and not (coalesce(m.payload,'{}'::jsonb) ? 'direct_requirement_root_id')
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
  where m.chat_id=p_chat_id and m.id<>v_message and m.archived_at is null and m.message_type<>'REQUIREMENT' and coalesce(m.payload->>'source','')<>'DIRECT_CATEGORY_REQUEST_TEST71' and not (coalesce(m.payload,'{}'::jsonb) ? 'direct_requirement_root_id') and (
    m.payload->>'direct_collection_cycle_id'=v_cycle.id::text or exists(
      select 1 from public.rr_collection_send_v9586 cs
      join public.rr_market_share_v9420 s on s.id=cs.share_id
      where cs.collection_cycle_id=v_cycle.id
        and (position(s.token in coalesce(m.body,''))>0
          or position(coalesce(s.short_code,'#NO-CODE#') in coalesce(m.body,''))>0)
    )
  );
  update public.rr_collection_update_request_v9630 r set status='FULFILLED',fulfilled_at=clock_timestamp()
   where r.collection_cycle_id=v_cycle.id and r.status='OPEN' and r.request_kind='MORE_SAMPLES'
    and not exists(select 1 from public.rr_collection_update_category_v9630 c where c.update_request_id=r.id
      and not (lower(trim(c.category))=any(chosen_cats)));
  return v_result||jsonb_build_object('chat_message_id',v_message,'url',v_url,'collection_update_no',v_update);
end
$function$
;
create or replace function public.rr_chat_customer_messages_session_test71(p_session_token text,p_device_id text,p_channel text default 'GROUP',p_limit integer default 100)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rowsj jsonb;
begin
 -- Use the existing session, channel and per-viewer authorization/filter before enriching results.
 select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('chat_id',m.chat_id,'sender_kind',m.sender_kind,'sender_customer_id',m.sender_customer_id,'sender_profile_id',m.sender_profile_id) order by r.created_at desc),'[]'::jsonb)
 into rowsj from public.rr_chat_customer_messages_session_v9593(p_session_token,p_device_id,p_channel,p_limit) r
 join public.rr_customer_chat_messages_v9433 m on m.id=r.id;
 return rowsj;
end $$;
revoke all on function public.rr_chat_customer_messages_session_test71(text,text,text,integer) from public;
grant execute on function public.rr_chat_customer_messages_session_test71(text,text,text,integer) to anon,authenticated,service_role;