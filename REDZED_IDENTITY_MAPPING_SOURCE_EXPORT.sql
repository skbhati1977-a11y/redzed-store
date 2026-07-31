-- READ ONLY: exports exact Cutting/Product/Art/Print identity source objects.
select jsonb_pretty(jsonb_build_object(
 'columns',coalesce((select jsonb_agg(to_jsonb(x) order by table_schema,table_name,ordinal_position) from (
   select table_schema,table_name,column_name,data_type,is_nullable,column_default,ordinal_position
   from information_schema.columns
   where table_schema='public' and (
     lower(table_name) like '%cut%' or lower(table_name) like '%product%' or lower(table_name) like '%art%' or lower(table_name) like '%print%' or lower(table_name) like '%frame%'
   ) and (
     lower(column_name) like '%art%' or lower(column_name) like '%print%' or lower(column_name) like '%frame%' or lower(column_name) like '%cb%' or lower(column_name) like '%lot%'
   )
 ) x),'[]'::jsonb),
 'views',coalesce((select jsonb_agg(jsonb_build_object('schema',schemaname,'name',viewname,'definition',definition)) from pg_views
   where schemaname='public' and (lower(definition) like '%art_no%' or lower(definition) like '%print_no%' or lower(definition) like '%frame_no%' or lower(definition) like '%cb_no%')),'[]'::jsonb),
 'functions',coalesce((select jsonb_agg(jsonb_build_object('schema',n.nspname,'name',p.proname,'arguments',pg_get_function_identity_arguments(p.oid),'definition',pg_get_functiondef(p.oid)))
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and (
    lower(pg_get_functiondef(p.oid)) like '%art_no%' or lower(pg_get_functiondef(p.oid)) like '%print_no%' or lower(pg_get_functiondef(p.oid)) like '%frame_no%' or lower(pg_get_functiondef(p.oid)) like '%cb_no%'
   )),'[]'::jsonb)
)) as exact_identity_mapping_source;
