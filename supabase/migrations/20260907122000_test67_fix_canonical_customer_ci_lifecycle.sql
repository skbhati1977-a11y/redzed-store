-- TEST67: keep downstream customer CI references canonical in
-- rr_market_partner_customer_ci_v67.  The partner order stores only lifecycle
-- visibility/state; it intentionally has no customer_ci_ref column.

create or replace function public.rr_market_staff_cancel_ci_v67(
  p_batch_id uuid,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_old_ci text;
begin
  perform public.rr_market_assert_sales_actor_v9420();

  if nullif(trim(p_reason), '') is null then
    raise exception 'Cancellation reason is required.';
  end if;

  select owner_customer_id, ci_ref
    into v_owner, v_old_ci
  from public.rr_market_partner_batch_v67
  where id = p_batch_id
    and data_mode = 'TEST'
    and status = 'CI_FINAL'
    and ci_ref is not null
  for update;

  if v_owner is null then
    raise exception 'Only an active CI can be cancelled.';
  end if;

  update public.rr_market_partner_customer_ci_v67 ci
  set status = 'CANCELLED',
      cancelled_at = now(),
      cancellation_reason = trim(p_reason)
  where ci.status = 'FINAL'
    and exists (
      select 1
      from public.rr_market_partner_batch_member_v67 m
      where m.batch_id = p_batch_id
        and m.order_id = ci.source_order_id
    );

  update public.rr_market_partner_order_v67 o
  set status = 'PI_PROPOSED',
      ci_ref = null,
      customer_ci_visible = false,
      customer_ci_pushed_at = null,
      updated_at = now()
  where o.status <> 'CANCELLED'
    and exists (
      select 1
      from public.rr_market_partner_batch_member_v67 m
      where m.batch_id = p_batch_id
        and m.order_id = o.id
    );

  update public.rr_market_partner_batch_v67
  set status = 'WAITING_CONFIRMATION',
      ci_ref = null,
      updated_at = now()
  where id = p_batch_id;

  insert into public.rr_market_partner_event_v67(
    owner_customer_id, batch_id, event_type, note, actor_kind, actor_id, payload
  ) values (
    v_owner,
    p_batch_id,
    'REDZED_CI_CANCELLED_PI_RESTORED',
    trim(p_reason),
    'STAFF',
    auth.uid(),
    jsonb_build_object('cancelled_ci_ref', v_old_ci)
  );

  return public.rr_market_staff_batch_detail_v67(p_batch_id);
end
$$;

create or replace function public.rr_market_partner_convert_customer_ci_v67(
  p_session_token text,
  p_device_id text,
  p_order_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ctx jsonb;
  v_owner uuid;
  v_order public.rr_market_partner_order_v67%rowtype;
  v_prefix text;
  v_no bigint;
  v_ci_ref text;
  v_ci uuid;
  v_revision integer := 1;
begin
  v_ctx := public.rr_market_partner_context_v67(p_session_token, p_device_id);
  if not (v_ctx->>'ci_convert_enabled')::boolean then
    raise exception 'Customer CI conversion is disabled.';
  end if;
  v_owner := (v_ctx->>'owner_customer_id')::uuid;

  select *
    into v_order
  from public.rr_market_partner_order_v67
  where id = p_order_id
    and owner_customer_id = v_owner
    and data_mode = 'TEST'
    and status = 'CI_FINAL'
  for update;

  if v_order.id is null or v_order.ci_ref is null then
    raise exception 'Final upstream CI allocation not found.';
  end if;

  select id, customer_ci_ref, revision_no
    into v_ci, v_ci_ref, v_revision
  from public.rr_market_partner_customer_ci_v67
  where source_order_id = p_order_id
  for update;

  if v_ci is not null and exists (
    select 1
    from public.rr_market_partner_customer_ci_v67
    where id = v_ci and status = 'FINAL'
  ) then
    return jsonb_build_object(
      'customer_ci_id', v_ci,
      'customer_ci_ref', v_ci_ref,
      'source_upstream_ci_ref', v_order.ci_ref,
      'status', 'FINAL',
      'revision_no', v_revision,
      'already_final', true
    );
  end if;

  if v_ci is null then
    select prefix
      into v_prefix
    from public.rr_market_owner_sequence_v67
    where owner_key = 'CUSTOMER:' || v_owner::text
      and data_mode = 'TEST';

    select coalesce(max((regexp_match(customer_ci_ref, '([0-9]+)$'))[1]::bigint), 0) + 1
      into v_no
    from public.rr_market_partner_customer_ci_v67
    where owner_customer_id = v_owner;

    v_ci_ref := v_prefix || '-CI-' || lpad(v_no::text, 4, '0');
    insert into public.rr_market_partner_customer_ci_v67(
      owner_customer_id,
      partner_customer_id,
      source_order_id,
      source_upstream_ci_ref,
      customer_ci_ref
    ) values (
      v_owner,
      v_order.partner_customer_id,
      p_order_id,
      v_order.ci_ref,
      v_ci_ref
    ) returning id into v_ci;
  else
    v_revision := v_revision + 1;
    update public.rr_market_partner_customer_ci_v67
    set status = 'FINAL',
        source_upstream_ci_ref = v_order.ci_ref,
        revision_no = v_revision,
        cancelled_at = null,
        cancellation_reason = null,
        created_at = now()
    where id = v_ci;

    delete from public.rr_market_partner_customer_ci_line_v67
    where customer_ci_id = v_ci;
  end if;

  insert into public.rr_market_partner_customer_ci_line_v67(
    customer_ci_id,
    source_order_line_id,
    lot_no,
    article_name,
    quantity,
    customer_rate
  )
  select
    v_ci,
    id,
    lot_no,
    article_name,
    greatest(0, coalesce(distributor_pi_qty, confirmed_qty, proposed_qty, requested_qty)),
    customer_rate
  from public.rr_market_partner_order_line_v67
  where order_id = p_order_id
    and greatest(0, coalesce(distributor_pi_qty, confirmed_qty, proposed_qty, requested_qty)) > 0;

  if not found then
    raise exception 'Customer CI needs at least one positive PI quantity.';
  end if;

  update public.rr_market_partner_order_v67
  set status = 'CLOSED',
      customer_ci_visible = true,
      customer_ci_pushed_at = now(),
      updated_at = now()
  where id = p_order_id
    and owner_customer_id = v_owner;

  insert into public.rr_market_partner_event_v67(
    owner_customer_id, order_id, event_type, actor_kind, payload
  ) values (
    v_owner,
    p_order_id,
    'CUSTOMER_CI_CREATED',
    'DISTRIBUTOR',
    jsonb_build_object(
      'customer_ci_ref', v_ci_ref,
      'upstream_ci_ref', v_order.ci_ref,
      'revision_no', v_revision,
      'confirmation_optional', true
    )
  );

  return jsonb_build_object(
    'customer_ci_id', v_ci,
    'customer_ci_ref', v_ci_ref,
    'source_upstream_ci_ref', v_order.ci_ref,
    'status', 'FINAL',
    'revision_no', v_revision,
    'already_final', false
  );
end
$$;

create or replace function public.rr_market_partner_cancel_customer_ci_v67(
  p_session_token text,
  p_device_id text,
  p_order_id uuid,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ctx jsonb;
  v_owner uuid;
  v_ci public.rr_market_partner_customer_ci_v67%rowtype;
  v_pi text;
begin
  v_ctx := public.rr_market_partner_context_v67(p_session_token, p_device_id);
  v_owner := (v_ctx->>'owner_customer_id')::uuid;

  if nullif(trim(p_reason), '') is null then
    raise exception 'Cancellation reason is required.';
  end if;

  select *
    into v_ci
  from public.rr_market_partner_customer_ci_v67
  where source_order_id = p_order_id
    and owner_customer_id = v_owner
    and status = 'FINAL'
  for update;

  if v_ci.id is null then
    raise exception 'Only an active customer CI can be cancelled.';
  end if;

  update public.rr_market_partner_customer_ci_v67
  set status = 'CANCELLED',
      cancelled_at = now(),
      cancellation_reason = trim(p_reason)
  where id = v_ci.id;

  update public.rr_market_partner_order_v67
  set status = 'CI_FINAL',
      customer_ci_visible = false,
      customer_ci_pushed_at = null,
      updated_at = now()
  where id = p_order_id
    and owner_customer_id = v_owner
  returning distributor_pi_ref into v_pi;

  insert into public.rr_market_partner_event_v67(
    owner_customer_id, order_id, event_type, note, actor_kind, payload
  ) values (
    v_owner,
    p_order_id,
    'CUSTOMER_CI_CANCELLED_PI_RESTORED',
    trim(p_reason),
    'DISTRIBUTOR',
    jsonb_build_object(
      'cancelled_ci_ref', v_ci.customer_ci_ref,
      'restored_pi_ref', v_pi
    )
  );

  return jsonb_build_object(
    'ok', true,
    'status', 'CI_FINAL',
    'cancelled_ci_ref', v_ci.customer_ci_ref,
    'distributor_pi_ref', v_pi,
    'revision_no', v_ci.revision_no
  );
end
$$;

revoke all on function public.rr_market_staff_cancel_ci_v67(uuid, text)
  from public, anon;
revoke all on function public.rr_market_partner_convert_customer_ci_v67(text, text, uuid)
  from public;
revoke all on function public.rr_market_partner_cancel_customer_ci_v67(text, text, uuid, text)
  from public;

grant execute on function public.rr_market_staff_cancel_ci_v67(uuid, text)
  to authenticated, service_role;
grant execute on function public.rr_market_partner_convert_customer_ci_v67(text, text, uuid)
  to anon, authenticated, service_role;
grant execute on function public.rr_market_partner_cancel_customer_ci_v67(text, text, uuid, text)
  to anon, authenticated, service_role;
