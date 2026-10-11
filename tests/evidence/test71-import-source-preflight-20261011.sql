BEGIN;
SELECT set_config('request.jwt.claim.sub','893c58dd-420b-4dfa-aff7-844e20e634c5',true);
CREATE TEMP TABLE import_result(label text,result jsonb) ON COMMIT DROP;
DO $test$
DECLARE k uuid:=gen_random_uuid();rows jsonb;r jsonb;s jsonb;blocked boolean:=false;
BEGIN
rows:=jsonb_build_array(
 jsonb_build_object('module','LEDGERS','source_key','cash','record_date','2026-09-03','evidence_status','KNOWN','values',jsonb_build_object('name','Source Cash'),'references','[]'::jsonb),
 jsonb_build_object('module','OPENING_GL','source_key','op-cash','record_date','2026-09-01','evidence_status','KNOWN','values',jsonb_build_object('ledger_key','cash','debit',100,'credit',0),'references',jsonb_build_array(jsonb_build_object('module','LEDGERS','source_key','cash'))),
 jsonb_build_object('module','OPENING_GL','source_key','op-capital','record_date','2026-09-02','evidence_status','KNOWN','values',jsonb_build_object('ledger_key','capital','debit',0,'credit',100),'references','[]'::jsonb));
r:=public.rr_import_stage_source_test71(k,'ROLLBACK-IMPORT-CANONICAL',repeat('a',64),rows);
IF r->>'status'<>'STAGED' OR r->>'earliest_source_date'<>'2026-09-01' OR (r->>'cleared_for_import')::boolean OR (r->>'business_records_posted')::int<>0 THEN RAISE EXCEPTION 'Staging source/date or posting boundary incorrect';END IF;
INSERT INTO import_result VALUES('earliest_supplied_date_no_business_posting',r);
s:=public.rr_import_stage_source_test71(k,'ROLLBACK-IMPORT-CANONICAL',repeat('a',64),rows);
IF s->>'batch_id'<>r->>'batch_id' OR NOT (s->>'already_staged')::boolean THEN RAISE EXCEPTION 'Duplicate source batch';END IF;
INSERT INTO import_result VALUES('exact_source_retry_one_batch','true');
BEGIN PERFORM public.rr_import_stage_source_test71(k,'ROLLBACK-IMPORT-CANONICAL',repeat('a',64),rows||jsonb_build_array(rows->0));EXCEPTION WHEN others THEN IF sqlerrm NOT LIKE '%different payload%' THEN RAISE;END IF;blocked:=true;END;
IF NOT blocked THEN RAISE EXCEPTION 'Changed payload accepted';END IF;
INSERT INTO import_result VALUES('changed_payload_same_request_rejected','true');
r:=public.rr_import_stage_source_test71(gen_random_uuid(),'ROLLBACK-IMPORT-UNKNOWN',repeat('b',64),jsonb_build_array(jsonb_build_object('module','OPENING_STOCK','source_key','stock','record_date','2026-09-01','evidence_status','UNKNOWN','values',jsonb_build_object('quantity',null,'value',null),'references','[]'::jsonb)));
IF r->>'status'<>'STAGED_WITH_ERRORS' OR NOT (r->'findings' @> '[{"code":"UNKNOWN_EVIDENCE"}]'::jsonb) THEN RAISE EXCEPTION 'Unknown was not blocked';END IF;
INSERT INTO import_result VALUES('unknown_is_preserved_not_zero','true');
r:=public.rr_import_stage_source_test71(gen_random_uuid(),'ROLLBACK-IMPORT-ZERO',repeat('c',64),jsonb_build_array(jsonb_build_object('module','OPENING_GL','source_key','zero','record_date','2026-09-01','evidence_status','ZERO','values',jsonb_build_object('ledger_key','cash','debit',1,'credit',0),'references','[]'::jsonb)));
IF NOT (r->'findings' @> '[{"code":"OPENING_GL_VALUES"}]'::jsonb) THEN RAISE EXCEPTION 'False zero accepted';END IF;
INSERT INTO import_result VALUES('zero_requires_exact_zero','true');
r:=public.rr_import_stage_source_test71(gen_random_uuid(),'ROLLBACK-IMPORT-UNBALANCED',repeat('d',64),jsonb_build_array(rows->1));
IF NOT (r->'findings' @> '[{"code":"OPENING_GL_UNBALANCED"}]'::jsonb) OR NOT (r->'findings' @> '[{"code":"UNRESOLVED_SOURCE_REFERENCE"}]'::jsonb) THEN RAISE EXCEPTION 'Opening/reference not blocked';END IF;
INSERT INTO import_result VALUES('unbalanced_opening_unmapped_reference_blocked','true');
r:=public.rr_import_stage_source_test71(gen_random_uuid(),'ROLLBACK-IMPORT-DUPLICATE',repeat('e',64),jsonb_build_array(rows->0,rows->0));
IF NOT (r->'findings' @> '[{"code":"DUPLICATE_SOURCE_KEY"}]'::jsonb) THEN RAISE EXCEPTION 'Duplicate source key accepted';END IF;
INSERT INTO import_result VALUES('duplicate_source_identity_blocked','true');
r:=public.rr_import_stage_source_test71(gen_random_uuid(),'ROLLBACK-IMPORT-BADDATE',repeat('f',64),jsonb_build_array(jsonb_build_object('module','WORKERS','source_key','w','record_date','2026-09-99','evidence_status','NOT_APPLICABLE','values','{}'::jsonb,'references','[]'::jsonb)));
IF NOT (r->'findings' @> '[{"code":"ROW_CONTRACT"}]'::jsonb) OR NOT (r->'findings' @> '[{"code":"NA_REASON"}]'::jsonb) THEN RAISE EXCEPTION 'Bad date or unexplained NA accepted';END IF;
INSERT INTO import_result VALUES('invalid_date_na_reason_blocked','true');
IF has_table_privilege('authenticated','public.rr_import_rows_test71','INSERT') OR has_table_privilege('anon','public.rr_import_rows_test71','SELECT') OR has_function_privilege('anon','public.rr_import_stage_source_test71(uuid,text,text,jsonb)','EXECUTE') THEN RAISE EXCEPTION 'Import privacy grants exposed';END IF;
INSERT INTO import_result VALUES('direct_table_write_and_anon_denied','true');
PERFORM set_config('request.jwt.claim.sub','',true);blocked:=false;
BEGIN PERFORM public.rr_import_preflight_report_test71((s->>'batch_id')::uuid);EXCEPTION WHEN others THEN IF sqlstate<>'42501' THEN RAISE;END IF;blocked:=true;END;
IF NOT blocked THEN RAISE EXCEPTION 'Anonymous report allowed';END IF;
INSERT INTO import_result VALUES('auth_null_report_denied','true');
END;$test$;
SELECT * FROM import_result;ROLLBACK;