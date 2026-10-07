CREATE OR REPLACE FUNCTION rr_collection_rules_test71.enforce_terminal_and_number()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE previous_max integer;
BEGIN
 IF NEW.data_mode<>'TEST' THEN RETURN NEW; END IF;
 IF TG_OP='UPDATE' AND OLD.data_mode='TEST' AND (OLD.closed_at IS NOT NULL OR OLD.status IN('PI_GENERATED','CI_GENERATED','CLOSED','CLOSED_NO_RESPONSE','CANCELLED'))
  AND NEW.status IN('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED')
 THEN RAISE EXCEPTION 'Closed or PI collection cannot reopen. Send with a new collection number.'; END IF;
 IF NEW.status IN('PI_GENERATED','CI_GENERATED','CLOSED','CLOSED_NO_RESPONSE','CANCELLED') THEN
  NEW.closed_at:=coalesce(NEW.closed_at,CASE WHEN TG_OP='UPDATE' THEN OLD.closed_at END,now());
  NEW.close_reason:=coalesce(nullif(NEW.close_reason,''),CASE WHEN NEW.status IN('PI_GENERATED','CI_GENERATED') THEN 'REDZED TEAM PI MADE — COLLECTION CLOSED' ELSE 'COLLECTION CLOSED' END);
 ELSIF NEW.closed_at IS NOT NULL THEN RAISE EXCEPTION 'An open collection cannot have a closure timestamp.'; END IF;
 IF TG_OP='INSERT' AND NOT EXISTS(SELECT 1 FROM public.rr_collection_cycle_v9586 current_cycle WHERE current_cycle.customer_id=NEW.customer_id AND current_cycle.data_mode=NEW.data_mode AND current_cycle.closed_at IS NULL AND current_cycle.status IN('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED')) AND NEW.status IN('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED') THEN
  SELECT max(collection_no) INTO previous_max FROM public.rr_collection_cycle_v9586 WHERE customer_id=NEW.customer_id AND data_mode=NEW.data_mode;
  IF previous_max IS NOT NULL AND NEW.collection_no<=previous_max THEN RAISE EXCEPTION 'New collection number must be greater than previous collection %.',previous_max; END IF;
 END IF;
 RETURN NEW;
END $function$;
CREATE OR REPLACE FUNCTION rr_collection_rules_test71.freeze_closed_requirement_lines()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE rid uuid; c public.rr_collection_cycle_v9586%rowtype;
BEGIN
 rid:=CASE WHEN TG_OP='DELETE' THEN OLD.requirement_id ELSE NEW.requirement_id END;
 SELECT cy.* INTO c FROM public.rr_collection_cycle_v9586 cy JOIN public.rr_market_requirements_v9420 r
 ON r.collection_cycle_id=cy.id OR EXISTS(SELECT 1 FROM public.rr_collection_send_v9586 cs WHERE cs.share_id=r.share_id AND cs.collection_cycle_id=cy.id) OR EXISTS(SELECT 1 FROM public.rr_collection_requirement_link_v9586 l WHERE l.requirement_id=r.id AND l.collection_cycle_id=cy.id)
 WHERE r.id=rid AND cy.data_mode='TEST' LIMIT 1 FOR UPDATE OF cy;
 IF c.id IS NOT NULL AND (c.closed_at IS NOT NULL OR c.status NOT IN('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED')) THEN
  RAISE EXCEPTION 'Closed collection requirement is frozen. Submit quantities under the new collection number.';
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $function$;
CREATE OR REPLACE FUNCTION rr_collection_rules_test71.close_partner_cycle_on_order()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE root uuid;
BEGIN
 IF NEW.data_mode='TEST' AND (NEW.customer_closed_at IS NOT NULL OR NEW.status NOT IN('DRAFT','SUPERSEDED')
 OR NEW.distributor_pi_created_at IS NOT NULL OR NEW.pi_ref IS NOT NULL OR NEW.ci_ref IS NOT NULL) THEN
  SELECT coalesce(pc.root_collection_id,pc.id) INTO root FROM public.rr_market_partner_collection_v67 pc WHERE pc.id=NEW.collection_id;
  UPDATE rr_collection_rules_test71.partner_cycles SET status='CLOSED',closed_at=coalesce(closed_at,now()),close_reason='CUSTOMER CLOSE OR DISTRIBUTOR/REDZED PI CI MADE' WHERE root_id=root AND status='OPEN';
  INSERT INTO rr_collection_rules_test71.chat_cleanup_audit(message_id,previous_row,reason)
   SELECT m.id,to_jsonb(m),'CLOSED_DISTRIBUTOR_COLLECTION_HISTORY' FROM public.rr_customer_chat_messages_v9433 m WHERE m.archived_at IS NULL AND (m.payload->>'partner_collection_root_id'=root::text OR EXISTS(SELECT 1 FROM public.rr_market_partner_order_v67 o JOIN public.rr_market_partner_collection_v67 pc ON pc.id=o.collection_id WHERE o.id::text=m.payload->>'partner_order_id' AND coalesce(pc.root_collection_id,pc.id)=root)) AND m.payload->>'source' IN('PARTNER_MARKET_WINDOW','PARTNER_MARKET_REQUIREMENT','PARTNER_CUSTOMER_REQUIREMENT') ON CONFLICT(message_id) DO NOTHING;
  UPDATE public.rr_customer_chat_messages_v9433 SET archived_at=now(),archive_reason='ONE_OPEN_COLLECTION_RULE_CLEANUP' WHERE archived_at IS NULL AND (payload->>'partner_collection_root_id'=root::text OR payload->>'partner_order_id'=NEW.id::text) AND payload->>'source' IN('PARTNER_MARKET_WINDOW','PARTNER_MARKET_REQUIREMENT','PARTNER_CUSTOMER_REQUIREMENT');
 END IF;RETURN NEW;
END $function$;
CREATE OR REPLACE FUNCTION rr_collection_rules_test71.close_cycle_when_pi_made()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 IF NEW.data_mode='TEST' AND NEW.market_requirement_id IS NOT NULL THEN
  UPDATE public.rr_collection_cycle_v9586 c SET status='PI_GENERATED',closed_at=coalesce(c.closed_at,now()),
   close_reason=coalesce(nullif(c.close_reason,''),'REDZED TEAM PI MADE — COLLECTION CLOSED')
  WHERE c.data_mode='TEST' AND c.closed_at IS NULL AND c.status IN('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED')
   AND (EXISTS(SELECT 1 FROM public.rr_collection_requirement_link_v9586 l WHERE l.collection_cycle_id=c.id AND l.requirement_id=NEW.market_requirement_id)
    OR EXISTS(SELECT 1 FROM public.rr_market_requirements_v9420 r WHERE r.id=NEW.market_requirement_id AND r.collection_cycle_id=c.id));
  UPDATE rr_collection_rules_test71.partner_cycles g SET status='CLOSED',closed_at=coalesce(g.closed_at,now()),close_reason='REDZED PI CI MADE'
  WHERE g.status='OPEN' AND EXISTS(SELECT 1 FROM public.rr_market_partner_order_v67 o JOIN public.rr_market_partner_collection_v67 pc ON pc.id=o.collection_id WHERE o.linked_requirement_id=NEW.market_requirement_id AND coalesce(pc.root_collection_id,pc.id)=g.root_id);
 END IF;
 RETURN NEW;
END $function$;
DROP TRIGGER test71_close_collection_when_pi_made ON public.rr_fg_pi_v787;
CREATE TRIGGER test71_close_collection_when_pi_made AFTER INSERT OR UPDATE OF market_requirement_id,status ON public.rr_fg_pi_v787 FOR EACH ROW EXECUTE FUNCTION rr_collection_rules_test71.close_cycle_when_pi_made();

CREATE FUNCTION rr_collection_rules_test71.freeze_partner_requirement_qty()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $guard$
DECLARE oid uuid;
BEGIN
 IF TG_OP='UPDATE' AND OLD.order_id=NEW.order_id AND OLD.lot_no=NEW.lot_no AND OLD.requested_qty=NEW.requested_qty THEN RETURN NEW;END IF;
 oid:=CASE WHEN TG_OP='DELETE' THEN OLD.order_id ELSE NEW.order_id END;
 IF EXISTS(SELECT 1 FROM public.rr_market_partner_order_v67 o JOIN public.rr_market_partner_collection_v67 pc ON pc.id=o.collection_id JOIN rr_collection_rules_test71.partner_cycles g ON g.root_id=coalesce(pc.root_collection_id,pc.id) WHERE o.id=oid AND o.data_mode='TEST' AND (g.status<>'OPEN' OR o.status<>'DRAFT')) THEN RAISE EXCEPTION 'Closed distributor requirement quantity is frozen. Use a new collection number.';END IF;
 IF TG_OP='DELETE' THEN RETURN OLD;END IF;RETURN NEW;
END $guard$;
REVOKE ALL ON FUNCTION rr_collection_rules_test71.freeze_partner_requirement_qty() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER test71_freeze_partner_requirement_qty BEFORE INSERT OR UPDATE OF order_id,lot_no,requested_qty OR DELETE ON public.rr_market_partner_order_line_v67 FOR EACH ROW EXECUTE FUNCTION rr_collection_rules_test71.freeze_partner_requirement_qty();

INSERT INTO rr_collection_rules_test71.chat_cleanup_audit(message_id,previous_row,reason)
 SELECT m.id,to_jsonb(m),'CLOSED_DISTRIBUTOR_REQUIREMENT_HISTORY' FROM public.rr_customer_chat_messages_v9433 m JOIN public.rr_market_partner_order_v67 o ON o.id::text=m.payload->>'partner_order_id' JOIN public.rr_market_partner_collection_v67 pc ON pc.id=o.collection_id JOIN rr_collection_rules_test71.partner_cycles g ON g.root_id=coalesce(pc.root_collection_id,pc.id)
 WHERE g.status='CLOSED' AND m.archived_at IS NULL AND m.payload->>'source'='PARTNER_CUSTOMER_REQUIREMENT' ON CONFLICT(message_id) DO NOTHING;
UPDATE public.rr_customer_chat_messages_v9433 m SET archived_at=now(),archive_reason='ONE_OPEN_COLLECTION_RULE_CLEANUP'
 FROM rr_collection_rules_test71.chat_cleanup_audit a WHERE a.message_id=m.id AND a.reason='CLOSED_DISTRIBUTOR_REQUIREMENT_HISTORY';

