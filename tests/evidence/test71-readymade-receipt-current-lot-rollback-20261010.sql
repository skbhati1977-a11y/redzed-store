-- Audit adaptation: current continuous lot suggestion; business assertions unchanged.
-- Run after scripts/test71-readymade-receipt-reconciliation.sql.
-- All business fixtures roll back; the schema migration is separate.
begin;
select set_config('request.jwt.claim.sub',(select auth_user_id::text from public.rr_user_profiles where is_active and lower(role_code)='owner' limit 1),true);
do $test$
declare received integer;pid uuid;sid uuid;ln jsonb;j jsonb;r jsonb;l record;note_record record;
lot text;bill text;supplier text;expected numeric;net numeric;n integer;
before_pl jsonb;after_pl jsonb;before_bs jsonb;after_bs jsonb;before_tb numeric;after_tb numeric;party uuid;
begin
 select supplier_name into supplier from public.rr_suppliers where is_active order by supplier_name limit 1;
 if supplier is null then raise exception 'Fixture needs an existing supplier';end if;
 foreach received in array array[530,550,540] loop
  lot:=public.rr_rm_lot_hint_test71()->>'suggested_lot';bill:=lot;
  ln:=jsonb_build_array(jsonb_build_object('lot_no',lot,'item_name','Receipt Audit','category','Polo','size_text','L, XL, XXL','colours_text','Red','cloth_name','Cotton','art_no','RA40','bill_qty',540,'qty',received,'purchase_rate',100,'final_image_url','https://example.com/receipt.jpg'));
  j:=public.rr_rm_chat_save_test71(null,supplier,bill,current_date,ln,false);pid:=(j->>'purchase_id')::uuid;
  r:=public.rr_rm_receipt_summary_test71(pid);
  if (r->'lines'->0->>'bill_qty')::numeric<>540 or (r->'lines'->0->>'received_qty')::numeric<>received then raise exception 'Draft receipt lost quantities';end if;
  if exists(select 1 from public.rr_account_transactions_v805 where source_record_id=pid::text) then raise exception 'Draft posted to Accounts';end if;
  if exists(select 1 from public.rr_rm_stock_v849_2c6 where source_purchase_id=pid) then raise exception 'Draft posted stock';end if;
  before_pl:=public.rr_profit_loss_v806(current_date,current_date,'TEST');before_bs:=public.rr_balance_sheet_v806(current_date,'TEST');
  party:=public.rr_supplier_ledger_resolve_v806(supplier);
  select coalesce(sum(total_credit-total_debit),0) into before_tb from public.rr_trial_balance_v806(current_date,current_date,'TEST') where ledger_id=party;
  j:=public.rr_rm_chat_save_test71(pid,supplier,bill,current_date,ln,true);
  r:=j->'receipt';expected:=received*100;
  if (r->>'bill_value')::numeric<>54000 or (r->>'received_value')::numeric<>expected then raise exception 'Gross/net receipt values';end if;
  select * into l from public.rr_rm_purchase_lines_v849_2c6 where purchase_id=pid;
  select stock_id into sid from public.rr_rm_stock_v849_2c6 where source_purchase_id=pid;
  if (select qty_received from public.rr_rm_stock_v849_2c6 where stock_id=sid)<>received or
     (select sum(qty_delta) from public.rr_fg_stock_ledger_v787 where ref_type='RM_STOCK' and ref_id=sid)<>received then raise exception 'Received stock mismatch';end if;
  if public.rr_rm_stock_receipt_test71(sid)<>r then raise exception 'Receipt history mismatch';end if;
  if received=540 then
   if l.receipt_note_transaction_id_test71 is not null then raise exception 'Matched quantity generated note';end if;
  else
   select * into note_record from public.rr_account_transactions_v805 where id=l.receipt_note_transaction_id_test71;
   if note_record.total_amount<>1000 or note_record.transaction_type<>(case when received<540 then 'PURCHASE_DEBIT_NOTE' else 'PURCHASE_CREDIT_NOTE' end) or note_record.bill_no<>bill then raise exception 'Note type/amount/bill link mismatch';end if;
   if (select sum(dr_amount)-sum(cr_amount) from public.rr_account_postings_v805 where transaction_id=note_record.id)<>0 then raise exception 'Unbalanced receipt note';end if;
  end if;
  select sum(p.cr_amount-p.dr_amount) into net from public.rr_account_postings_v805 p join public.rr_account_transactions_v805 t on t.id=p.transaction_id
  where t.bill_no=bill and t.data_mode='TEST' and p.ledger_id=(select supplier_ledger_id_test71 from public.rr_rm_purchase_header_v849_2c6 where purchase_id=pid);
  if net<>expected then raise exception 'Supplier payable mismatch';end if;
  after_pl:=public.rr_profit_loss_v806(current_date,current_date,'TEST');after_bs:=public.rr_balance_sheet_v806(current_date,'TEST');
  if (after_pl->>'net_purchase')::numeric-(before_pl->>'net_purchase')::numeric<>expected or
     (after_pl->>'net_profit_loss')::numeric-(before_pl->>'net_profit_loss')::numeric<>-expected then raise exception 'P&L delta mismatch';end if;
  if (after_bs->>'liabilities')::numeric-(before_bs->>'liabilities')::numeric<>expected or
     (after_bs->>'difference')::numeric<>(before_bs->>'difference')::numeric then raise exception 'Balance Sheet delta mismatch';end if;
  select coalesce(sum(total_credit-total_debit),0) into after_tb from public.rr_trial_balance_v806(current_date,current_date,'TEST') where ledger_id=party;
  if after_tb-before_tb<>expected then raise exception 'Trial Balance supplier delta mismatch';end if;
  -- Compare raw journal totals; the trial balance intentionally omits settled ledgers.
  if exists(select 1 from public.rr_account_transactions_v805 t join public.rr_account_postings_v805 p on p.transaction_id=t.id where t.bill_no=bill and t.data_mode='TEST' group by t.id having sum(p.dr_amount)<>sum(p.cr_amount)) then raise exception 'Trial/journal imbalance';end if;
  perform public.rr_rm_chat_save_test71(pid,supplier,bill,current_date,ln,true);
  perform public.rr_rm_finish_purchase_test71(pid);
  if (select count(*) from public.rr_account_transactions_v805 where bill_no=bill and data_mode='TEST')<>(case when received=540 then 1 else 2 end) then raise exception 'Retry duplicated Accounts';end if;
  if (select count(*) from public.rr_fg_stock_ledger_v787 where ref_type='RM_STOCK' and ref_id=sid)<>1 then raise exception 'Retry duplicated stock';end if;
  perform public.rr_rm_purchase_return_test71(sid,2,'Receipt audit return',current_date,null,lot||'-RETURN');
  if (select available_qty from public.rr_rm_stock_v849_2c6 where stock_id=sid)<>received-2 then raise exception 'Return used bill qty instead of received stock';end if;
 end loop;
 -- Editing an OPEN draft recalculates without creating stale notes.
 lot:=public.rr_rm_lot_hint_test71()->>'suggested_lot';
 ln:=jsonb_build_array(jsonb_build_object('lot_no',lot,'item_name','Edit Audit','category','Polo','size_text','L, XL, XXL','bill_qty',540,'qty',530,'purchase_rate',100,'final_image_url','https://example.com/receipt.jpg'));
 j:=public.rr_rm_chat_save_test71(null,supplier,lot,current_date,ln,false);pid:=(j->>'purchase_id')::uuid;
 ln:=jsonb_set(ln,'{0,qty}','550'::jsonb);
 j:=public.rr_rm_chat_save_test71(pid,supplier,lot,current_date,ln,true);
 if j->'receipt'->'lines'->0->>'note_type'<>'CREDIT_NOTE' then raise exception 'Edited draft retained old shortage';end if;
 -- Invalid fractional bill PCS fails atomically.
 lot:=public.rr_rm_lot_hint_test71()->>'suggested_lot';n:=0;
 ln:=jsonb_set(jsonb_set(ln,'{0,lot_no}',to_jsonb(lot)),'{0,bill_qty}','540.5'::jsonb);
 begin perform public.rr_rm_chat_save_test71(null,supplier,lot,current_date,ln,true);
 exception when others then n:=1;end;
 if n<>1 or exists(select 1 from public.rr_rm_purchase_header_v849_2c6 where bill_no_test71=lot) then raise exception 'Invalid bill quantity left partial purchase';end if;
 if has_function_privilege('anon','public.rr_rm_receipt_summary_test71(uuid)','execute') or has_function_privilege('anon','public.rr_rm_stock_receipt_test71(uuid)','execute') then raise exception 'Anonymous receipt access';end if;
 perform set_config('rm.receipt.audit','PASS: Short/Excess/Matched; draft edit; stock; original bill; notes; supplier; P&L; Balance Sheet; Trial Balance; balanced journals; retry; purchase return; invalid input rollback; anon denied',true);
end $test$;
select current_setting('rm.receipt.audit') as receipt_result;
rollback;
