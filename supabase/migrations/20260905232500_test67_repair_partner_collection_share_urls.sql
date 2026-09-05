-- TEST67: repair collection-card messages created by the cached pre-v86
-- sender adapter. That adapter replaced REDZED globally and could therefore
-- rewrite the redzed-test65 hostname itself. Keep the private share token and
-- only canonicalize the URL origin/path.

update public.rr_customer_chat_messages_v9433 m
set body =
  split_part(m.body, 'Open collection:', 1)
  || 'Open collection: https://redzed-test65-git-test67-customer-marke-a24b35-skbhati1977-4414.vercel.app'
  || substring(m.body from '(/s\.html\?.*)')
where m.archived_at is null
  and m.payload->>'relation_scope'='DISTRIBUTOR_CUSTOMER'
  and m.body like '%Open collection:%'
  and m.body like '%/s.html?%'
  and m.body not like '%Open collection: https://redzed-test65-git-test67-customer-marke-a24b35-skbhati1977-4414.vercel.app/s.html?%';
