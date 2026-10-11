-- Read-only catalog evidence. No history changes, classification or archive activation.
SELECT jsonb_build_object(
 'dataset_columns',(SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND column_name IN('dataset_id','workspace_id','rehearsal_id')),
 'mode_tables',(SELECT count(*) FROM information_schema.columns c JOIN information_schema.tables t USING(table_schema,table_name) WHERE c.table_schema='public' AND c.column_name='data_mode' AND t.table_type='BASE TABLE'),
 'mode_functions',(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind='f' AND p.prosrc ILIKE '%data_mode%'),
 'missing_mode_core',(SELECT jsonb_agg(x) FROM(SELECT t.table_name FROM information_schema.tables t WHERE t.table_schema='public' AND t.table_name IN('rr_fabric_purchases','rr_cutting_lots_v3','rr_upm_lot_registry') AND NOT EXISTS(SELECT 1 FROM information_schema.columns c WHERE c.table_schema=t.table_schema AND c.table_name=t.table_name AND c.column_name='data_mode'))x),
 'holiday_relations',(SELECT jsonb_agg(x) FROM(SELECT table_name,array_agg(column_name ORDER BY ordinal_position) columns FROM information_schema.columns WHERE table_schema='public' AND table_name ILIKE '%holiday%' GROUP BY table_name)x)
) inventory;
