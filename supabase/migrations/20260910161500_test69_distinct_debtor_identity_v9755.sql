-- V9755: every canonical customer/buyer gets a distinct ID-linked debtor ledger.
-- Same display names are allowed; buyer UUID remains the identity.
begin;
create or replace function public.rr_accounts_ensure_buyer_ledger_v9754(p_buyer_id uuid)
returns uuid language plpgsql security definer set search_path='public' as $function$
declare b public.rr_buyers_v787%rowtype; v_category uuid; v_ledger uuid;
 v_source text; v_name text; v_type text; v_code text; v_norm text;
begin
  select * into b from public.rr_buyers_v787 where id=p_buyer_id;
  if b.id is null then raise exception 'Canonical buyer not found.'; end if;
  select source_kind into v_source from public.rr_customer_sales_map_v9745
   where buyer_id=b.id and is_active order by updated_at desc limit 1;
  v_type:=case when v_source='DISTRIBUTOR_CUSTOMER' then 'DISTRIBUTOR_CUSTOMER' else 'CUSTOMER' end;
  v_name:=case when v_type='DISTRIBUTOR_CUSTOMER' then
    'Distributor Customer · '||upper(substr(replace(b.id::text,'-',''),1,8)) else b.buyer_name end;
  v_code:='CUST-'||upper(substr(replace(b.id::text,'-',''),1,12));
  select id into v_ledger from public.rr_ledgers_v805 where is_active and linked_entity_id=b.id::text
   and upper(coalesce(linked_entity_type,'')) in('BUYER','CUSTOMER','DISTRIBUTOR_CUSTOMER') limit 1;
  if v_ledger is not null then return v_ledger; end if;

  v_norm:=public.rr_name_normalize_v805(v_name);
  if v_type='CUSTOMER' then
    select id into v_ledger from public.rr_ledgers_v805 where is_active and normalized_name=v_norm
      and nullif(trim(coalesce(linked_entity_id,'')),'') is null limit 1;
    if v_ledger is not null then
      update public.rr_ledgers_v805 set linked_entity_type='CUSTOMER',linked_entity_id=b.id::text,
        mobile=b.contact_no,opening_balance=0,opening_side='DR',updated_at=now() where id=v_ledger;
      return v_ledger;
    end if;
  end if;
  if exists(select 1 from public.rr_ledgers_v805 where normalized_name=v_norm) then
    v_name:=v_name||' · '||upper(substr(replace(b.id::text,'-',''),1,8));
    v_norm:=public.rr_name_normalize_v805(v_name);
  end if;
  select id into v_category from public.rr_account_categories_v805
   where category_code='CUSTOMER_RECEIVABLE' and is_active limit 1;
  if v_category is null then raise exception 'Customer Receivable category missing.'; end if;
  insert into public.rr_ledgers_v805(ledger_code,ledger_name,normalized_name,category_id,ledger_kind,
    linked_entity_type,linked_entity_id,mobile,opening_balance,opening_side,is_active)
  values(v_code,v_name,v_norm,v_category,'CUSTOMER',v_type,b.id::text,
    case when v_type='DISTRIBUTOR_CUSTOMER' then null else b.contact_no end,0,'DR',true)
  returning id into v_ledger;
  return v_ledger;
end $function$;

do $block$ declare x record; begin
 for x in select distinct buyer_id id from public.rr_customer_sales_map_v9745 where is_active loop
  perform public.rr_accounts_ensure_buyer_ledger_v9754(x.id);
 end loop;
end $block$;
commit;
