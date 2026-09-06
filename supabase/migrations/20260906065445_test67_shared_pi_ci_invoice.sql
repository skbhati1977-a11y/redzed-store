-- TEST67 shared PI/CI invoice support. MAIN remains untouched until acceptance.

create or replace function public.rr_pi_staff_godown_v67(p_lot_no text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare v_result text;
begin
  perform public.rr_fg_assert_user_v787();
  select string_agg(format('%s · %s PCS', location_code, available_qty), ', ' order by location_code)
    into v_result
  from public.rr_fg_stock_balance_v787
  where upper(trim(lot_no)) = upper(trim(p_lot_no))
    and data_mode = 'TEST'
    and available_qty > 0;
  return coalesce(v_result, '—');
end $$;

revoke all on function public.rr_pi_staff_godown_v67(text) from public, anon;
grant execute on function public.rr_pi_staff_godown_v67(text) to authenticated, service_role;

create or replace function public.rr_market_partner_customer_invoice_view_v67(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_map public.rr_market_partner_collection_v67%rowtype;
  v_root uuid;
  v_order public.rr_market_partner_order_v67%rowtype;
  v_customer_ci public.rr_market_partner_customer_ci_v67%rowtype;
begin
  select pc.* into v_map
  from public.rr_market_partner_collection_v67 pc
  join public.rr_market_share_v9420 s on s.id = pc.share_id
  where (s.token = p_token or s.short_code = upper(p_token))
    and s.data_mode = 'TEST' and s.status = 'ACTIVE'
  order by case when s.token = p_token then 0 else 1 end
  limit 1;
  if v_map.id is null then return null; end if;

  v_root := coalesce(v_map.root_collection_id, v_map.id);
  select o.* into v_order
  from public.rr_market_partner_order_v67 o
  join public.rr_market_partner_collection_v67 pc on pc.id = o.collection_id
  where pc.root_collection_id = v_root and o.status <> 'SUPERSEDED'
  order by o.requirement_update_no desc, o.created_at desc
  limit 1;
  if v_order.id is null then return null; end if;

  select * into v_customer_ci
  from public.rr_market_partner_customer_ci_v67
  where source_order_id = v_order.id
  order by created_at desc limit 1;

  if v_customer_ci.id is not null then
    return jsonb_build_object(
      'kind','CI','ref',v_customer_ci.customer_ci_ref,'status',v_customer_ci.status,
      'created_at',v_customer_ci.created_at,
      'requirement_display_no',v_order.requirement_display_no,
      'collection_display_no',v_map.collection_display_no,
      'lines',(select coalesce(jsonb_agg(jsonb_build_object(
        'id',cl.id,'lot_no',cl.lot_no,'article_name',cl.article_name,
        'category',ol.category,'size_text',ol.size_text,'image_url',ol.image_url,
        'quantity',cl.quantity,'rate',cl.customer_rate,'discount',0,
        'line_amount',cl.line_amount
      ) order by cl.lot_no),'[]'::jsonb)
      from public.rr_market_partner_customer_ci_line_v67 cl
      left join public.rr_market_partner_order_line_v67 ol on ol.id=cl.source_order_line_id
      where cl.customer_ci_id=v_customer_ci.id)
    );
  end if;

  if not v_order.distributor_pi_visible or v_order.distributor_pi_ref is null then return null; end if;
  return jsonb_build_object(
    'kind','PI','ref',v_order.distributor_pi_ref,'status',v_order.distributor_pi_status,
    'note',v_order.distributor_pi_note,'pushed_at',v_order.distributor_pi_pushed_at,
    'requirement_display_no',v_order.requirement_display_no,
    'collection_display_no',v_map.collection_display_no,
    'lines',(select coalesce(jsonb_agg(jsonb_build_object(
      'id',l.id,'lot_no',l.lot_no,'article_name',l.article_name,
      'category',l.category,'size_text',l.size_text,'image_url',l.image_url,
      'requested_qty',l.requested_qty,
      'proposed_qty',coalesce(l.distributor_pi_qty,l.requested_qty),
      'rate',l.final_customer_rate,'discount',0,
      'decision',l.distributor_pi_decision,'customer_qty',l.distributor_pi_customer_qty
    ) order by l.lot_no),'[]'::jsonb)
    from public.rr_market_partner_order_line_v67 l where l.order_id=v_order.id)
  );
end $$;

revoke all on function public.rr_market_partner_customer_invoice_view_v67(text) from public;
grant execute on function public.rr_market_partner_customer_invoice_view_v67(text) to anon, authenticated, service_role;
