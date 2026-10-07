-- TEST direct customers may have only one active collection.
-- Historical duplicate cycles are retained; this prevents new duplicates and reopening.
CREATE SCHEMA IF NOT EXISTS rr_collection_rules_test71;
REVOKE ALL ON SCHEMA rr_collection_rules_test71 FROM PUBLIC,anon,authenticated;
CREATE TABLE rr_collection_rules_test71.customer_cycle_lock (
 customer_id uuid NOT NULL REFERENCES public.rr_customers(id),
 data_mode text NOT NULL,
 checked_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(customer_id,data_mode)
);
REVOKE ALL ON rr_collection_rules_test71.customer_cycle_lock FROM PUBLIC,anon,authenticated;
ALTER TABLE rr_collection_rules_test71.customer_cycle_lock ENABLE ROW LEVEL SECURITY;
CREATE POLICY no_direct_access ON rr_collection_rules_test71.customer_cycle_lock AS RESTRICTIVE FOR ALL TO PUBLIC USING(false) WITH CHECK(false);
INSERT INTO rr_collection_rules_test71.customer_cycle_lock(customer_id,data_mode)
 SELECT DISTINCT c.customer_id,c.data_mode FROM public.rr_collection_cycle_v9586 c
 JOIN public.rr_customer_chat_v9433 ch ON ch.id=c.chat_id
 WHERE c.data_mode='TEST' AND ch.relation_kind='DIRECT_CUSTOMER';
CREATE FUNCTION rr_collection_rules_test71.enforce_one_open_collection()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $guard$
DECLARE existing_no integer;
BEGIN
 IF NEW.data_mode<>'TEST' OR NEW.closed_at IS NOT NULL OR NEW.status NOT IN('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED')
  OR NOT EXISTS(SELECT 1 FROM public.rr_customer_chat_v9433 ch WHERE ch.id=NEW.chat_id AND ch.customer_id=NEW.customer_id AND ch.data_mode=NEW.data_mode AND ch.relation_kind='DIRECT_CUSTOMER')
 THEN RETURN NEW; END IF;
 -- Updating the already-open cycle is allowed, including legacy duplicate records.
 IF TG_OP='UPDATE' THEN
  IF OLD.id=NEW.id AND OLD.customer_id=NEW.customer_id AND OLD.chat_id=NEW.chat_id AND OLD.data_mode=NEW.data_mode
   AND OLD.closed_at IS NULL AND OLD.status IN('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED')
  THEN RETURN NEW; END IF;
 END IF;
 -- UPSERT serializes competing creation requests. A real write also makes
 -- stale REPEATABLE READ/SERIALIZABLE transactions fail rather than miss a rival.
 INSERT INTO rr_collection_rules_test71.customer_cycle_lock(customer_id,data_mode,checked_at)
 VALUES(NEW.customer_id,NEW.data_mode,clock_timestamp())
 ON CONFLICT(customer_id,data_mode) DO UPDATE SET checked_at=excluded.checked_at;
 SELECT c.collection_no INTO existing_no FROM public.rr_collection_cycle_v9586 c
 JOIN public.rr_customer_chat_v9433 ch ON ch.id=c.chat_id AND ch.relation_kind='DIRECT_CUSTOMER'
 WHERE c.customer_id=NEW.customer_id AND c.data_mode=NEW.data_mode AND c.id<>NEW.id
  AND c.closed_at IS NULL AND c.status IN('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED')
 ORDER BY c.created_at DESC,c.id DESC LIMIT 1;
 IF existing_no IS NOT NULL THEN
  RAISE EXCEPTION USING ERRCODE='23505',
   MESSAGE=format('Collection %s is already open. Close it before creating or reopening another collection.',existing_no),
   CONSTRAINT='test71_one_open_collection_per_customer';
 END IF;
 RETURN NEW;
END $guard$;
REVOKE ALL ON FUNCTION rr_collection_rules_test71.enforce_one_open_collection() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER test71_one_open_collection_per_customer
 BEFORE INSERT OR UPDATE OF customer_id,chat_id,data_mode,status,closed_at
 ON public.rr_collection_cycle_v9586 FOR EACH ROW
 EXECUTE FUNCTION rr_collection_rules_test71.enforce_one_open_collection();
