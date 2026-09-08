-- TEST67: bind customer secure sessions to the collection recipient.
-- Prevents a staff-opened/customer share token from creating a second chat
-- when a shortened or mistyped customer name is entered.
create or replace function public.rr_customer_session_issue_bound_v9680(
  p_token text,
  p_customer_name text,
  p_mobile text,
  p_device_id text
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_share public.rr_market_share_v9420%rowtype;
  v_customer public.rr_customers%rowtype;
  v_mobile text := right(regexp_replace(coalesce(p_mobile, ''), '[^0-9]', '', 'g'), 10);
  v_result jsonb;
begin
  select s.* into v_share
  from public.rr_market_share_v9420 s
  where (s.token = p_token or s.short_code = upper(trim(p_token)))
    and s.status = 'ACTIVE'
  order by case when s.token = p_token then 0 else 1 end
  limit 1;

  if v_share.id is null then
    raise exception 'Collection link unavailable.';
  end if;
  if length(v_mobile) <> 10 then
    raise exception 'Valid 10 digit registered mobile required.';
  end if;

  if v_share.customer_id is not null then
    select c.* into v_customer
    from public.rr_customers c
    where c.id = v_share.customer_id and c.is_active;

    if v_customer.id is null then
      raise exception 'Collection customer is inactive or unavailable.';
    end if;
    if right(regexp_replace(coalesce(v_customer.mobile, ''), '[^0-9]', '', 'g'), 10) <> v_mobile
       and not exists (
         select 1 from public.rr_customer_contact_phone_v67 p
         where p.customer_id = v_customer.id
           and right(regexp_replace(coalesce(p.mobile, ''), '[^0-9]', '', 'g'), 10) = v_mobile
           and p.data_mode = 'TEST'
       ) then
      raise exception 'Mobile does not match the customer assigned to this collection.';
    end if;
  else
    select c.* into v_customer
    from public.rr_customers c
    where c.is_active
      and right(regexp_replace(coalesce(c.mobile, ''), '[^0-9]', '', 'g'), 10) = v_mobile
    order by c.updated_at desc
    limit 1;
  end if;

  v_result := public.rr_customer_session_issue_v9590(
    p_token,
    coalesce(nullif(trim(v_customer.customer_name), ''), nullif(trim(p_customer_name), '')),
    coalesce(nullif(trim(v_customer.mobile), ''), p_mobile),
    p_device_id
  );

  return coalesce(v_result, '{}'::jsonb) || jsonb_build_object(
    'customer_id', v_customer.id,
    'customer_name', coalesce(nullif(trim(v_customer.customer_name), ''), nullif(trim(p_customer_name), '')),
    'share_id', v_share.id
  );
end
$$;

revoke all on function public.rr_customer_session_issue_bound_v9680(text,text,text,text) from public;
grant execute on function public.rr_customer_session_issue_bound_v9680(text,text,text,text) to anon, authenticated, service_role;

