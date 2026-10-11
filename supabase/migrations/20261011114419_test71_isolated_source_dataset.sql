-- Dedicated source intake namespace; no historical rows moved or operational balances posted.
CREATE TABLE public.rr_source_datasets_test71(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), request_id uuid NOT NULL,
 name text NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 120),
 data_mode text NOT NULL DEFAULT 'TEST' CHECK(data_mode='TEST'),
 status text NOT NULL DEFAULT 'DRAFT' CHECK(status='DRAFT'),
 created_by uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(created_by,request_id)
);
ALTER TABLE public.rr_source_datasets_test71 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rr_source_datasets_test71 FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.rr_source_dataset_create_test71(p_request_id uuid,p_name text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE d public.rr_source_datasets_test71%rowtype;
BEGIN
 PERFORM public.rr_import_admin_assert_test71();
 IF p_request_id IS NULL OR p_name IS NULL OR length(trim(p_name)) NOT BETWEEN 1 AND 120 THEN RAISE EXCEPTION 'Request and dataset name required.';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('TEST71_DATASET|'||auth.uid()::text||'|'||p_request_id::text,0));
 SELECT * INTO d FROM public.rr_source_datasets_test71 WHERE created_by=auth.uid() AND request_id=p_request_id;
 IF d.id IS NOT NULL AND d.name<>trim(p_name) THEN RAISE EXCEPTION 'Dataset request already used with a different name.';END IF;
 IF d.id IS NULL THEN INSERT INTO public.rr_source_datasets_test71(request_id,name,created_by) VALUES(p_request_id,trim(p_name),auth.uid()) RETURNING * INTO d;END IF;
 RETURN jsonb_build_object('dataset_id',d.id,'name',d.name,'status',d.status,'data_mode','TEST','operational_posting_enabled',false);
END;$$;
REVOKE ALL ON FUNCTION public.rr_source_dataset_create_test71(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_source_dataset_create_test71(uuid,text) TO authenticated;
CREATE TABLE public.rr_dataset_import_batches_test71(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 dataset_id uuid NOT NULL REFERENCES public.rr_source_datasets_test71(id),
 data_mode text NOT NULL DEFAULT 'TEST' CHECK(data_mode='TEST'),
 request_id uuid NOT NULL,source_ref text NOT NULL,source_sha256 text NOT NULL CHECK(source_sha256~'^[0-9a-f]{64}$'),
 source_payload jsonb NOT NULL CHECK(jsonb_typeof(source_payload)='array'),
 earliest_date date,latest_date date,row_count integer NOT NULL,
 status text NOT NULL CHECK(status IN('STAGED','STAGED_WITH_ERRORS')),
 created_by uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(dataset_id,id),UNIQUE(dataset_id,created_by,request_id),UNIQUE(dataset_id,source_ref,source_sha256)
);
CREATE TABLE public.rr_dataset_import_rows_test71(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 batch_id uuid NOT NULL REFERENCES public.rr_dataset_import_batches_test71(id),
 row_no integer NOT NULL,module text,source_key text,record_date date,
 evidence_status text,values_json jsonb NOT NULL,reference_json jsonb NOT NULL,
 original_row jsonb NOT NULL,UNIQUE(batch_id,row_no)
);
CREATE INDEX rr_dataset_import_rows_source_test71 ON public.rr_dataset_import_rows_test71(batch_id,module,source_key);
CREATE TABLE public.rr_dataset_import_findings_test71(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 batch_id uuid NOT NULL REFERENCES public.rr_dataset_import_batches_test71(id),
 row_no integer,code text NOT NULL,severity text NOT NULL CHECK(severity IN('ERROR','REVIEW')),detail text NOT NULL
);
CREATE INDEX rr_dataset_import_findings_batch_test71 ON public.rr_dataset_import_findings_test71(batch_id);
ALTER TABLE public.rr_dataset_import_batches_test71 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rr_dataset_import_rows_test71 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rr_dataset_import_findings_test71 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rr_dataset_import_batches_test71,public.rr_dataset_import_rows_test71,public.rr_dataset_import_findings_test71 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON SEQUENCE public.rr_dataset_import_findings_test71_id_seq FROM PUBLIC,anon,authenticated;


CREATE OR REPLACE FUNCTION public.rr_dataset_import_report_test71(p_dataset_id uuid,p_batch_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE b public.rr_dataset_import_batches_test71%rowtype;f jsonb;rows_json jsonb;totals jsonb;
BEGIN
 PERFORM public.rr_import_admin_assert_test71();
 SELECT * INTO b FROM public.rr_dataset_import_batches_test71 WHERE id=p_batch_id AND dataset_id=p_dataset_id;
 IF b.id IS NULL THEN RAISE EXCEPTION 'Batch does not belong to requested TEST dataset.';END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('row_no',row_no,'code',code,'severity',severity,'detail',detail) ORDER BY row_no NULLS FIRST,id),'[]'::jsonb) INTO f FROM public.rr_dataset_import_findings_test71 WHERE batch_id=b.id;
 SELECT coalesce(jsonb_agg(original_row ORDER BY row_no),'[]'::jsonb) INTO rows_json FROM public.rr_dataset_import_rows_test71 WHERE batch_id=b.id;
 -- Only validated opening rows contribute. Errors never silently become zero balances.
 SELECT jsonb_build_object('kind','SOURCE_REVIEW_ONLY','opening_gl',jsonb_build_object('debit',sum(CASE WHEN module='OPENING_GL' THEN (values_json->>'debit')::numeric END),'credit',sum(CASE WHEN module='OPENING_GL' THEN (values_json->>'credit')::numeric END)),
 'stock_wip',coalesce((SELECT jsonb_agg(g) FROM(SELECT module,values_json->>'unit' unit,sum((values_json->>'quantity')::numeric) quantity,sum((values_json->>'value')::numeric) value FROM public.rr_dataset_import_rows_test71 r WHERE r.batch_id=b.id AND r.module IN('OPENING_STOCK','OPENING_WIP') AND r.evidence_status IN('KNOWN','ZERO') AND NOT EXISTS(SELECT 1 FROM public.rr_dataset_import_findings_test71 e WHERE e.batch_id=b.id AND e.row_no=r.row_no AND e.severity='ERROR') GROUP BY module,values_json->>'unit')g),'[]'::jsonb)) INTO totals
 FROM public.rr_dataset_import_rows_test71 r WHERE r.batch_id=b.id AND r.module='OPENING_GL' AND r.evidence_status IN('KNOWN','ZERO') AND NOT EXISTS(SELECT 1 FROM public.rr_dataset_import_findings_test71 e WHERE e.batch_id=b.id AND e.row_no=r.row_no AND e.severity='ERROR');
 RETURN jsonb_build_object('dataset_id',b.dataset_id,'batch_id',b.id,'data_mode','TEST','source_ref',b.source_ref,'source_sha256',b.source_sha256,'status',b.status,'row_count',b.row_count,'earliest_source_date',b.earliest_date,'latest_source_date',b.latest_date,
 'opening_cutoff_rule','EARLIEST_SUPPLIED_DATA_DATE','findings',f,'rows',rows_json,'source_totals',totals,'cleared_for_import',false,'operational_posting_enabled',false,'business_records_posted',0);
END;$$;
REVOKE ALL ON FUNCTION public.rr_dataset_import_report_test71(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_dataset_import_report_test71(uuid,uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_dataset_import_stage_test71(p_dataset_id uuid,p_request_id uuid,p_source_ref text,p_source_sha256 text,p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE b public.rr_dataset_import_batches_test71%rowtype;r jsonb;n integer:=0;d date;m text;k text;e text;v jsonb;refs jsonb;x record;
 dr numeric;cr numeric;qty numeric;value_amount numeric;opening_dr numeric;opening_cr numeric;
BEGIN
 PERFORM public.rr_import_admin_assert_test71();
 PERFORM 1 FROM public.rr_source_datasets_test71 WHERE id=p_dataset_id AND data_mode='TEST' AND status='DRAFT' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Draft TEST dataset required.';END IF;
 IF p_request_id IS NULL OR nullif(trim(p_source_ref),'') IS NULL OR lower(p_source_sha256) !~ '^[0-9a-f]{64}$' OR p_source_sha256 IS NULL OR p_rows IS NULL OR jsonb_typeof(p_rows)<>'array' OR jsonb_array_length(p_rows) NOT BETWEEN 1 AND 10000 OR octet_length(p_rows::text)>10485760 THEN RAISE EXCEPTION 'Request, source reference, SHA256 and 1–10000 source rows within 10MB required.';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('TEST71_DATASET_SOURCE|'||p_dataset_id::text||'|'||trim(p_source_ref)||'|'||lower(p_source_sha256),0));
 SELECT * INTO b FROM public.rr_dataset_import_batches_test71 WHERE dataset_id=p_dataset_id AND ((created_by=auth.uid() AND request_id=p_request_id) OR (source_ref=trim(p_source_ref) AND source_sha256=lower(p_source_sha256))) ORDER BY created_at LIMIT 1 FOR UPDATE;
 IF b.id IS NOT NULL THEN
  IF b.source_ref<>trim(p_source_ref) OR b.source_sha256<>lower(p_source_sha256) OR b.source_payload IS DISTINCT FROM p_rows THEN RAISE EXCEPTION 'Import request/source already staged with different payload. Supply a new source version.';END IF;
  RETURN public.rr_dataset_import_report_test71(p_dataset_id,b.id)||jsonb_build_object('already_staged',true);
 END IF;
 INSERT INTO public.rr_dataset_import_batches_test71(dataset_id,request_id,source_ref,source_sha256,source_payload,row_count,status,created_by)
 VALUES(p_dataset_id,p_request_id,trim(p_source_ref),lower(p_source_sha256),p_rows,jsonb_array_length(p_rows),'STAGED',auth.uid()) RETURNING * INTO b;
 FOR r IN SELECT j FROM jsonb_array_elements(p_rows) t(j) LOOP
  n:=n+1;d:=NULL;m:=upper(nullif(trim(r->>'module'),''));k:=nullif(trim(r->>'source_key'),'');e:=upper(nullif(trim(r->>'evidence_status'),''));
  v:=coalesce(r->'values','{}'::jsonb);refs:=coalesce(r->'references','[]'::jsonb);
  BEGIN
   IF r->>'record_date' ~ '^\d{4}-\d{2}-\d{2}$' THEN d:=(r->>'record_date')::date;END IF;
  EXCEPTION WHEN others THEN d:=NULL;END;
  INSERT INTO public.rr_dataset_import_rows_test71(batch_id,row_no,module,source_key,record_date,evidence_status,values_json,reference_json,original_row)
  VALUES(b.id,n,m,k,d,e,v,refs,r);
  IF jsonb_typeof(r)<>'object' OR m IS NULL OR k IS NULL OR d IS NULL OR jsonb_typeof(v)<>'object' OR jsonb_typeof(refs)<>'array' OR e IS NULL OR e NOT IN('KNOWN','ZERO','UNKNOWN','NOT_APPLICABLE') THEN
   INSERT INTO public.rr_dataset_import_findings_test71(batch_id,row_no,code,severity,detail) VALUES(b.id,n,'ROW_CONTRACT','ERROR','Object row, module, stable source key, ISO record date, values object, references array and explicit evidence status required.');
  END IF;
  IF m IS NOT NULL AND m NOT IN('CUSTOMERS','SUPPLIERS','WORKERS','ART','PRODUCTS','LEDGERS','OPENING_GL','OPENING_STOCK','OPENING_WIP','CB','MC1','MATERIAL','ACCESSORIES','CUTTING','FABRICATION','PRINTING','STICKER','METAL_ID','STITCHING','OVERLOCK','FOLDING','KAAJ_BUTTON','TEAK_TANKI','THREAD_CUT','QC','PRESS','PACKING','DISPATCH','SALES','RETURNS','RCI','COMMITTEE','ATTENDANCE','PAYROLL','ADVANCE','CLAIM','PAYMENT','RECEIPT') THEN
   INSERT INTO public.rr_dataset_import_findings_test71(batch_id,row_no,code,severity,detail) VALUES(b.id,n,'MODULE_MAPPING','ERROR','Module is outside the approved intake mapping; resolve source module before posting.');
  END IF;
  IF e='UNKNOWN' THEN INSERT INTO public.rr_dataset_import_findings_test71(batch_id,row_no,code,severity,detail) VALUES(b.id,n,'UNKNOWN_EVIDENCE','ERROR','Unknown amount/quantity/history remains unknown; cannot convert to zero or post.');END IF;
  IF e='NOT_APPLICABLE' AND nullif(trim(v->>'reason'),'') IS NULL THEN INSERT INTO public.rr_dataset_import_findings_test71(batch_id,row_no,code,severity,detail) VALUES(b.id,n,'NA_REASON','ERROR','Not-applicable requires an explicit source reason.');END IF;
  IF m='OPENING_GL' AND e IN('KNOWN','ZERO') THEN
   dr:=NULL;cr:=NULL;
   BEGIN IF coalesce((v->>'debit') ~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$',false) AND coalesce((v->>'credit') ~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$',false) THEN dr:=(v->>'debit')::numeric;cr:=(v->>'credit')::numeric;END IF;EXCEPTION WHEN others THEN NULL;END;
   IF nullif(trim(v->>'ledger_key'),'') IS NULL OR dr IS NULL OR cr IS NULL OR dr::text IN('NaN','Infinity','-Infinity') OR cr::text IN('NaN','Infinity','-Infinity') OR dr<0 OR cr<0 OR (dr>0 AND cr>0) OR (e='ZERO' AND (dr<>0 OR cr<>0)) THEN
    INSERT INTO public.rr_dataset_import_findings_test71(batch_id,row_no,code,severity,detail) VALUES(b.id,n,'OPENING_GL_VALUES','ERROR','Opening requires ledger key and explicit nonnegative debit/credit; ZERO must contain exact zeros.');
   END IF;
  END IF;
  IF m IN('OPENING_STOCK','OPENING_WIP') AND e IN('KNOWN','ZERO') THEN
   qty:=NULL;value_amount:=NULL;
   BEGIN IF coalesce((v->>'quantity') ~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$',false) AND coalesce((v->>'value') ~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$',false) THEN qty:=(v->>'quantity')::numeric;value_amount:=(v->>'value')::numeric;END IF;EXCEPTION WHEN others THEN NULL;END;
   IF nullif(trim(v->>'item_key'),'') IS NULL OR nullif(trim(v->>'unit'),'') IS NULL OR qty IS NULL OR value_amount IS NULL OR qty::text IN('NaN','Infinity','-Infinity') OR value_amount::text IN('NaN','Infinity','-Infinity') OR qty<0 OR value_amount<0 OR (e='ZERO' AND (qty<>0 OR value_amount<>0)) THEN
    INSERT INTO public.rr_dataset_import_findings_test71(batch_id,row_no,code,severity,detail) VALUES(b.id,n,'OPENING_STOCK_VALUES','ERROR','Stock/WIP requires stable item key, unit, explicit nonnegative quantity/value; ZERO must contain exact zeros.');
   END IF;
  END IF;
 END LOOP;
 INSERT INTO public.rr_dataset_import_findings_test71(batch_id,row_no,code,severity,detail)
 SELECT b.id,min(row_no),'DUPLICATE_SOURCE_KEY','ERROR','Duplicate module/source key within supplied data.'
 FROM public.rr_dataset_import_rows_test71 WHERE batch_id=b.id AND module IS NOT NULL AND source_key IS NOT NULL GROUP BY module,source_key HAVING count(*)>1;
 FOR x IN SELECT a.row_no,z.ref FROM public.rr_dataset_import_rows_test71 a CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(a.reference_json)='array' THEN a.reference_json ELSE '[]'::jsonb END) z(ref) WHERE a.batch_id=b.id LOOP
  IF jsonb_typeof(x.ref)<>'object' OR NOT EXISTS(SELECT 1 FROM public.rr_dataset_import_rows_test71 t WHERE t.batch_id=b.id AND t.module=upper(x.ref->>'module') AND t.source_key=x.ref->>'source_key') THEN
   INSERT INTO public.rr_dataset_import_findings_test71(batch_id,row_no,code,severity,detail) VALUES(b.id,x.row_no,'UNRESOLVED_SOURCE_REFERENCE','ERROR','Reference does not resolve uniquely to the supplied source rows; existing master mappings require explicit review.');
  END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM public.rr_dataset_import_rows_test71 WHERE batch_id=b.id AND module='OPENING_GL')
 AND NOT EXISTS(SELECT 1 FROM public.rr_dataset_import_findings_test71 WHERE batch_id=b.id AND code IN('OPENING_GL_VALUES','ROW_CONTRACT','UNKNOWN_EVIDENCE')) THEN
  SELECT sum((values_json->>'debit')::numeric),sum((values_json->>'credit')::numeric) INTO opening_dr,opening_cr FROM public.rr_dataset_import_rows_test71 WHERE batch_id=b.id AND module='OPENING_GL' AND evidence_status IN('KNOWN','ZERO');
  IF opening_dr IS DISTINCT FROM opening_cr THEN INSERT INTO public.rr_dataset_import_findings_test71(batch_id,row_no,code,severity,detail) VALUES(b.id,NULL,'OPENING_GL_UNBALANCED','ERROR','Supplied opening debit and credit totals differ.');END IF;
 END IF;
 UPDATE public.rr_dataset_import_batches_test71 SET earliest_date=(SELECT min(record_date) FROM public.rr_dataset_import_rows_test71 WHERE batch_id=b.id),latest_date=(SELECT max(record_date) FROM public.rr_dataset_import_rows_test71 WHERE batch_id=b.id),
 status=CASE WHEN EXISTS(SELECT 1 FROM public.rr_dataset_import_findings_test71 WHERE batch_id=b.id AND severity='ERROR') THEN 'STAGED_WITH_ERRORS' ELSE 'STAGED' END WHERE id=b.id;
 RETURN public.rr_dataset_import_report_test71(p_dataset_id,b.id)||jsonb_build_object('already_staged',false);
END;$$;
REVOKE ALL ON FUNCTION public.rr_dataset_import_stage_test71(uuid,uuid,text,text,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_dataset_import_stage_test71(uuid,uuid,text,text,jsonb) TO authenticated;

COMMENT ON TABLE public.rr_source_datasets_test71 IS 'Isolated TEST source-review datasets. No operational posting activation capability.';
