-- TEST67 distributors use an application session token over the anon API role.
-- The function validates token + device and scopes every row to its owner.
grant execute on function public.rr_market_partner_batches_v67(text,text)
  to anon,authenticated,service_role;
