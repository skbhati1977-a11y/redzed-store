-- TEST67 only: customer-facing headers identify only the two direct parties.
create or replace function public.rr_market_partner_header_v67(
  p_owner_customer_id uuid,
  p_partner_customer_id uuid
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select
    upper(trim(rc.customer_name)) ||
    case
      when upper(trim(rc.customer_name)) like '%DISTRIBUTOR%' then ''
      else ' DISTRIBUTOR'
    end ||
    ' ↔ ' ||
    upper(trim(coalesce(nullif(g.group_name, ''), c.private_name))) ||
    case
      when upper(trim(coalesce(nullif(g.group_name, ''), c.private_name))) like '%GROUP%' then ''
      else ' GROUP'
    end
  from public.rr_customers as rc
  join public.rr_market_partner_customer_v67 as c
    on c.id = p_partner_customer_id
   and c.owner_customer_id = rc.id
  left join public.rr_market_partner_group_v67 as g
    on g.id = c.group_id
  where rc.id = p_owner_customer_id;
$$;

revoke all on function public.rr_market_partner_header_v67(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.rr_market_partner_header_v67(uuid, uuid)
  to service_role;
