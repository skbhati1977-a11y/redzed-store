BEGIN;
SET LOCAL statement_timeout='35s';
CREATE TEMP TABLE test71_noop_proof(result jsonb) ON COMMIT DROP;
DO $proof$
DECLARE row_id uuid; first_run jsonb; repeated_run jsonb; final_ok boolean;
BEGIN
  SELECT b.id INTO row_id FROM public.rr_real_chat_message_bridge_v70 b
  WHERE b.data_mode='TEST' AND b.archived_at IS NULL
    AND b.source_module='CUTTING' AND b.source_event_type='READY_FOR_CUTTING'
    AND NOT EXISTS(SELECT 1 FROM public.rr_cutting_lots_v3 l WHERE l.cb_unit_id::text=b.source_record_id AND upper(coalesce(l.status,'')) NOT IN('CANCELLED','CANCELED'))
    AND NOT EXISTS(SELECT 1 FROM public.rr_production_lots l WHERE l.cb_unit_id::text=b.source_record_id AND upper(coalesce(l.status,'')) NOT IN('CANCELLED','CANCELED'))
  LIMIT 1;
  IF row_id IS NULL THEN RAISE EXCEPTION 'TEST ready-card source missing'; END IF;
  UPDATE public.rr_real_chat_message_bridge_v70
    SET personal_payload=jsonb_set(personal_payload,'{status}','"WORKING"'::jsonb)
    WHERE id=row_id;
  -- Existing bridge triggers may normalize immediately; first_run is not required to write.
  first_run:=public.rr_real_chat_reconcile_cutting_v628();
  repeated_run:=public.rr_real_chat_reconcile_cutting_v628();
  SELECT personal_payload->>'canonical_state'='OPEN'
    AND personal_payload->>'status'='OPEN'
    AND group_payload->>'canonical_state'='OPEN'
    AND group_payload->>'status'='OPEN'
  INTO final_ok FROM public.rr_real_chat_message_bridge_v70 WHERE id=row_id;
  IF NOT coalesce(final_ok,false) OR (repeated_run->>'ready_open_normalized')::int<>0 THEN
    RAISE EXCEPTION 'TEST Cutting normalization/repeat invariant failed';
  END IF;
  INSERT INTO test71_noop_proof VALUES(jsonb_build_object(
    'first',first_run,'repeated',repeated_run,'normalization_correct',final_ok,'rolled_back',true));
END $proof$;
SELECT * FROM test71_noop_proof;
ROLLBACK;
