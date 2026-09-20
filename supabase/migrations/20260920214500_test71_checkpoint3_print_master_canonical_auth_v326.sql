-- TEST71 Checkpoint 3: Print Master must use the same canonical owner/admin helper
-- as Art, Print Frames, Sticker and Metal ID. This includes canonical SUPER_ADMIN.
drop policy if exists rr_print_master_owner_admin_select on public.rr_print_master;
drop policy if exists rr_print_master_owner_admin_insert on public.rr_print_master;
drop policy if exists rr_print_master_owner_admin_update on public.rr_print_master;
drop policy if exists rr_print_master_owner_admin_delete on public.rr_print_master;

create policy rr_print_master_owner_admin_select on public.rr_print_master
for select to authenticated using (public.rr_is_owner_or_admin());
create policy rr_print_master_owner_admin_insert on public.rr_print_master
for insert to authenticated with check (public.rr_is_owner_or_admin());
create policy rr_print_master_owner_admin_update on public.rr_print_master
for update to authenticated using (public.rr_is_owner_or_admin()) with check (public.rr_is_owner_or_admin());
create policy rr_print_master_owner_admin_delete on public.rr_print_master
for delete to authenticated using (public.rr_is_owner_or_admin());
