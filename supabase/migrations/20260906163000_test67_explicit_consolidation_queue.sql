-- TEST67: explicit distributor routing choice for each closed requirement.
create or replace function public.rr_market_partner_consolidation_queue_v67(
  p_session_token text,p_device_id text,p_order_id uuid,p_add boolean
) returns jsonb language plpgsql security definer set search_path='' as $function$
declare v_ctx jsonb;v_owner uuid;v_order public.rr_market_partner_order_v67%rowtype;v_next text;
begin
  v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
  v_owner:=(v_ctx->>'owner_customer_id')::uuid;
  select * into v_order from public.rr_market_partner_order_v67
  where id=p_order_id and owner_customer_id=v_owner and data_mode='TEST' for update;
  if v_order.id is null then raise exception 'Requirement is unavailable.'; end if;
  if v_order.redzed_pushed_at is not null or v_order.status='BATCHED' then raise exception 'Requirement is already sent to REDZED.'; end if;
  if p_add then
    if v_order.status<>'READY' or v_order.customer_closed_at is null then raise exception 'Only closed requirements can be added to consolidated list.'; end if;
    v_next:='CONSOLIDATION_QUEUED';
  else
    if v_order.status<>'CONSOLIDATION_QUEUED' then raise exception 'Requirement is not in consolidated list.'; end if;
    v_next:='READY';
  end if;
  update public.rr_market_partner_order_v67 set status=v_next,updated_at=now() where id=v_order.id;
  insert into public.rr_market_partner_event_v67(owner_customer_id,order_id,event_type,actor_kind,payload)
  values(v_owner,v_order.id,case when p_add then 'REQUIREMENT_ADDED_TO_CONSOLIDATED_LIST' else 'REQUIREMENT_REMOVED_FROM_CONSOLIDATED_LIST' end,
    'DISTRIBUTOR',jsonb_build_object('requirement_display_no',v_order.requirement_display_no,'status',v_next));
  return jsonb_build_object('ok',true,'order_id',v_order.id,'status',v_next);
end $function$;
revoke all on function public.rr_market_partner_consolidation_queue_v67(text,text,uuid,boolean) from public;
grant execute on function public.rr_market_partner_consolidation_queue_v67(text,text,uuid,boolean) to anon,authenticated,service_role;

create or replace function public.rr_market_partner_batch_submit_v67(p_session_token text,p_device_id text,p_order_ids uuid[])
returns jsonb language plpgsql security definer set search_path=public as $function$
declare v_ctx jsonb;v_owner uuid;v_batch uuid;v_batch_ref text;v_count int;v_refs jsonb;
begin
 v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
 if not(v_ctx->>'send_collection_enabled')::boolean then raise exception 'Requirement push is disabled.';end if;
 v_owner:=(v_ctx->>'owner_customer_id')::uuid;
 select count(*)into v_count from public.rr_market_partner_order_v67 where id=any(p_order_ids)and owner_customer_id=v_owner
 and status in('READY','CONSOLIDATION_QUEUED')and customer_closed_at is not null and redzed_pushed_at is null;
 if coalesce(array_length(p_order_ids,1),0)=0 or v_count<>array_length(p_order_ids,1)then
  raise exception 'Only unsent customer-closed requirements can be sent to REDZED.';end if;
 select jsonb_agg(requirement_display_no order by requirement_no,requirement_update_no)into v_refs
 from public.rr_market_partner_order_v67 where id=any(p_order_ids);
 v_batch_ref:='B-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS');
 insert into public.rr_market_partner_batch_v67(owner_customer_id,batch_ref)values(v_owner,v_batch_ref)returning id into v_batch;
 insert into public.rr_market_partner_batch_member_v67(batch_id,order_id)select v_batch,unnest(p_order_ids);
 update public.rr_market_partner_order_v67 set status='BATCHED',redzed_pushed_at=now(),updated_at=now()where id=any(p_order_ids);
 insert into public.rr_market_partner_event_v67(owner_customer_id,batch_id,event_type,actor_kind,payload)
 values(v_owner,v_batch,'CLOSED_REQUIREMENTS_PUSHED_TO_REDZED','DISTRIBUTOR',jsonb_build_object(
 'order_count',v_count,'requirements',coalesce(v_refs,'[]'::jsonb),'destination','REDZED_STAFF_QUEUE'));
 return jsonb_build_object('batch_id',v_batch,'batch_ref',v_batch_ref,'order_count',v_count,'status','SUBMITTED',
 'redzed_status','PUSHED','requirements',coalesce(v_refs,'[]'::jsonb));
end $function$;
revoke all on function public.rr_market_partner_batch_submit_v67(text,text,uuid[]) from public;
grant execute on function public.rr_market_partner_batch_submit_v67(text,text,uuid[]) to anon,authenticated,service_role;