-- V9760: make canonical CI/RCI vouchers reversible through the standard mirror lifecycle.
begin;
create or replace function public.rr_accounts_direct_source_link_trg_v9760()
returns trigger language plpgsql security definer set search_path='public' as $function$
begin
 if new.source_module in('FG_CPI_V787','RCI_V9740') and new.source_record_id is not null and new.status='POSTED' then
  insert into public.rr_account_source_links_v806(source_module,source_record_id,account_transaction_id,data_mode,status,created_by)
  values(new.source_module,new.source_record_id,new.id,new.data_mode,'ACTIVE',new.created_by)
  on conflict(source_module,source_record_id,data_mode) do update set
   account_transaction_id=excluded.account_transaction_id,status='ACTIVE',created_by=excluded.created_by;
 end if;
 return new;
end $function$;
revoke all on function public.rr_accounts_direct_source_link_trg_v9760() from public,anon,authenticated;
drop trigger if exists rr_accounts_direct_source_link_v9760 on public.rr_account_transactions_v805;
create trigger rr_accounts_direct_source_link_v9760 after insert on public.rr_account_transactions_v805
for each row execute function public.rr_accounts_direct_source_link_trg_v9760();

insert into public.rr_account_source_links_v806(source_module,source_record_id,account_transaction_id,data_mode,status,created_by)
select distinct on(t.source_module,t.source_record_id,t.data_mode)
 t.source_module,t.source_record_id,t.id,t.data_mode,'ACTIVE',t.created_by
from public.rr_account_transactions_v805 t
where t.source_module in('FG_CPI_V787','RCI_V9740') and t.source_record_id is not null and t.status='POSTED'
order by t.source_module,t.source_record_id,t.data_mode,t.created_at desc,t.id desc
on conflict(source_module,source_record_id,data_mode) do update set
 account_transaction_id=excluded.account_transaction_id,status='ACTIVE',created_by=excluded.created_by;
commit;
