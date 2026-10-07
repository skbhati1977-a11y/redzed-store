CREATE FUNCTION rr_collection_rules_test71.archive_cycle_chat_on_close()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $guard$
BEGIN
 IF NEW.data_mode='TEST' AND (NEW.closed_at IS NOT NULL OR NEW.status IN('PI_GENERATED','CI_GENERATED','CLOSED','CLOSED_NO_RESPONSE','CANCELLED'))
 AND OLD.closed_at IS NULL AND OLD.status IN('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED') THEN
  INSERT INTO rr_collection_rules_test71.chat_cleanup_audit(message_id,previous_row,reason)
   SELECT m.id,to_jsonb(m),'CLOSED_COLLECTION_HISTORY' FROM public.rr_customer_chat_messages_v9433 m
   WHERE m.chat_id=NEW.chat_id AND m.archived_at IS NULL AND m.payload->>'direct_collection_cycle_id'=NEW.id::text
    AND m.message_type IN('LINK','REQUIREMENT','ATTACHMENT') AND coalesce(m.payload->>'source','')<>'DIRECT_CATEGORY_REQUEST_TEST71'
   ON CONFLICT(message_id) DO NOTHING;
  UPDATE public.rr_customer_chat_messages_v9433 m SET archived_at=now(),archive_reason='ONE_OPEN_COLLECTION_RULE_CLEANUP',
   archive_meta=coalesce(m.archive_meta,'{}'::jsonb)||jsonb_build_object('cleanup_reason','CLOSED_COLLECTION_HISTORY','history_preserved',true)
  WHERE m.chat_id=NEW.chat_id AND m.archived_at IS NULL AND m.payload->>'direct_collection_cycle_id'=NEW.id::text
   AND m.message_type IN('LINK','REQUIREMENT','ATTACHMENT') AND coalesce(m.payload->>'source','')<>'DIRECT_CATEGORY_REQUEST_TEST71';
 END IF; RETURN NEW;
END $guard$;
REVOKE ALL ON FUNCTION rr_collection_rules_test71.archive_cycle_chat_on_close() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER test71_archive_closed_collection_cards AFTER UPDATE OF status,closed_at
 ON public.rr_collection_cycle_v9586 FOR EACH ROW EXECUTE FUNCTION rr_collection_rules_test71.archive_cycle_chat_on_close();

CREATE FUNCTION rr_collection_rules_test71.enforce_requirement_cycle_binding()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $guard$
DECLARE c public.rr_collection_cycle_v9586%rowtype; s public.rr_market_share_v9420%rowtype;
BEGIN
 SELECT * INTO s FROM public.rr_market_share_v9420 WHERE id=NEW.share_id;
 IF s.data_mode<>'TEST' OR public.rr_market_share_relation_v81(s.token)='DISTRIBUTOR_CUSTOMER' THEN RETURN NEW; END IF;
 SELECT cy.* INTO c FROM public.rr_collection_cycle_v9586 cy WHERE cy.id=NEW.collection_cycle_id
 OR (NEW.collection_cycle_id IS NULL AND EXISTS(SELECT 1 FROM public.rr_collection_send_v9586 cs WHERE cs.collection_cycle_id=cy.id AND cs.share_id=NEW.share_id)) LIMIT 1 FOR UPDATE;
 IF c.id IS NULL THEN RETURN NEW; END IF;
 IF c.customer_id IS DISTINCT FROM NEW.customer_id OR c.customer_id IS DISTINCT FROM s.customer_id THEN RAISE EXCEPTION 'Requirement must belong to this collection customer.'; END IF;
 IF c.closed_at IS NOT NULL OR c.status NOT IN('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED') THEN RAISE EXCEPTION 'Closed collection requirement is frozen. Use the new collection number.'; END IF;
 RETURN NEW;
END $guard$;
REVOKE ALL ON FUNCTION rr_collection_rules_test71.enforce_requirement_cycle_binding() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER test71_requirement_cycle_binding BEFORE INSERT OR UPDATE OF share_id,customer_id,collection_cycle_id
 ON public.rr_market_requirements_v9420 FOR EACH ROW EXECUTE FUNCTION rr_collection_rules_test71.enforce_requirement_cycle_binding();

