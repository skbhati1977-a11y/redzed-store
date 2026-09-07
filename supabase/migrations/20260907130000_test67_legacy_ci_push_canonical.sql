-- TEST67: keep legacy distributor screens safe by routing their "push CI"
-- action through the canonical customer-CI lifecycle.

create or replace function public.rr_market_partner_ci_push_v67(
  p_session_token text,
  p_device_id text,
  p_order_ids uuid[]
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ctx jsonb;
  v_owner uuid;
  v_expected integer;
  v_order_id uuid;
  v_result jsonb;
  v_refs jsonb := '[]'::jsonb;
begin
  v_ctx := public.rr_market_partner_context_v67(p_session_token, p_device_id);
  v_owner := (v_ctx->>'owner_customer_id')::uuid;
  v_expected := coalesce(array_length(p_order_ids, 1), 0);

  if v_expected = 0 then
    raise exception 'Select at least one customer PI.';
  end if;

  if (
    select count(distinct o.id)
    from public.rr_market_partner_order_v67 o
    where o.id = any(p_order_ids)
      and o.owner_customer_id = v_owner
      and o.data_mode = 'TEST'
      and o.status = 'CI_FINAL'
      and o.ci_ref is not null
      and o.distributor_pi_ref is not null
      and not exists (
        select 1
        from public.rr_market_partner_customer_ci_v67 ci
        where ci.source_order_id = o.id and ci.status = 'FINAL'
      )
  ) <> v_expected then
    raise exception 'Every selected requirement needs a mapped customer PI and final REDZED allocation.';
  end if;

  foreach v_order_id in array p_order_ids loop
    v_result := public.rr_market_partner_convert_customer_ci_v67(
      p_session_token,
      p_device_id,
      v_order_id
    );
    v_refs := v_refs || jsonb_build_array(jsonb_build_object(
      'order_id', v_order_id,
      'customer_ci_ref', v_result->>'customer_ci_ref',
      'revision_no', v_result->>'revision_no'
    ));
  end loop;

  return jsonb_build_object(
    'ok', true,
    'count', v_expected,
    'status', 'CUSTOMER_CI_SENT',
    'customer_cis', v_refs
  );
end
$$;

revoke all on function public.rr_market_partner_ci_push_v67(text, text, uuid[])
  from public;
grant execute on function public.rr_market_partner_ci_push_v67(text, text, uuid[])
  to anon, authenticated, service_role;
