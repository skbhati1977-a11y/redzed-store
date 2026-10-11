BEGIN;
SELECT set_config('request.jwt.claim.sub','af915a18-3823-48df-b039-1e4c7a88479b',true);
CREATE TEMP TABLE committee_branches(label text,result text) ON COMMIT DROP;
DO $proof$
DECLARE original uuid:='3b32ab0d-4e98-4c23-9e7b-7ee62a6036ff'; sid uuid;mid uuid;mode text;r jsonb;s jsonb;tx uuid;expected numeric;
BEGIN
 FOR mode IN SELECT unnest(ARRAY['BANK','CASH']) LOOP
  sid:=gen_random_uuid();
  INSERT INTO public.rr_committee_schemes_v820
  SELECT (jsonb_populate_record(NULL::public.rr_committee_schemes_v820,to_jsonb(x)||jsonb_build_object('id',sid,'scheme_code','ROLLBACK-'||sid,'scheme_name','TEST71 rollback-only committee'))).* FROM public.rr_committee_schemes_v820 x WHERE id=original;
  IF NOT FOUND THEN RAISE EXCEPTION 'Safe TEST committee fixture missing';END IF;
  INSERT INTO public.rr_committee_months_v820
  SELECT (jsonb_populate_record(NULL::public.rr_committee_months_v820,to_jsonb(x)||jsonb_build_object('id',gen_random_uuid(),'scheme_id',sid,'installment_status','PENDING','prize_status','NOT_APPLICABLE','installment_transaction_id',NULL,'prize_transaction_id',NULL,'our_payment_status','PENDING','our_paid_amount',0,'our_prize_received',0))).* FROM public.rr_committee_months_v820 x WHERE scheme_id=original;
  SELECT m.id,m.our_dividend_share INTO mid,expected FROM public.rr_committee_months_v820 m WHERE scheme_id=sid AND our_dividend_share>0 ORDER BY month_no LIMIT 1;
  r:=public.rr_committee_dividend_post_v827(mid);s:=public.rr_committee_dividend_post_v827(mid);tx:=(r->>'transaction_id')::uuid;
  IF tx IS NULL OR s->>'transaction_id'<>tx::text OR NOT (s->>'already_posted')::boolean THEN RAISE EXCEPTION 'Dividend retry not canonical';END IF;
  IF (SELECT count(*) FROM public.rr_account_transactions_v805 WHERE source_module='COMMITTEE_MEMBER_V827_DIVIDEND' AND source_record_id=mid::text AND status='POSTED')<>1 THEN RAISE EXCEPTION 'Dividend duplicate';END IF;
  IF (SELECT count(*) FROM public.rr_account_postings_v805 WHERE transaction_id=tx)<>2 OR (SELECT sum(dr_amount-cr_amount) FROM public.rr_account_postings_v805 WHERE transaction_id=tx)<>0 OR (SELECT sum(dr_amount) FROM public.rr_account_postings_v805 WHERE transaction_id=tx)<>expected THEN RAISE EXCEPTION 'Dividend journal amount/balance wrong';END IF;
  INSERT INTO committee_branches VALUES(mode||'_dividend_exactly_once_balanced','PASS');
  SELECT id INTO mid FROM public.rr_committee_months_v820 WHERE scheme_id=sid AND our_dividend_share=0 LIMIT 1;
  IF mid IS NULL THEN RAISE EXCEPTION 'Zero dividend fixture missing';END IF;
  r:=public.rr_committee_dividend_post_v827(mid);
  IF NOT (r->>'skipped')::boolean THEN RAISE EXCEPTION 'Zero dividend not skipped';END IF;
  INSERT INTO committee_branches VALUES(mode||'_zero_dividend_skipped','PASS');
  SELECT m.id,m.prize_amount INTO mid,expected FROM public.rr_committee_months_v820 m JOIN public.rr_committee_schemes_v820 x ON x.id=m.scheme_id WHERE m.scheme_id=sid AND m.month_no=x.our_win_month;
  r:=public.rr_committee_prize_receive_v826_6(sid,mode,current_date,'ROLLBACK');s:=public.rr_committee_prize_receive_v826_6(sid,mode,current_date,'ROLLBACK');tx:=(r->>'transaction_id')::uuid;
  IF tx IS NULL OR s->>'transaction_id'<>tx::text OR NOT (s->>'already_received')::boolean THEN RAISE EXCEPTION 'Prize retry not canonical';END IF;
  IF (SELECT count(*) FROM public.rr_account_transactions_v805 WHERE source_module='COMMITTEE_MEMBER_V826_PRIZE' AND source_record_id=mid::text AND status='POSTED')<>1 THEN RAISE EXCEPTION 'Prize duplicate';END IF;
  IF (SELECT count(*) FROM public.rr_account_postings_v805 WHERE transaction_id=tx)<>2 OR (SELECT sum(dr_amount-cr_amount) FROM public.rr_account_postings_v805 WHERE transaction_id=tx)<>0 OR (SELECT sum(dr_amount) FROM public.rr_account_postings_v805 WHERE transaction_id=tx)<>expected THEN RAISE EXCEPTION 'Prize journal amount/balance wrong';END IF;
  IF NOT EXISTS(SELECT 1 FROM public.rr_account_postings_v805 p JOIN public.rr_ledgers_v805 l ON l.id=p.ledger_id WHERE p.transaction_id=tx AND p.dr_amount=expected AND ((mode='CASH' AND l.ledger_code='CASH_MAIN') OR (mode='BANK' AND l.id=(SELECT bank_ledger_id FROM public.rr_committee_schemes_v820 WHERE id=sid)))) THEN RAISE EXCEPTION 'Prize receipt ledger wrong';END IF;
  INSERT INTO committee_branches VALUES(mode||'_prize_exactly_once_balanced','PASS');
 END LOOP;
END;$proof$;
SELECT * FROM committee_branches;
ROLLBACK;
