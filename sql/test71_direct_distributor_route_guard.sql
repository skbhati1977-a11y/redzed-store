CREATE OR REPLACE FUNCTION rr_collection_rules_test71.enforce_send_to_open_cycle()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE c public.rr_collection_cycle_v9586%rowtype; s public.rr_market_share_v9420%rowtype;
BEGIN
 SELECT * INTO c FROM public.rr_collection_cycle_v9586 WHERE id=NEW.collection_cycle_id FOR UPDATE;
 IF c.data_mode<>'TEST' THEN RETURN NEW; END IF;
 IF c.closed_at IS NOT NULL OR c.status NOT IN('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED') THEN
  RAISE EXCEPTION 'Collection is closed or PI has been made. Send with a new collection number.';
 END IF;
 IF EXISTS(SELECT 1 FROM public.rr_market_partner_collection_v67 pc WHERE pc.share_id=NEW.share_id) THEN RAISE EXCEPTION 'Distributor private share cannot be attached to a REDZED direct collection.';END IF;
 SELECT * INTO s FROM public.rr_market_share_v9420 WHERE id=NEW.share_id;
 IF s.customer_id IS DISTINCT FROM c.customer_id OR s.data_mode IS DISTINCT FROM c.data_mode OR (s.origin_chat_id IS NOT NULL AND s.origin_chat_id IS DISTINCT FROM c.chat_id) THEN
  RAISE EXCEPTION 'Update share must belong to this collection customer and chat.';
 END IF;
 RETURN NEW;
END $function$
;
