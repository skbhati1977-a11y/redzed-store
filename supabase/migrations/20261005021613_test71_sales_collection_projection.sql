create or replace function public.rr_collection_requirement_snapshot_test71(p_cycle_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_lines jsonb;
begin
  with q as (
    select l.requirement_id,r.submitted_at,coalesce(a.update_no,0) update_no
    from public.rr_collection_requirement_link_v9586 l join public.rr_market_requirements_v9420 r on r.id=l.requirement_id
    left join public.rr_collection_activity_v9633 a on a.collection_cycle_id=l.collection_cycle_id and a.reference_id=l.requirement_id
      and a.activity_kind in('REQUIREMENT','REQUIREMENT_UPDATE') where l.collection_cycle_id=p_cycle_id
  ), ranked as (
    select ml.lot_no,ml.requested_qty,ml.accepted_qty,q.requirement_id,q.update_no,q.submitted_at,
      row_number() over(partition by ml.lot_no order by q.update_no desc,q.submitted_at desc,q.requirement_id desc) rn
    from q join public.rr_market_requirement_lines_v9420 ml on ml.requirement_id=q.requirement_id
  )
  select coalesce(jsonb_agg(jsonb_build_object('lot_no',lot_no,'requested_qty',requested_qty,'accepted_qty',accepted_qty,
    'requirement_id',requirement_id,'update_no',update_no) order by lot_no),'[]'::jsonb) into v_lines from ranked where rn=1;

return v_lines;
end $$;
revoke all on function public.rr_collection_requirement_snapshot_test71(uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.rr_collection_customer_requirement_summary_v9778(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_share public.rr_market_share_v9420%rowtype; v_cycle uuid; v_lines jsonb;
begin
  select * into v_share from public.rr_market_share_v9420 where (token=p_token or short_code=upper(p_token)) and status='ACTIVE'
  order by case when token=p_token then 0 else 1 end limit 1;
  if v_share.id is null then raise exception 'INVALID_COLLECTION_TOKEN'; end if;
  select cs.collection_cycle_id into v_cycle from public.rr_collection_send_v9586 cs where cs.share_id=v_share.id limit 1;
  v_cycle:=coalesce(v_cycle,v_share.origin_collection_cycle_id);
  if v_cycle is null then return jsonb_build_object('collection_cycle_id',null,'lines','[]'::jsonb); end if;
  v_lines:=public.rr_collection_requirement_snapshot_test71(v_cycle);
  return jsonb_build_object('collection_cycle_id',v_cycle,'lines',v_lines);
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
 where l.requirement_id=r.id and l.requested_qty>0;
 return outj||jsonb_build_object('update_history',public.rr_direct_cycle_history_test71(r.collection_cycle_id),
 'current_collection_update_no',greatest(coalesce((select max(cs.send_seq) from public.rr_collection_send_v9586 cs where cs.collection_cycle_id=r.collection_cycle_id),1)-1,0));
end $function$;

CREATE OR REPLACE FUNCTION public.rr_sales_real_chat_queue_v500(p_status text DEFAULT 'OPEN'::text, p_search text DEFAULT NULL::text, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s text:=upper(coalesce(p_status,'OPEN')); rows_json jsonb;
begin
  perform public.rr_market_assert_sales_actor_v9420();
  if s not in('OPEN','WORKING','CLOSE') then raise exception 'OPEN / WORKING / CLOSE required.'; end if;
  if s='OPEN' then
    with req as (
      select coalesce(r.root_requirement_id,r.id) root_id,max(r.requirement_display_no) requirement_no,
        sum(coalesce(l.accepted_qty,0)) present_qty,max(r.submitted_at) last_update,max(r.pi_generated_at) pi_generated_at,
        max(r.customer_name) customer_name,max(r.collection_display_no) collection_display_no,max(r.lifecycle_stage) lifecycle_stage
      from public.rr_market_requirements_v9420 r left join public.rr_market_requirement_lines_v9420 l on l.requirement_id=r.id
      group by coalesce(r.root_requirement_id,r.id)
    ), cy as (
      select c.id,c.display_no collection_no,c.status,c.created_at,c.chat_id,ch.customer_name,
        coalesce(max(cs.send_seq)-1,0) update_no,max(cs.sent_at) last_update,
        coalesce((select sum((line->>'accepted_qty')::integer) from jsonb_array_elements(public.rr_collection_requirement_snapshot_test71(c.id)) line),0) present_qty,
        (select max(q.requirement_no) from req q join public.rr_collection_requirement_link_v9586 rl on rl.requirement_id=q.root_id where rl.collection_cycle_id=c.id) requirement_no,
        (select max(q.pi_generated_at) from req q join public.rr_collection_requirement_link_v9586 rl on rl.requirement_id=q.root_id where rl.collection_cycle_id=c.id) pi_generated_at
      from public.rr_collection_cycle_v9586 c left join public.rr_customer_chat_v9433 ch on ch.id=c.chat_id
      left join public.rr_collection_send_v9586 cs on cs.collection_cycle_id=c.id
      where c.data_mode=upper(p_data_mode) group by c.id,ch.customer_name
    )
    select coalesce(jsonb_agg(jsonb_build_object('id',cy.id,'card_type','COLLECTION_FOLLOWUP','customer',cy.customer_name,
      'collection_no',cy.collection_no,'collection_update_no',cy.update_no,'requirement_no',cy.requirement_no,'present_qty',cy.present_qty,
      'present_amount',0,'all_qty',cy.present_qty,'all_amount',0,'last_update',coalesce(cy.last_update,cy.created_at),
      'current_status',case when cy.pi_generated_at is not null then 'COMPLETE' else cy.status end,'chat_id',cy.chat_id)
      order by coalesce(cy.last_update,cy.created_at) desc),'[]'::jsonb) into rows_json
    from cy where cy.pi_generated_at is null and cy.status not in('CLOSED','CLOSED_NO_RESPONSE','CANCELLED')
      and (nullif(trim(p_search),'') is null or concat_ws(' ',cy.customer_name,cy.collection_no,cy.requirement_no) ilike '%'||trim(p_search)||'%');
  elsif s='WORKING' then
    select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'card_type','PI_CI_READY','customer',p.buyer_snapshot->>'buyer_name',
      'pi_no',p.pi_no,'date',p.created_at::date,'qty',coalesce(x.qty,0),'amount',p.grand_total,'salesman',u.full_name,
      'current_status','CI READY','market_requirement_id',p.market_requirement_id) order by p.updated_at desc),'[]'::jsonb) into rows_json
    from public.rr_fg_pi_v787 p left join lateral(select sum(qty) qty from public.rr_fg_pi_lines_v787 where pi_id=p.id)x on true
    left join public.rr_user_profiles u on u.auth_user_id=p.created_by
    where p.data_mode=upper(p_data_mode) and p.status='DRAFT'
      and (nullif(trim(p_search),'') is null or concat_ws(' ',p.pi_no,p.buyer_snapshot->>'buyer_name') ilike '%'||trim(p_search)||'%');
  else
    select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'card_type','CI_HISTORY','customer',p.buyer_snapshot->>'buyer_name',
      'ci_no',p.cpi_no,'pi_no',p.pi_no,'date',p.finalized_at::date,'qty',coalesce(x.qty,0),'amount',p.grand_total,
      'current_status','CLOSE','rci_count',coalesce(r.rci_count,0),'rci_amount',coalesce(r.rci_amount,0),'payment_status','LEDGER')
      order by p.finalized_at desc),'[]'::jsonb) into rows_json
    from public.rr_fg_pi_v787 p left join lateral(select sum(qty) qty from public.rr_fg_pi_lines_v787 where pi_id=p.id)x on true
    left join lateral(select count(*) rci_count,sum(total_amount) rci_amount from public.rr_rci_v9740 where linked_ci_id=p.id and status='POSTED')r on true
    where p.data_mode=upper(p_data_mode) and p.status in('CI_FINAL','CPI_FINAL')
      and (nullif(trim(p_search),'') is null or concat_ws(' ',p.pi_no,p.cpi_no,p.buyer_snapshot->>'buyer_name') ilike '%'||trim(p_search)||'%');
  end if;
  return jsonb_build_object('version','V502_CANONICAL_SALES_CHAT','status',s,'cards',rows_json,
    'market_window','real-web-window-v9329.html','direct_pi','real-web-window-v9329.html?share_mode=direct_pi',
    'direct_ci','real-finished-goods-v787.html?view=sale&direct_ci=1','rci','real-rci-v9740.html');
end $function$;

create or replace function public.rr_sales_collection_context_test71(
 p_chat_id uuid,p_requirement_id uuid default null,p_collection_cycle_id uuid default null
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare ch public.rr_customer_chat_v9433%rowtype; cy public.rr_collection_cycle_v9586%rowtype;
 req public.rr_market_requirements_v9420%rowtype; cats jsonb; sent jsonb;
begin
 perform public.rr_market_assert_sales_actor_v9420();
 select * into ch from public.rr_customer_chat_v9433 where id=p_chat_id and data_mode='TEST'
  and status='OPEN' and relation_kind='DIRECT_CUSTOMER';
 if ch.id is null or not exists(select 1 from public.rr_customer_chat_members_v9433 m
 join public.rr_user_profiles p on p.id=m.profile_id where m.chat_id=ch.id and m.is_active
 and p.auth_user_id=auth.uid() and p.is_active) then raise exception 'This party chat is unavailable for your account.'; end if;
 if p_requirement_id is not null then
  select * into req from public.rr_market_requirements_v9420
   where id=p_requirement_id and customer_id=ch.customer_id;
  if req.id is null or (p_collection_cycle_id is not null and req.collection_cycle_id is distinct from p_collection_cycle_id)
   then raise exception 'Requirement does not belong to this collection.'; end if;
  p_collection_cycle_id:=req.collection_cycle_id;
 end if;
 if p_collection_cycle_id is not null then
  select * into cy from public.rr_collection_cycle_v9586
   where id=p_collection_cycle_id and chat_id=ch.id and customer_id=ch.customer_id and data_mode=ch.data_mode;
  if cy.id is null then raise exception 'Collection does not belong to this party chat.'; end if;
 else
  select * into cy from public.rr_collection_cycle_v9586
   where chat_id=ch.id and customer_id=ch.customer_id and data_mode=ch.data_mode
   and status in('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED')
   order by created_at desc,id desc limit 1;
 end if;
 if cy.id is not null then
  select * into req from public.rr_market_requirements_v9420 where collection_cycle_id=cy.id
   and coalesce(lifecycle_stage,status,'') not in('SUPERSEDED','CANCELLED')
   order by submitted_at desc,id desc limit 1;
 end if;
 select coalesce(jsonb_agg(x.category order by x.category),'[]'::jsonb) into cats from (
  select distinct trim(c.category) category from public.rr_collection_update_request_v9630 r
  join public.rr_collection_update_category_v9630 c on c.update_request_id=r.id
  where r.collection_cycle_id=cy.id and r.request_kind='MORE_SAMPLES' and (r.status='OPEN' or (r.status='FULFILLED'
   and not exists(select 1 from public.rr_collection_update_request_v9630 pending where pending.collection_cycle_id=cy.id and pending.status='OPEN' and pending.request_kind='MORE_SAMPLES')
   and r.update_no=(select max(done.update_no) from public.rr_collection_update_request_v9630 done where done.collection_cycle_id=cy.id and done.status='FULFILLED' and done.request_kind='MORE_SAMPLES')))
  and nullif(trim(c.category),'') is not null
 ) x;
 select coalesce(jsonb_agg(x.lot_no order by x.lot_no),'[]'::jsonb) into sent from (
  select distinct upper(trim(l.lot_no)) lot_no from public.rr_collection_send_v9586 s
  join public.rr_market_share_lots_v9420 l on l.share_id=s.share_id where s.collection_cycle_id=cy.id
 ) x;
 return jsonb_build_object('chat_id',ch.id,'customer_id',ch.customer_id,'customer_name',ch.customer_name,
 'requirement_lines',public.rr_collection_requirement_snapshot_test71(cy.id),'update_history',public.rr_direct_cycle_history_test71(cy.id),'data_mode',ch.data_mode,'collection_status',cy.status,'collection_cycle_id',cy.id,'collection_display_no',cy.display_no,
 'requirement_id',req.id,'categories',cats,'sent_lots',sent,
 'can_send',coalesce(cy.status in('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED'),cy.id is null)
   and req.pi_generated_at is null and coalesce(req.lifecycle_stage,req.status,'') not in('PI_GENERATED','CI_FINAL','CANCELLED')
   and not exists(select 1 from public.rr_fg_pi_v787 p where p.market_requirement_id=req.id));
end $$;
revoke all on function public.rr_sales_collection_context_test71(uuid,uuid,uuid) from public,anon;
grant execute on function public.rr_sales_collection_context_test71(uuid,uuid,uuid) to authenticated,service_role;
