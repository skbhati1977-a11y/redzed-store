-- TEST67: PI editing closes a received requirement, and remains editable only until it is sent upstream.
create or replace function public.rr_market_partner_make_customer_pi_v67(
  p_session_token text,p_device_id text,p_order_id uuid,p_lines jsonb,p_note text default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_ctx jsonb;v_owner uuid;v_order public.rr_market_partner_order_v67%rowtype;
  v_line public.rr_market_partner_order_line_v67%rowtype;v_input jsonb;v_qty integer;
  v_ref text;v_expected integer;v_supplied integer;
begin
  v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
  v_owner:=(v_ctx->>'owner_customer_id')::uuid;
  select * into v_order from public.rr_market_partner_order_v67
  where id=p_order_id and owner_customer_id=v_owner and data_mode='TEST'
    and status in('DRAFT','READY')
  for update;
  if v_order.id is null then raise exception 'Customer requirement is unavailable for PI.';end if;
  if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then
    raise exception 'PI needs every requirement line.';
  end if;
  select count(*) into v_expected from public.rr_market_partner_order_line_v67 where order_id=v_order.id;
  select count(distinct(value->>'line_id')) into v_supplied from jsonb_array_elements(p_lines);
  if v_supplied<>v_expected or jsonb_array_length(p_lines)<>v_expected then
    raise exception 'PI needs every requirement line exactly once.';
  end if;

  for v_input in select value from jsonb_array_elements(p_lines) loop
    begin
      v_qty:=(v_input->>'qty')::integer;
    exception when others then
      raise exception 'PI quantity must be a whole number.';
    end;
    if v_qty is null or v_qty<0 then raise exception 'PI quantity cannot be negative or empty.';end if;
    select * into v_line from public.rr_market_partner_order_line_v67
    where id=(v_input->>'line_id')::uuid and order_id=v_order.id for update;
    if v_line.id is null then raise exception 'PI line does not belong to this requirement.';end if;
    update public.rr_market_partner_order_line_v67 set
      distributor_pi_qty=v_qty,distributor_pi_decision='WAITING',
      distributor_pi_customer_qty=null,distributor_pi_note=null,updated_at=now()
    where id=v_line.id;
  end loop;

  v_ref:=coalesce(v_order.distributor_pi_ref,public.rr_market_partner_next_distributor_pi_v67());
  update public.rr_market_partner_order_v67 set
    distributor_pi_ref=v_ref,
    distributor_pi_created_at=coalesce(distributor_pi_created_at,now()),
    distributor_pi_visible=true,distributor_pi_pushed_at=now(),
    distributor_pi_status='WAITING',distributor_pi_note=nullif(trim(p_note),''),
    distributor_pi_responded_at=null,
    status=case when status='DRAFT' then 'READY' else status end,
    customer_closed_at=case when status='DRAFT' then coalesce(customer_closed_at,now()) else customer_closed_at end,
    updated_at=now()
  where id=v_order.id;
  insert into public.rr_market_partner_event_v67(
    owner_customer_id,order_id,event_type,note,actor_kind,payload
  ) values(
    v_owner,v_order.id,'DISTRIBUTOR_PI_SENT_TO_CUSTOMER',nullif(trim(p_note),''),'DISTRIBUTOR',
    jsonb_build_object('distributor_pi_ref',v_ref,'requirement_display_no',v_order.requirement_display_no,
      'requirement_closed',true,'next_action','DISTRIBUTOR_SEND_TO_REDZED',
      'customer_ref',(select customer_ref from public.rr_market_partner_customer_v67 where id=v_order.partner_customer_id))
  );
  return jsonb_build_object('ok',true,'order_id',v_order.id,'distributor_pi_ref',v_ref,
    'distributor_pi_status','WAITING','requirement_status',case when v_order.status='DRAFT' then 'READY' else v_order.status end,
    'sent_to','DISTRIBUTOR_CUSTOMER');
end $$;

revoke all on function public.rr_market_partner_make_customer_pi_v67(text,text,uuid,jsonb,text) from public;
grant execute on function public.rr_market_partner_make_customer_pi_v67(text,text,uuid,jsonb,text) to anon,authenticated,service_role;
