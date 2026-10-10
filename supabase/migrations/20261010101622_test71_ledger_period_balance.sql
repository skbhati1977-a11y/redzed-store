BEGIN;
CREATE OR REPLACE FUNCTION public.rr_ledger_statement_v806(p_ledger_id uuid, p_from_date date, p_to_date date, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS TABLE(posting_id uuid, transaction_id uuid, entry_date date, voucher_no text, transaction_type text, source_module text, debit numeric, credit numeric, running_balance numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
BEGIN
 PERFORM public.rr_accounts_report_access_assert_test71();
 IF p_from_date IS NULL OR p_to_date IS NULL OR p_to_date<p_from_date THEN RAISE EXCEPTION 'Valid ledger date range required.';END IF;
 RETURN QUERY select
    b.posting_id,
    b.transaction_id,
    b.created_at::date,
    b.voucher_no,
    b.transaction_type,
    b.source_module,
    round(coalesce(b.dr_amount,0),2),
    round(coalesce(b.cr_amount,0),2),

    round(
      coalesce((SELECT sum(coalesce(prior.dr_amount,0)-coalesce(prior.cr_amount,0)) FROM public.rr_account_reporting_base_v806 prior WHERE prior.ledger_id=p_ledger_id AND prior.data_mode=upper(coalesce(p_data_mode,'TEST')) AND prior.created_at::date<p_from_date AND coalesce(prior.transaction_status,'POSTED') NOT IN('VOIDED','CANCELLED')),0) + sum(
        coalesce(b.dr_amount,0)-coalesce(b.cr_amount,0)
      )
      over(
        order by b.created_at,b.posting_id
        rows between unbounded preceding and current row
      ),
      2
    ) as running_balance

  from public.rr_account_reporting_base_v806 b

  where b.ledger_id=p_ledger_id
    and b.data_mode=upper(coalesce(p_data_mode,'TEST'))
    and b.created_at::date between p_from_date and p_to_date
    and coalesce(b.transaction_status,'POSTED') not in('VOIDED','CANCELLED')

  order by b.created_at,b.posting_id;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.rr_ledger_statement_v807(p_ledger_id uuid, p_from_date date, p_to_date date, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS TABLE(posting_id uuid, transaction_id uuid, entry_date date, voucher_no text, transaction_type text, source_module text, debit numeric, credit numeric, running_balance numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
BEGIN
 PERFORM public.rr_accounts_report_access_assert_test71();
 IF p_from_date IS NULL OR p_to_date IS NULL OR p_to_date<p_from_date THEN RAISE EXCEPTION 'Valid ledger date range required.';END IF;
 RETURN QUERY with x as(
 select b.* from rr_account_reporting_base_v806 b where b.ledger_id=p_ledger_id and b.data_mode=upper(coalesce(p_data_mode,'TEST')) and b.created_at::date between p_from_date and p_to_date and coalesce(b.transaction_status,'POSTED') not in('VOIDED','CANCELLED')
 and not exists(select 1 from rr_account_book_hidden_pairs_v1 h where h.original_transaction_id=b.transaction_id or h.reversal_transaction_id=b.transaction_id))
 select x.posting_id,x.transaction_id,x.created_at::date,x.voucher_no,x.transaction_type,x.source_module,round(coalesce(x.dr_amount,0),2),round(coalesce(x.cr_amount,0),2),round(coalesce((SELECT sum(coalesce(prior.dr_amount,0)-coalesce(prior.cr_amount,0)) FROM public.rr_account_reporting_base_v806 prior WHERE prior.ledger_id=p_ledger_id AND prior.data_mode=upper(coalesce(p_data_mode,'TEST')) AND prior.created_at::date<p_from_date AND coalesce(prior.transaction_status,'POSTED') NOT IN('VOIDED','CANCELLED') AND NOT EXISTS(SELECT 1 FROM public.rr_account_book_hidden_pairs_v1 h WHERE h.original_transaction_id=prior.transaction_id OR h.reversal_transaction_id=prior.transaction_id)),0) + sum(coalesce(x.dr_amount,0)-coalesce(x.cr_amount,0)) over(order by x.created_at,x.posting_id rows between unbounded preceding and current row),2) from x order by x.created_at,x.posting_id;
END;
$function$
;
COMMIT;

