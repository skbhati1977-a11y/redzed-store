BEGIN;
DO $test$
DECLARE c public.rr_market_partner_customer_v67%rowtype;before_bills jsonb;after_bills jsonb;new_discount numeric;
BEGIN
SELECT * INTO c FROM public.rr_market_partner_customer_v67 WHERE data_mode='TEST' AND status='ACTIVE' LIMIT 1;
IF c.id IS NULL THEN RAISE EXCEPTION 'Distributor fixture missing';END IF;
SELECT jsonb_build_object('headers',(SELECT jsonb_agg(to_jsonb(p) ORDER BY to_jsonb(p)::text) FROM public.rr_market_partner_customer_ci_v67 p),'lines',(SELECT jsonb_agg(to_jsonb(p) ORDER BY to_jsonb(p)::text) FROM public.rr_market_partner_customer_ci_line_v67 p),'collection_lines',(SELECT jsonb_agg(to_jsonb(p) ORDER BY to_jsonb(p)::text) FROM public.rr_market_partner_collection_line_v67 p)) INTO before_bills;
new_discount:=coalesce(c.default_discount_amount,0)+0.01;
UPDATE public.rr_market_partner_customer_v67 SET default_discount_amount=new_discount WHERE id=c.id;
IF NOT EXISTS(SELECT 1 FROM rr_customer_auth_test71.partner_discount_history h WHERE h.partner_customer_id=c.id AND h.discount_per_piece=new_discount AND h.effective_from>=transaction_timestamp()) THEN RAISE EXCEPTION 'Distributor discount effective time missing';END IF;
SELECT jsonb_build_object('headers',(SELECT jsonb_agg(to_jsonb(p) ORDER BY to_jsonb(p)::text) FROM public.rr_market_partner_customer_ci_v67 p),'lines',(SELECT jsonb_agg(to_jsonb(p) ORDER BY to_jsonb(p)::text) FROM public.rr_market_partner_customer_ci_line_v67 p),'collection_lines',(SELECT jsonb_agg(to_jsonb(p) ORDER BY to_jsonb(p)::text) FROM public.rr_market_partner_collection_line_v67 p)) INTO after_bills;
IF before_bills IS DISTINCT FROM after_bills THEN RAISE EXCEPTION 'Distributor edit changed previous pricing snapshots';END IF;
END $test$;
ROLLBACK;
