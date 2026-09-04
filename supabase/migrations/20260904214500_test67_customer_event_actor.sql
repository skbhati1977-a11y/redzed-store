-- TEST67 downstream customer is a first-class actor in the private journey.
alter table public.rr_market_partner_event_v67
  drop constraint if exists rr_market_partner_event_v67_actor_kind_check;

alter table public.rr_market_partner_event_v67
  add constraint rr_market_partner_event_v67_actor_kind_check
  check(actor_kind in('STAFF','DISTRIBUTOR','CUSTOMER','SYSTEM'));
