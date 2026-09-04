-- Cover TEST67 distributor workflow foreign-key lookups used by CI, orders and events.

create index if not exists rr_market_partner_customer_ci_line_v67_order_line_idx
  on public.rr_market_partner_customer_ci_line_v67(source_order_line_id);
create index if not exists rr_market_partner_customer_ci_v67_customer_idx
  on public.rr_market_partner_customer_ci_v67(partner_customer_id);
create index if not exists rr_market_partner_event_v67_batch_idx
  on public.rr_market_partner_event_v67(batch_id);
create index if not exists rr_market_partner_event_v67_order_idx
  on public.rr_market_partner_event_v67(order_id);
create index if not exists rr_market_partner_event_v67_owner_idx
  on public.rr_market_partner_event_v67(owner_customer_id);
