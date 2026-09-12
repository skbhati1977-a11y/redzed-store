-- V9754: promotion gate for canonical buyer ledgers and RCI financial posting.
-- Additive/idempotent. Distributor-customer identity is always partner_customer_id,
-- never shared mobile/name. Distributor customer names stay hidden from Accounts UI.
begin;

create table if not exists public.rr_rci_accounts_link_v9754(
  rci_id uuid primary key references public.rr_rci_v9740(id) on delete restrict,
  rci_no text,
  buyer_id uuid not null references public.rr_buyers_v787(id) on delete restrict,
  customer_ledger_id uuid references public.rr_ledgers_v805(id) on delete restrict,
  sales_return_ledger_id uuid references public.rr_ledgers_v805(id) on delete restrict,
  total_amount numeric(16,2) not null default 0,
  data_mode text not null,
  status text not null,
  account_transaction_id uuid references public.rr_account_transactions_v805(id) on delete restrict,
  account_voucher_no text,
  message text,
  updated_at timestamptz not null default now()
);
alter table public.rr_rci_accounts_link_v9754 enable row level security;
revoke all on public.rr_rci_accounts_link_v9754 from public,anon,authenticated;

create or replace function public.rr_accounts_ensure_buyer_ledger_v9754(p_buyer_id uuid)
returns uuid language plpgsql security definer set search_path='public' as $function$
declare
  b public.rr_buyers_v787%rowtype; v_category uuid; v_ledger uuid;
  v_source text; v_name text; v_type text; v_code text;
begin
  select * into b from public.rr_buyers_v787 where id=p_buyer_id;
  if b.id is null then raise exception 'Canonical buyer not found.'; end if;

  select source_kind into v_source from public.rr_customer_sales_map_v9745
   where buyer_id=b.id and is_active order by updated_at desc limit 1;

  v_type:=case when v_source='DISTRIBUTOR_CUSTOMER' then 'DISTRIBUTOR_CUSTOMER' else 'CUSTOMER' end;
  -- Do not expose distributor customer's personal name to Redzed Accounts users.
  v_name:=case when v_type='DISTRIBUTOR_CUSTOMER'
    then 'Distributor Customer · '||upper(substr(replace(b.id::text,'-',''),1,8))
    else b.buyer_name end;
  v_code:='CUST-'||upper(substr(replace(b.id::text,'-',''),1,12));

  select id into v_ledger from public.rr_ledgers_v805
   where is_active and linked_entity_id=b.id::text
     and upper(coalesce(linked_entity_type,'')) in('BUYER','CUSTOMER','DISTRIBUTOR_CUSTOMER')
   order by created_at limit 1;
  if v_ledger is not null then
    update public.rr_ledgers_v805 set linked_entity_type=v_type,
      ledger_name=v_name,normalized_name=public.rr_name_normalize_v805(v_name),
      mobile=case when v_type='DISTRIBUTOR_CUSTOMER' then null else b.contact_no end,
      opening_balance=0,opening_side='DR',updated_at=now()
    where id=v_ledger;
    return v_ledger;
  end if;

  -- Safely adopt a legacy unlinked direct-customer ledger with the same name.
  -- Distributor customers must never resolve by name/mobile.
  if v_type='CUSTOMER' then
    select id into v_ledger from public.rr_ledgers_v805
     where is_active and public.rr_name_normalize_v805(ledger_name)=public.rr_name_normalize_v805(v_name)
       and nullif(trim(coalesce(linked_entity_id,'')),'') is null
     order by created_at limit 1;
    if v_ledger is not null then
      update public.rr_ledgers_v805 set linked_entity_type=v_type,linked_entity_id=b.id::text,
        mobile=b.contact_no,opening_balance=0,opening_side='DR',updated_at=now()
      where id=v_ledger;
      return v_ledger;
    end if;
  end if;

  select id into v_category from public.rr_account_categories_v805
   where category_code='CUSTOMER_RECEIVABLE' and is_active limit 1;
  if v_category is null then raise exception 'Customer Receivable category missing.'; end if;

  insert into public.rr_ledgers_v805(ledger_code,ledger_name,normalized_name,category_id,
    ledger_kind,linked_entity_type,linked_entity_id,mobile,opening_balance,opening_side,is_active)
  values(v_code,v_name,public.rr_name_normalize_v805(v_name),v_category,'CUSTOMER',v_type,b.id::text,
    case when v_type='DISTRIBUTOR_CUSTOMER' then null else b.contact_no end,0,'DR',true)
  returning id into v_ledger;
  return v_ledger;
exception when unique_violation then
  select id into v_ledger from public.rr_ledgers_v805
   where linked_entity_id=b.id::text or ledger_code=v_code
      or (v_type='CUSTOMER' and public.rr_name_normalize_v805(ledger_name)=public.rr_name_normalize_v805(v_name))
   order by created_at limit 1;
  if v_ledger is null then raise; end if;
  return v_ledger;
end $function$;

create or replace function public.rr_accounts_post_rci_v9754(p_rci_id uuid)
returns jsonb language plpgsql security definer set search_path='public' as $function$
declare h public.rr_rci_v9740%rowtype; v_customer uuid; v_return uuid; v_tx jsonb;
begin
  select * into h from public.rr_rci_v9740 where id=p_rci_id and status='POSTED';
  if h.id is null then raise exception 'Posted RCI not found.'; end if;
  if coalesce(h.total_amount,0)<=0 then return jsonb_build_object('posted',false,'status','ZERO_VALUE_NO_POST'); end if;
  select jsonb_build_object('posted',true,'status','POSTED','transaction_id',t.id,'voucher_no',t.voucher_no)
    into v_tx from public.rr_account_transactions_v805 t
   where t.source_module='RCI_V9740' and t.source_record_id=h.id::text
     and t.data_mode=h.data_mode and t.status<>'REVERSED' limit 1;
  if v_tx is not null then return v_tx; end if;

  v_customer:=public.rr_accounts_ensure_buyer_ledger_v9754(h.buyer_id);
  select l.id into v_return from public.rr_ledgers_v805 l
   join public.rr_account_categories_v805 c on c.id=l.category_id
   where l.is_active and c.category_code='SALES_RETURN' order by l.created_at limit 1;
  if v_return is null then raise exception 'Sales Return ledger mapping required.'; end if;

  v_tx:=public.rr_accounts_post_v805('SALES_RETURN',h.total_amount,
    jsonb_build_array(
      jsonb_build_object('ledger_id',v_return,'dr',h.total_amount,'cr',0,'narration','Sales Return · '||h.rci_no),
      jsonb_build_object('ledger_id',v_customer,'dr',0,'cr',h.total_amount,'narration','Customer Return · '||h.rci_no)
    ),'RCI_V9740',h.id::text,v_customer,h.rci_no,coalesce(h.posted_at::date,current_date),
    'Posted RCI '||h.rci_no,h.data_mode);

  insert into public.rr_rci_accounts_link_v9754(rci_id,rci_no,buyer_id,customer_ledger_id,
    sales_return_ledger_id,total_amount,data_mode,status,account_transaction_id,account_voucher_no,message)
  values(h.id,h.rci_no,h.buyer_id,v_customer,v_return,h.total_amount,h.data_mode,'POSTED',
    (v_tx->>'transaction_id')::uuid,v_tx->>'voucher_no','RCI automatically posted to Accounts.')
  on conflict(rci_id) do update set status='POSTED',account_transaction_id=excluded.account_transaction_id,
    account_voucher_no=excluded.account_voucher_no,message=excluded.message,updated_at=now();
  return v_tx||jsonb_build_object('rci_id',h.id,'rci_no',h.rci_no);
end $function$;

create or replace function public.rr_rci_accounts_status_trg_v9754()
returns trigger language plpgsql security definer set search_path='public' as $function$
begin
  if new.status='POSTED' and (tg_op='INSERT' or old.status is distinct from new.status) then
    perform public.rr_accounts_post_rci_v9754(new.id);
  elsif new.status='REVERSED' and old.status is distinct from new.status then
    perform public.rr_accounts_reverse_source_mirror_v806('RCI_V9740',new.id::text,new.data_mode,
      coalesce(new.reversal_reason,'RCI reversed'));
    update public.rr_rci_accounts_link_v9754 set status='REVERSED',message='RCI reversed in Accounts',updated_at=now()
     where rci_id=new.id;
  end if;
  return new;
end $function$;
drop trigger if exists rr_rci_accounts_status_v9754 on public.rr_rci_v9740;
create trigger rr_rci_accounts_status_v9754 after insert or update of status on public.rr_rci_v9740
for each row execute function public.rr_rci_accounts_status_trg_v9754();

-- Never merge a distributor customer by mobile or name. Its partner_customer_id is identity.
create or replace function public.rr_customer_sales_map_sync_v9745(
  p_source_kind text,p_source_id uuid,p_name text,p_mobile text,p_active boolean default true
) returns uuid language plpgsql security definer set search_path='public' as $function$
declare v_kind text:=upper(trim(coalesce(p_source_kind,''))); v_name text:=trim(coalesce(p_name,''));
 v_mobile text:=right(regexp_replace(coalesce(p_mobile,''),'\D','','g'),10); v_buyer uuid; v_basis text;
begin
  if v_kind not in('REDZED_CUSTOMER','DISTRIBUTOR_CUSTOMER') or p_source_id is null or v_name='' then
    raise exception 'Canonical party source, id and name required.'; end if;
  if v_kind='REDZED_CUSTOMER' then
    select buyer_id into v_buyer from public.rr_customer_sales_map_v9745 where customer_id=p_source_id;
  else
    select buyer_id into v_buyer from public.rr_customer_sales_map_v9745 where partner_customer_id=p_source_id;
  end if;
  if v_buyer is not null then v_basis:='CUSTOMER_ID'; end if;

  if v_buyer is null and v_kind='REDZED_CUSTOMER' and length(v_mobile)=10 then
    select b.id into v_buyer from public.rr_buyers_v787 b
    where right(regexp_replace(coalesce(b.contact_no,''),'\D','','g'),10)=v_mobile
      and not exists(select 1 from public.rr_customer_sales_map_v9745 m
        where m.buyer_id=b.id and m.source_kind='DISTRIBUTOR_CUSTOMER')
    order by b.active desc nulls last,b.id limit 1;
    if v_buyer is not null then v_basis:='MOBILE'; end if;
  end if;
  if v_buyer is null and v_kind='REDZED_CUSTOMER' then
    select b.id into v_buyer from public.rr_buyers_v787 b where lower(trim(b.buyer_name))=lower(v_name)
      and not exists(select 1 from public.rr_customer_sales_map_v9745 m
        where m.buyer_id=b.id and m.source_kind='DISTRIBUTOR_CUSTOMER')
    order by b.active desc nulls last,b.id limit 1;
    if v_buyer is not null then v_basis:='EXACT_NAME'; end if;
  end if;
  if v_buyer is null then
    insert into public.rr_buyers_v787(buyer_name,contact_no,discount_type,discount_value,active)
    values(v_name,nullif(p_mobile,''),'PER_PIECE',0,coalesce(p_active,true)) returning id into v_buyer;
    v_basis:='CREATED';
  else update public.rr_buyers_v787 set buyer_name=v_name,contact_no=coalesce(nullif(p_mobile,''),contact_no),
    active=coalesce(p_active,true) where id=v_buyer; end if;
  if v_kind='REDZED_CUSTOMER' then
    insert into public.rr_customer_sales_map_v9745(source_kind,customer_id,buyer_id,canonical_name,canonical_mobile,match_basis,is_active)
    values(v_kind,p_source_id,v_buyer,v_name,nullif(v_mobile,''),v_basis,coalesce(p_active,true))
    on conflict(customer_id) where customer_id is not null do update set buyer_id=excluded.buyer_id,
      canonical_name=excluded.canonical_name,canonical_mobile=excluded.canonical_mobile,match_basis=excluded.match_basis,
      is_active=excluded.is_active,updated_at=now();
  else
    insert into public.rr_customer_sales_map_v9745(source_kind,partner_customer_id,buyer_id,canonical_name,canonical_mobile,match_basis,is_active)
    values(v_kind,p_source_id,v_buyer,v_name,nullif(v_mobile,''),v_basis,coalesce(p_active,true))
    on conflict(partner_customer_id) where partner_customer_id is not null do update set buyer_id=excluded.buyer_id,
      canonical_name=excluded.canonical_name,canonical_mobile=excluded.canonical_mobile,match_basis=excluded.match_basis,
      is_active=excluded.is_active,updated_at=now();
  end if;
  perform public.rr_accounts_ensure_buyer_ledger_v9754(v_buyer);
  return v_buyer;
end $function$;

-- Backfill canonical debtor ledgers, then retry only incomplete final CI links.
do $block$ declare x record; begin
  for x in select id from public.rr_buyers_v787 where active loop
    perform public.rr_accounts_ensure_buyer_ledger_v9754(x.id);
  end loop;
  for x in select p.id from public.rr_fg_pi_v787 p left join public.rr_cpi_accounts_link_v847 a on a.cpi_id=p.id
    where p.status='CI_FINAL' and coalesce(a.status,'') in('','PENDING_CUSTOMER_LEDGER','PENDING_SALES_LEDGER','ERROR') loop
    perform public.rr_accounts_post_cpi_v847(x.id);
  end loop;
  for x in select id from public.rr_rci_v9740 where status='POSTED' loop
    perform public.rr_accounts_post_rci_v9754(x.id);
  end loop;
end $block$;

revoke all on function public.rr_accounts_ensure_buyer_ledger_v9754(uuid),
 public.rr_accounts_post_rci_v9754(uuid),public.rr_rci_accounts_status_trg_v9754() from public,anon,authenticated;
grant execute on function public.rr_accounts_ensure_buyer_ledger_v9754(uuid),
 public.rr_accounts_post_rci_v9754(uuid) to service_role;
commit;
