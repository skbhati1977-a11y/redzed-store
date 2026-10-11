-- Additional app business schemas; preserves live customer login/auth records.
CREATE FUNCTION legacy_archive_test71_20261011.capture_auxiliary()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r record;target text;source_key text;src_count bigint;dst_count bigint;src_hash text;dst_hash text;cols jsonb;n integer:=0;
BEGIN
 IF current_setting('transaction_isolation') NOT IN('repeatable read','serializable') THEN RAISE EXCEPTION 'Consistent archive transaction required';END IF;
 FOR r IN SELECT ns.nspname,c.relname FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace WHERE c.relkind='r' AND ns.nspname IN('rr_chat_notifications_test71','rr_collection_rules_test71','rr_customer_auth_test71') ORDER BY ns.nspname,c.relname LOOP
 source_key:=r.nspname||'.'||r.relname;target:='aux_'||md5(source_key);
 IF EXISTS(SELECT 1 FROM legacy_archive_test71_20261011.manifest WHERE table_name=source_key) THEN CONTINUE;END IF;
 EXECUTE format('CREATE TABLE legacy_archive_test71_20261011.%I AS TABLE %I.%I',target,r.nspname,r.relname);
 EXECUTE format('ALTER TABLE legacy_archive_test71_20261011.%I ENABLE ROW LEVEL SECURITY',target);
 EXECUTE format('REVOKE ALL ON legacy_archive_test71_20261011.%I FROM PUBLIC,anon,authenticated,service_role',target);
 EXECUTE format('SELECT count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'''' ORDER BY md5(to_jsonb(x)::text)),'''')) FROM %I.%I x',r.nspname,r.relname) INTO src_count,src_hash;
 EXECUTE format('SELECT count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'''' ORDER BY md5(to_jsonb(x)::text)),'''')) FROM legacy_archive_test71_20261011.%I x',target) INTO dst_count,dst_hash;
 IF src_count IS DISTINCT FROM dst_count OR src_hash IS DISTINCT FROM dst_hash THEN RAISE EXCEPTION 'Auxiliary archive verification failed';END IF;
 SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull) ORDER BY a.attnum) INTO cols FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace ns ON ns.oid=c.relnamespace WHERE ns.nspname=r.nspname AND c.relname=r.relname AND a.attnum>0 AND NOT a.attisdropped;
 INSERT INTO legacy_archive_test71_20261011.manifest(table_name,archived_rows,content_hash,columns_json) VALUES(source_key,src_count,src_hash,jsonb_build_object('source_schema',r.nspname,'archive_table',target,'columns',cols));n:=n+1;
 END LOOP;
 RETURN jsonb_build_object('auxiliary_tables',n,'working_data_removed',false);
END;$$;
REVOKE ALL ON FUNCTION legacy_archive_test71_20261011.capture_auxiliary() FROM PUBLIC,anon,authenticated,service_role;
