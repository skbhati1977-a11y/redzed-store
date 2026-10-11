BEGIN;
SELECT set_config('request.jwt.claim.sub','893c58dd-420b-4dfa-aff7-844e20e634c5',true);
CREATE TEMP TABLE opening_approval_checks(label text,passed boolean) ON COMMIT DROP;
DO $test$
DECLARE ds uuid;b uuid;request uuid:=gen_random_uuid();a jsonb;r jsonb;rows jsonb;coverage jsonb:='{}';mapping jsonb;category text;cash uuid;capital uuid;blocked boolean;before_tx bigint;stock_ds uuid;stock_batch uuid;stock_coverage jsonb;stock_mapping jsonb;material uuid;bad_items jsonb;
BEGIN
SELECT count(*) INTO before_tx FROM public.rr_account_transactions_v805;
SELECT id INTO cash FROM public.rr_ledgers_v805 WHERE ledger_code='CASH_MAIN' AND is_active;
SELECT id INTO capital FROM public.rr_ledgers_v805 WHERE is_active AND id<>cash ORDER BY id LIMIT 1;
IF cash IS NULL OR capital IS NULL THEN RAISE EXCEPTION 'Synthetic rollback requires two existing active ledgers.';END IF;
-- Existing second ledger is only a synthetic mapping; no real ledger classification is approved.
FOR category IN SELECT unnest(ARRAY['CASH_BANK','RECEIVABLES','PAYABLES','ADVANCES','SALARY_PAYABLE','CLAIMS','STOCK','WIP','EQUITY','OTHER']) LOOP
 coverage:=coverage||jsonb_build_object(category,jsonb_build_object('state',CASE WHEN category IN('CASH_BANK','EQUITY') THEN 'KNOWN' ELSE 'NOT_APPLICABLE' END,'evidence_ref','ROLLBACK_SYNTHETIC_ONLY','reason','Synthetic absent class'));
END LOOP;
mapping:=jsonb_build_object('cash',jsonb_build_object('ledger_id',cash,'class','CASH_BANK','evidence_ref','ROLLBACK_ONLY'),'capital',jsonb_build_object('ledger_id',capital,'class','EQUITY','evidence_ref','ROLLBACK_ONLY'));
rows:=jsonb_build_array(jsonb_build_object('module','OPENING_GL','source_key','cash','record_date','2026-09-01','evidence_status','KNOWN','values',jsonb_build_object('ledger_key','cash','debit',10.10,'credit',0),'references','[]'::jsonb),jsonb_build_object('module','OPENING_GL','source_key','capital','record_date','2026-09-01','evidence_status','KNOWN','values',jsonb_build_object('ledger_key','capital','debit',0,'credit',10.10),'references','[]'::jsonb));
r:=public.rr_source_dataset_create_test71(gen_random_uuid(),'ROLLBACK-OPENING-APPROVAL');ds:=(r->>'dataset_id')::uuid;
r:=public.rr_dataset_import_stage_test71(ds,gen_random_uuid(),'ROLLBACK-OPENING-SOURCE',repeat('a',64),rows);b:=(r->>'batch_id')::uuid;
blocked:=false;BEGIN PERFORM public.rr_opening_approve_test71(ds,b,request,'2026-09-02','ROLLBACK_ONLY',coverage,mapping,'{}');EXCEPTION WHEN others THEN IF sqlerrm NOT LIKE '%cutoff%' THEN RAISE;END IF;blocked:=true;END;
IF NOT blocked THEN RAISE EXCEPTION 'Cutoff mismatch accepted';END IF;INSERT INTO opening_approval_checks VALUES('approved_cutoff_bound_to_source',true);
blocked:=false;BEGIN PERFORM public.rr_opening_approve_test71(ds,b,request,'2026-09-01','ROLLBACK_ONLY',coverage-'CLAIMS',mapping,'{}');EXCEPTION WHEN others THEN IF sqlerrm NOT LIKE '%coverage%' THEN RAISE;END IF;blocked:=true;END;
IF NOT blocked THEN RAISE EXCEPTION 'Missing coverage accepted';END IF;INSERT INTO opening_approval_checks VALUES('all_financial_classes_explicit',true);
blocked:=false;BEGIN PERFORM public.rr_opening_approve_test71(ds,b,request,'2026-09-01','ROLLBACK_ONLY',coverage,jsonb_set(mapping,'{cash,ledger_id}',to_jsonb(gen_random_uuid())),'{}');EXCEPTION WHEN others THEN IF sqlerrm NOT LIKE '%active ledger%' THEN RAISE;END IF;blocked:=true;END;
IF NOT blocked THEN RAISE EXCEPTION 'Unknown ledger accepted';END IF;INSERT INTO opening_approval_checks VALUES('unknown_master_not_guessed',true);
a:=public.rr_opening_approve_test71(ds,b,request,'2026-09-01','ROLLBACK_ONLY',coverage,mapping,'{}');
IF a->>'approval_status'<>'APPROVED_PLAN_ONLY' OR (a->>'cleared_for_import')::boolean OR (a->>'business_records_posted')::int<>0 OR (a->>'total_debit')::numeric<>10.10 OR jsonb_array_length(a->'ledger_postings')<>2 THEN RAISE EXCEPTION 'Invalid approval plan contract';END IF;INSERT INTO opening_approval_checks VALUES('balanced_plan_without_business_posting',true);
r:=public.rr_opening_approve_test71(ds,b,request,'2026-09-01','ROLLBACK_ONLY',coverage,mapping,'{}');IF r->>'approval_id'<>a->>'approval_id' OR NOT (r->>'already_approved')::boolean THEN RAISE EXCEPTION 'Approval retry duplicated';END IF;INSERT INTO opening_approval_checks VALUES('exact_retry_one_approval',true);
blocked:=false;BEGIN PERFORM public.rr_opening_approve_test71(ds,b,request,'2026-09-01','CHANGED',coverage,mapping,'{}');EXCEPTION WHEN others THEN IF sqlerrm NOT LIKE '%immutable%' THEN RAISE;END IF;blocked:=true;END;
IF NOT blocked THEN RAISE EXCEPTION 'Changed evidence accepted';END IF;INSERT INTO opening_approval_checks VALUES('changed_approval_rejected',true);
blocked:=false;BEGIN UPDATE public.rr_opening_approvals_test71 SET cutoff='2026-09-02' WHERE id=(a->>'approval_id')::uuid;EXCEPTION WHEN others THEN IF sqlerrm NOT LIKE '%immutable%' THEN RAISE;END IF;blocked:=true;END;
IF NOT blocked THEN RAISE EXCEPTION 'Approval mutated';END IF;INSERT INTO opening_approval_checks VALUES('approved_evidence_immutable',true);
blocked:=false;BEGIN PERFORM public.rr_opening_post_test71(ds,(a->>'approval_id')::uuid,gen_random_uuid());EXCEPTION WHEN SQLSTATE '55000' THEN blocked:=true;END;
IF NOT blocked THEN RAISE EXCEPTION 'Shared posting gate bypassed';END IF;INSERT INTO opening_approval_checks VALUES('unverified_downstream_posting_closed',true);
IF before_tx<>(SELECT count(*) FROM public.rr_account_transactions_v805) THEN RAISE EXCEPTION 'Plan wrote business journal';END IF;INSERT INTO opening_approval_checks VALUES('zero_shared_journal_writes',true);
SELECT id INTO material FROM public.rr_material_master_v805 WHERE is_active ORDER BY id LIMIT 1;
stock_coverage:=jsonb_set(jsonb_set(coverage,'{CASH_BANK,state}','"NOT_APPLICABLE"'),'{STOCK,state}','"KNOWN"');
stock_mapping:=jsonb_set(mapping,'{cash,class}','"STOCK"');
rows:=rows||jsonb_build_array(jsonb_build_object('module','OPENING_STOCK','source_key','physical','record_date','2026-09-01','evidence_status','KNOWN','values',jsonb_build_object('item_key','material','quantity',1,'unit','PCS','value',10.10),'references','[]'::jsonb));
r:=public.rr_source_dataset_create_test71(gen_random_uuid(),'ROLLBACK-OPENING-PHYSICAL');stock_ds:=(r->>'dataset_id')::uuid;
r:=public.rr_dataset_import_stage_test71(stock_ds,gen_random_uuid(),'ROLLBACK-OPENING-PHYSICAL-SOURCE',repeat('b',64),rows);stock_batch:=(r->>'batch_id')::uuid;
FOREACH bad_items IN ARRAY ARRAY['{}'::jsonb,jsonb_build_object('material',jsonb_build_object('master_id',material,'kind','UNKNOWN','evidence_ref','ROLLBACK')),jsonb_build_object('material',jsonb_build_object('master_id',null,'kind','MATERIAL','evidence_ref','ROLLBACK'))] LOOP
 blocked:=false;BEGIN PERFORM public.rr_opening_approve_test71(stock_ds,stock_batch,gen_random_uuid(),'2026-09-01','ROLLBACK_ONLY',stock_coverage,stock_mapping,bad_items);EXCEPTION WHEN others THEN IF sqlerrm NOT LIKE '%item mapping%' THEN RAISE;END IF;blocked:=true;END;
 IF NOT blocked THEN RAISE EXCEPTION 'Missing/invalid item mapping accepted';END IF;
END LOOP;INSERT INTO opening_approval_checks VALUES('null_missing_invalid_kind_items_blocked',true);
blocked:=false;BEGIN PERFORM public.rr_opening_approve_test71(stock_ds,stock_batch,gen_random_uuid(),'2026-09-01','ROLLBACK_ONLY',stock_coverage||'{"EXTRA":{"state":"KNOWN","evidence_ref":"ROLLBACK"}}',jsonb_set(stock_mapping,'{cash,class}','"EXTRA"'),jsonb_build_object('material',jsonb_build_object('master_id',material,'kind','MATERIAL','evidence_ref','ROLLBACK')));EXCEPTION WHEN others THEN IF sqlerrm NOT LIKE '%ledger class%' THEN RAISE;END IF;blocked:=true;END;
IF NOT blocked THEN RAISE EXCEPTION 'Extra ledger class accepted';END IF;INSERT INTO opening_approval_checks VALUES('only_explicit_financial_classes',true);
-- Corrupt only rollback-local normalized evidence to verify approval's independent checks.
UPDATE public.rr_dataset_import_rows_test71 SET values_json=jsonb_set(values_json,'{value}','10.09') WHERE batch_id=stock_batch AND module='OPENING_STOCK';
blocked:=false;BEGIN PERFORM public.rr_opening_approve_test71(stock_ds,stock_batch,gen_random_uuid(),'2026-09-01','ROLLBACK_ONLY',stock_coverage,stock_mapping,jsonb_build_object('material',jsonb_build_object('master_id',material,'kind','MATERIAL','evidence_ref','ROLLBACK')));EXCEPTION WHEN others THEN IF sqlerrm NOT LIKE '%does not reconcile%' THEN RAISE;END IF;blocked:=true;END;
IF NOT blocked THEN RAISE EXCEPTION 'Physical mismatch accepted';END IF;INSERT INTO opening_approval_checks VALUES('balanced_gl_cannot_hide_physical_mismatch',true);
UPDATE public.rr_dataset_import_rows_test71 SET values_json=jsonb_set(values_json,'{value}','"NaN"') WHERE batch_id=stock_batch AND module='OPENING_STOCK';
blocked:=false;BEGIN PERFORM public.rr_opening_approve_test71(stock_ds,stock_batch,gen_random_uuid(),'2026-09-01','ROLLBACK_ONLY',stock_coverage,stock_mapping,jsonb_build_object('material',jsonb_build_object('master_id',material,'kind','MATERIAL','evidence_ref','ROLLBACK')));EXCEPTION WHEN others THEN IF sqlerrm NOT LIKE '%Finite exact%' THEN RAISE;END IF;blocked:=true;END;
IF NOT blocked THEN RAISE EXCEPTION 'NaN accepted';END IF;INSERT INTO opening_approval_checks VALUES('finite_numeric_rechecked_at_approval',true);
UPDATE public.rr_dataset_import_rows_test71 SET values_json=jsonb_set(values_json,'{value}','10.10') WHERE batch_id=stock_batch AND module='OPENING_STOCK';
r:=public.rr_opening_approve_test71(stock_ds,stock_batch,gen_random_uuid(),'2026-09-01','ROLLBACK_ONLY',stock_coverage,stock_mapping,jsonb_build_object('material',jsonb_build_object('master_id',material,'kind','MATERIAL','evidence_ref','ROLLBACK')));
IF (r->>'stock_value')::numeric<>10.10 OR r->>'stock_value'<>r->>'stock_gl' OR jsonb_array_length(r->'physical_openings')<>1 THEN RAISE EXCEPTION 'Physical plan reconciliation incorrect';END IF;INSERT INTO opening_approval_checks VALUES('physical_stock_to_gl_reconciled',true);
blocked:=false;BEGIN PERFORM public.rr_opening_post_test71(ds,(a->>'approval_id')::uuid,null);EXCEPTION WHEN others THEN IF sqlerrm NOT LIKE '%request required%' THEN RAISE;END IF;blocked:=true;END;
IF NOT blocked THEN RAISE EXCEPTION 'Null posting request accepted';END IF;INSERT INTO opening_approval_checks VALUES('posting_request_required',true);
IF has_table_privilege('authenticated','public.rr_opening_approvals_test71','INSERT') OR has_function_privilege('anon','public.rr_opening_approve_test71(uuid,uuid,uuid,date,text,jsonb,jsonb,jsonb)','EXECUTE') OR has_function_privilege('authenticated','public.rr_opening_plan_build_test71(uuid,uuid,date,jsonb,jsonb,jsonb)','EXECUTE') THEN RAISE EXCEPTION 'Approval permission leak';END IF;INSERT INTO opening_approval_checks VALUES('private_table_and_builder_anon_denied',true);
PERFORM set_config('request.jwt.claim.sub','',true);blocked:=false;
BEGIN PERFORM public.rr_opening_approval_report_test71(ds);EXCEPTION WHEN SQLSTATE '42501' THEN blocked:=true;END;
IF NOT blocked THEN RAISE EXCEPTION 'Anonymous report accepted';END IF;INSERT INTO opening_approval_checks VALUES('anonymous_runtime_denied',true);
END;$test$;
SELECT * FROM opening_approval_checks;ROLLBACK;
