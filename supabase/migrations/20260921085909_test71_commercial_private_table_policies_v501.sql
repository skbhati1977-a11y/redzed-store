-- Explicit deny policies document and enforce that these derived financial
-- tables are backend-only. Authorized clients use the audited projection RPCs.
create policy rr_account_bills_v500_backend_only
  on public.rr_account_bills_v500 for all to anon,authenticated
  using (false) with check (false);

create policy rr_account_allocations_v500_backend_only
  on public.rr_account_allocations_v500 for all to anon,authenticated
  using (false) with check (false);

create policy rr_account_advances_v500_backend_only
  on public.rr_account_advances_v500 for all to anon,authenticated
  using (false) with check (false);

create policy rr_accounts_work_item_v500_backend_only
  on public.rr_accounts_work_item_v500 for all to anon,authenticated
  using (false) with check (false);
