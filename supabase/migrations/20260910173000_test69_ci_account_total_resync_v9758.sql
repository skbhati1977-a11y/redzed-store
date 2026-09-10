-- V9758: if final CI totals are recalculated after finalization, keep Accounts exact.
begin;
create or replace function public.rr_ci_accounts_total_sync_trg_v9758()
returns trigger language plpgsql security definer set search_path='public' as $function$
declare a public.rr_cpi_accounts_link_v847%rowtype;
begin
 if new.status='CI_FINAL' and new.grand_total is distinct from old.grand_total then
  select * into a from public.rr_cpi_accounts_link_v847 where cpi_id=new.id for update;
  if a.cpi_id is not null and a.status='POSTED' and abs(coalesce(a.grand_total,0)-coalesce(new.grand_total,0))>0.005 then
   perform public.rr_accounts_reverse_source_mirror_v806('FG_CPI_V787',new.id::text,new.data_mode,
    'Final CI total synchronized V9758');
   update public.rr_cpi_accounts_link_v847 set status='REVERSED',message='Reposting corrected CI total',updated_at=now()
    where cpi_id=new.id;
   perform public.rr_accounts_post_cpi_v847(new.id);
  end if;
 end if;
 return new;
end $function$;
revoke all on function public.rr_ci_accounts_total_sync_trg_v9758() from public,anon,authenticated;
drop trigger if exists rr_ci_accounts_total_sync_v9758 on public.rr_fg_pi_v787;
create trigger rr_ci_accounts_total_sync_v9758 after update of grand_total on public.rr_fg_pi_v787
for each row execute function public.rr_ci_accounts_total_sync_trg_v9758();
commit;

