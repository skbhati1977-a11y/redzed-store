-- TEST67: private distributor customers, owner-wide orders and multi-order batches.
-- Additive and TEST-only. No REAL rows can be created through these RPCs.

create table if not exists public.rr_market_partner_customer_v67 (
  id uuid primary key default gen_random_uuid(),
  owner_customer_id uuid not null references public.rr_customers(id),
  customer_ref text not null,
  private_name text not null,
  private_mobile text,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','INACTIVE')),
  data_mode text not null default 'TEST' check (data_mode='TEST'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_customer_id,customer_ref,data_mode)
);

create table if not exists public.rr_market_partner_order_v67 (
  id uuid primary key default gen_random_uuid(),
  owner_customer_id uuid not null references public.rr_customers(id),
  partner_customer_id uuid not null references public.rr_market_partner_customer_v67(id),
  sequence_no bigint not null,
  order_ref text not null,
  status text not null default 'DRAFT' check (status in
    ('DRAFT','READY','BATCHED','PI_PROPOSED','CONFIRMED','PARTIAL_CONFIRMED','CANCELLED','CI_FINAL','CLOSED')),
  confirmation_note text,
  linked_requirement_id uuid references public.rr_market_requirements_v9420(id),
  pi_ref text,
  ci_ref text,
  data_mode text not null default 'TEST' check (data_mode='TEST'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_customer_id,sequence_no,data_mode),
  unique(owner_customer_id,order_ref,data_mode)
);

create table if not exists public.rr_market_partner_order_line_v67 (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.rr_market_partner_order_v67(id) on delete cascade,
  lot_no text not null,
  article_name text,
  image_url text,
  requested_qty integer not null check (requested_qty>0),
  proposed_qty integer check (proposed_qty>=0),
  confirmed_qty integer check (confirmed_qty>=0),
  base_rate numeric(14,2) not null check (base_rate>=0),
  rate_enhancement numeric(14,2) not null default 0 check (rate_enhancement>=0),
  customer_rate numeric(14,2) generated always as (base_rate+rate_enhancement) stored,
  confirmation_status text not null default 'WAITING' check (confirmation_status in
    ('WAITING','CONFIRMED','CHANGE_REQUESTED','CANCELLED')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(order_id,lot_no)
);

create table if not exists public.rr_market_partner_batch_v67 (
  id uuid primary key default gen_random_uuid(),
  owner_customer_id uuid not null references public.rr_customers(id),
  batch_ref text not null,
  status text not null default 'SUBMITTED' check (status in
    ('SUBMITTED','PI_PROPOSED','WAITING_CONFIRMATION','CONFIRMED','PARTIAL_CONFIRMED','CANCELLED','CI_FINAL','CLOSED')),
  pi_ref text,
  ci_ref text,
  data_mode text not null default 'TEST' check (data_mode='TEST'),
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_customer_id,batch_ref,data_mode)
);

create table if not exists public.rr_market_partner_batch_member_v67 (
  batch_id uuid not null references public.rr_market_partner_batch_v67(id) on delete cascade,
  order_id uuid not null references public.rr_market_partner_order_v67(id),
  selected_at timestamptz not null default now(),
  primary key(batch_id,order_id),
  unique(order_id)
);

create table if not exists public.rr_market_partner_event_v67 (
  id bigint generated always as identity primary key,
  owner_customer_id uuid not null references public.rr_customers(id),
  batch_id uuid references public.rr_market_partner_batch_v67(id),
  order_id uuid references public.rr_market_partner_order_v67(id),
  event_type text not null,
  note text,
  payload jsonb not null default '{}'::jsonb,
  actor_kind text not null check (actor_kind in ('STAFF','DISTRIBUTOR','SYSTEM')),
  actor_id uuid,
  created_at timestamptz not null default now()
);

alter table public.rr_market_partner_customer_v67 enable row level security;
alter table public.rr_market_partner_order_v67 enable row level security;
alter table public.rr_market_partner_order_line_v67 enable row level security;
alter table public.rr_market_partner_batch_v67 enable row level security;
alter table public.rr_market_partner_batch_member_v67 enable row level security;
alter table public.rr_market_partner_event_v67 enable row level security;

revoke all on public.rr_market_partner_customer_v67 from public,anon,authenticated;
revoke all on public.rr_market_partner_order_v67 from public,anon,authenticated;
revoke all on public.rr_market_partner_order_line_v67 from public,anon,authenticated;
revoke all on public.rr_market_partner_batch_v67 from public,anon,authenticated;
revoke all on public.rr_market_partner_batch_member_v67 from public,anon,authenticated;
revoke all on public.rr_market_partner_event_v67 from public,anon,authenticated;
grant all on public.rr_market_partner_customer_v67 to service_role;
grant all on public.rr_market_partner_order_v67 to service_role;
grant all on public.rr_market_partner_order_line_v67 to service_role;
grant all on public.rr_market_partner_batch_v67 to service_role;
grant all on public.rr_market_partner_batch_member_v67 to service_role;
grant all on public.rr_market_partner_event_v67 to service_role;

create or replace function public.rr_market_configure_distributor_v67(
  p_customer_id uuid, p_prefix text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_prefix text:=upper(regexp_replace(coalesce(p_prefix,''),'[^A-Za-z0-9]','','g'));
begin
  perform public.rr_market_superadmin_required_v61();
  if p_customer_id is null then raise exception 'Distributor customer is required.'; end if;
  if length(v_prefix)<2 or length(v_prefix)>8 then raise exception 'Prefix must be 2-8 letters/numbers.'; end if;
  if not exists(select 1 from public.rr_customers where id=p_customer_id and is_active) then
    raise exception 'Active distributor customer not found.';
  end if;
  insert into public.rr_market_owner_sequence_v67(owner_key,data_mode,prefix,current_no)
  values('CUSTOMER:'||p_customer_id::text,'TEST',v_prefix,0)
  on conflict(owner_key,data_mode) do update set prefix=excluded.prefix,updated_at=now();
  insert into public.rr_market_workspace_access_v61(
    subject_kind,subject_id,menu_enabled,seller_workspace_enabled,customer_groups_enabled,
    send_collection_enabled,receive_requirement_enabled,forward_requirement_enabled,
    pi_convert_enabled,ci_convert_enabled,updated_at,updated_by
  ) values('CUSTOMER',p_customer_id,true,true,true,true,true,true,true,true,now(),auth.uid())
  on conflict(subject_kind,subject_id) do update set
    menu_enabled=true,seller_workspace_enabled=true,customer_groups_enabled=true,
    send_collection_enabled=true,receive_requirement_enabled=true,forward_requirement_enabled=true,
    pi_convert_enabled=true,ci_convert_enabled=true,updated_at=now(),updated_by=auth.uid();
  return jsonb_build_object('ok',true,'customer_id',p_customer_id,'prefix',v_prefix,'data_mode','TEST');
end $$;

create or replace function public.rr_market_partner_context_v67(p_session_token text,p_device_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_session jsonb; v_owner uuid; v_access public.rr_market_workspace_access_v61%rowtype;
begin
  v_session:=public.rr_customer_session_validate_v9590(p_session_token,p_device_id);
  if upper(v_session->>'data_mode')<>'TEST' then raise exception 'TEST67 workspace is TEST-only.'; end if;
  v_owner:=(v_session->>'customer_id')::uuid;
  select * into v_access from public.rr_market_workspace_access_v61
   where subject_kind='CUSTOMER' and subject_id=v_owner;
  if v_access.subject_id is null or not v_access.menu_enabled or not v_access.seller_workspace_enabled then
    raise exception 'Distributor Market Window is not enabled.';
  end if;
  return jsonb_build_object('owner_customer_id',v_owner,'data_mode','TEST',
    'customer_groups_enabled',v_access.customer_groups_enabled,
    'send_collection_enabled',v_access.send_collection_enabled,
    'receive_requirement_enabled',v_access.receive_requirement_enabled,
    'pi_convert_enabled',v_access.pi_convert_enabled,'ci_convert_enabled',v_access.ci_convert_enabled);
end $$;

create or replace function public.rr_market_partner_customer_create_v67(
  p_session_token text,p_device_id text,p_name text,p_mobile text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb; v_owner uuid; v_no bigint; v_prefix text; v_id uuid; v_ref text;
begin
  v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
  if not (v_ctx->>'customer_groups_enabled')::boolean then raise exception 'Customer creation is disabled.'; end if;
  if nullif(trim(p_name),'') is null then raise exception 'Customer name is required.'; end if;
  v_owner:=(v_ctx->>'owner_customer_id')::uuid;
  select prefix,current_no+1 into v_prefix,v_no from public.rr_market_owner_sequence_v67
   where owner_key='CUSTOMER:'||v_owner::text and data_mode='TEST' for update;
  if v_prefix is null then raise exception 'Distributor prefix is not configured.'; end if;
  -- Customer IDs have their own private counter, independent from order numbering.
  select coalesce(max((regexp_match(customer_ref,'([0-9]+)$'))[1]::bigint),0)+1 into v_no
   from public.rr_market_partner_customer_v67 where owner_customer_id=v_owner and data_mode='TEST';
  v_ref:=v_prefix||'-C-'||lpad(v_no::text,4,'0');
  insert into public.rr_market_partner_customer_v67(owner_customer_id,customer_ref,private_name,private_mobile)
   values(v_owner,v_ref,trim(p_name),nullif(trim(p_mobile),'')) returning id into v_id;
  return jsonb_build_object('id',v_id,'customer_ref',v_ref,'private_name',trim(p_name));
end $$;

create or replace function public.rr_market_partner_order_create_v67(
  p_session_token text,p_device_id text,p_partner_customer_id uuid,p_lines jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb; v_owner uuid; v_seq bigint; v_prefix text; v_ref text; v_order uuid;
  v_line jsonb; v_card record; v_lot text; v_qty int; v_enh numeric;
begin
  v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
  v_owner:=(v_ctx->>'owner_customer_id')::uuid;
  if not exists(select 1 from public.rr_market_partner_customer_v67
    where id=p_partner_customer_id and owner_customer_id=v_owner and status='ACTIVE') then
    raise exception 'Private customer not found.';
  end if;
  if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'At least one order line is required.'; end if;
  select prefix,current_no+1 into v_prefix,v_seq from public.rr_market_owner_sequence_v67
   where owner_key='CUSTOMER:'||v_owner::text and data_mode='TEST' for update;
  if v_prefix is null then raise exception 'Distributor prefix is not configured.'; end if;
  update public.rr_market_owner_sequence_v67 set current_no=v_seq,updated_at=now()
   where owner_key='CUSTOMER:'||v_owner::text and data_mode='TEST';
  v_ref:=v_prefix||'-'||lpad(v_seq::text,3,'0');
  insert into public.rr_market_partner_order_v67(owner_customer_id,partner_customer_id,sequence_no,order_ref,status)
   values(v_owner,p_partner_customer_id,v_seq,v_ref,'READY') returning id into v_order;
  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_lot:=nullif(trim(v_line->>'lot_no'),'');
    v_qty:=coalesce((v_line->>'requested_qty')::int,0);
    v_enh:=coalesce((v_line->>'rate_enhancement')::numeric,0);
    if v_lot is null or v_qty<=0 or v_enh<0 then raise exception 'Invalid lot, quantity or rate enhancement.'; end if;
    select * into v_card from public.rr_web_window_cards_v9329(v_lot,null,null,'TEST',10,0)
     where lot_no=v_lot limit 1;
    if v_card.lot_no is null then raise exception 'Lot % is not available in TEST Market Window.',v_lot; end if;
    insert into public.rr_market_partner_order_line_v67(
      order_id,lot_no,article_name,image_url,requested_qty,base_rate,rate_enhancement
    ) values(v_order,v_lot,coalesce(v_card.full_item_name,v_card.short_item_name),v_card.primary_image_url,
      v_qty,coalesce(v_card.sale_rate,0),v_enh);
  end loop;
  insert into public.rr_market_partner_event_v67(owner_customer_id,order_id,event_type,actor_kind,payload)
   values(v_owner,v_order,'ORDER_CREATED','DISTRIBUTOR',jsonb_build_object('order_ref',v_ref));
  return jsonb_build_object('order_id',v_order,'order_ref',v_ref,'collection_no',v_ref,
    'requirement_no',v_ref,'status','READY');
end $$;

create or replace function public.rr_market_partner_batch_submit_v67(
  p_session_token text,p_device_id text,p_order_ids uuid[]
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb; v_owner uuid; v_batch uuid; v_batch_ref text; v_count int;
begin
  v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
  if not (v_ctx->>'send_collection_enabled')::boolean then raise exception 'Batch submission is disabled.'; end if;
  v_owner:=(v_ctx->>'owner_customer_id')::uuid;
  select count(*) into v_count from public.rr_market_partner_order_v67
   where id=any(p_order_ids) and owner_customer_id=v_owner and status='READY';
  if coalesce(array_length(p_order_ids,1),0)=0 or v_count<>array_length(p_order_ids,1) then
    raise exception 'Select only your READY orders.';
  end if;
  v_batch_ref:='B-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS');
  insert into public.rr_market_partner_batch_v67(owner_customer_id,batch_ref)
   values(v_owner,v_batch_ref) returning id into v_batch;
  insert into public.rr_market_partner_batch_member_v67(batch_id,order_id)
   select v_batch,unnest(p_order_ids);
  update public.rr_market_partner_order_v67 set status='BATCHED',updated_at=now() where id=any(p_order_ids);
  insert into public.rr_market_partner_event_v67(owner_customer_id,batch_id,event_type,actor_kind,payload)
   values(v_owner,v_batch,'BATCH_SUBMITTED','DISTRIBUTOR',jsonb_build_object('order_count',v_count));
  return jsonb_build_object('batch_id',v_batch,'batch_ref',v_batch_ref,'order_count',v_count,'status','SUBMITTED');
end $$;

create or replace function public.rr_market_partner_workspace_v67(p_session_token text,p_device_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb; v_owner uuid;
begin
  v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
  v_owner:=(v_ctx->>'owner_customer_id')::uuid;
  return v_ctx||jsonb_build_object(
    'customers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'customer_ref',customer_ref,
      'name',private_name,'mobile',private_mobile,'status',status) order by customer_ref)
      from public.rr_market_partner_customer_v67 where owner_customer_id=v_owner),'[]'::jsonb),
    'orders',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'order_ref',o.order_ref,
      'status',o.status,'customer_id',o.partner_customer_id,'customer_ref',c.customer_ref,'customer_name',c.private_name,
      'pi_ref',o.pi_ref,'ci_ref',o.ci_ref,'lines',(select jsonb_agg(jsonb_build_object(
        'id',l.id,'lot_no',l.lot_no,'article_name',l.article_name,'image_url',l.image_url,
        'requested_qty',l.requested_qty,'proposed_qty',l.proposed_qty,'confirmed_qty',l.confirmed_qty,
        'base_rate',l.base_rate,'rate_enhancement',l.rate_enhancement,'customer_rate',l.customer_rate,
        'confirmation_status',l.confirmation_status) order by l.lot_no)
        from public.rr_market_partner_order_line_v67 l where l.order_id=o.id)) order by o.sequence_no desc)
      from public.rr_market_partner_order_v67 o join public.rr_market_partner_customer_v67 c on c.id=o.partner_customer_id
      where o.owner_customer_id=v_owner),'[]'::jsonb),
    'batches',coalesce((select jsonb_agg(jsonb_build_object('id',id,'batch_ref',batch_ref,'status',status,
      'pi_ref',pi_ref,'ci_ref',ci_ref,'submitted_at',submitted_at) order by submitted_at desc)
      from public.rr_market_partner_batch_v67 where owner_customer_id=v_owner),'[]'::jsonb));
end $$;

create or replace function public.rr_market_staff_batch_detail_v67(p_batch_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_batch public.rr_market_partner_batch_v67%rowtype;
begin
  perform public.rr_market_assert_sales_actor_v9420();
  select * into v_batch from public.rr_market_partner_batch_v67 where id=p_batch_id and data_mode='TEST';
  if v_batch.id is null then raise exception 'TEST67 batch not found.'; end if;
  return jsonb_build_object('id',v_batch.id,'batch_ref',v_batch.batch_ref,'status',v_batch.status,
    'direct_customer_id',v_batch.owner_customer_id,
    'direct_customer_name',(select customer_name from public.rr_customers where id=v_batch.owner_customer_id),
    'pi_ref',v_batch.pi_ref,'ci_ref',v_batch.ci_ref,
    -- Privacy boundary: staff receives downstream customer_ref, never private_name/mobile.
    'orders',(select jsonb_agg(jsonb_build_object('id',o.id,'order_ref',o.order_ref,'status',o.status,
      'customer_ref',c.customer_ref,'lines',(select jsonb_agg(jsonb_build_object('id',l.id,'lot_no',l.lot_no,
      'article_name',l.article_name,'image_url',l.image_url,'requested_qty',l.requested_qty,
      'proposed_qty',l.proposed_qty,'confirmed_qty',l.confirmed_qty,'base_rate',l.base_rate,
      'confirmation_status',l.confirmation_status) order by l.lot_no)
      from public.rr_market_partner_order_line_v67 l where l.order_id=o.id)) order by o.sequence_no)
      from public.rr_market_partner_batch_member_v67 m join public.rr_market_partner_order_v67 o on o.id=m.order_id
      join public.rr_market_partner_customer_v67 c on c.id=o.partner_customer_id where m.batch_id=v_batch.id),
    'consolidated',(select jsonb_agg(x order by x->>'lot_no') from (
      select jsonb_build_object('lot_no',l.lot_no,'article_name',max(l.article_name),
        'customer_count',count(distinct o.partner_customer_id),'order_count',count(distinct o.id),
        'total_requested_qty',sum(l.requested_qty),'total_proposed_qty',sum(coalesce(l.proposed_qty,l.requested_qty)),
        'total_confirmed_qty',sum(coalesce(l.confirmed_qty,0))) x
      from public.rr_market_partner_batch_member_v67 m join public.rr_market_partner_order_v67 o on o.id=m.order_id
      join public.rr_market_partner_order_line_v67 l on l.order_id=o.id where m.batch_id=v_batch.id group by l.lot_no
    ) q));
end $$;

create or replace function public.rr_market_staff_batch_queue_v67()
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  perform public.rr_market_assert_sales_actor_v9420();
  return coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'batch_ref',b.batch_ref,'status',b.status,
    'direct_customer_id',b.owner_customer_id,'direct_customer_name',c.customer_name,
    'order_count',(select count(*) from public.rr_market_partner_batch_member_v67 m where m.batch_id=b.id),
    'submitted_at',b.submitted_at) order by b.submitted_at desc)
    from public.rr_market_partner_batch_v67 b join public.rr_customers c on c.id=b.owner_customer_id
    where b.data_mode='TEST'),'[]'::jsonb);
end $$;

create or replace function public.rr_market_staff_propose_batch_v67(
  p_batch_id uuid,p_line_proposals jsonb,p_pi_ref text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_line jsonb; v_line_id uuid; v_qty int; v_owner uuid;
begin
  perform public.rr_market_assert_sales_actor_v9420();
  if nullif(trim(p_pi_ref),'') is null then raise exception 'PI reference is required.'; end if;
  select owner_customer_id into v_owner from public.rr_market_partner_batch_v67
   where id=p_batch_id and data_mode='TEST' and status in ('SUBMITTED','PI_PROPOSED','WAITING_CONFIRMATION') for update;
  if v_owner is null then raise exception 'Batch cannot receive a PI proposal.'; end if;
  for v_line in select value from jsonb_array_elements(p_line_proposals) loop
    v_line_id:=(v_line->>'line_id')::uuid; v_qty:=(v_line->>'proposed_qty')::int;
    if v_qty<0 then raise exception 'Proposed quantity cannot be negative.'; end if;
    update public.rr_market_partner_order_line_v67 l set proposed_qty=v_qty,confirmed_qty=null,
      confirmation_status='WAITING',updated_at=now()
    where l.id=v_line_id and exists(select 1 from public.rr_market_partner_batch_member_v67 m
      where m.batch_id=p_batch_id and m.order_id=l.order_id);
    if not found then raise exception 'Proposal line does not belong to batch.'; end if;
  end loop;
  update public.rr_market_partner_order_v67 o set status='PI_PROPOSED',pi_ref=trim(p_pi_ref),updated_at=now()
   where exists(select 1 from public.rr_market_partner_batch_member_v67 m where m.batch_id=p_batch_id and m.order_id=o.id);
  update public.rr_market_partner_batch_v67 set status='WAITING_CONFIRMATION',pi_ref=trim(p_pi_ref),updated_at=now()
   where id=p_batch_id;
  insert into public.rr_market_partner_event_v67(owner_customer_id,batch_id,event_type,actor_kind,actor_id,payload)
   values(v_owner,p_batch_id,'PI_PROPOSED','STAFF',auth.uid(),jsonb_build_object('pi_ref',trim(p_pi_ref)));
  return public.rr_market_staff_batch_detail_v67(p_batch_id);
end $$;

create or replace function public.rr_market_partner_confirm_order_v67(
  p_session_token text,p_device_id text,p_order_id uuid,p_decisions jsonb,p_note text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb; v_owner uuid; v_batch uuid; v_dec jsonb; v_line uuid; v_action text; v_qty int;
  v_wait int; v_confirm int; v_cancel int;
begin
  v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
  v_owner:=(v_ctx->>'owner_customer_id')::uuid;
  select m.batch_id into v_batch from public.rr_market_partner_batch_member_v67 m
   join public.rr_market_partner_order_v67 o on o.id=m.order_id
   where o.id=p_order_id and o.owner_customer_id=v_owner and o.status='PI_PROPOSED';
  if v_batch is null then raise exception 'Order is not waiting for confirmation.'; end if;
  for v_dec in select value from jsonb_array_elements(p_decisions) loop
    v_line:=(v_dec->>'line_id')::uuid; v_action:=upper(v_dec->>'action');
    if v_action not in ('CONFIRM','CHANGE','CANCEL') then raise exception 'Invalid confirmation action.'; end if;
    update public.rr_market_partner_order_line_v67 set
      confirmed_qty=case when v_action='CONFIRM' then coalesce(proposed_qty,requested_qty)
                         when v_action='CHANGE' then greatest(0,(v_dec->>'confirmed_qty')::int) else 0 end,
      confirmation_status=case v_action when 'CONFIRM' then 'CONFIRMED' when 'CHANGE' then 'CHANGE_REQUESTED' else 'CANCELLED' end,
      updated_at=now()
    where id=v_line and order_id=p_order_id;
    if not found then raise exception 'Confirmation line does not belong to order.'; end if;
  end loop;
  select count(*) filter(where confirmation_status='WAITING'),count(*) filter(where confirmation_status in ('CONFIRMED','CHANGE_REQUESTED')),
    count(*) filter(where confirmation_status='CANCELLED') into v_wait,v_confirm,v_cancel
   from public.rr_market_partner_order_line_v67 where order_id=p_order_id;
  if v_wait>0 then raise exception 'Every order line needs a decision.'; end if;
  update public.rr_market_partner_order_v67 set status=case when v_confirm=0 then 'CANCELLED'
    when v_cancel>0 then 'PARTIAL_CONFIRMED' else 'CONFIRMED' end,confirmation_note=nullif(trim(p_note),''),updated_at=now()
   where id=p_order_id;
  update public.rr_market_partner_batch_v67 b set status=case
    when exists(select 1 from public.rr_market_partner_batch_member_v67 m join public.rr_market_partner_order_v67 o on o.id=m.order_id
      where m.batch_id=b.id and o.status='PI_PROPOSED') then 'WAITING_CONFIRMATION'
    when exists(select 1 from public.rr_market_partner_batch_member_v67 m join public.rr_market_partner_order_v67 o on o.id=m.order_id
      where m.batch_id=b.id and o.status in ('PARTIAL_CONFIRMED','CANCELLED')) then 'PARTIAL_CONFIRMED'
    else 'CONFIRMED' end,updated_at=now() where b.id=v_batch;
  insert into public.rr_market_partner_event_v67(owner_customer_id,batch_id,order_id,event_type,note,actor_kind,payload)
   values(v_owner,v_batch,p_order_id,'ORDER_CONFIRMATION',nullif(trim(p_note),''),'DISTRIBUTOR',
     jsonb_build_object('confirmed_lines',v_confirm,'cancelled_lines',v_cancel));
  return jsonb_build_object('ok',true,'order_id',p_order_id,'batch_id',v_batch,
    'batch_status',(select status from public.rr_market_partner_batch_v67 where id=v_batch));
end $$;

create or replace function public.rr_market_staff_finalize_ci_v67(p_batch_id uuid,p_ci_ref text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_owner uuid;
begin
  perform public.rr_market_assert_sales_actor_v9420();
  if nullif(trim(p_ci_ref),'') is null then raise exception 'CI reference is required.'; end if;
  select owner_customer_id into v_owner from public.rr_market_partner_batch_v67
   where id=p_batch_id and data_mode='TEST' and status in ('CONFIRMED','PARTIAL_CONFIRMED') for update;
  if v_owner is null then raise exception 'Batch confirmation is not complete.'; end if;
  update public.rr_market_partner_batch_v67 set status='CI_FINAL',ci_ref=trim(p_ci_ref),updated_at=now() where id=p_batch_id;
  update public.rr_market_partner_order_v67 o set status=case when o.status='CANCELLED' then 'CANCELLED' else 'CI_FINAL' end,
    ci_ref=trim(p_ci_ref),updated_at=now() where exists(select 1 from public.rr_market_partner_batch_member_v67 m
      where m.batch_id=p_batch_id and m.order_id=o.id);
  insert into public.rr_market_partner_event_v67(owner_customer_id,batch_id,event_type,actor_kind,actor_id,payload)
   values(v_owner,p_batch_id,'CI_FINAL','STAFF',auth.uid(),jsonb_build_object('ci_ref',trim(p_ci_ref)));
  return public.rr_market_staff_batch_detail_v67(p_batch_id);
end $$;

revoke all on function public.rr_market_configure_distributor_v67(uuid,text) from public,anon;
revoke all on function public.rr_market_partner_context_v67(text,text) from public;
revoke all on function public.rr_market_partner_customer_create_v67(text,text,text,text) from public;
revoke all on function public.rr_market_partner_order_create_v67(text,text,uuid,jsonb) from public;
revoke all on function public.rr_market_partner_batch_submit_v67(text,text,uuid[]) from public;
revoke all on function public.rr_market_partner_workspace_v67(text,text) from public;
revoke all on function public.rr_market_staff_batch_detail_v67(uuid) from public,anon;
revoke all on function public.rr_market_staff_batch_queue_v67() from public,anon;
revoke all on function public.rr_market_staff_propose_batch_v67(uuid,jsonb,text) from public,anon;
revoke all on function public.rr_market_partner_confirm_order_v67(text,text,uuid,jsonb,text) from public;
revoke all on function public.rr_market_staff_finalize_ci_v67(uuid,text) from public,anon;

grant execute on function public.rr_market_configure_distributor_v67(uuid,text) to authenticated,service_role;
grant execute on function public.rr_market_partner_context_v67(text,text) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_create_v67(text,text,text,text) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_order_create_v67(text,text,uuid,jsonb) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_batch_submit_v67(text,text,uuid[]) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_workspace_v67(text,text) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_confirm_order_v67(text,text,uuid,jsonb,text) to anon,authenticated,service_role;
grant execute on function public.rr_market_staff_batch_detail_v67(uuid) to authenticated,service_role;
grant execute on function public.rr_market_staff_batch_queue_v67() to authenticated,service_role;
grant execute on function public.rr_market_staff_propose_batch_v67(uuid,jsonb,text) to authenticated,service_role;
grant execute on function public.rr_market_staff_finalize_ci_v67(uuid,text) to authenticated,service_role;
