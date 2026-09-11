-- V9775: full voucher sharing, canonical PI drill-down and piece-aware ledgers.
create or replace function public.rr_accounts_piece_context_v9775(p_transaction_id uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  with tx as (
    select t.*,
      case when split_part(coalesce(t.source_record_id,''),':',1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        then split_part(t.source_record_id,':',1)::uuid end source_uuid
    from public.rr_account_transactions_v805 t where t.id=p_transaction_id
  ), ctx as (
    select tx.id,pi.id pi_id,pi.pi_no,pi.cpi_no,pi.market_requirement_id,
      case
        when upper(tx.transaction_type) in ('SALE','SALES') then coalesce((select sum(l.qty) from public.rr_fg_pi_lines_v787 l where l.pi_id=pi.id),0)
        when upper(tx.transaction_type)='SALES_RETURN' then -coalesce(r.total_qty,0)
        when upper(tx.transaction_type)='REVERSAL' and upper(coalesce(tx.source_module,'')) like 'RCI%REVERSAL%' then coalesce(r.total_qty,0)
        else 0 end::numeric piece_qty
    from tx
    left join public.rr_fg_pi_v787 pi on pi.id=tx.source_uuid
    left join public.rr_rci_v9740 r on r.id=tx.source_uuid
  )
  select jsonb_build_object('piece_qty',coalesce(piece_qty,0),'pi_id',pi_id,'pi_no',pi_no,'cpi_no',cpi_no,'requirement_id',market_requirement_id)
  from ctx
$$;

create or replace function public.rr_accounts_ledger_summary_v9775(
  p_scope text default 'ALL', p_search text default '', p_from_date date default date_trunc('month',current_date)::date,
  p_to_date date default current_date, p_data_mode text default 'TEST'
) returns table(ledger_id uuid, ledger_name text, opening_balance numeric, total_debit numeric, total_credit numeric, closing_balance numeric, total_pieces numeric)
language plpgsql security definer set search_path=public as $$
begin
  if not public.rr_acct_can_view_v805() then raise exception 'Accounts permission required.'; end if;
  return query
  with eligible as (
    select l.id,l.ledger_name,l.opening_balance,l.opening_side,l.ledger_kind,c.category_code,g.group_code
    from public.rr_ledgers_v805 l
    left join public.rr_account_categories_v805 c on c.id=l.category_id
    left join public.rr_account_groups_v805 g on g.id=c.group_id
    where l.is_active and (coalesce(trim(p_search),'')='' or l.ledger_name ilike '%'||trim(p_search)||'%' or l.ledger_code ilike '%'||trim(p_search)||'%')
      and case upper(coalesce(p_scope,'ALL')) when 'DEBTORS' then l.ledger_kind='CUSTOMER' when 'CREDITORS' then l.ledger_kind='SUPPLIER'
        when 'SALARY' then g.group_code='SALARY' or c.category_code ilike '%SALARY%' or c.category_code ilike '%WAGE%'
        when 'EXPENSE' then g.group_code in('EXPENSE','SALARY') when 'CASH_BANK' then l.ledger_kind in('CASH','BANK')
        when 'LOAN_ADVANCE' then l.ledger_kind='LOAN' or c.category_code ilike '%LOAN%' or c.category_code ilike '%ADVANCE%' else true end
  ), movement as (
    select e.id,coalesce(e.opening_balance,0)*(case when e.opening_side='CR' then -1 else 1 end)
        +coalesce(sum(case when t.transaction_datetime::date<p_from_date then p.dr_amount-p.cr_amount else 0 end),0) opening,
      coalesce(sum(case when t.transaction_datetime::date between p_from_date and p_to_date then p.dr_amount else 0 end),0) dr,
      coalesce(sum(case when t.transaction_datetime::date between p_from_date and p_to_date then p.cr_amount else 0 end),0) cr,
      coalesce(sum(case when t.transaction_datetime::date between p_from_date and p_to_date then (public.rr_accounts_piece_context_v9775(t.id)->>'piece_qty')::numeric else 0 end),0) pcs
    from eligible e left join public.rr_account_postings_v805 p on p.ledger_id=e.id
    left join public.rr_account_transactions_v805 t on t.id=p.transaction_id and t.data_mode=upper(coalesce(p_data_mode,'TEST')) and coalesce(t.status,'POSTED') not in('VOIDED','CANCELLED','REVERSED')
    group by e.id,e.opening_balance,e.opening_side
  )
  select e.id,e.ledger_name,round(m.opening,2),round(m.dr,2),round(m.cr,2),round(m.opening+m.dr-m.cr,2),round(m.pcs,2)
  from eligible e join movement m on m.id=e.id order by e.ledger_name;
end $$;

create or replace function public.rr_accounts_ledger_statement_v9775(p_ledger_id uuid,p_from_date date,p_to_date date,p_data_mode text default 'TEST')
returns table(entry_date date,particulars text,voucher_no text,voucher_type text,debit numeric,credit numeric,running_balance numeric,piece_qty numeric,pi_id uuid,pi_no text,cpi_no text,requirement_id uuid)
language plpgsql security definer set search_path=public as $$
declare v_open numeric;
begin
  if not public.rr_acct_can_view_v805() then raise exception 'Accounts permission required.'; end if;
  select coalesce(l.opening_balance,0)*(case when l.opening_side='CR' then -1 else 1 end)+coalesce(sum(case when t.transaction_datetime::date<p_from_date then p.dr_amount-p.cr_amount else 0 end),0)
  into v_open from public.rr_ledgers_v805 l left join public.rr_account_postings_v805 p on p.ledger_id=l.id
  left join public.rr_account_transactions_v805 t on t.id=p.transaction_id and t.data_mode=upper(coalesce(p_data_mode,'TEST')) and coalesce(t.status,'POSTED') not in('VOIDED','CANCELLED','REVERSED')
  where l.id=p_ledger_id group by l.opening_balance,l.opening_side;
  return query
  select t.transaction_datetime::date,coalesce(nullif(p.line_narration,''),nullif(t.narration,''),replace(initcap(t.transaction_type),'_',' ')),
    t.voucher_no,replace(initcap(t.transaction_type),'_',' '),round(p.dr_amount,2),round(p.cr_amount,2),
    round(coalesce(v_open,0)+sum(p.dr_amount-p.cr_amount) over(order by t.transaction_datetime,p.id rows unbounded preceding),2),
    (pc.j->>'piece_qty')::numeric,(pc.j->>'pi_id')::uuid,pc.j->>'pi_no',pc.j->>'cpi_no',(pc.j->>'requirement_id')::uuid
  from public.rr_account_postings_v805 p join public.rr_account_transactions_v805 t on t.id=p.transaction_id
  cross join lateral (select public.rr_accounts_piece_context_v9775(t.id) j) pc
  where p.ledger_id=p_ledger_id and t.data_mode=upper(coalesce(p_data_mode,'TEST')) and t.transaction_datetime::date between p_from_date and p_to_date
    and coalesce(t.status,'POSTED') not in('VOIDED','CANCELLED','REVERSED') order by t.transaction_datetime,p.id;
end $$;

create or replace function public.rr_accounts_voucher_detail_v9775(p_voucher_no text,p_data_mode text default 'TEST')
returns table(transaction_id uuid,voucher_no text,entry_date date,voucher_type text,particulars text,ledger_name text,debit numeric,credit numeric,status text,voucher_piece_qty numeric,pi_id uuid,pi_no text,cpi_no text,requirement_id uuid,source_module text,source_record_id text)
language plpgsql security definer set search_path=public as $$
begin
  if not public.rr_acct_can_view_v805() then raise exception 'Accounts permission required.'; end if;
  return query select t.id,t.voucher_no,t.transaction_datetime::date,replace(initcap(t.transaction_type),'_',' '),
    coalesce(nullif(p.line_narration,''),nullif(t.narration,''),'—'),l.ledger_name,round(p.dr_amount,2),round(p.cr_amount,2),t.status,
    (pc.j->>'piece_qty')::numeric,(pc.j->>'pi_id')::uuid,pc.j->>'pi_no',pc.j->>'cpi_no',(pc.j->>'requirement_id')::uuid,t.source_module,t.source_record_id
  from public.rr_account_transactions_v805 t join public.rr_account_postings_v805 p on p.transaction_id=t.id join public.rr_ledgers_v805 l on l.id=p.ledger_id
  cross join lateral (select public.rr_accounts_piece_context_v9775(t.id) j) pc
  where (t.voucher_no=trim(p_voucher_no) or t.bill_no=trim(p_voucher_no)) and t.data_mode=upper(coalesce(p_data_mode,'TEST')) order by p.created_at,p.id;
end $$;

create or replace function public.rr_pi_editor_by_id_v9775(p_pi_id uuid,p_data_mode text default 'TEST')
returns jsonb language plpgsql security definer set search_path=public as $$
declare v jsonb;
begin
  if not public.rr_acct_can_view_v805() then raise exception 'Authorized PI view required.'; end if;
  select jsonb_build_object(
    'pi_id',p.id,'pi_no',p.pi_no,'ci_no',p.cpi_no,'pi_status',p.status,'requirement_id',p.market_requirement_id,
    'customer_name',coalesce(p.buyer_snapshot->>'customer_name',p.buyer_snapshot->>'buyer_name',p.buyer_snapshot->>'name','Customer'),
    'dispatch_details',p.dispatch_details,'value_added_pct',p.value_added_pct,'freight_amount',p.freight_amount,'packing_other',p.packing_other,
    'lines',coalesce((select jsonb_agg(jsonb_build_object('lot_no',l.lot_no,'qty',l.qty,'stock_type',l.stock_type,'rate',coalesce(l.original_rate,l.final_rate),'discount',coalesce(l.party_discount_per_piece,l.discount_amount,0),'category',l.short_item_name,'size','') order by l.serial_no,l.id) from public.rr_fg_pi_lines_v787 l where l.pi_id=p.id),'[]'::jsonb)
  ) into v from public.rr_fg_pi_v787 p where p.id=p_pi_id and p.data_mode=upper(coalesce(p_data_mode,'TEST'));
  if v is null then raise exception 'PI not found.'; end if;
  return v;
end $$;

revoke all on function public.rr_accounts_piece_context_v9775(uuid),public.rr_accounts_ledger_summary_v9775(text,text,date,date,text),public.rr_accounts_ledger_statement_v9775(uuid,date,date,text),public.rr_accounts_voucher_detail_v9775(text,text),public.rr_pi_editor_by_id_v9775(uuid,text) from public,anon;
grant execute on function public.rr_accounts_piece_context_v9775(uuid) to service_role;
grant execute on function public.rr_accounts_ledger_summary_v9775(text,text,date,date,text),public.rr_accounts_ledger_statement_v9775(uuid,date,date,text),public.rr_accounts_voucher_detail_v9775(text,text),public.rr_pi_editor_by_id_v9775(uuid,text) to authenticated,service_role;
