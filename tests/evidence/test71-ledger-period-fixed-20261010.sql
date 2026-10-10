BEGIN;SELECT set_config('request.jwt.claim.sub','af915a18-3823-48df-b039-1e4c7a88479b',true);
DO $t$ DECLARE party uuid;cash uuid;tx uuid;from_day date:=current_date;previous numeric;expected numeric;actual numeric;n int;
BEGIN
 SELECT id INTO party FROM rr_ledgers_v805 WHERE is_active AND ledger_kind='SUPPLIER' LIMIT 1;
 SELECT id INTO cash FROM rr_ledgers_v805 WHERE ledger_code='CASH_MAIN';
 tx:=(rr_accounts_post_payment_v805(party,cash,10,'PERIOD-PRIOR-AUDIT','rollback','TEST')->>'transaction_id')::uuid;
 UPDATE rr_account_postings_v805 SET created_at=(from_day-1)::timestamptz WHERE transaction_id=tx;
 tx:=(rr_accounts_post_payment_v805(party,cash,2,'PERIOD-CURRENT-AUDIT','rollback','TEST')->>'transaction_id')::uuid;
 SELECT coalesce(sum(dr_amount-cr_amount),0) INTO previous FROM rr_account_reporting_base_v806 WHERE ledger_id=party AND data_mode='TEST' AND created_at::date<from_day AND coalesce(transaction_status,'POSTED') NOT IN('VOIDED','CANCELLED');
 SELECT coalesce(sum(dr_amount-cr_amount),0)+previous INTO expected FROM rr_account_reporting_base_v806 WHERE ledger_id=party AND data_mode='TEST' AND created_at::date=from_day AND coalesce(transaction_status,'POSTED') NOT IN('VOIDED','CANCELLED');
 SELECT running_balance INTO actual FROM rr_ledger_statement_v806(party,from_day,from_day,'TEST') ORDER BY entry_date DESC,posting_id DESC LIMIT 1;
 -- Ordered current postings share the DB transaction timestamp; use the newly returned posting's row.
 SELECT s.running_balance INTO actual FROM rr_ledger_statement_v806(party,from_day,from_day,'TEST') s WHERE s.transaction_id=tx;
 IF actual<>expected THEN RAISE EXCEPTION 'v806 period balance % expected %',actual,expected;END IF;
 SELECT coalesce(sum(b.dr_amount-b.cr_amount),0) INTO expected FROM rr_account_reporting_base_v806 b WHERE b.ledger_id=party AND b.data_mode='TEST' AND b.created_at::date<=from_day AND coalesce(b.transaction_status,'POSTED') NOT IN('VOIDED','CANCELLED') AND NOT EXISTS(SELECT 1 FROM rr_account_book_hidden_pairs_v1 h WHERE h.original_transaction_id=b.transaction_id OR h.reversal_transaction_id=b.transaction_id);
 SELECT s.running_balance INTO actual FROM rr_ledger_statement_v807(party,from_day,from_day,'TEST') s WHERE s.transaction_id=tx;
 IF actual<>expected THEN RAISE EXCEPTION 'v807 period balance % expected %',actual,expected;END IF;
 PERFORM set_config('audit.ledger.period',jsonb_build_object('v806_prior_balance_included',true,'v807_prior_balance_included',true,'prior_balance',previous,'closing_balance',actual)::text,true);
END;$t$;
SELECT current_setting('audit.ledger.period')::jsonb result;ROLLBACK;
