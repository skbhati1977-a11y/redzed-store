-- Customers have a verified actor identity, not a staff worker ID.
-- Preserve staff requirements without rejecting customer Web Push subscriptions.
alter table public.rr_web_push_subscriptions_v61 alter column worker_id drop not null;
alter table public.rr_web_push_subscriptions_v61 add constraint rr_web_push_actor_identity_test71 check (
 (coalesce(actor_kind,'STAFF')='STAFF' and worker_id is not null)
 or (actor_kind in ('CUSTOMER','PARTNER_CUSTOMER','DISTRIBUTOR') and actor_id is not null)
) not valid;
alter table public.rr_web_push_subscriptions_v61 validate constraint rr_web_push_actor_identity_test71;
