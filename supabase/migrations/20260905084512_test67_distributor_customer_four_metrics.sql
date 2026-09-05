-- TEST67 only: direct-chat four-metric contract for Distributor <-> Customer.
-- No MAIN/REAL tables or direct REDZED <-> Customer functions are changed.

create or replace function public.rr_market_partner_customer_metrics_core_v67(
  p_owner uuid,
  p_customer uuid,
  p_root uuid default null
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_root uuid:=p_root;
  v_latest public.rr_market_partner_order_v67%rowtype;
  v_req_visible boolean:=true;
  v_req_qty numeric;
  v_req_amount numeric;
  v_req_average numeric;
  v_req_resolved boolean:=true;
  v_history_qty numeric;
  v_history_amount numeric;
  v_history_resolved boolean:=true;
  v_all_average numeric;
begin
  if p_owner is null or p_customer is null or not exists(
    select 1
    from public.rr_market_partner_customer_v67 c
    where c.id=p_customer
      and c.owner_customer_id=p_owner
      and c.status='ACTIVE'
  ) then
    raise exception 'Distributor customer relation is unavailable.';
  end if;

  if v_root is null then
    select coalesce(pc.root_collection_id,pc.id)
    into v_root
    from public.rr_market_partner_collection_v67 pc
    where pc.owner_customer_id=p_owner
      and pc.partner_customer_id=p_customer
    order by pc.created_at desc,pc.collection_update_no desc
    limit 1;
  elsif not exists(
    select 1
    from public.rr_market_partner_collection_v67 pc
    where coalesce(pc.root_collection_id,pc.id)=v_root
      and pc.owner_customer_id=p_owner
      and pc.partner_customer_id=p_customer
  ) then
    raise exception 'Collection relation is unavailable.';
  end if;

  if v_root is not null then
    select o.*
    into v_latest
    from public.rr_market_partner_order_v67 o
    join public.rr_market_partner_collection_v67 pc on pc.id=o.collection_id
    where coalesce(pc.root_collection_id,pc.id)=v_root
      and o.owner_customer_id=p_owner
      and o.partner_customer_id=p_customer
      and o.data_mode='TEST'
      and o.status<>'SUPERSEDED'
    order by o.requirement_update_no desc,o.created_at desc
    limit 1;
  end if;

  v_req_visible:=v_latest.id is null or v_latest.status='DRAFT';

  if v_latest.id is not null and v_latest.status='DRAFT' then
    select
      coalesce(sum(greatest(0,l.requested_qty)),0),
      sum(greatest(0,l.requested_qty)*l.final_customer_rate),
      coalesce(bool_and(l.final_customer_rate is not null),true)
    into v_req_qty,v_req_amount,v_req_resolved
    from public.rr_market_partner_order_line_v67 l
    where l.order_id=v_latest.id
      and greatest(0,l.requested_qty)>0;

    if coalesce(v_req_qty,0)<=0 then
      v_req_qty:=null;
      v_req_amount:=null;
      v_req_average:=null;
    elsif not v_req_resolved then
      v_req_amount:=null;
      v_req_average:=null;
    else
      v_req_average:=round(v_req_amount/nullif(v_req_qty,0),2);
    end if;
  else
    v_req_qty:=null;
    v_req_amount:=null;
    v_req_average:=null;
  end if;

  select
    coalesce(sum(h.qty),0),
    sum(h.qty*h.rate),
    coalesce(bool_and(h.rate is not null),true)
  into v_history_qty,v_history_amount,v_history_resolved
  from (
    select
      greatest(0,coalesce(
        l.distributor_pi_customer_qty,
        l.distributor_pi_qty,
        l.confirmed_qty,
        l.customer_pi_qty,
        l.proposed_qty,
        l.requested_qty,
        0
      ))::numeric as qty,
      l.final_customer_rate as rate
    from public.rr_market_partner_order_v67 o
    join public.rr_market_partner_order_line_v67 l on l.order_id=o.id
    where o.owner_customer_id=p_owner
      and o.partner_customer_id=p_customer
      and o.data_mode='TEST'
      and o.status='CI_FINAL'
      and o.ci_ref is not null
      and o.customer_ci_visible
  ) h
  where h.qty>0;

  if coalesce(v_history_qty,0)<=0 or not v_history_resolved then
    v_history_qty:=coalesce(v_history_qty,0);
    v_history_amount:=null;
    v_all_average:=null;
  elsif v_req_visible and v_req_qty is not null and v_req_amount is not null then
    v_all_average:=round((v_history_amount+v_req_amount)/nullif(v_history_qty+v_req_qty,0),2);
  else
    v_all_average:=round(v_history_amount/nullif(v_history_qty,0),2);
  end if;

  return jsonb_build_object(
    'req_visible',v_req_visible,
    'req_qty',v_req_qty,
    'req_amount',v_req_amount,
    'req_average',v_req_average,
    'all_average',v_all_average,
    'history_qty',v_history_qty,
    'history_amount',v_history_amount,
    'latest_status',v_latest.status
  );
end
$$;

create or replace function public.rr_market_partner_customer_metrics_v67(
  p_session_token text,
  p_device_id text,
  p_partner_customer_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_ctx jsonb;
  v_owner uuid;
begin
  v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
  v_owner:=(v_ctx->>'owner_customer_id')::uuid;
  return public.rr_market_partner_customer_metrics_core_v67(v_owner,p_partner_customer_id,null);
end
$$;

create or replace function public.rr_market_partner_customer_metrics_by_token_v67(
  p_token text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_owner uuid;
  v_customer uuid;
  v_root uuid;
begin
  select pc.owner_customer_id,pc.partner_customer_id,coalesce(pc.root_collection_id,pc.id)
  into v_owner,v_customer,v_root
  from public.rr_market_share_v9420 s
  join public.rr_market_partner_collection_v67 pc on pc.share_id=s.id
  where (s.token=p_token or s.short_code=upper(p_token))
    and s.status='ACTIVE'
    and s.data_mode='TEST'
  order by case when s.token=p_token then 0 else 1 end
  limit 1;

  if v_owner is null or v_customer is null then
    raise exception 'Distributor customer share relation is unavailable.';
  end if;

  return public.rr_market_partner_customer_metrics_core_v67(v_owner,v_customer,v_root);
end
$$;

revoke all on function public.rr_market_partner_customer_metrics_core_v67(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.rr_market_partner_customer_metrics_v67(text,text,uuid) from public;
revoke all on function public.rr_market_partner_customer_metrics_by_token_v67(text) from public;

grant execute on function public.rr_market_partner_customer_metrics_v67(text,text,uuid) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_metrics_by_token_v67(text) to anon,authenticated,service_role;
