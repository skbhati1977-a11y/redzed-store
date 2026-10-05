create or replace function public.rr_direct_cycle_live_meta_test71(p_cycle_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
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
 'pi_id',pi.id,'pi_no',pi.pi_no,'pi_generated_at',coalesce(req.pi_generated_at,pi.created_at),
 'ci_no',ci,'ci_generated_at',ci_at,
 'live_status',case when ci is not null then 'CI GENERATED' when req.pi_generated_at is not null or pi.id is not null then 'PI GENERATED'
 when req.id is not null then 'REQUIREMENT RECEIVED' when sample_no is not null then 'CATEGORIES REQUESTED' else replace(cy.status,'_',' ') end);
end $$;
revoke all on function public.rr_direct_cycle_live_meta_test71(uuid) from public,anon,authenticated;

create or replace function public.rr_sales_collection_live_status_test71(p_chat_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare cy uuid; ctx jsonb;
begin
 -- The existing contract checks staff role and active membership before revealing party data.
 ctx:=public.rr_sales_collection_context_test71(p_chat_id);
 select id into cy from public.rr_collection_cycle_v9586 where chat_id=p_chat_id and data_mode='TEST' order by created_at desc,id desc limit 1;
 if cy is null then return ctx;end if;
 ctx:=public.rr_sales_collection_context_test71(p_chat_id,null,cy);
 return ctx||public.rr_direct_cycle_live_meta_test71(cy);
end $$;
revoke all on function public.rr_sales_collection_live_status_test71(uuid) from public,anon;
grant execute on function public.rr_sales_collection_live_status_test71(uuid) to authenticated,service_role;

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
    'collection_status',cy.status,'update_no',n,'collection_update_no',cn,'requirement_update_no',rn,'requirement_response_collection_update_no',coalesce((select greatest(coalesce((select max(cs.send_seq) from public.rr_collection_send_v9586 cs where cs.collection_cycle_id=cy.id and cs.sent_at<=a.created_at),1)-1,0) from public.rr_collection_activity_v9633 a where a.collection_cycle_id=cy.id and a.activity_kind in('REQUIREMENT','REQUIREMENT_UPDATE') order by a.created_at desc,a.update_no desc limit 1),-1),'update_history',public.rr_direct_cycle_history_test71(cy.id))||public.rr_direct_cycle_live_meta_test71(cy.id);
end $function$
;
CREATE OR REPLACE FUNCTION public.rr_collection_more_samples_request_v9630(p_token text, p_categories text[], p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cy public.rr_collection_cycle_v9586%rowtype; v_no integer; v_id uuid; c text; cyid uuid; msg uuid; txt text; cats text[];
begin
  cyid:=public.rr_collection_cycle_for_share_v9631(p_token);
  select * into cy from public.rr_collection_cycle_v9586 where id=cyid for update;
  if cy.status in ('CLOSED','CLOSED_NO_RESPONSE','CANCELLED','CI_GENERATED','PI_GENERATED') then raise exception 'Collection is already closed.'; end if;
  if coalesce(array_length(p_categories,1),0)=0 then raise exception 'Select at least one category.'; end if;

  if cy.data_mode='TEST' and exists(select 1 from unnest(p_categories) picked where not exists(
    select 1 from public.rr_collection_categories_v9630() available
    where lower(trim(available.category))=lower(trim(picked))))
   then raise exception 'Choose categories from the available collection list.'; end if;
  v_no:=public.rr_collection_next_update_v9633(cy.id);
  insert into public.rr_collection_update_request_v9630(collection_cycle_id,update_no,request_kind,requested_by,note)
  values(cy.id,v_no,'MORE_SAMPLES','CUSTOMER',nullif(trim(coalesce(p_note,'')),'')) returning id into v_id;
  foreach c in array p_categories loop
    c:=trim(coalesce(c,''));
    if c<>'' then insert into public.rr_collection_update_category_v9630(update_request_id,category) values(v_id,c) on conflict do nothing; end if;
  end loop;
  if not exists(select 1 from public.rr_collection_update_category_v9630 where update_request_id=v_id) then raise exception 'Select at least one valid category.'; end if;
  insert into public.rr_collection_activity_v9633(collection_cycle_id,update_no,activity_kind,actor_kind,reference_id,payload)
  values(cy.id,v_no,'MORE_SAMPLES','CUSTOMER',v_id,jsonb_build_object('categories',p_categories,'note',nullif(trim(coalesce(p_note,'')),'')));

  if cy.data_mode='TEST' and exists(select 1 from public.rr_customer_chat_v9433 ch where ch.id=cy.chat_id and ch.relation_kind='DIRECT_CUSTOMER') then
    select array_agg(category order by category) into cats from public.rr_collection_update_category_v9630 where update_request_id=v_id;
    txt:=cy.display_no||' · CATEGORY REQUEST · UPDATE '||v_no||E'\n'||array_to_string(cats,' / ')||case when nullif(trim(p_note),'') is null then '' else E'\n'||trim(p_note) end;
    select id into msg from public.rr_customer_chat_messages_v9433 where chat_id=cy.chat_id and channel='GROUP' and archived_at is null
     and payload->>'source'='DIRECT_CATEGORY_REQUEST_TEST71' and payload->>'direct_collection_cycle_id'=cy.id::text limit 1 for update;
    if msg is null then
      insert into public.rr_customer_chat_messages_v9433(chat_id,channel,sender_kind,sender_customer_id,sender_name,message_type,body,payload)
      select cy.chat_id,'GROUP','CUSTOMER',cy.customer_id,ch.customer_name,'TEXT',txt,
      jsonb_build_object('source','DIRECT_CATEGORY_REQUEST_TEST71','direct_collection_cycle_id',cy.id,'sample_request_update_no',v_no,'requested_categories',cats,'update_request_id',v_id)
      from public.rr_customer_chat_v9433 ch where ch.id=cy.chat_id returning id into msg;
    else
      update public.rr_customer_chat_messages_v9433 set body=txt,created_at=clock_timestamp(),payload=payload||jsonb_build_object('sample_request_update_no',v_no,'requested_categories',cats,'update_request_id',v_id) where id=msg;
    end if;
  end if;
  return jsonb_build_object('collection_cycle_id',cy.id,'collection_display_no',cy.display_no,'collection_status',cy.status,'update_request_id',v_id,'update_no',v_no,'request_kind','MORE_SAMPLES');
end$function$
;
-- Recover the latest missing current category request once per TEST direct cycle.
insert into public.rr_customer_chat_messages_v9433(chat_id,channel,sender_kind,sender_customer_id,sender_name,message_type,body,payload)
select cy.chat_id,'GROUP','CUSTOMER',cy.customer_id,ch.customer_name,'TEXT',
 cy.display_no||' · CATEGORY REQUEST · UPDATE '||r.update_no||E'\n'||(select string_agg(k.category,' / ' order by k.category) from public.rr_collection_update_category_v9630 k where k.update_request_id=r.id)||case when r.note is null then '' else E'\n'||r.note end,
 jsonb_build_object('source','DIRECT_CATEGORY_REQUEST_TEST71','direct_collection_cycle_id',cy.id,'sample_request_update_no',r.update_no,'requested_categories',(select jsonb_agg(k.category order by k.category) from public.rr_collection_update_category_v9630 k where k.update_request_id=r.id),'update_request_id',r.id)
from public.rr_collection_cycle_v9586 cy join public.rr_customer_chat_v9433 ch on ch.id=cy.chat_id
join lateral (select * from public.rr_collection_update_request_v9630 u where u.collection_cycle_id=cy.id and u.request_kind='MORE_SAMPLES' order by u.created_at desc,u.update_no desc limit 1) r on true
where cy.data_mode='TEST' and ch.relation_kind='DIRECT_CUSTOMER' and ch.status='OPEN' and cy.status in ('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED')
 and r.created_at>=current_date
 and not exists(select 1 from public.rr_customer_chat_messages_v9433 m where m.chat_id=cy.chat_id and m.archived_at is null and m.payload->>'source'='DIRECT_CATEGORY_REQUEST_TEST71' and m.payload->>'direct_collection_cycle_id'=cy.id::text);

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
  if cy.data_mode='TEST' and exists(select 1 from public.rr_customer_chat_v9433 ch where ch.id=cy.chat_id and ch.customer_id=cy.customer_id and ch.relation_kind='DIRECT_CUSTOMER') then
    select newest.id into cyid from public.rr_collection_cycle_v9586 newest where newest.chat_id=cy.chat_id and newest.customer_id=cy.customer_id and newest.data_mode='TEST' order by newest.created_at desc,newest.id desc limit 1;
    select * into cy from public.rr_collection_cycle_v9586 where id=cyid;
  end if;
  select greatest(
    coalesce((select max(update_no) from public.rr_collection_activity_v9633 where collection_cycle_id=cyid),0),
    coalesce((select max(update_no) from public.rr_collection_update_request_v9630 where collection_cycle_id=cyid),0)
  ) into n;
  select greatest(coalesce(max(send_seq),1)-1,0) into cn
  from public.rr_collection_send_v9586 where collection_cycle_id=cyid;
  select coalesce(max(r.requirement_update_no),0) into rn
  from public.rr_market_requirements_v9420 r where r.collection_cycle_id=cyid;
  return jsonb_build_object('collection_cycle_id',cy.id,'collection_display_no',cy.display_no,
    'collection_status',cy.status,'update_no',n,'collection_update_no',cn,'requirement_update_no',rn,'requirement_response_collection_update_no',coalesce((select greatest(coalesce((select max(cs.send_seq) from public.rr_collection_send_v9586 cs where cs.collection_cycle_id=cy.id and cs.sent_at<=a.created_at),1)-1,0) from public.rr_collection_activity_v9633 a where a.collection_cycle_id=cy.id and a.activity_kind in('REQUIREMENT','REQUIREMENT_UPDATE') order by a.created_at desc,a.update_no desc limit 1),-1),'update_history',public.rr_direct_cycle_history_test71(cy.id))||public.rr_direct_cycle_live_meta_test71(cy.id)||jsonb_build_object('latest_collection_token',(select s.token from public.rr_collection_send_v9586 cs join public.rr_market_share_v9420 s on s.id=cs.share_id where cs.collection_cycle_id=cy.id and s.status='ACTIVE' order by cs.send_seq desc limit 1));
end $function$
;
