-- TEST71 commercial Real Chat integration.
-- This migration adds projections and bill allocation to the existing canonical
-- Sales, Costing and Accounts engines. It intentionally creates no replacement
-- PI/CI/RCI, purchase, costing, voucher or ledger engine.

create table if not exists public.rr_account_bills_v500 (
  id uuid primary key default gen_random_uuid(),
  source_transaction_id uuid not null references public.rr_account_transactions_v805(id),
  party_ledger_id uuid not null references public.rr_ledgers_v805(id),
  bill_kind text not null check (bill_kind in ('RECEIVABLE','PAYABLE')),
  bill_no text not null,
  bill_date date not null,
  original_amount numeric(18,2) not null check (original_amount >= 0),
  outstanding_amount numeric(18,2) not null check (outstanding_amount >= 0),
  status text not null default 'UNPAID' check (status in ('UNPAID','PART_PAID','PAID','REVERSED')),
  cleared_at timestamptz,
  data_mode text not null check (data_mode in ('TEST','REAL')),
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
  ,unique(source_transaction_id,party_ledger_id,bill_kind)
);

create table if not exists public.rr_account_allocations_v500 (
  id uuid primary key default gen_random_uuid(),
  settlement_transaction_id uuid not null references public.rr_account_transactions_v805(id),
  bill_id uuid not null references public.rr_account_bills_v500(id),
  allocation_seq integer not null,
  allocated_amount numeric(18,2) not null check (allocated_amount > 0),
  allocation_mode text not null default 'AUTO_FIFO' check (allocation_mode in ('AUTO_FIFO','AUTO_ADVANCE','MANUAL')),
  allocated_by uuid,
  allocated_at timestamptz not null default now(),
  unique(settlement_transaction_id,bill_id)
);

create table if not exists public.rr_account_advances_v500 (
  id uuid primary key default gen_random_uuid(),
  source_transaction_id uuid not null references public.rr_account_transactions_v805(id),
  party_ledger_id uuid not null references public.rr_ledgers_v805(id),
  advance_kind text not null check (advance_kind in ('CUSTOMER_CREDIT','SUPPLIER_ADVANCE')),
  original_amount numeric(18,2) not null check (original_amount > 0),
  remaining_amount numeric(18,2) not null check (remaining_amount >= 0),
  status text not null default 'OPEN' check (status in ('OPEN','CONSUMED','REVERSED')),
  data_mode text not null check (data_mode in ('TEST','REAL')),
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
  ,unique(source_transaction_id,party_ledger_id,advance_kind)
);

create table if not exists public.rr_accounts_work_item_v500 (
  id uuid primary key default gen_random_uuid(),
  source_module text not null,
  source_record_id text not null,
  action_kind text not null,
  reference_no text,
  party_ledger_id uuid references public.rr_ledgers_v805(id),
  amount numeric(18,2),
  state text not null default 'OPEN' check (state in ('OPEN','WORKING','CLOSE','CANCELLED')),
  data_mode text not null default 'TEST' check (data_mode in ('TEST','REAL')),
  accepted_by uuid,
  accepted_at timestamptz,
  closed_by uuid,
  closed_at timestamptz,
  canonical_transaction_id uuid references public.rr_account_transactions_v805(id),
  audit jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(source_module,source_record_id,action_kind,data_mode)
);

create index if not exists rr_account_bills_v500_party_fifo
  on public.rr_account_bills_v500(party_ledger_id,data_mode,bill_kind,status,bill_date,created_at);
create index if not exists rr_account_allocations_v500_bill
  on public.rr_account_allocations_v500(bill_id,allocated_at);
create index if not exists rr_account_advances_v500_party_fifo
  on public.rr_account_advances_v500(party_ledger_id,data_mode,advance_kind,status,created_at);
create index if not exists rr_accounts_work_item_v500_state
  on public.rr_accounts_work_item_v500(data_mode,state,created_at);

alter table public.rr_account_bills_v500 enable row level security;
alter table public.rr_account_allocations_v500 enable row level security;
alter table public.rr_account_advances_v500 enable row level security;
alter table public.rr_accounts_work_item_v500 enable row level security;
revoke all on public.rr_account_bills_v500 from anon,authenticated;
revoke all on public.rr_account_allocations_v500 from anon,authenticated;
revoke all on public.rr_account_advances_v500 from anon,authenticated;
revoke all on public.rr_accounts_work_item_v500 from anon,authenticated;

create or replace function public.rr_accounts_bill_status_v500(p_bill_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare b public.rr_account_bills_v500%rowtype;
begin
  select * into b from public.rr_account_bills_v500 where id=p_bill_id for update;
  if b.id is null or b.status='REVERSED' then return; end if;
  update public.rr_account_bills_v500 set
    status=case when outstanding_amount<=0 then 'PAID' when outstanding_amount<original_amount then 'PART_PAID' else 'UNPAID' end,
    cleared_at=case when outstanding_amount<=0 then coalesce(cleared_at,now()) else null end,
    updated_at=now()
  where id=p_bill_id;
end $$;

create or replace function public.rr_accounts_fifo_settle_v500(
  p_transaction_id uuid,p_party_ledger_id uuid,p_bill_kind text,p_amount numeric,
  p_data_mode text,p_mode text default 'AUTO_FIFO'
) returns jsonb language plpgsql security definer set search_path=public as $$
declare left_amount numeric:=round(coalesce(p_amount,0),2); b public.rr_account_bills_v500%rowtype;
  take_amount numeric; seq_no integer:=0; adv_kind text;
begin
  if left_amount<=0 then return jsonb_build_object('allocated',0,'advance',0); end if;
  if exists(select 1 from public.rr_account_allocations_v500 x join public.rr_account_bills_v500 xb on xb.id=x.bill_id
      where x.settlement_transaction_id=p_transaction_id and xb.party_ledger_id=p_party_ledger_id and xb.bill_kind=upper(p_bill_kind))
     or exists(select 1 from public.rr_account_advances_v500 xa where xa.source_transaction_id=p_transaction_id
      and xa.party_ledger_id=p_party_ledger_id and xa.advance_kind=case when upper(p_bill_kind)='RECEIVABLE' then 'CUSTOMER_CREDIT' else 'SUPPLIER_ADVANCE' end)
  then return jsonb_build_object('already_synced',true); end if;
  for b in select * from public.rr_account_bills_v500
    where party_ledger_id=p_party_ledger_id and bill_kind=upper(p_bill_kind)
      and data_mode=upper(p_data_mode) and status in('UNPAID','PART_PAID') and outstanding_amount>0
    order by bill_date,created_at,id for update
  loop
    exit when left_amount<=0;
    take_amount:=least(left_amount,b.outstanding_amount); seq_no:=seq_no+1;
    insert into public.rr_account_allocations_v500(settlement_transaction_id,bill_id,allocation_seq,allocated_amount,allocation_mode,allocated_by)
    values(p_transaction_id,b.id,seq_no,take_amount,upper(p_mode),auth.uid())
    on conflict(settlement_transaction_id,bill_id) do nothing;
    if found then
      update public.rr_account_bills_v500 set outstanding_amount=greatest(0,outstanding_amount-take_amount),updated_at=now() where id=b.id;
      perform public.rr_accounts_bill_status_v500(b.id);
      left_amount:=left_amount-take_amount;
    end if;
  end loop;
  if left_amount>0 then
    adv_kind:=case when upper(p_bill_kind)='RECEIVABLE' then 'CUSTOMER_CREDIT' else 'SUPPLIER_ADVANCE' end;
    insert into public.rr_account_advances_v500(source_transaction_id,party_ledger_id,advance_kind,original_amount,remaining_amount,data_mode,created_by)
    values(p_transaction_id,p_party_ledger_id,adv_kind,left_amount,left_amount,upper(p_data_mode),auth.uid())
    on conflict(source_transaction_id,party_ledger_id,advance_kind) do nothing;
  end if;
  return jsonb_build_object('allocated',round(coalesce(p_amount,0)-left_amount,2),'advance',left_amount);
end $$;

create or replace function public.rr_accounts_create_bill_v500(
  p_transaction_id uuid,p_party_ledger_id uuid,p_bill_kind text,p_bill_no text,
  p_bill_date date,p_amount numeric,p_data_mode text,p_created_by uuid
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_bill_id uuid; remaining numeric:=round(coalesce(p_amount,0),2); a public.rr_account_advances_v500%rowtype;
  take_amount numeric; seq_no integer:=0; wanted text;
begin
  if remaining<=0 then return null; end if;
  insert into public.rr_account_bills_v500(source_transaction_id,party_ledger_id,bill_kind,bill_no,bill_date,original_amount,outstanding_amount,data_mode,created_by)
  values(p_transaction_id,p_party_ledger_id,upper(p_bill_kind),coalesce(nullif(trim(p_bill_no),''),'VOUCHER'),coalesce(p_bill_date,current_date),remaining,remaining,upper(p_data_mode),p_created_by)
  on conflict(source_transaction_id,party_ledger_id,bill_kind) do update set updated_at=now() returning id into v_bill_id;
  wanted:=case when upper(p_bill_kind)='RECEIVABLE' then 'CUSTOMER_CREDIT' else 'SUPPLIER_ADVANCE' end;
  for a in select * from public.rr_account_advances_v500 where party_ledger_id=p_party_ledger_id
    and advance_kind=wanted and data_mode=upper(p_data_mode) and status='OPEN' and remaining_amount>0
    order by created_at,id for update
  loop
    exit when remaining<=0;
    take_amount:=least(remaining,a.remaining_amount); seq_no:=seq_no+1;
    insert into public.rr_account_allocations_v500(settlement_transaction_id,bill_id,allocation_seq,allocated_amount,allocation_mode,allocated_by)
    values(a.source_transaction_id,v_bill_id,seq_no,take_amount,'AUTO_ADVANCE',p_created_by)
    on conflict(settlement_transaction_id,bill_id) do nothing;
    if found then
      update public.rr_account_advances_v500 set remaining_amount=greatest(0,remaining_amount-take_amount),
        status=case when remaining_amount-take_amount<=0 then 'CONSUMED' else 'OPEN' end,updated_at=now() where id=a.id;
      update public.rr_account_bills_v500 set outstanding_amount=greatest(0,outstanding_amount-take_amount),updated_at=now() where id=v_bill_id;
      remaining:=remaining-take_amount;
    end if;
  end loop;
  perform public.rr_accounts_bill_status_v500(v_bill_id);
  return v_bill_id;
end $$;

create or replace function public.rr_accounts_fifo_sync_transaction_v500(p_transaction_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare t public.rr_account_transactions_v805%rowtype; l public.rr_ledgers_v805%rowtype; k text; p record; n integer:=0;
begin
  select * into t from public.rr_account_transactions_v805 where id=p_transaction_id;
  if t.id is null or t.status<>'POSTED' then return jsonb_build_object('ignored',true); end if;
  k:=upper(t.transaction_type);
  if k='JOURNAL' then
    for p in select ap.ledger_id,ap.dr_amount,ap.cr_amount,ll.ledger_kind
      from public.rr_account_postings_v805 ap join public.rr_ledgers_v805 ll on ll.id=ap.ledger_id
      where ap.transaction_id=t.id and ll.is_active and upper(ll.ledger_kind) in('CUSTOMER','SUPPLIER')
    loop
      if upper(p.ledger_kind)='CUSTOMER' and p.dr_amount>0 then
        perform public.rr_accounts_create_bill_v500(t.id,p.ledger_id,'RECEIVABLE',coalesce(t.bill_no,t.voucher_no),coalesce(t.bill_date,t.transaction_datetime::date),p.dr_amount,t.data_mode,t.created_by);
      elsif upper(p.ledger_kind)='CUSTOMER' and p.cr_amount>0 then
        perform public.rr_accounts_fifo_settle_v500(t.id,p.ledger_id,'RECEIVABLE',p.cr_amount,t.data_mode,'MANUAL');
      elsif upper(p.ledger_kind)='SUPPLIER' and p.cr_amount>0 then
        perform public.rr_accounts_create_bill_v500(t.id,p.ledger_id,'PAYABLE',coalesce(t.bill_no,t.voucher_no),coalesce(t.bill_date,t.transaction_datetime::date),p.cr_amount,t.data_mode,t.created_by);
      elsif upper(p.ledger_kind)='SUPPLIER' and p.dr_amount>0 then
        perform public.rr_accounts_fifo_settle_v500(t.id,p.ledger_id,'PAYABLE',p.dr_amount,t.data_mode,'MANUAL');
      end if;
      n:=n+1;
    end loop;
    return jsonb_build_object('journal_party_effects',n);
  end if;
  if t.party_ledger_id is null then return jsonb_build_object('ignored',true); end if;
  select * into l from public.rr_ledgers_v805 where id=t.party_ledger_id and is_active;
  if l.id is null or upper(l.ledger_kind) not in('CUSTOMER','SUPPLIER') then return jsonb_build_object('ignored',true); end if;
  if upper(l.ledger_kind)='CUSTOMER' and k in('SALE','SALES') then
    return jsonb_build_object('bill_id',public.rr_accounts_create_bill_v500(t.id,l.id,'RECEIVABLE',coalesce(t.bill_no,t.voucher_no),coalesce(t.bill_date,t.transaction_datetime::date),t.total_amount,t.data_mode,t.created_by));
  elsif upper(l.ledger_kind)='SUPPLIER' and k='PURCHASE' then
    return jsonb_build_object('bill_id',public.rr_accounts_create_bill_v500(t.id,l.id,'PAYABLE',coalesce(t.bill_no,t.voucher_no),coalesce(t.bill_date,t.transaction_datetime::date),t.total_amount,t.data_mode,t.created_by));
  elsif upper(l.ledger_kind)='CUSTOMER' and k in('RECEIPT','SALES_RETURN') then
    return public.rr_accounts_fifo_settle_v500(t.id,l.id,'RECEIVABLE',t.total_amount,t.data_mode,'AUTO_FIFO');
  elsif upper(l.ledger_kind)='SUPPLIER' and k in('PAYMENT','PURCHASE_RETURN') then
    return public.rr_accounts_fifo_settle_v500(t.id,l.id,'PAYABLE',t.total_amount,t.data_mode,'AUTO_FIFO');
  end if;
  return jsonb_build_object('ignored',true);
end $$;

create or replace function public.rr_accounts_fifo_rebuild_party_v500(p_party_ledger_id uuid,p_data_mode text)
returns void language plpgsql security definer set search_path=public as $$
declare r record;
begin
  delete from public.rr_account_allocations_v500 a using public.rr_account_bills_v500 b
    where a.bill_id=b.id and b.party_ledger_id=p_party_ledger_id and b.data_mode=upper(p_data_mode);
  delete from public.rr_account_advances_v500 where party_ledger_id=p_party_ledger_id and data_mode=upper(p_data_mode);
  delete from public.rr_account_bills_v500 where party_ledger_id=p_party_ledger_id and data_mode=upper(p_data_mode);
  for r in
    select distinct t.id,t.transaction_datetime,t.created_at
    from public.rr_account_transactions_v805 t
    left join public.rr_account_postings_v805 ap on ap.transaction_id=t.id
    where t.status='POSTED' and t.data_mode=upper(p_data_mode)
      and (t.party_ledger_id=p_party_ledger_id or ap.ledger_id=p_party_ledger_id)
    order by t.transaction_datetime,t.created_at,t.id
  loop perform public.rr_accounts_fifo_sync_transaction_v500(r.id); end loop;
end $$;

create or replace function public.rr_accounts_fifo_after_status_v500()
returns trigger language plpgsql security definer set search_path=public as $$
declare r record;
begin
  if old.status is distinct from new.status then
    if coalesce(new.party_ledger_id,old.party_ledger_id) is not null then
      perform public.rr_accounts_fifo_rebuild_party_v500(coalesce(new.party_ledger_id,old.party_ledger_id),new.data_mode);
    end if;
    if upper(new.transaction_type)='JOURNAL' then
      for r in select distinct ap.ledger_id from public.rr_account_postings_v805 ap
        join public.rr_ledgers_v805 l on l.id=ap.ledger_id
        where ap.transaction_id=new.id and upper(l.ledger_kind) in('CUSTOMER','SUPPLIER')
      loop perform public.rr_accounts_fifo_rebuild_party_v500(r.ledger_id,new.data_mode); end loop;
    end if;
  end if;
  return new;
end $$;

create or replace function public.rr_accounts_fifo_after_insert_v500()
returns trigger language plpgsql security definer set search_path=public as $$
begin perform public.rr_accounts_fifo_sync_transaction_v500(new.id); return new; end $$;
drop trigger if exists rr_accounts_fifo_after_insert_v500 on public.rr_account_transactions_v805;
create trigger rr_accounts_fifo_after_insert_v500 after insert on public.rr_account_transactions_v805
for each row execute function public.rr_accounts_fifo_after_insert_v500();
drop trigger if exists rr_accounts_fifo_after_status_v500 on public.rr_account_transactions_v805;
create trigger rr_accounts_fifo_after_status_v500 after update of status on public.rr_account_transactions_v805
for each row execute function public.rr_accounts_fifo_after_status_v500();

-- Idempotent chronological backfill of canonical posted transactions.
do $$ declare r record; begin
  for r in select id from public.rr_account_transactions_v805 where status='POSTED' order by transaction_datetime,created_at,id
  loop perform public.rr_accounts_fifo_sync_transaction_v500(r.id); end loop;
end $$;

-- Preserve the existing Journal engine and add only the derived party FIFO
-- projection after its canonical transaction and posting lines are complete.
create or replace function public.rr_accounts_post_journal_v9763(
  p_debit_ledger_id uuid,p_credit_ledger_id uuid,p_amount numeric,p_ref_no text,p_narration text,p_data_mode text default 'TEST'
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_amount numeric:=round(coalesce(p_amount,0),2); v_source text:=gen_random_uuid()::text; out_json jsonb;
begin
  if not public.rr_acct_can_view_v805() then raise exception 'Accounts permission required.'; end if;
  if p_debit_ledger_id is null or p_credit_ledger_id is null or p_debit_ledger_id=p_credit_ledger_id then raise exception 'Distinct Debit and Credit ledgers required.'; end if;
  if v_amount<=0 then raise exception 'Journal amount must be greater than zero.'; end if;
  if nullif(trim(coalesce(p_narration,'')),'') is null then raise exception 'Journal narration required.'; end if;
  out_json:=public.rr_accounts_post_v805('JOURNAL',v_amount,jsonb_build_array(
    jsonb_build_object('ledger_id',p_debit_ledger_id,'dr',v_amount,'cr',0,'narration',trim(p_narration)),
    jsonb_build_object('ledger_id',p_credit_ledger_id,'dr',0,'cr',v_amount,'narration',trim(p_narration))
  ),'ACCOUNTS_TEMPLATE',v_source,null,p_ref_no,current_date,trim(p_narration),p_data_mode);
  perform public.rr_accounts_fifo_sync_transaction_v500((out_json->>'transaction_id')::uuid);
  return out_json||jsonb_build_object('billwise_fifo_synced',true);
end $$;

create or replace function public.rr_accounts_work_item_set_v500(
  p_source_module text,p_source_record_id text,p_action_kind text,p_reference_no text default null,
  p_party_ledger_id uuid default null,p_amount numeric default null,p_state text default 'WORKING',
  p_canonical_transaction_id uuid default null,p_data_mode text default 'TEST'
) returns jsonb language plpgsql security definer set search_path=public as $$
declare w public.rr_accounts_work_item_v500%rowtype; next_state text:=upper(coalesce(p_state,'WORKING')); actor uuid:=auth.uid(); event jsonb;
begin
  if not public.rr_acct_can_view_v805() then raise exception 'Accounts permission required.'; end if;
  if next_state not in('OPEN','WORKING','CLOSE','CANCELLED') then raise exception 'Valid accounting action state required.'; end if;
  if nullif(trim(p_source_module),'') is null or nullif(trim(p_source_record_id),'') is null or nullif(trim(p_action_kind),'') is null then
    raise exception 'Canonical source and action required.';
  end if;
  event:=jsonb_build_object('actor',actor,'effective_actor',actor,'role',coalesce(auth.jwt()->>'role','authenticated'),
    'timestamp',now(),'source','REAL_CHAT','previous_state',null,'new_state',next_state);
  insert into public.rr_accounts_work_item_v500(source_module,source_record_id,action_kind,reference_no,party_ledger_id,amount,state,data_mode,
    accepted_by,accepted_at,closed_by,closed_at,canonical_transaction_id,audit)
  values(upper(trim(p_source_module)),trim(p_source_record_id),upper(trim(p_action_kind)),nullif(trim(p_reference_no),''),p_party_ledger_id,p_amount,next_state,upper(p_data_mode),
    case when next_state='WORKING' then actor end,case when next_state='WORKING' then now() end,
    case when next_state='CLOSE' then actor end,case when next_state='CLOSE' then now() end,p_canonical_transaction_id,jsonb_build_array(event))
  on conflict(source_module,source_record_id,action_kind,data_mode) do update set
    state=excluded.state,reference_no=coalesce(excluded.reference_no,rr_accounts_work_item_v500.reference_no),
    party_ledger_id=coalesce(excluded.party_ledger_id,rr_accounts_work_item_v500.party_ledger_id),amount=coalesce(excluded.amount,rr_accounts_work_item_v500.amount),
    accepted_by=case when excluded.state='WORKING' then actor else rr_accounts_work_item_v500.accepted_by end,
    accepted_at=case when excluded.state='WORKING' then now() else rr_accounts_work_item_v500.accepted_at end,
    closed_by=case when excluded.state='CLOSE' then actor else rr_accounts_work_item_v500.closed_by end,
    closed_at=case when excluded.state='CLOSE' then now() else rr_accounts_work_item_v500.closed_at end,
    canonical_transaction_id=coalesce(excluded.canonical_transaction_id,rr_accounts_work_item_v500.canonical_transaction_id),
    audit=rr_accounts_work_item_v500.audit||jsonb_build_array(event||jsonb_build_object('previous_state',rr_accounts_work_item_v500.state)),updated_at=now()
  returning * into w;
  return jsonb_build_object('ok',true,'id',w.id,'state',w.state,'canonical_transaction_id',w.canonical_transaction_id,'audit',w.audit);
end $$;

create or replace function public.rr_accounts_party_summary_v500(
  p_kind text default null,p_data_mode text default 'TEST',p_search text default null
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare rows_json jsonb;
begin
  if not public.rr_acct_can_view_v805() then raise exception 'Accounts permission required.'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.outstanding desc,x.party_name),'[]'::jsonb) into rows_json from (
    select l.id party_ledger_id,l.ledger_name party_name,upper(l.ledger_kind) party_kind,
      round(coalesce(sum(b.outstanding_amount) filter(where b.status<>'REVERSED'),0),2) outstanding,
      min(b.bill_date) filter(where b.outstanding_amount>0 and b.status<>'REVERSED') oldest_bill_date,
      coalesce(max(current_date-b.bill_date) filter(where b.outstanding_amount>0 and b.status<>'REVERSED'),0) oldest_due_days,
      count(*) filter(where b.status='UNPAID') unpaid_count,count(*) filter(where b.status='PART_PAID') part_paid_count,
      round(coalesce(avg((b.cleared_at::date-b.bill_date)) filter(where b.status='PAID'),0),1) average_clearance_days,
      round(coalesce(sum(b.outstanding_amount) filter(where b.outstanding_amount>0 and current_date-b.bill_date between 0 and 30),0),2) aging_0_30,
      round(coalesce(sum(b.outstanding_amount) filter(where b.outstanding_amount>0 and current_date-b.bill_date between 31 and 60),0),2) aging_31_60,
      round(coalesce(sum(b.outstanding_amount) filter(where b.outstanding_amount>0 and current_date-b.bill_date between 61 and 90),0),2) aging_61_90,
      round(coalesce(sum(b.outstanding_amount) filter(where b.outstanding_amount>0 and current_date-b.bill_date>90),0),2) aging_90_plus,
      round(coalesce((select sum(a.remaining_amount) from public.rr_account_advances_v500 a where a.party_ledger_id=l.id and a.data_mode=upper(p_data_mode) and a.status='OPEN'),0),2) advance
    from public.rr_ledgers_v805 l left join public.rr_account_bills_v500 b on b.party_ledger_id=l.id and b.data_mode=upper(p_data_mode)
    where l.is_active and upper(l.ledger_kind) in('CUSTOMER','SUPPLIER')
      and (p_kind is null or upper(l.ledger_kind)=upper(p_kind))
      and (nullif(trim(p_search),'') is null or l.ledger_name ilike '%'||trim(p_search)||'%')
    group by l.id,l.ledger_name,l.ledger_kind
  ) x;
  return jsonb_build_object('data_mode',upper(p_data_mode),'parties',rows_json);
end $$;

create or replace function public.rr_accounts_bill_detail_v500(p_party_ledger_id uuid,p_data_mode text default 'TEST')
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare l public.rr_ledgers_v805%rowtype; bills_json jsonb; alloc_json jsonb;
begin
  if not public.rr_acct_can_view_v805() then raise exception 'Accounts permission required.'; end if;
  select * into l from public.rr_ledgers_v805 where id=p_party_ledger_id and is_active;
  if l.id is null then raise exception 'Party ledger not found.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('bill_id',b.id,'bill_no',b.bill_no,'bill_date',b.bill_date,
    'original_amount',b.original_amount,'allocated',b.original_amount-b.outstanding_amount,'outstanding',b.outstanding_amount,
    'status',b.status,'cleared_date',b.cleared_at::date,'clearance_days',case when b.cleared_at is not null then b.cleared_at::date-b.bill_date else current_date-b.bill_date end)
    order by b.bill_date,b.created_at),'[]'::jsonb) into bills_json from public.rr_account_bills_v500 b
    where b.party_ledger_id=l.id and b.data_mode=upper(p_data_mode);
  select coalesce(jsonb_agg(jsonb_build_object('bill_id',a.bill_id,'bill_no',b.bill_no,'settlement_voucher',t.voucher_no,
    'amount',a.allocated_amount,'mode',a.allocation_mode,'allocated_at',a.allocated_at) order by a.allocated_at),'[]'::jsonb) into alloc_json
    from public.rr_account_allocations_v500 a join public.rr_account_bills_v500 b on b.id=a.bill_id
    join public.rr_account_transactions_v805 t on t.id=a.settlement_transaction_id
    where b.party_ledger_id=l.id and b.data_mode=upper(p_data_mode);
  return jsonb_build_object('party_ledger_id',l.id,'party_name',l.ledger_name,'party_kind',l.ledger_kind,'bills',bills_json,'allocations',alloc_json);
end $$;

create or replace function public.rr_accounts_real_chat_home_v500(p_status text default 'OPEN',p_data_mode text default 'TEST')
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare cats jsonb; cards jsonb; s text:=upper(coalesce(p_status,'OPEN'));
begin
  if not public.rr_acct_can_view_v805() then raise exception 'Accounts permission required.'; end if;
  if s not in('OPEN','WORKING','CLOSE') then raise exception 'OPEN / WORKING / CLOSE required.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('code',x.code,'label',x.label,'count',x.n,'amount',x.amount) order by x.sort_no),'[]'::jsonb) into cats from (
    select 1 sort_no,'DEBTORS' code,'SUNDRY DEBTORS' label,count(*) n,coalesce(sum(outstanding_amount),0) amount from public.rr_account_bills_v500 where data_mode=upper(p_data_mode) and bill_kind='RECEIVABLE' and status<>'REVERSED'
    union all select 2,'CREDITORS','SUNDRY CREDITORS',count(*),coalesce(sum(outstanding_amount),0) from public.rr_account_bills_v500 where data_mode=upper(p_data_mode) and bill_kind='PAYABLE' and status<>'REVERSED'
    union all select 3,'SALES','SALES',count(*),coalesce(sum(total_amount),0) from public.rr_account_transactions_v805 where data_mode=upper(p_data_mode) and status='POSTED' and transaction_type in('SALE','SALES')
    union all select 4,'PURCHASE','PURCHASE',count(*),coalesce(sum(total_amount),0) from public.rr_account_transactions_v805 where data_mode=upper(p_data_mode) and status='POSTED' and transaction_type='PURCHASE'
    union all select 5,'RECEIPTS','RECEIPTS',count(*),coalesce(sum(total_amount),0) from public.rr_account_transactions_v805 where data_mode=upper(p_data_mode) and status='POSTED' and transaction_type='RECEIPT'
    union all select 6,'PAYMENTS','PAYMENTS',count(*),coalesce(sum(total_amount),0) from public.rr_account_transactions_v805 where data_mode=upper(p_data_mode) and status='POSTED' and transaction_type='PAYMENT'
    union all select 7,'EXPENSES','EXPENSES',count(*),coalesce(sum(total_amount),0) from public.rr_account_transactions_v805 where data_mode=upper(p_data_mode) and status='POSTED' and transaction_type='EXPENSE'
    union all select 8,'JOURNALS','JOURNALS',count(*),coalesce(sum(total_amount),0) from public.rr_account_transactions_v805 where data_mode=upper(p_data_mode) and status='POSTED' and transaction_type='JOURNAL'
  ) x;
  if s='OPEN' then
    select coalesce(jsonb_agg(jsonb_build_object('id',d.source_id,'kind',d.due_type,'reference_no',d.reference_no,'detail',d.reference_detail,'amount',d.due_amount,'since',d.due_since,'state','OPEN') order by d.sort_at),'[]'::jsonb) into cards
    from (select * from public.rr_accounts_due_v834 where coalesce(due_state,'OPEN') not in('CLOSE','CLOSED','POSTED') order by sort_at limit 80) d;
  elsif s='WORKING' then
    select coalesce(jsonb_agg(jsonb_build_object('id',w.id,'kind',w.action_kind,'reference_no',w.reference_no,'amount',w.amount,'since',w.accepted_at,'state',w.state,'party_ledger_id',w.party_ledger_id) order by w.accepted_at),'[]'::jsonb) into cards
    from public.rr_accounts_work_item_v500 w where w.data_mode=upper(p_data_mode) and w.state='WORKING';
  else
    select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'kind',t.transaction_type,'reference_no',t.voucher_no,'bill_no',t.bill_no,'amount',t.total_amount,'since',t.transaction_datetime,'state','CLOSE','party_ledger_id',t.party_ledger_id) order by t.transaction_datetime desc),'[]'::jsonb) into cards
    from (select * from public.rr_account_transactions_v805 where data_mode=upper(p_data_mode) and status='POSTED' order by transaction_datetime desc limit 80) t;
  end if;
  return jsonb_build_object('version','V500_CANONICAL_ACCOUNTS_CHAT','status',s,'categories',cats,'cards',cards,
    'day_book_rpc','rr_day_book_v806','ledger_rpc','rr_accounts_ledger_statement_v9785');
end $$;

create or replace function public.rr_sales_real_chat_queue_v500(p_status text default 'OPEN',p_search text default null,p_data_mode text default 'TEST')
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare s text:=upper(coalesce(p_status,'OPEN')); rows_json jsonb;
begin
  perform public.rr_market_assert_sales_actor_v9420();
  if s not in('OPEN','WORKING','CLOSE') then raise exception 'OPEN / WORKING / CLOSE required.'; end if;
  if s='OPEN' then
    with req as (
      select coalesce(r.root_requirement_id,r.id) root_id,max(r.requirement_display_no) requirement_no,
        sum(coalesce(l.accepted_qty,0)) present_qty,max(r.submitted_at) last_update,max(r.pi_generated_at) pi_generated_at,
        max(r.customer_name) customer_name,max(r.collection_display_no) collection_display_no,max(r.lifecycle_stage) lifecycle_stage
      from public.rr_market_requirements_v9420 r left join public.rr_market_requirement_lines_v9420 l on l.requirement_id=r.id
      group by coalesce(r.root_requirement_id,r.id)
    ), cy as (
      select c.id,c.display_no collection_no,c.status,c.created_at,c.chat_id,ch.customer_name,
        coalesce(max(cs.send_seq)-1,0) update_no,max(cs.sent_at) last_update,
        coalesce((select sum(q.present_qty) from req q join public.rr_collection_requirement_link_v9586 rl on rl.requirement_id=q.root_id where rl.collection_cycle_id=c.id),0) present_qty,
        (select max(q.requirement_no) from req q join public.rr_collection_requirement_link_v9586 rl on rl.requirement_id=q.root_id where rl.collection_cycle_id=c.id) requirement_no,
        (select max(q.pi_generated_at) from req q join public.rr_collection_requirement_link_v9586 rl on rl.requirement_id=q.root_id where rl.collection_cycle_id=c.id) pi_generated_at
      from public.rr_collection_cycle_v9586 c left join public.rr_customer_chat_v9433 ch on ch.id=c.chat_id
      left join public.rr_collection_send_v9586 cs on cs.collection_cycle_id=c.id
      where c.data_mode=upper(p_data_mode) group by c.id,ch.customer_name
    )
    select coalesce(jsonb_agg(jsonb_build_object('id',cy.id,'card_type','COLLECTION_FOLLOWUP','customer',cy.customer_name,
      'collection_no',cy.collection_no,'collection_update_no',cy.update_no,'requirement_no',cy.requirement_no,'present_qty',cy.present_qty,
      'present_amount',0,'all_qty',cy.present_qty,'all_amount',0,'last_update',coalesce(cy.last_update,cy.created_at),
      'current_status',case when cy.pi_generated_at is not null then 'COMPLETE' else cy.status end,'chat_id',cy.chat_id)
      order by coalesce(cy.last_update,cy.created_at) desc),'[]'::jsonb) into rows_json
    from cy where cy.pi_generated_at is null and cy.status not in('CLOSED','CLOSED_NO_RESPONSE','CANCELLED')
      and (nullif(trim(p_search),'') is null or concat_ws(' ',cy.customer_name,cy.collection_no,cy.requirement_no) ilike '%'||trim(p_search)||'%');
  elsif s='WORKING' then
    select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'card_type','PI_CI_READY','customer',p.buyer_snapshot->>'buyer_name',
      'pi_no',p.pi_no,'date',p.created_at::date,'qty',coalesce(x.qty,0),'amount',p.grand_total,'salesman',coalesce(u.display_name,u.full_name),
      'current_status','CI READY','market_requirement_id',p.market_requirement_id) order by p.updated_at desc),'[]'::jsonb) into rows_json
    from public.rr_fg_pi_v787 p left join lateral(select sum(qty) qty from public.rr_fg_pi_lines_v787 where pi_id=p.id)x on true
    left join public.rr_user_profiles u on u.auth_user_id=p.created_by
    where p.data_mode=upper(p_data_mode) and p.status='DRAFT'
      and (nullif(trim(p_search),'') is null or concat_ws(' ',p.pi_no,p.buyer_snapshot->>'buyer_name') ilike '%'||trim(p_search)||'%');
  else
    select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'card_type','CI_HISTORY','customer',p.buyer_snapshot->>'buyer_name',
      'ci_no',p.cpi_no,'pi_no',p.pi_no,'date',p.finalized_at::date,'qty',coalesce(x.qty,0),'amount',p.grand_total,
      'current_status','CLOSE','rci_count',coalesce(r.rci_count,0),'rci_amount',coalesce(r.rci_amount,0),'payment_status','LEDGER')
      order by p.finalized_at desc),'[]'::jsonb) into rows_json
    from public.rr_fg_pi_v787 p left join lateral(select sum(qty) qty from public.rr_fg_pi_lines_v787 where pi_id=p.id)x on true
    left join lateral(select count(*) rci_count,sum(total_amount) rci_amount from public.rr_rci_v9740 where linked_ci_id=p.id and status='POSTED')r on true
    where p.data_mode=upper(p_data_mode) and p.status in('CI_FINAL','CPI_FINAL')
      and (nullif(trim(p_search),'') is null or concat_ws(' ',p.pi_no,p.cpi_no,p.buyer_snapshot->>'buyer_name') ilike '%'||trim(p_search)||'%');
  end if;
  return jsonb_build_object('version','V500_CANONICAL_SALES_CHAT','status',s,'cards',rows_json,
    'market_window','real-web-window-v9329.html','direct_pi','real-web-window-v9329.html?share_mode=direct_pi',
    'direct_ci','real-finished-goods-v787.html?view=sale&direct_ci=1','rci','real-rci-v9740.html');
end $$;

create or replace function public.rr_sales_pi_detail_v500(p_pi_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare p public.rr_fg_pi_v787%rowtype; lines_json jsonb;
begin
  perform public.rr_market_assert_sales_actor_v9420();
  select * into p from public.rr_fg_pi_v787 where id=p_pi_id and data_mode='TEST';
  if p.id is null then raise exception 'Canonical PI not found.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('lot_no',l.lot_no,'qty',l.qty,'rate',l.original_rate,
    'discount',l.discount_amount,'category',l.short_item_name,'stock_type',l.stock_type) order by l.serial_no,l.id),'[]'::jsonb)
    into lines_json from public.rr_fg_pi_lines_v787 l where l.pi_id=p.id;
  return jsonb_build_object('pi_id',p.id,'pi_no',p.pi_no,'customer_name',p.buyer_snapshot->>'buyer_name',
    'dispatch_details',p.dispatch_details,'requirement_id',p.market_requirement_id,'status',p.status,'lines',lines_json);
end $$;

create or replace function public.rr_costing_real_chat_queue_v500(p_status text default 'OPEN',p_search text default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare scope_json jsonb:=public.rr_costing_user_scope_v760(null); s text:=upper(coalesce(p_status,'OPEN')); rows_json jsonb;
begin
  if not coalesce((scope_json->>'can_edit_rate')::boolean,false) then raise exception 'Canonical rate editor permission required.'; end if;
  if s not in('OPEN','WORKING','CLOSE') then raise exception 'OPEN / WORKING / CLOSE required.'; end if;
  with dep as (
    select w.canonical_lot_id,max(w.lot_no) lot_no,public.rr_costing_canonical_department_v760(w.department_code) department_code,
      max(w.worker_name_snapshot) worker_name,min(w.assigned_at) accept_time,max(w.completed_at) submit_time,
      sum(coalesce(w.assigned_qty,0)) pcs,max(w.actual_rate) assignment_rate
    from public.rr_upm_work_assignments_v8 w where w.cancelled_at is null group by w.canonical_lot_id,public.rr_costing_canonical_department_v760(w.department_code)
    union
    select s.canonical_lot_id,max(s.lot_no),public.rr_costing_canonical_department_v760(s.department_code),
      max(s.assigned_worker_name),null,max(s.created_at),sum(coalesce(s.submitted_qty,0)),max(s.actual_rate)
    from public.rr_upm_submit_ledger_v2 s where s.reversed_at is null group by s.canonical_lot_id,public.rr_costing_canonical_department_v760(s.department_code)
  ), d as (
    select dep.canonical_lot_id,max(dep.lot_no) lot_no,dep.department_code,max(dep.worker_name) worker_name,
      min(dep.accept_time) accept_time,max(dep.submit_time) submit_time,max(dep.pcs) pcs,
      coalesce(max(r.actual_rate),max(dep.assignment_rate),0) actual_rate
    from dep left join public.rr_upm_department_rates_v2 r on r.canonical_lot_id=dep.canonical_lot_id
      and public.rr_costing_canonical_department_v760(r.department_code)=dep.department_code
    group by dep.canonical_lot_id,dep.department_code
  ), lots as (
    select l.canonical_lot_id,l.lot_no,l.art_no,l.art_image_urls thumbnail,l.total_qty pcs,l.status production_status,
      array_agg(d.department_code order by d.department_code) filter(where d.actual_rate<=0) missing_departments,
      count(*) filter(where d.actual_rate<=0) missing_count,count(*) department_count,
      max(d.submit_time) last_submit,max(d.accept_time) last_accept,
      (select jsonb_agg(jsonb_build_object('department_code',dx.department_code,'department_name',public.rr_costing_department_display_v760(dx.department_code),
        'worker',dx.worker_name,'accept_time',dx.accept_time,'submit_time',dx.submit_time,'pcs',dx.pcs,'actual_rate',dx.actual_rate) order by dx.department_code)
       from d dx where dx.canonical_lot_id=l.canonical_lot_id) departments,
      exists(select 1 from public.rr_upm_rate_requests_v760 q where q.canonical_lot_id=l.canonical_lot_id and q.request_status in('PENDING','OPENED','RATE_FILLED')
        and not exists(select 1 from public.rr_upm_department_rates_v2 rr where rr.canonical_lot_id=q.canonical_lot_id
          and public.rr_costing_canonical_department_v760(rr.department_code)=public.rr_costing_canonical_department_v760(q.department_code) and rr.actual_rate>0)) has_pending_event
    from public.rr_upm_lot_registry l join d on d.canonical_lot_id=l.canonical_lot_id
    left join public.rr_upm_lot_costing_v760 c on c.canonical_lot_id=l.canonical_lot_id
    where c.dispatched_at is null and c.archived_at is null
    group by l.canonical_lot_id,l.lot_no,l.art_no,l.art_image_urls,l.total_qty,l.status
  )
  select coalesce(jsonb_agg(jsonb_build_object('canonical_lot_id',x.canonical_lot_id,'lot_no',x.lot_no,'art_no',x.art_no,
    'thumbnail',x.thumbnail,'pcs',x.pcs,'production_status',x.production_status,'missing_count',x.missing_count,
    'missing_departments',x.missing_departments,'departments',x.departments,'last_action',coalesce(x.last_submit,x.last_accept),
    'chat_status',s,'source_module','UPM_RATE') order by coalesce(x.last_submit,x.last_accept) desc),'[]'::jsonb) into rows_json
  from lots x where ((s='OPEN' and x.missing_count>0 and not x.has_pending_event)
    or (s='WORKING' and x.missing_count>0 and x.has_pending_event)
    or (s='CLOSE' and x.missing_count=0))
    and (nullif(trim(p_search),'') is null or concat_ws(' ',x.lot_no,x.art_no,array_to_string(x.missing_departments,' ')) ilike '%'||trim(p_search)||'%');
  return jsonb_build_object('version','V500_CANONICAL_COSTING_CHAT','status',s,'cards',rows_json,'private_cost_included',false,
    'rate_save_rpc','rr_upm_set_department_rate_v760');
end $$;

revoke all on function public.rr_accounts_party_summary_v500(text,text,text) from public,anon;
revoke all on function public.rr_accounts_bill_detail_v500(uuid,text) from public,anon;
revoke all on function public.rr_accounts_real_chat_home_v500(text,text) from public,anon;
revoke all on function public.rr_sales_real_chat_queue_v500(text,text,text) from public,anon;
revoke all on function public.rr_sales_pi_detail_v500(uuid) from public,anon;
revoke all on function public.rr_costing_real_chat_queue_v500(text,text) from public,anon;
revoke all on function public.rr_accounts_work_item_set_v500(text,text,text,text,uuid,numeric,text,uuid,text) from public,anon;
grant execute on function public.rr_accounts_party_summary_v500(text,text,text) to authenticated;
grant execute on function public.rr_accounts_bill_detail_v500(uuid,text) to authenticated;
grant execute on function public.rr_accounts_real_chat_home_v500(text,text) to authenticated;
grant execute on function public.rr_sales_real_chat_queue_v500(text,text,text) to authenticated;
grant execute on function public.rr_sales_pi_detail_v500(uuid) to authenticated;
grant execute on function public.rr_costing_real_chat_queue_v500(text,text) to authenticated;
grant execute on function public.rr_accounts_work_item_set_v500(text,text,text,text,uuid,numeric,text,uuid,text) to authenticated;
