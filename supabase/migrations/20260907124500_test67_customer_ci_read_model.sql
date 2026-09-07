-- TEST67: expose the canonical downstream customer CI in distributor read
-- models, and make customer rollback immediately fall back to the live PI.

create or replace function public.rr_market_partner_customer_pi_state_v67(
  p_session_token text,
  p_device_id text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ctx jsonb;
  v_owner uuid;
begin
  v_ctx := public.rr_market_partner_context_v67(p_session_token, p_device_id);
  v_owner := (v_ctx->>'owner_customer_id')::uuid;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'order_id', o.id,
        'distributor_pi_ref', o.distributor_pi_ref,
        'distributor_pi_created_at', o.distributor_pi_created_at,
        'distributor_pi_visible', o.distributor_pi_visible,
        'distributor_pi_pushed_at', o.distributor_pi_pushed_at,
        'distributor_pi_status', o.distributor_pi_status,
        'distributor_pi_note', o.distributor_pi_note,
        'distributor_pi_responded_at', o.distributor_pi_responded_at,
        'customer_ci_id', ci.id,
        'customer_ci_ref', ci.customer_ci_ref,
        'customer_ci_status', ci.status,
        'customer_ci_revision_no', ci.revision_no,
        'customer_ci_visible', o.customer_ci_visible,
        'customer_ci_pushed_at', o.customer_ci_pushed_at,
        'lines', (
          select coalesce(jsonb_agg(jsonb_build_object(
            'id', l.id,
            'distributor_pi_qty', l.distributor_pi_qty,
            'distributor_pi_decision', l.distributor_pi_decision,
            'distributor_pi_customer_qty', l.distributor_pi_customer_qty,
            'distributor_pi_note', l.distributor_pi_note
          ) order by l.lot_no), '[]'::jsonb)
          from public.rr_market_partner_order_line_v67 l
          where l.order_id = o.id
        )
      ) order by o.created_at desc
    )
    from public.rr_market_partner_order_v67 o
    left join lateral (
      select active_ci.id,
             active_ci.customer_ci_ref,
             active_ci.status,
             active_ci.revision_no
      from public.rr_market_partner_customer_ci_v67 active_ci
      where active_ci.source_order_id = o.id
        and active_ci.owner_customer_id = v_owner
        and active_ci.data_mode = 'TEST'
        and active_ci.status = 'FINAL'
      order by active_ci.created_at desc
      limit 1
    ) ci on true
    where o.owner_customer_id = v_owner
      and o.data_mode = 'TEST'
  ), '[]'::jsonb);
end
$$;

create or replace function public.rr_market_partner_customer_invoice_view_v67(
  p_token text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_map public.rr_market_partner_collection_v67%rowtype;
  v_root uuid;
  v_order public.rr_market_partner_order_v67%rowtype;
  v_customer_ci public.rr_market_partner_customer_ci_v67%rowtype;
  v_charges jsonb;
begin
  select pc.*
    into v_map
  from public.rr_market_partner_collection_v67 pc
  join public.rr_market_share_v9420 s on s.id = pc.share_id
  where (s.token = p_token or s.short_code = upper(p_token))
    and s.data_mode = 'TEST'
    and s.status = 'ACTIVE'
  order by case when s.token = p_token then 0 else 1 end
  limit 1;

  if v_map.id is null then
    return null;
  end if;

  v_root := coalesce(v_map.root_collection_id, v_map.id);
  select o.*
    into v_order
  from public.rr_market_partner_order_v67 o
  join public.rr_market_partner_collection_v67 pc on pc.id = o.collection_id
  where pc.root_collection_id = v_root
    and o.status <> 'SUPERSEDED'
  order by o.requirement_update_no desc, o.created_at desc
  limit 1;

  if v_order.id is null then
    return null;
  end if;

  v_charges := jsonb_build_object(
    'value_pct', v_order.distributor_pi_value_pct,
    'freight', v_order.distributor_pi_freight,
    'other', v_order.distributor_pi_other,
    'tax_pct', v_order.distributor_pi_tax_pct
  );

  -- A cancelled CI is audit history, not the customer's current document.
  select *
    into v_customer_ci
  from public.rr_market_partner_customer_ci_v67
  where source_order_id = v_order.id
    and data_mode = 'TEST'
    and status = 'FINAL'
  order by created_at desc
  limit 1;

  if v_customer_ci.id is not null then
    return jsonb_build_object(
      'kind', 'CI',
      'ref', v_customer_ci.customer_ci_ref,
      'status', v_customer_ci.status,
      'created_at', v_customer_ci.created_at,
      'requirement_display_no', v_order.requirement_display_no,
      'collection_display_no', v_map.collection_display_no,
      'charges', v_charges,
      'lines', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'id', cl.id,
          'lot_no', cl.lot_no,
          'article_name', cl.article_name,
          'category', ol.category,
          'size_text', ol.size_text,
          'image_url', ol.image_url,
          'quantity', cl.quantity,
          'rate', cl.customer_rate,
          'line_amount', cl.line_amount
        ) order by cl.lot_no), '[]'::jsonb)
        from public.rr_market_partner_customer_ci_line_v67 cl
        left join public.rr_market_partner_order_line_v67 ol
          on ol.id = cl.source_order_line_id
        where cl.customer_ci_id = v_customer_ci.id
      )
    );
  end if;

  if not v_order.distributor_pi_visible or v_order.distributor_pi_ref is null then
    return null;
  end if;

  return jsonb_build_object(
    'kind', 'PI',
    'ref', v_order.distributor_pi_ref,
    'status', v_order.distributor_pi_status,
    'note', v_order.distributor_pi_note,
    'pushed_at', v_order.distributor_pi_pushed_at,
    'requirement_display_no', v_order.requirement_display_no,
    'collection_display_no', v_map.collection_display_no,
    'charges', v_charges,
    'lines', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', l.id,
        'lot_no', l.lot_no,
        'article_name', l.article_name,
        'category', l.category,
        'size_text', l.size_text,
        'image_url', l.image_url,
        'requested_qty', l.requested_qty,
        'proposed_qty', coalesce(l.distributor_pi_qty, l.requested_qty),
        'rate', l.final_customer_rate,
        'decision', l.distributor_pi_decision,
        'customer_qty', l.distributor_pi_customer_qty
      ) order by l.lot_no), '[]'::jsonb)
      from public.rr_market_partner_order_line_v67 l
      where l.order_id = v_order.id
    )
  );
end
$$;

revoke all on function public.rr_market_partner_customer_pi_state_v67(text, text)
  from public;
revoke all on function public.rr_market_partner_customer_invoice_view_v67(text)
  from public;

grant execute on function public.rr_market_partner_customer_pi_state_v67(text, text)
  to anon, authenticated, service_role;
grant execute on function public.rr_market_partner_customer_invoice_view_v67(text)
  to anon, authenticated, service_role;
