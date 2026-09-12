-- V9778: use canonical Collection identity; old links stay bound to their own cycle.
create or replace function public.rr_collection_submit_requirement_v9778(
  p_token text,p_message text,p_lines jsonb,p_requirement_id uuid default null
) returns jsonb language plpgsql security definer set search_path='public' as $$
declare s public.rr_market_share_v9420%rowtype; canonical record;
begin
  select * into s from public.rr_market_share_v9420 where (token=p_token or short_code=upper(p_token)) and status='ACTIVE'
  order by case when token=p_token then 0 else 1 end limit 1;
  if s.id is null then raise exception 'Share link unavailable.'; end if;
  if s.customer_id is null then raise exception 'Collection customer mapping is missing.'; end if;
  select ch.customer_name,ch.mobile into canonical from public.rr_customer_chat_v9433 ch
  where ch.customer_id=s.customer_id and ch.status='OPEN' and (ch.id=s.origin_chat_id or ch.relation_kind='DIRECT_CUSTOMER')
  order by case when ch.id=s.origin_chat_id then 0 else 1 end,ch.created_at limit 1;
  if canonical.mobile is null or trim(canonical.mobile)='' then raise exception 'Collection customer mobile mapping is missing.'; end if;
  return public.rr_collection_submit_requirement_v9588(p_token,canonical.customer_name,canonical.mobile,p_message,p_lines,p_requirement_id)
    ||jsonb_build_object('identity_source','CANONICAL_COLLECTION');
end $$;

create or replace function public.rr_collection_customer_requirement_summary_v9778(p_token text)
returns jsonb language plpgsql security definer set search_path='public' as $$
declare v_share public.rr_market_share_v9420%rowtype; v_cycle uuid; v_lines jsonb;
begin
  select * into v_share from public.rr_market_share_v9420 where (token=p_token or short_code=upper(p_token)) and status='ACTIVE'
  order by case when token=p_token then 0 else 1 end limit 1;
  if v_share.id is null then raise exception 'INVALID_COLLECTION_TOKEN'; end if;
  select cs.collection_cycle_id into v_cycle from public.rr_collection_send_v9586 cs where cs.share_id=v_share.id limit 1;
  v_cycle:=coalesce(v_cycle,v_share.origin_collection_cycle_id);
  if v_cycle is null then return jsonb_build_object('collection_cycle_id',null,'lines','[]'::jsonb); end if;
  with q as (
    select l.requirement_id,r.submitted_at,coalesce(a.update_no,0) update_no
    from public.rr_collection_requirement_link_v9586 l join public.rr_market_requirements_v9420 r on r.id=l.requirement_id
    left join public.rr_collection_activity_v9633 a on a.collection_cycle_id=l.collection_cycle_id and a.reference_id=l.requirement_id
      and a.activity_kind in('REQUIREMENT','REQUIREMENT_UPDATE') where l.collection_cycle_id=v_cycle
  ), ranked as (
    select ml.lot_no,ml.requested_qty,ml.accepted_qty,q.requirement_id,q.update_no,q.submitted_at,
      row_number() over(partition by ml.lot_no order by q.update_no desc,q.submitted_at desc,q.requirement_id desc) rn
    from q join public.rr_market_requirement_lines_v9420 ml on ml.requirement_id=q.requirement_id
  )
  select coalesce(jsonb_agg(jsonb_build_object('lot_no',lot_no,'requested_qty',requested_qty,'accepted_qty',accepted_qty,
    'requirement_id',requirement_id,'update_no',update_no) order by lot_no),'[]'::jsonb) into v_lines from ranked where rn=1;
  return jsonb_build_object('collection_cycle_id',v_cycle,'lines',v_lines);
end $$;

revoke all on function public.rr_collection_submit_requirement_v9778(text,text,jsonb,uuid),
  public.rr_collection_customer_requirement_summary_v9778(text) from public;
grant execute on function public.rr_collection_submit_requirement_v9778(text,text,jsonb,uuid),
  public.rr_collection_customer_requirement_summary_v9778(text) to anon,authenticated,service_role;
