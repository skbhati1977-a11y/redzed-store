-- TEST67: distributor-created customer PI, independent from REDZED's upstream PI.
-- TEST-only. MAIN/REAL flows and data are untouched.

alter table public.rr_market_partner_order_v67
  add column if not exists distributor_pi_ref text,
  add column if not exists distributor_pi_created_at timestamptz,
  add column if not exists distributor_pi_visible boolean not null default false,
  add column if not exists distributor_pi_pushed_at timestamptz,
  add column if not exists distributor_pi_status text not null default 'WAITING',
  add column if not exists distributor_pi_note text,
  add column if not exists distributor_pi_responded_at timestamptz;

alter table public.rr_market_partner_order_line_v67
  add column if not exists distributor_pi_qty integer,
  add column if not exists distributor_pi_decision text not null default 'WAITING',
  add column if not exists distributor_pi_customer_qty integer,
  add column if not exists distributor_pi_note text;

do $$ begin
  if not exists(
    select 1 from pg_constraint
    where conname='rr_market_partner_order_v67_distributor_pi_status_check'
  ) then
    alter table public.rr_market_partner_order_v67
      add constraint rr_market_partner_order_v67_distributor_pi_status_check
      check(distributor_pi_status in('WAITING','CONFIRMED','CHANGE_REQUESTED','PARTIAL','CANCELLED'));
  end if;
  if not exists(
    select 1 from pg_constraint
    where conname='rr_market_partner_order_line_v67_distributor_pi_decision_check'
  ) then
    alter table public.rr_market_partner_order_line_v67
      add constraint rr_market_partner_order_line_v67_distributor_pi_decision_check
      check(distributor_pi_decision in('WAITING','CONFIRM','CHANGE','CANCEL'));
  end if;
  if not exists(
    select 1 from pg_constraint
    where conname='rr_market_partner_order_line_v67_distributor_pi_qty_check'
  ) then
    alter table public.rr_market_partner_order_line_v67
      add constraint rr_market_partner_order_line_v67_distributor_pi_qty_check
      check(distributor_pi_qty is null or distributor_pi_qty>=0);
  end if;
  if not exists(
    select 1 from pg_constraint
    where conname='rr_market_partner_order_line_v67_distributor_pi_customer_qty_check'
  ) then
    alter table public.rr_market_partner_order_line_v67
      add constraint rr_market_partner_order_line_v67_distributor_pi_customer_qty_check
      check(distributor_pi_customer_qty is null or distributor_pi_customer_qty>=0);
  end if;
end $$;

alter table public.rr_market_partner_document_sequence_v67
  drop constraint if exists rr_market_partner_document_sequence_v67_document_kind_check;
alter table public.rr_market_partner_document_sequence_v67
  add constraint rr_market_partner_document_sequence_v67_document_kind_check
  check(document_kind in('CI','DPI'));
insert into public.rr_market_partner_document_sequence_v67(document_kind,current_no)
values('DPI',0) on conflict(document_kind)do nothing;

create or replace function public.rr_market_partner_next_distributor_pi_v67()
returns text language plpgsql security definer set search_path=public as $$
declare v_no bigint;
begin
  perform pg_advisory_xact_lock(hashtext('RR_TEST67_GLOBAL_DISTRIBUTOR_PI'));
  update public.rr_market_partner_document_sequence_v67
  set current_no=current_no+1,updated_at=now()
  where document_kind='DPI'
  returning current_no into v_no;
  if v_no is null then raise exception 'Distributor PI sequence is unavailable.';end if;
  return 'DPI67-'||lpad(v_no::text,6,'0');
end $$;

create or replace function public.rr_market_partner_make_customer_pi_v67(
  p_session_token text,p_device_id text,p_order_id uuid,p_lines jsonb,p_note text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_ctx jsonb;v_owner uuid;v_order public.rr_market_partner_order_v67%rowtype;
  v_line public.rr_market_partner_order_line_v67%rowtype;v_input jsonb;v_qty integer;
  v_ref text;v_expected integer;v_supplied integer;
begin
  v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
  v_owner:=(v_ctx->>'owner_customer_id')::uuid;
  select * into v_order from public.rr_market_partner_order_v67
  where id=p_order_id and owner_customer_id=v_owner and data_mode='TEST'
    and status in('DRAFT','READY','BATCHED','PI_PROPOSED','CONFIRMED','PARTIAL_CONFIRMED','CI_FINAL')
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

create or replace function public.rr_market_partner_customer_pi_state_v67(
  p_session_token text,p_device_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb;v_owner uuid;
begin
  v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
  v_owner:=(v_ctx->>'owner_customer_id')::uuid;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'order_id',o.id,'distributor_pi_ref',o.distributor_pi_ref,
    'distributor_pi_created_at',o.distributor_pi_created_at,
    'distributor_pi_visible',o.distributor_pi_visible,
    'distributor_pi_pushed_at',o.distributor_pi_pushed_at,
    'distributor_pi_status',o.distributor_pi_status,
    'distributor_pi_note',o.distributor_pi_note,
    'distributor_pi_responded_at',o.distributor_pi_responded_at,
    'lines',(select coalesce(jsonb_agg(jsonb_build_object(
      'id',l.id,'distributor_pi_qty',l.distributor_pi_qty,
      'distributor_pi_decision',l.distributor_pi_decision,
      'distributor_pi_customer_qty',l.distributor_pi_customer_qty,
      'distributor_pi_note',l.distributor_pi_note
    ) order by l.lot_no),'[]'::jsonb)
    from public.rr_market_partner_order_line_v67 l where l.order_id=o.id)
  ) order by o.created_at desc)
  from public.rr_market_partner_order_v67 o
  where o.owner_customer_id=v_owner and o.data_mode='TEST'),'[]'::jsonb);
end $$;

create or replace function public.rr_market_partner_customer_pi_view_v67(p_token text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_map public.rr_market_partner_collection_v67%rowtype;v_root uuid;
  v_order public.rr_market_partner_order_v67%rowtype;
begin
  select pc.* into v_map from public.rr_market_partner_collection_v67 pc
  join public.rr_market_share_v9420 s on s.id=pc.share_id
  where(s.token=p_token or s.short_code=upper(p_token))
    and s.data_mode='TEST' and s.status='ACTIVE'
  order by case when s.token=p_token then 0 else 1 end limit 1;
  if v_map.id is null then return null;end if;
  v_root:=coalesce(v_map.root_collection_id,v_map.id);
  select o.* into v_order from public.rr_market_partner_order_v67 o
  join public.rr_market_partner_collection_v67 pc on pc.id=o.collection_id
  where pc.root_collection_id=v_root and o.status<>'SUPERSEDED'
  order by o.requirement_update_no desc,o.created_at desc limit 1;
  if v_order.id is null or not v_order.distributor_pi_visible or v_order.distributor_pi_ref is null then
    return null;
  end if;
  return jsonb_build_object(
    'ref',v_order.distributor_pi_ref,'status',v_order.distributor_pi_status,
    'note',v_order.distributor_pi_note,'pushed_at',v_order.distributor_pi_pushed_at,
    'lines',(select coalesce(jsonb_agg(jsonb_build_object(
      'id',l.id,'lot_no',l.lot_no,'category',l.category,'size_text',l.size_text,
      'image_url',l.image_url,'requested_qty',l.requested_qty,
      'proposed_qty',coalesce(l.distributor_pi_qty,l.requested_qty),
      'rate',l.final_customer_rate,'decision',l.distributor_pi_decision,
      'customer_qty',l.distributor_pi_customer_qty
    ) order by l.lot_no),'[]'::jsonb)
    from public.rr_market_partner_order_line_v67 l where l.order_id=v_order.id)
  );
end $$;

create or replace function public.rr_market_partner_customer_distributor_pi_response_v67(
  p_token text,p_decisions jsonb,p_note text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_map public.rr_market_partner_collection_v67%rowtype;v_root uuid;
  v_order public.rr_market_partner_order_v67%rowtype;
  v_dec jsonb;v_line uuid;v_action text;v_qty integer;
  v_expected integer;v_supplied integer;v_wait integer;v_confirm integer;v_change integer;v_cancel integer;v_status text;
begin
  select pc.* into v_map from public.rr_market_partner_collection_v67 pc
  join public.rr_market_share_v9420 s on s.id=pc.share_id
  where(s.token=p_token or s.short_code=upper(p_token))
    and s.data_mode='TEST' and s.status='ACTIVE'
  order by case when s.token=p_token then 0 else 1 end limit 1;
  if v_map.id is null then raise exception 'Distributor collection is unavailable.';end if;
  v_root:=coalesce(v_map.root_collection_id,v_map.id);
  select o.* into v_order from public.rr_market_partner_order_v67 o
  join public.rr_market_partner_collection_v67 pc on pc.id=o.collection_id
  where pc.root_collection_id=v_root and o.status<>'SUPERSEDED'
    and o.distributor_pi_visible and o.distributor_pi_ref is not null
  order by o.requirement_update_no desc,o.created_at desc limit 1 for update of o;
  if v_order.id is null then raise exception 'Distributor PI is unavailable.';end if;
  if jsonb_typeof(p_decisions)<>'array' or jsonb_array_length(p_decisions)=0 then
    raise exception 'PI response needs every line.';
  end if;
  select count(*) into v_expected from public.rr_market_partner_order_line_v67 where order_id=v_order.id;
  select count(distinct(value->>'line_id')) into v_supplied from jsonb_array_elements(p_decisions);
  if v_supplied<>v_expected or jsonb_array_length(p_decisions)<>v_expected then
    raise exception 'PI response needs every line exactly once.';
  end if;

  for v_dec in select value from jsonb_array_elements(p_decisions) loop
    v_line:=(v_dec->>'line_id')::uuid;v_action:=upper(coalesce(v_dec->>'action',''));
    if v_action not in('CONFIRM','CHANGE','CANCEL') then raise exception 'Invalid PI response action.';end if;
    begin
      v_qty:=(v_dec->>'qty')::integer;
    exception when others then
      raise exception 'PI response quantity must be a whole number.';
    end;
    if v_action='CHANGE' and (v_qty is null or v_qty<0) then
      raise exception 'Changed PI quantity cannot be negative or empty.';
    end if;
    update public.rr_market_partner_order_line_v67 set
      distributor_pi_decision=v_action,
      distributor_pi_customer_qty=case when v_action='CONFIRM' then coalesce(distributor_pi_qty,requested_qty)
        when v_action='CANCEL' then 0 else v_qty end,
      distributor_pi_note=nullif(trim(v_dec->>'note'),''),updated_at=now()
    where id=v_line and order_id=v_order.id;
    if not found then raise exception 'PI response line does not belong to this requirement.';end if;
  end loop;
  select count(*)filter(where distributor_pi_decision='WAITING'),
    count(*)filter(where distributor_pi_decision='CONFIRM'),
    count(*)filter(where distributor_pi_decision='CHANGE'),
    count(*)filter(where distributor_pi_decision='CANCEL')
  into v_wait,v_confirm,v_change,v_cancel
  from public.rr_market_partner_order_line_v67 where order_id=v_order.id;
  if v_wait>0 then raise exception 'Every PI line needs a customer decision.';end if;
  v_status:=case when v_cancel=v_expected then 'CANCELLED'
    when v_change=v_expected then 'CHANGE_REQUESTED'
    when v_cancel>0 or v_change>0 then 'PARTIAL' else 'CONFIRMED' end;
  update public.rr_market_partner_order_v67 set
    distributor_pi_status=v_status,distributor_pi_note=nullif(trim(p_note),''),
    distributor_pi_responded_at=now(),updated_at=now()
  where id=v_order.id;
  insert into public.rr_market_partner_event_v67(
    owner_customer_id,order_id,event_type,note,actor_kind,payload
  ) values(
    v_order.owner_customer_id,v_order.id,'CUSTOMER_DISTRIBUTOR_PI_RESPONSE',nullif(trim(p_note),''),'CUSTOMER',
    jsonb_build_object('distributor_pi_ref',v_order.distributor_pi_ref,'distributor_pi_status',v_status)
  );
  return jsonb_build_object('ok',true,'order_id',v_order.id,
    'distributor_pi_ref',v_order.distributor_pi_ref,'distributor_pi_status',v_status,'sent_to','DISTRIBUTOR');
end $$;

revoke all on function public.rr_market_partner_next_distributor_pi_v67() from public,anon,authenticated;
revoke all on function public.rr_market_partner_make_customer_pi_v67(text,text,uuid,jsonb,text) from public;
revoke all on function public.rr_market_partner_customer_pi_state_v67(text,text) from public;
revoke all on function public.rr_market_partner_customer_pi_view_v67(text) from public;
revoke all on function public.rr_market_partner_customer_distributor_pi_response_v67(text,jsonb,text) from public;
grant execute on function public.rr_market_partner_make_customer_pi_v67(text,text,uuid,jsonb,text) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_pi_state_v67(text,text) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_pi_view_v67(text) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_distributor_pi_response_v67(text,jsonb,text) to anon,authenticated,service_role;
