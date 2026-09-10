-- V9763: canonical Sundry Creditors, scalable read model, journal and auditable reversal.
begin;

create table if not exists public.rr_supplier_accounts_map_v9763(
 supplier_id uuid primary key references public.rr_suppliers(id) on delete restrict,
 supplier_ledger_id uuid not null unique references public.rr_ledgers_v805(id) on delete restrict,
 is_active boolean not null default true,
 mapped_by uuid,
 mapped_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
alter table public.rr_supplier_accounts_map_v9763 enable row level security;
revoke all on table public.rr_supplier_accounts_map_v9763 from public,anon,authenticated;

insert into public.rr_supplier_accounts_map_v9763(supplier_id,supplier_ledger_id,mapped_by)
select s.id,a.supplier_ledger_id,auth.uid()
from public.rr_suppliers s
join public.rr_supplier_alias_map_v806 a
 on a.normalized_raw_name=public.rr_name_normalize_v805(s.supplier_name) and a.is_active
join public.rr_ledgers_v805 l on l.id=a.supplier_ledger_id and l.is_active and l.ledger_kind='SUPPLIER'
where s.is_active
on conflict(supplier_id) do update set supplier_ledger_id=excluded.supplier_ledger_id,is_active=true,updated_at=now();

create or replace function public.rr_supplier_accounts_sync_trg_v9763()
returns trigger language plpgsql security definer set search_path='public' as $function$
declare v_ledger uuid;
begin
 if coalesce(new.is_active,true) then
  v_ledger:=public.rr_supplier_ledger_resolve_v806(new.supplier_name);
  insert into public.rr_supplier_accounts_map_v9763(supplier_id,supplier_ledger_id,mapped_by)
  values(new.id,v_ledger,auth.uid())
  on conflict(supplier_id) do update set supplier_ledger_id=excluded.supplier_ledger_id,is_active=true,updated_at=now();
 else
  update public.rr_supplier_accounts_map_v9763 set is_active=false,updated_at=now() where supplier_id=new.id;
 end if;
 return new;
end $function$;
revoke all on function public.rr_supplier_accounts_sync_trg_v9763() from public,anon,authenticated;
drop trigger if exists rr_supplier_accounts_sync_v9763 on public.rr_suppliers;
create trigger rr_supplier_accounts_sync_v9763 after insert or update of supplier_name,is_active on public.rr_suppliers
for each row execute function public.rr_supplier_accounts_sync_trg_v9763();

create index if not exists rr_supplier_accounts_search_v9763 on public.rr_suppliers(lower(supplier_name) text_pattern_ops) where is_active;

create or replace function public.rr_accounts_creditor_search_v9763(p_search text default '',p_limit integer default 100,p_offset integer default 0,p_data_mode text default 'TEST')
returns table(supplier_id uuid,supplier_name text,ledger_id uuid,ledger_code text,closing_debit numeric,closing_credit numeric,net_payable numeric)
language plpgsql stable security definer set search_path='public' as $function$
declare v_q text:=lower(trim(coalesce(p_search,'')));v_limit int:=least(greatest(coalesce(p_limit,100),1),200);v_offset int:=greatest(coalesce(p_offset,0),0);v_role text;
begin
 select lower(role_code) into v_role from public.rr_user_profiles where auth_user_id=auth.uid() and is_active and upper(coalesce(access_status,'ACTIVE'))='ACTIVE' limit 1;
 if v_role not in('owner','super_admin','superadmin','admin','sales','account','accounts') then raise exception 'Owner/Admin/Sales/Accounts access required.'; end if;
 return query
 with totals as(
  select b.ledger_id,sum(coalesce(b.dr_amount,0)) dr,sum(coalesce(b.cr_amount,0)) cr
  from public.rr_account_reporting_base_v806 b
  where b.data_mode=upper(coalesce(p_data_mode,'TEST')) and coalesce(b.transaction_status,'POSTED') not in('VOIDED','CANCELLED')
  group by b.ledger_id
 )
 select s.id,s.supplier_name,l.id,l.ledger_code,round(greatest(coalesce(t.dr,0)-coalesce(t.cr,0),0),2),round(greatest(coalesce(t.cr,0)-coalesce(t.dr,0),0),2),round(coalesce(t.cr,0)-coalesce(t.dr,0),2)
 from public.rr_suppliers s join public.rr_supplier_accounts_map_v9763 m on m.supplier_id=s.id and m.is_active
 join public.rr_ledgers_v805 l on l.id=m.supplier_ledger_id and l.is_active
 left join totals t on t.ledger_id=l.id
 where s.is_active and (v_q='' or lower(s.supplier_name) like '%'||v_q||'%' or lower(coalesce(l.ledger_code,'')) like '%'||v_q||'%')
 order by lower(s.supplier_name),s.id limit v_limit offset v_offset;
end $function$;

create or replace function public.rr_accounts_post_journal_v9763(p_debit_ledger_id uuid,p_credit_ledger_id uuid,p_amount numeric,p_ref_no text,p_narration text,p_data_mode text default 'TEST')
returns jsonb language plpgsql security definer set search_path='public' as $function$
declare v_amount numeric:=round(coalesce(p_amount,0),2);v_source text:=gen_random_uuid()::text;
begin
 if not public.rr_acct_can_view_v805() then raise exception 'Accounts permission required.'; end if;
 if p_debit_ledger_id is null or p_credit_ledger_id is null or p_debit_ledger_id=p_credit_ledger_id then raise exception 'Distinct Debit and Credit ledgers required.'; end if;
 if v_amount<=0 then raise exception 'Journal amount must be greater than zero.'; end if;
 if nullif(trim(coalesce(p_narration,'')),'') is null then raise exception 'Journal narration required.'; end if;
 return public.rr_accounts_post_v805('JOURNAL',v_amount,jsonb_build_array(
  jsonb_build_object('ledger_id',p_debit_ledger_id,'dr',v_amount,'cr',0,'narration',trim(p_narration)),
  jsonb_build_object('ledger_id',p_credit_ledger_id,'dr',0,'cr',v_amount,'narration',trim(p_narration))
 ),'ACCOUNTS_TEMPLATE',v_source,null,p_ref_no,current_date,trim(p_narration),p_data_mode);
end $function$;

create or replace function public.rr_accounts_reverse_transaction_v9761(p_transaction_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='public' as $function$
declare t public.rr_account_transactions_v805%rowtype;
begin
 if not public.rr_acct_can_view_v805() then raise exception 'Accounts permission required.'; end if;
 if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Reverse reason required.'; end if;
 select * into t from public.rr_account_transactions_v805 where id=p_transaction_id for update;
 if not found then raise exception 'Accounts transaction not found.'; end if;
 if t.status<>'POSTED' then raise exception 'Only POSTED transaction can be reversed.'; end if;
 if t.source_module<>'ACCOUNTS_TEMPLATE' or t.transaction_type not in('RECEIPT','PAYMENT','JOURNAL') then raise exception 'Reverse the source document instead.'; end if;
 return public.rr_accounts_reverse_source_mirror_v806(t.source_module,t.source_record_id,t.data_mode,p_reason);
end $function$;

create or replace function public.rr_accounts_reverse_voucher_v9763(p_voucher_no text,p_reason text,p_data_mode text default 'TEST')
returns jsonb language plpgsql security definer set search_path='public' as $function$
declare v_id uuid;
begin
 if not public.rr_acct_can_view_v805() then raise exception 'Accounts permission required.'; end if;
 select id into v_id from public.rr_account_transactions_v805 where voucher_no=trim(p_voucher_no) and data_mode=upper(coalesce(p_data_mode,'TEST')) for update;
 if v_id is null then raise exception 'Voucher not found.'; end if;
 return public.rr_accounts_reverse_transaction_v9761(v_id,p_reason);
end $function$;

revoke all on function public.rr_accounts_creditor_search_v9763(text,integer,integer,text),public.rr_accounts_post_journal_v9763(uuid,uuid,numeric,text,text,text),public.rr_accounts_reverse_transaction_v9761(uuid,text),public.rr_accounts_reverse_voucher_v9763(text,text,text) from public,anon;
grant execute on function public.rr_accounts_creditor_search_v9763(text,integer,integer,text),public.rr_accounts_post_journal_v9763(uuid,uuid,numeric,text,text,text),public.rr_accounts_reverse_transaction_v9761(uuid,text),public.rr_accounts_reverse_voucher_v9763(text,text,text) to authenticated,service_role;

commit;
