CREATE TABLE rr_collection_rules_test71.wiring_cleanup_audit(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),row_kind text NOT NULL,row_id uuid NOT NULL,previous_row jsonb NOT NULL,reason text NOT NULL,cleaned_at timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON rr_collection_rules_test71.wiring_cleanup_audit FROM PUBLIC,anon,authenticated;
ALTER TABLE rr_collection_rules_test71.wiring_cleanup_audit ENABLE ROW LEVEL SECURITY;
CREATE POLICY no_direct_access ON rr_collection_rules_test71.wiring_cleanup_audit AS RESTRICTIVE FOR ALL TO PUBLIC USING(false) WITH CHECK(false);
-- Canonical direct share customer follows its uniquely bound cycle and chat.
INSERT INTO rr_collection_rules_test71.wiring_cleanup_audit(row_kind,row_id,previous_row,reason)
 SELECT 'DIRECT_SHARE',s.id,to_jsonb(s),'CANONICAL_CYCLE_CUSTOMER_IDENTITY_REPAIR' FROM public.rr_market_share_v9420 s JOIN public.rr_collection_send_v9586 cs ON cs.share_id=s.id JOIN public.rr_collection_cycle_v9586 c ON c.id=cs.collection_cycle_id
 WHERE c.data_mode='TEST' AND s.customer_id IS DISTINCT FROM c.customer_id AND s.origin_chat_id=c.chat_id AND s.origin_collection_cycle_id=c.id
 AND NOT EXISTS(SELECT 1 FROM public.rr_market_partner_collection_v67 pc WHERE pc.share_id=s.id)
 AND (SELECT count(*) FROM public.rr_collection_send_v9586 x WHERE x.share_id=s.id)=1;
UPDATE public.rr_customer_session_v9590 sess SET revoked_at=now()
 WHERE sess.revoked_at IS NULL AND EXISTS(SELECT 1 FROM rr_collection_rules_test71.wiring_cleanup_audit a WHERE a.row_kind='DIRECT_SHARE' AND a.row_id=sess.share_id);
UPDATE public.rr_market_share_v9420 s SET customer_id=c.customer_id,customer_name=ch.customer_name,
 origin_owner_customer_id=c.customer_id,origin_partner_customer_id=NULL
 FROM public.rr_collection_send_v9586 cs JOIN public.rr_collection_cycle_v9586 c ON c.id=cs.collection_cycle_id JOIN public.rr_customer_chat_v9433 ch ON ch.id=c.chat_id
 WHERE cs.share_id=s.id AND EXISTS(SELECT 1 FROM rr_collection_rules_test71.wiring_cleanup_audit a WHERE a.row_kind='DIRECT_SHARE' AND a.row_id=s.id);

-- Distributor private shares must never be adopted into their owner's direct REDZED cycle.
INSERT INTO rr_collection_rules_test71.wiring_cleanup_audit(row_kind,row_id,previous_row,reason)
 SELECT 'MISROUTED_SEND',cs.id,to_jsonb(cs),'DISTRIBUTOR_PRIVATE_SHARE_REMOVED_FROM_DIRECT_CYCLE'
 FROM public.rr_collection_send_v9586 cs JOIN public.rr_collection_cycle_v9586 c ON c.id=cs.collection_cycle_id
 JOIN public.rr_market_partner_collection_v67 pc ON pc.share_id=cs.share_id JOIN public.rr_market_share_v9420 s ON s.id=pc.share_id
 WHERE c.data_mode='TEST' AND s.data_mode='TEST' AND c.customer_id=pc.owner_customer_id;
INSERT INTO rr_collection_rules_test71.wiring_cleanup_audit(row_kind,row_id,previous_row,reason)
 SELECT 'PARTNER_SHARE',s.id,to_jsonb(s),'RESTORE_PRIVATE_DISTRIBUTOR_AUTHORITY'
 FROM public.rr_market_share_v9420 s WHERE EXISTS(SELECT 1 FROM rr_collection_rules_test71.wiring_cleanup_audit a WHERE a.row_kind='MISROUTED_SEND' AND a.previous_row->>'share_id'=s.id::text);
DELETE FROM public.rr_collection_send_v9586 cs USING rr_collection_rules_test71.wiring_cleanup_audit a WHERE a.row_kind='MISROUTED_SEND' AND a.row_id=cs.id;
UPDATE public.rr_market_share_v9420 s SET origin_chat_id=NULL,origin_collection_cycle_id=NULL,origin_relation_kind=NULL,
 origin_owner_customer_id=pc.owner_customer_id,origin_partner_customer_id=pc.partner_customer_id
 FROM public.rr_market_partner_collection_v67 pc WHERE pc.share_id=s.id AND EXISTS(SELECT 1 FROM rr_collection_rules_test71.wiring_cleanup_audit a WHERE a.row_kind='PARTNER_SHARE' AND a.row_id=s.id);

