-- RRQ tables use a second existing app prefix. No working records changed.
CREATE OR REPLACE FUNCTION legacy_archive_test71_20261011.capture(p_tables text[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE t text; src_rows bigint; dst_rows bigint; src_hash text; dst_hash text; cols jsonb;n integer:=0;
BEGIN
 IF current_setting('transaction_isolation') NOT IN('repeatable read','serializable') THEN RAISE EXCEPTION 'Consistent archive transaction required';END IF;
 FOREACH t IN ARRAY p_tables LOOP
 IF (t NOT LIKE 'rr\_%' ESCAPE '\' AND t NOT LIKE 'rrq\_%' ESCAPE '\') OR NOT EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace WHERE ns.nspname='public' AND c.relname=t AND c.relkind='r') THEN RAISE EXCEPTION 'Public app base table required';END IF;
 IF EXISTS(SELECT 1 FROM legacy_archive_test71_20261011.manifest WHERE table_name=t) THEN CONTINUE;END IF;
 EXECUTE format('CREATE TABLE legacy_archive_test71_20261011.%I AS TABLE public.%I',t,t);
 EXECUTE format('ALTER TABLE legacy_archive_test71_20261011.%I ENABLE ROW LEVEL SECURITY',t);
 EXECUTE format('REVOKE ALL ON legacy_archive_test71_20261011.%I FROM PUBLIC,anon,authenticated,service_role',t);
 EXECUTE format('SELECT count(*),md5(coalesce(string_agg(md5(to_jsonb(r)::text),'''' ORDER BY md5(to_jsonb(r)::text)),'''')) FROM public.%I r',t) INTO src_rows,src_hash;
 EXECUTE format('SELECT count(*),md5(coalesce(string_agg(md5(to_jsonb(r)::text),'''' ORDER BY md5(to_jsonb(r)::text)),'''')) FROM legacy_archive_test71_20261011.%I r',t) INTO dst_rows,dst_hash;
 IF src_rows IS DISTINCT FROM dst_rows OR src_hash IS DISTINCT FROM dst_hash THEN RAISE EXCEPTION 'Archive verification failed for %',t;END IF;
 SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull) ORDER BY a.attnum) INTO cols FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace ns ON ns.oid=c.relnamespace WHERE ns.nspname='public' AND c.relname=t AND a.attnum>0 AND NOT a.attisdropped;
 INSERT INTO legacy_archive_test71_20261011.manifest(table_name,archived_rows,content_hash,columns_json) VALUES(t,src_rows,src_hash,cols);n:=n+1;
 END LOOP;
 RETURN jsonb_build_object('captured_tables',n,'working_data_removed',false);
END;$$;
REVOKE ALL ON FUNCTION legacy_archive_test71_20261011.capture(text[]) FROM PUBLIC,anon,authenticated,service_role;
