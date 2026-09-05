-- TEST67: cover the group foreign key used by staff/group sync and deletes.
create index if not exists rr_market_partner_staff_group_v67_group_idx
  on public.rr_market_partner_staff_group_v67(group_id);
