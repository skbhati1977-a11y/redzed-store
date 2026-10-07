-- Clean collection/requirement chat cards into archived history; preserve all business rows.
CREATE TABLE rr_collection_rules_test71.chat_cleanup_audit(
 message_id uuid PRIMARY KEY,previous_row jsonb NOT NULL,reason text NOT NULL,cleaned_at timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON rr_collection_rules_test71.chat_cleanup_audit FROM PUBLIC,anon,authenticated;
ALTER TABLE rr_collection_rules_test71.chat_cleanup_audit ENABLE ROW LEVEL SECURITY;
CREATE POLICY no_direct_access ON rr_collection_rules_test71.chat_cleanup_audit AS RESTRICTIVE FOR ALL TO PUBLIC USING(false) WITH CHECK(false);
WITH bound AS(
 SELECT m.id,c.id cycle_id,c.status,c.closed_at,
 CASE WHEN m.message_type='REQUIREMENT' OR m.payload?'direct_requirement_root_id' THEN 'REQUIREMENT' ELSE 'COLLECTION' END kind,
 row_number() OVER(PARTITION BY m.chat_id,c.id,CASE WHEN m.message_type='REQUIREMENT' OR m.payload?'direct_requirement_root_id' THEN 'REQUIREMENT' ELSE 'COLLECTION' END ORDER BY m.created_at DESC,m.id DESC) rn
 FROM public.rr_customer_chat_messages_v9433 m JOIN public.rr_collection_cycle_v9586 c ON c.id::text=m.payload->>'direct_collection_cycle_id' AND c.chat_id=m.chat_id
 WHERE c.data_mode='TEST' AND m.archived_at IS NULL AND m.message_type IN('LINK','REQUIREMENT','ATTACHMENT')
 AND coalesce(m.payload->>'source','')<>'DIRECT_CATEGORY_REQUEST_TEST71'
)
INSERT INTO rr_collection_rules_test71.chat_cleanup_audit(message_id,previous_row,reason)
 SELECT m.id,to_jsonb(m),CASE WHEN b.closed_at IS NOT NULL OR b.status NOT IN('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED') THEN 'CLOSED_COLLECTION_HISTORY' ELSE 'OLDER_COLLECTION_REQUIREMENT_CARD' END
 FROM bound b JOIN public.rr_customer_chat_messages_v9433 m ON m.id=b.id
 WHERE b.closed_at IS NOT NULL OR b.status NOT IN('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED') OR b.rn>1;
UPDATE public.rr_customer_chat_messages_v9433 m SET archived_at=now(),archive_reason='ONE_OPEN_COLLECTION_RULE_CLEANUP',
 archive_meta=coalesce(m.archive_meta,'{}'::jsonb)||jsonb_build_object('cleanup_reason',a.reason,'history_preserved',true)
 FROM rr_collection_rules_test71.chat_cleanup_audit a WHERE m.id=a.message_id;

CREATE FUNCTION rr_collection_rules_test71.freeze_closed_requirement_lines()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $guard$
DECLARE rid uuid; c public.rr_collection_cycle_v9586%rowtype;
BEGIN
 rid:=CASE WHEN TG_OP='DELETE' THEN OLD.requirement_id ELSE NEW.requirement_id END;
 SELECT cy.* INTO c FROM public.rr_collection_cycle_v9586 cy JOIN public.rr_market_requirements_v9420 r
 ON r.collection_cycle_id=cy.id OR EXISTS(SELECT 1 FROM public.rr_collection_requirement_link_v9586 l WHERE l.requirement_id=r.id AND l.collection_cycle_id=cy.id)
 WHERE r.id=rid AND cy.data_mode='TEST' LIMIT 1 FOR UPDATE OF cy;
 IF c.id IS NOT NULL AND (c.closed_at IS NOT NULL OR c.status NOT IN('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED')) THEN
  RAISE EXCEPTION 'Closed collection requirement is frozen. Submit quantities under the new collection number.';
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $guard$;
REVOKE ALL ON FUNCTION rr_collection_rules_test71.freeze_closed_requirement_lines() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER test71_frozen_closed_requirement_lines BEFORE INSERT OR UPDATE OR DELETE
 ON public.rr_market_requirement_lines_v9420 FOR EACH ROW EXECUTE FUNCTION rr_collection_rules_test71.freeze_closed_requirement_lines();

