-- V9761: make manual receipt/payment vouchers reversible; physical deletion remains forbidden.
begin;

create or replace function public.rr_accounts_direct_source_link_trg_v9760()
returns trigger language plpgsql security definer set search_path='public' as $function$
begin
 if new.source_module in('FG_CPI_V787','RCI_V9740','ACCOUNTS_TEMPLATE')
    and new.source_record_id is not null and new.status='POSTED' then
  insert into public.rr_account_source_links_v806(source_module,source_record_id,account_transaction_id,data_mode,status,created_by)
  values(new.source_module,new.source_record_id,new.id,new.data_mode,'ACTIVE',new.created_by)
  on conflict(source_module,source_record_id,data_mode) do update set
   account_transaction_id=excluded.account_transaction_id,status='ACTIVE',created_by=excluded.created_by;
 end if;
 return new;
end $function$;

insert into public.rr_account_source_links_v806(source_module,source_record_id,account_transaction_id,data_mode,status,created_by)
select distinct on(t.source_module,t.source_record_id,t.data_mode)
 t.source_module,t.source_record_id,t.id,t.data_mode,'ACTIVE',t.created_by
from public.rr_account_transactions_v805 t
where t.source_module='ACCOUNTS_TEMPLATE' and t.source_record_id is not null and t.status='POSTED'
order by t.source_module,t.source_record_id,t.data_mode,t.created_at desc,t.id desc
on conflict(source_module,source_record_id,data_mode) do update set
 account_transaction_id=excluded.account_transaction_id,status='ACTIVE',created_by=excluded.created_by;

create or replace function public.rr_accounts_reverse_transaction_v9761(p_transaction_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='public' as $function$
declare t public.rr_account_transactions_v805%rowtype;
begin
 if not public.rr_acct_can_view_v805() then raise exception 'Accounts permission required.'; end if;
 if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Reverse reason required.'; end if;
 select * into t from public.rr_account_transactions_v805 where id=p_transaction_id for update;
 if not found then raise exception 'Accounts transaction not found.'; end if;
 if t.status<>'POSTED' then raise exception 'Only POSTED transaction can be reversed.'; end if;
 if t.source_module<>'ACCOUNTS_TEMPLATE' or t.transaction_type not in('RECEIPT','PAYMENT') then
  raise exception 'Only manual Receipt/Payment can be reversed here; reverse source document instead.';
 end if;
 return public.rr_accounts_reverse_source_mirror_v806(t.source_module,t.source_record_id,t.data_mode,p_reason);
end $function$;

revoke all on function public.rr_accounts_reverse_transaction_v9761(uuid,text) from public,anon;
grant execute on function public.rr_accounts_reverse_transaction_v9761(uuid,text) to authenticated,service_role;

commit;
