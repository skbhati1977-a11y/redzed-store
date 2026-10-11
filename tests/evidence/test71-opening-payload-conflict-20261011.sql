BEGIN;
SELECT set_config('request.jwt.claim.sub','af915a18-3823-48df-b039-1e4c7a88479b',true);
DO $test$
DECLARE a jsonb;b jsonb;ok boolean:=false;n integer;
BEGIN
 a:=public.rr_material_opening_balance_v664('77c61feb-f81d-4baa-abb9-b0d8d7eed1b7',10,20,'2026-10-01','TEST','AUDIT-OPENING-CONFLICT-ROLLBACK');
 b:=public.rr_material_opening_balance_v664('77c61feb-f81d-4baa-abb9-b0d8d7eed1b7',10,20,'2026-10-01','TEST','AUDIT-OPENING-CONFLICT-ROLLBACK');
 IF NOT (b->>'duplicate_blocked')::boolean THEN RAISE EXCEPTION 'Retry not deduplicated';END IF;
 BEGIN PERFORM public.rr_material_opening_balance_v664('77c61feb-f81d-4baa-abb9-b0d8d7eed1b7',15,30,'2026-10-01','TEST','AUDIT-OPENING-CONFLICT-ROLLBACK');EXCEPTION WHEN OTHERS THEN ok:=position('different quantity' in SQLERRM)>0;END;
 IF NOT ok THEN RAISE EXCEPTION 'Changed payload not rejected';END IF;
 SELECT count(*) INTO n FROM public.rr_material_purchases_v805 WHERE source_record_id='AUDIT-OPENING-CONFLICT-ROLLBACK';
 IF n<>1 THEN RAISE EXCEPTION 'Expected one opening row';END IF;
END $test$;
SELECT '{"identical_import_retry":"PASS","changed_payload_rejected":"PASS","one_opening_row":"PASS","no_business_rows_committed":true}'::jsonb result;
ROLLBACK;