CREATE FUNCTION rr_collection_rules_test71.archive_partner_cycle_history()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $guard$
BEGIN
 IF NEW.status='CLOSED' AND OLD.status='OPEN' THEN
  INSERT INTO rr_collection_rules_test71.chat_cleanup_audit(message_id,previous_row,reason)
   SELECT m.id,to_jsonb(m),'CLOSED_DISTRIBUTOR_COLLECTION_HISTORY' FROM public.rr_customer_chat_messages_v9433 m WHERE m.archived_at IS NULL
   AND m.payload->>'source' IN('PARTNER_MARKET_WINDOW','PARTNER_MARKET_REQUIREMENT','PARTNER_CUSTOMER_REQUIREMENT')
   AND (m.payload->>'partner_collection_root_id'=NEW.root_id::text OR EXISTS(SELECT 1 FROM public.rr_market_partner_order_v67 o JOIN public.rr_market_partner_collection_v67 pc ON pc.id=o.collection_id WHERE o.id::text=m.payload->>'partner_order_id' AND coalesce(pc.root_collection_id,pc.id)=NEW.root_id))
   ON CONFLICT(message_id) DO NOTHING;
  UPDATE public.rr_customer_chat_messages_v9433 m SET archived_at=now(),archive_reason='ONE_OPEN_COLLECTION_RULE_CLEANUP'
   WHERE m.archived_at IS NULL AND m.payload->>'source' IN('PARTNER_MARKET_WINDOW','PARTNER_MARKET_REQUIREMENT','PARTNER_CUSTOMER_REQUIREMENT')
   AND (m.payload->>'partner_collection_root_id'=NEW.root_id::text OR EXISTS(SELECT 1 FROM public.rr_market_partner_order_v67 o JOIN public.rr_market_partner_collection_v67 pc ON pc.id=o.collection_id WHERE o.id::text=m.payload->>'partner_order_id' AND coalesce(pc.root_collection_id,pc.id)=NEW.root_id));
 END IF;RETURN NEW;
END $guard$;
REVOKE ALL ON FUNCTION rr_collection_rules_test71.archive_partner_cycle_history() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER partner_cycle_history_on_close AFTER UPDATE OF status ON rr_collection_rules_test71.partner_cycles FOR EACH ROW EXECUTE FUNCTION rr_collection_rules_test71.archive_partner_cycle_history();

