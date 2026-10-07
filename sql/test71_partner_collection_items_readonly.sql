CREATE OR REPLACE FUNCTION rr_collection_rules_test71.freeze_partner_collection_items() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE cid uuid;root uuid;
BEGIN
 cid:=CASE WHEN TG_OP='DELETE' THEN OLD.collection_id ELSE NEW.collection_id END;
 SELECT coalesce(pc.root_collection_id,pc.id) INTO root FROM public.rr_market_partner_collection_v67 pc WHERE pc.id=cid;
 PERFORM 1 FROM rr_collection_rules_test71.partner_cycles WHERE root_id=root FOR UPDATE;
 IF EXISTS(SELECT 1 FROM rr_collection_rules_test71.partner_cycles WHERE root_id=root AND status='CLOSED') THEN RAISE EXCEPTION 'Closed distributor collection items are view only';END IF;
 IF TG_OP='UPDATE' AND NEW.collection_id IS DISTINCT FROM OLD.collection_id AND EXISTS(SELECT 1 FROM public.rr_market_partner_collection_v67 pc JOIN rr_collection_rules_test71.partner_cycles g ON g.root_id=coalesce(pc.root_collection_id,pc.id) WHERE pc.id=OLD.collection_id AND g.status='CLOSED') THEN RAISE EXCEPTION 'Closed distributor collection items are view only';END IF;
 IF TG_OP='DELETE' THEN RETURN OLD;END IF;RETURN NEW;
END $fn$;
REVOKE ALL ON FUNCTION rr_collection_rules_test71.freeze_partner_collection_items() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER test71_freeze_closed_partner_collection_items BEFORE INSERT OR UPDATE OR DELETE ON public.rr_market_partner_collection_line_v67 FOR EACH ROW EXECUTE FUNCTION rr_collection_rules_test71.freeze_partner_collection_items();
