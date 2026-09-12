-- TEST68: safely restore permanent identity on legacy named share links.
-- Null/ambiguous names remain untouched; this never creates a customer.

with candidates as (
  select s.id share_id,min(c.id::text)::uuid customer_id,count(*) match_count
  from public.rr_market_share_v9420 s
  join public.rr_customers c on c.is_active and (
    lower(trim(c.customer_name))=lower(trim(s.customer_name))
    or lower(trim(c.customer_name)) like lower(trim(s.customer_name))||' %'
  )
  where s.status='ACTIVE' and s.customer_id is null
    and nullif(trim(s.customer_name),'') is not null
  group by s.id
)
update public.rr_market_share_v9420 s
set customer_id=c.customer_id
from candidates c
where s.id=c.share_id and c.match_count=1 and s.customer_id is null;
