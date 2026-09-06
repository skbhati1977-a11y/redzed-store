-- TEST67 only: distributor-owner controlled permanent customer pricing defaults.
create or replace function public.rr_market_partner_customer_pricing_set_v67(
  p_session_token text,p_device_id text,p_partner_customer_id uuid,
  p_margin_amount numeric,p_discount_amount numeric
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_ctx jsonb;v_owner uuid;
 v_margin numeric(14,2):=greatest(0,coalesce(p_margin_amount,0));
 v_discount numeric(14,2):=greatest(0,coalesce(p_discount_amount,0));
begin
  -- Distributor staff sessions are deliberately not accepted by this owner context.
  v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
  v_owner:=(v_ctx->>'owner_customer_id')::uuid;
  update public.rr_market_partner_customer_v67
  set default_margin_amount=v_margin,default_discount_amount=v_discount,updated_at=now()
  where id=p_partner_customer_id and owner_customer_id=v_owner and data_mode='TEST';
  if not found then raise exception 'Distributor customer is unavailable.';end if;
  return jsonb_build_object('ok',true,'customer_id',p_partner_customer_id,
    'margin',v_margin,'discount',v_discount,'editable_by','DISTRIBUTOR_OWNER');
end $$;
revoke all on function public.rr_market_partner_customer_pricing_set_v67(text,text,uuid,numeric,numeric) from public;
grant execute on function public.rr_market_partner_customer_pricing_set_v67(text,text,uuid,numeric,numeric) to anon,authenticated,service_role;
