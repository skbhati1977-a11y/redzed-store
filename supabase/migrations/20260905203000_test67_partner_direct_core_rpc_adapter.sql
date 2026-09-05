-- TEST67 only: map the established REDZED -> customer collection core onto
-- Distributor -> Distributor Customer while preserving relation privacy.

create or replace function public.rr_market_partner_customer_context_v80(
  p_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
  v_customer uuid;
  v_root uuid;
begin
  select
    pc.owner_customer_id,
    pc.partner_customer_id,
    coalesce(pc.root_collection_id, pc.id)
  into v_owner, v_customer, v_root
  from public.rr_market_share_v9420 s
  join public.rr_market_partner_collection_v67 pc on pc.share_id = s.id
  join public.rr_market_partner_customer_v67 c
    on c.id = pc.partner_customer_id
   and c.owner_customer_id = pc.owner_customer_id
  where (s.token = p_token or s.short_code = upper(p_token))
    and s.status = 'ACTIVE'
    and s.data_mode = 'TEST'
    and c.status = 'ACTIVE'
    and pc.status <> 'CANCELLED'
    and not pc.legacy_hidden_v78
  order by case when s.token = p_token then 0 else 1 end
  limit 1;

  if v_owner is null or v_customer is null or v_root is null then
    raise exception 'Distributor customer collection is unavailable.';
  end if;

  return jsonb_build_object(
    'owner_customer_id', v_owner,
    'partner_customer_id', v_customer,
    'root_collection_id', v_root
  );
end;
$$;

create or replace function public.rr_market_partner_customer_current_state_v80(
  p_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ctx jsonb;
  v_owner uuid;
  v_customer uuid;
  v_root uuid;
  v_collection public.rr_market_partner_collection_v67%rowtype;
  v_order public.rr_market_partner_order_v67%rowtype;
  v_requested_update integer;
  v_update integer;
  v_status text;
begin
  v_ctx := public.rr_market_partner_customer_context_v80(p_token);
  v_owner := (v_ctx ->> 'owner_customer_id')::uuid;
  v_customer := (v_ctx ->> 'partner_customer_id')::uuid;
  v_root := (v_ctx ->> 'root_collection_id')::uuid;

  select pc.*
  into v_collection
  from public.rr_market_partner_collection_v67 pc
  where coalesce(pc.root_collection_id, pc.id) = v_root
    and pc.owner_customer_id = v_owner
    and pc.partner_customer_id = v_customer
    and pc.status <> 'CANCELLED'
    and not pc.legacy_hidden_v78
  order by pc.collection_update_no desc, pc.created_at desc
  limit 1;

  select o.*
  into v_order
  from public.rr_market_partner_order_v67 o
  join public.rr_market_partner_collection_v67 pc on pc.id = o.collection_id
  where coalesce(pc.root_collection_id, pc.id) = v_root
    and o.owner_customer_id = v_owner
    and o.partner_customer_id = v_customer
    and o.data_mode = 'TEST'
    and o.status <> 'SUPERSEDED'
  order by o.requirement_update_no desc, o.created_at desc
  limit 1;

  select max(
    case
      when e.payload ->> 'requested_update_no' ~ '^[0-9]+$'
        then (e.payload ->> 'requested_update_no')::integer
      else null
    end
  )
  into v_requested_update
  from public.rr_market_partner_event_v67 e
  where e.owner_customer_id = v_owner
    and e.event_type = 'CHAT_MESSAGE'
    and e.payload ->> 'action' = 'MORE_SAMPLES_REQUESTED'
    and e.payload ->> 'customer_id' = v_customer::text
    and e.payload ->> 'root_collection_id' = v_root::text;

  v_update := greatest(
    coalesce(v_collection.collection_update_no, 0),
    coalesce(v_requested_update, 0)
  );
  v_status := case
    when v_order.id is null or v_order.status = 'DRAFT' then 'OPEN'
    when v_order.status = 'CI_FINAL' then 'CI_GENERATED'
    when v_order.distributor_pi_ref is not null then 'PI_GENERATED'
    else 'CLOSED'
  end;

  return jsonb_build_object(
    'collection_cycle_id', v_root,
    'collection_display_no', 'COLLECTION ' || v_collection.collection_no::text,
    'collection_status', v_status,
    'update_no', v_update,
    'requirement_display_no', v_order.requirement_display_no,
    'requirement_status', v_order.status,
    'sent_to', 'DISTRIBUTOR'
  );
end;
$$;

create or replace function public.rr_market_partner_customer_pricing_v80(
  p_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ctx jsonb;
  v_owner uuid;
  v_customer uuid;
  v_root uuid;
  v_rows jsonb;
begin
  v_ctx := public.rr_market_partner_customer_context_v80(p_token);
  v_owner := (v_ctx ->> 'owner_customer_id')::uuid;
  v_customer := (v_ctx ->> 'partner_customer_id')::uuid;
  v_root := (v_ctx ->> 'root_collection_id')::uuid;

  with latest_line as (
    select distinct on (lower(trim(l.lot_no)))
      l.lot_no,
      l.distributor_sale_rate,
      l.discount_amount,
      l.final_customer_rate,
      pc.collection_update_no,
      l.created_at
    from public.rr_market_partner_collection_v67 pc
    join public.rr_market_partner_collection_line_v67 l
      on l.collection_id = pc.id
    where coalesce(pc.root_collection_id, pc.id) = v_root
      and pc.owner_customer_id = v_owner
      and pc.partner_customer_id = v_customer
      and pc.status <> 'CANCELLED'
      and not pc.legacy_hidden_v78
    order by
      lower(trim(l.lot_no)),
      pc.collection_update_no desc,
      l.created_at desc
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'lot_no', lot_no,
        'approved_rate', distributor_sale_rate,
        'allowed_discount', discount_amount,
        'net_rate', final_customer_rate,
        'pricing_status', 'RESOLVED'
      )
      order by collection_update_no desc, created_at desc
    ),
    '[]'::jsonb
  )
  into v_rows
  from latest_line;

  return jsonb_build_object(
    'partner_customer_id', v_customer,
    'rows', v_rows
  );
end;
$$;

create or replace function public.rr_market_partner_customer_requirement_summary_v80(
  p_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ctx jsonb;
  v_owner uuid;
  v_customer uuid;
  v_root uuid;
  v_order public.rr_market_partner_order_v67%rowtype;
  v_lines jsonb;
begin
  v_ctx := public.rr_market_partner_customer_context_v80(p_token);
  v_owner := (v_ctx ->> 'owner_customer_id')::uuid;
  v_customer := (v_ctx ->> 'partner_customer_id')::uuid;
  v_root := (v_ctx ->> 'root_collection_id')::uuid;

  select o.*
  into v_order
  from public.rr_market_partner_order_v67 o
  join public.rr_market_partner_collection_v67 pc on pc.id = o.collection_id
  where coalesce(pc.root_collection_id, pc.id) = v_root
    and o.owner_customer_id = v_owner
    and o.partner_customer_id = v_customer
    and o.data_mode = 'TEST'
    and o.status <> 'SUPERSEDED'
  order by o.requirement_update_no desc, o.created_at desc
  limit 1;

  if v_order.id is null then
    return jsonb_build_object(
      'collection_cycle_id', v_root,
      'requirement_id', null,
      'lines', '[]'::jsonb
    );
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'lot_no', l.lot_no,
        'requested_qty', l.requested_qty,
        'accepted_qty', l.requested_qty,
        'requirement_id', v_order.id,
        'update_no', v_order.requirement_update_no
      )
      order by l.lot_no
    ),
    '[]'::jsonb
  )
  into v_lines
  from public.rr_market_partner_order_line_v67 l
  where l.order_id = v_order.id;

  return jsonb_build_object(
    'collection_cycle_id', v_root,
    'requirement_id', v_order.id,
    'requirement_display_no', v_order.requirement_display_no,
    'status', v_order.status,
    'lines', v_lines
  );
end;
$$;

create or replace function public.rr_market_partner_customer_ci_history_v80(
  p_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_metrics jsonb;
  v_qty numeric;
  v_amount numeric;
begin
  v_metrics := public.rr_market_partner_customer_metrics_by_token_v67(p_token);
  v_qty := greatest(0, coalesce((v_metrics ->> 'history_qty')::numeric, 0));
  v_amount := (v_metrics ->> 'history_amount')::numeric;

  if v_qty <= 0 then
    return jsonb_build_object(
      'status', 'NO_CI_HISTORY',
      'history_ci_count', 0,
      'history_qty', null,
      'history_net_value', null,
      'history_avg_per_pc', null
    );
  end if;

  if v_amount is null then
    return jsonb_build_object(
      'status', 'UNRESOLVED_CI_PRICING',
      'history_ci_count', null,
      'history_qty', v_qty,
      'history_net_value', null,
      'history_avg_per_pc', null
    );
  end if;

  return jsonb_build_object(
    'status', 'RESOLVED',
    'history_ci_count', null,
    'history_qty', v_qty,
    'history_net_value', v_amount,
    'history_avg_per_pc', round(v_amount / nullif(v_qty, 0), 2)
  );
end;
$$;

create or replace function public.rr_market_partner_customer_more_samples_v80(
  p_token text,
  p_categories text[],
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ctx jsonb;
  v_owner uuid;
  v_customer uuid;
  v_root uuid;
  v_collection public.rr_market_partner_collection_v67%rowtype;
  v_order public.rr_market_partner_order_v67%rowtype;
  v_pending integer;
  v_next integer;
  v_categories text[];
  v_message text;
  v_event_id bigint;
begin
  v_ctx := public.rr_market_partner_customer_context_v80(p_token);
  v_owner := (v_ctx ->> 'owner_customer_id')::uuid;
  v_customer := (v_ctx ->> 'partner_customer_id')::uuid;
  v_root := (v_ctx ->> 'root_collection_id')::uuid;

  perform pg_advisory_xact_lock(
    hashtextextended('RR_PARTNER_MORE_SAMPLES:' || v_root::text, 0)
  );

  select pc.*
  into v_collection
  from public.rr_market_partner_collection_v67 pc
  where coalesce(pc.root_collection_id, pc.id) = v_root
    and pc.owner_customer_id = v_owner
    and pc.partner_customer_id = v_customer
    and pc.status <> 'CANCELLED'
    and not pc.legacy_hidden_v78
  order by pc.collection_update_no desc, pc.created_at desc
  limit 1
  for update;

  select o.*
  into v_order
  from public.rr_market_partner_order_v67 o
  join public.rr_market_partner_collection_v67 pc on pc.id = o.collection_id
  where coalesce(pc.root_collection_id, pc.id) = v_root
    and o.owner_customer_id = v_owner
    and o.partner_customer_id = v_customer
    and o.data_mode = 'TEST'
    and o.status <> 'SUPERSEDED'
  order by o.requirement_update_no desc, o.created_at desc
  limit 1;

  if v_order.id is not null and v_order.status <> 'DRAFT' then
    raise exception 'Requirement is closed. Distributor will continue this order.';
  end if;

  select array_agg(distinct trim(category) order by trim(category))
  into v_categories
  from unnest(coalesce(p_categories, array[]::text[])) as category
  where nullif(trim(category), '') is not null;

  if coalesce(array_length(v_categories, 1), 0) = 0 then
    raise exception 'Select at least one category.';
  end if;

  select max(
    case
      when e.payload ->> 'requested_update_no' ~ '^[0-9]+$'
        then (e.payload ->> 'requested_update_no')::integer
      else null
    end
  )
  into v_pending
  from public.rr_market_partner_event_v67 e
  where e.owner_customer_id = v_owner
    and e.event_type = 'CHAT_MESSAGE'
    and e.payload ->> 'action' = 'MORE_SAMPLES_REQUESTED'
    and e.payload ->> 'customer_id' = v_customer::text
    and e.payload ->> 'root_collection_id' = v_root::text;

  if coalesce(v_pending, 0) > coalesce(v_collection.collection_update_no, 0) then
    raise exception 'Previous sample request is waiting for distributor update.';
  end if;

  v_next := coalesce(v_collection.collection_update_no, 0) + 1;
  v_message := 'MORE SAMPLES REQUEST · ' || array_to_string(v_categories, ', ');
  if nullif(trim(coalesce(p_note, '')), '') is not null then
    v_message := v_message || E'\n' || trim(p_note);
  end if;

  insert into public.rr_market_partner_event_v67(
    owner_customer_id,
    order_id,
    event_type,
    note,
    actor_kind,
    payload
  )
  values(
    v_owner,
    v_order.id,
    'CHAT_MESSAGE',
    left(v_message, 4000),
    'CUSTOMER',
    jsonb_build_object(
      'lane', 'CUSTOMER_GROUP',
      'customer_id', v_customer,
      'root_collection_id', v_root,
      'collection_no', v_collection.collection_no,
      'requested_update_no', v_next,
      'categories', to_jsonb(v_categories),
      'action', 'MORE_SAMPLES_REQUESTED'
    )
  )
  returning id into v_event_id;

  return jsonb_build_object(
    'ok', true,
    'event_id', v_event_id,
    'collection_cycle_id', v_root,
    'collection_display_no', 'COLLECTION ' || v_collection.collection_no::text,
    'collection_status', 'OPEN',
    'update_no', v_next,
    'request_kind', 'MORE_SAMPLES',
    'sent_to', 'DISTRIBUTOR'
  );
end;
$$;

revoke all on function public.rr_market_partner_customer_context_v80(text)
  from public, anon, authenticated;
grant execute on function public.rr_market_partner_customer_context_v80(text)
  to service_role;

revoke all on function public.rr_market_partner_customer_current_state_v80(text)
  from public;
revoke all on function public.rr_market_partner_customer_pricing_v80(text)
  from public;
revoke all on function public.rr_market_partner_customer_requirement_summary_v80(text)
  from public;
revoke all on function public.rr_market_partner_customer_ci_history_v80(text)
  from public;
revoke all on function public.rr_market_partner_customer_more_samples_v80(text, text[], text)
  from public;

grant execute on function public.rr_market_partner_customer_current_state_v80(text)
  to anon, authenticated, service_role;
grant execute on function public.rr_market_partner_customer_pricing_v80(text)
  to anon, authenticated, service_role;
grant execute on function public.rr_market_partner_customer_requirement_summary_v80(text)
  to anon, authenticated, service_role;
grant execute on function public.rr_market_partner_customer_ci_history_v80(text)
  to anon, authenticated, service_role;
grant execute on function public.rr_market_partner_customer_more_samples_v80(text, text[], text)
  to anon, authenticated, service_role;
