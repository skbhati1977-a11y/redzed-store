alter table public.rr_web_push_subscriptions_v61 drop constraint rr_web_push_actor_identity_test71;
alter table public.rr_web_push_subscriptions_v61 add constraint rr_web_push_actor_identity_test71 check (
 (coalesce(actor_kind,'STAFF')='STAFF' and worker_id is not null)
 or (coalesce(actor_kind,'STAFF') in ('CUSTOMER','PARTNER_CUSTOMER','DISTRIBUTOR') and actor_id is not null)
) not valid;
alter table public.rr_web_push_subscriptions_v61 validate constraint rr_web_push_actor_identity_test71;
