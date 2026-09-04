-- Isolated TEST67 customer-to-group assignment for the distributor workspace.

create or replace function public.rr_market_partner_customer_group_set_v67(
  p_session_token text,
  p_device_id text,
  p_partner_customer_id uuid,
  p_group_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_ctx jsonb;
  v_owner uuid;
begin
  v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
  v_owner:=(v_ctx->>'owner_customer_id')::uuid;

  if p_group_id is not null and not exists(
    select 1
    from public.rr_market_partner_group_v67
    where id=p_group_id
      and owner_customer_id=v_owner
      and status='ACTIVE'
      and data_mode='TEST'
  ) then
    raise exception 'Private group not found.';
  end if;

  update public.rr_market_partner_customer_v67
  set group_id=p_group_id,updated_at=now()
  where id=p_partner_customer_id
    and owner_customer_id=v_owner
    and data_mode='TEST';
  if not found then raise exception 'Private customer not found.';end if;

  return jsonb_build_object('customer_id',p_partner_customer_id,'group_id',p_group_id);
end $$;

revoke all on function public.rr_market_partner_customer_group_set_v67(text,text,uuid,uuid) from public;
grant execute on function public.rr_market_partner_customer_group_set_v67(text,text,uuid,uuid)
  to anon,authenticated,service_role;
