-- TEST-only isolated approval and deterministic posting plan; shared posting remains closed.
CREATE TABLE public.rr_opening_approvals_test71 (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),dataset_id uuid NOT NULL UNIQUE,
 batch_id uuid NOT NULL,request_id uuid NOT NULL,source_ref text NOT NULL,source_sha256 text NOT NULL,
 source_payload jsonb NOT NULL,cutoff date NOT NULL,approval_evidence_ref text NOT NULL CHECK(length(trim(approval_evidence_ref))>0),
 coverage jsonb NOT NULL,ledger_mapping jsonb NOT NULL,item_mapping jsonb NOT NULL,posting_plan jsonb NOT NULL,
 approved_by uuid NOT NULL,approved_at timestamptz NOT NULL DEFAULT now(),data_mode text NOT NULL DEFAULT 'TEST' CHECK(data_mode='TEST'),
 FOREIGN KEY(dataset_id,batch_id) REFERENCES public.rr_dataset_import_batches_test71(dataset_id,id),UNIQUE(dataset_id,request_id)
);
ALTER TABLE public.rr_opening_approvals_test71 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rr_opening_approvals_test71 FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.rr_opening_plan_build_test71(p_dataset_id uuid,p_batch_id uuid,p_cutoff date,p_coverage jsonb,p_ledger_mapping jsonb,p_item_mapping jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE b public.rr_dataset_import_batches_test71%rowtype;report jsonb;r record;x jsonb;mapping jsonb;class text;category text;state text;
 lid uuid;iid uuid;dr numeric;cr numeric;qty numeric;val numeric;total_dr numeric:=0;total_cr numeric:=0;stock numeric:=0;wip numeric:=0;stock_gl numeric:=0;wip_gl numeric:=0;
 lines jsonb:='[]';physical jsonb:='[]';class_totals jsonb:='{}';class_rows jsonb:='{}';stock_rows int:=0;wip_rows int:=0;
BEGIN
 PERFORM public.rr_import_admin_assert_test71();
 report:=public.rr_dataset_import_report_test71(p_dataset_id,p_batch_id);
 SELECT * INTO b FROM public.rr_dataset_import_batches_test71 WHERE dataset_id=p_dataset_id AND id=p_batch_id FOR SHARE;
 IF b.id IS NULL OR b.status<>'STAGED' OR jsonb_array_length(coalesce(report->'findings','[]'))>0 THEN RAISE EXCEPTION 'Source batch must be staged without unresolved findings.';END IF;
 IF p_cutoff IS NULL OR p_cutoff IS DISTINCT FROM b.earliest_date THEN RAISE EXCEPTION 'Approved opening cutoff must match earliest supplied source date.';END IF;
 IF jsonb_typeof(p_coverage) IS DISTINCT FROM 'object' OR jsonb_typeof(p_ledger_mapping) IS DISTINCT FROM 'object' OR jsonb_typeof(p_item_mapping) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Explicit coverage and approved master mappings required.';END IF;
 FOR category IN SELECT unnest(ARRAY['CASH_BANK','RECEIVABLES','PAYABLES','ADVANCES','SALARY_PAYABLE','CLAIMS','STOCK','WIP','EQUITY','OTHER']) LOOP
  x:=p_coverage->category;state:=x->>'state';
  IF state IS NULL OR state NOT IN('KNOWN','ZERO','NOT_APPLICABLE') OR nullif(trim(x->>'evidence_ref'),'') IS NULL OR (state='NOT_APPLICABLE' AND nullif(trim(x->>'reason'),'') IS NULL) THEN RAISE EXCEPTION 'Complete explicit approved coverage required for %; UNKNOWN cannot be approved.',category;END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM jsonb_each(p_ledger_mapping) m GROUP BY m.value->>'ledger_id' HAVING count(DISTINCT m.value->>'class')>1) THEN RAISE EXCEPTION 'One ledger cannot map to conflicting opening classes.';END IF;
 FOR r IN SELECT * FROM public.rr_dataset_import_rows_test71 WHERE batch_id=b.id ORDER BY row_no LOOP
  IF r.module NOT IN('OPENING_GL','OPENING_STOCK','OPENING_WIP') THEN CONTINUE;END IF;
  IF r.record_date IS DISTINCT FROM p_cutoff THEN RAISE EXCEPTION 'Opening row % differs from approved cutoff.',r.row_no;END IF;
  IF r.evidence_status='NOT_APPLICABLE' THEN
   IF EXISTS(SELECT 1 FROM jsonb_each(r.values_json) f WHERE f.key IN('debit','credit','quantity','value') AND f.value<>'null'::jsonb AND (f.value#>>'{}') !~ '^0+(\.0+)?$') THEN RAISE EXCEPTION 'Not-applicable opening cannot hide a quantity or value.';END IF;
   CONTINUE;END IF;
  IF r.evidence_status NOT IN('KNOWN','ZERO') THEN RAISE EXCEPTION 'Unknown opening row cannot be approved.';END IF;
  IF r.module='OPENING_GL' THEN
   mapping:=p_ledger_mapping->(r.values_json->>'ledger_key');class:=mapping->>'class';
   IF class IS NULL OR class NOT IN('CASH_BANK','RECEIVABLES','PAYABLES','ADVANCES','SALARY_PAYABLE','CLAIMS','STOCK','WIP','EQUITY','OTHER') OR NOT p_coverage ? class OR nullif(trim(mapping->>'evidence_ref'),'') IS NULL THEN RAISE EXCEPTION 'Approved ledger class/reference mapping required for row %.',r.row_no;END IF;
   lid:=(mapping->>'ledger_id')::uuid;
   IF NOT EXISTS(SELECT 1 FROM public.rr_ledgers_v805 WHERE id=lid AND is_active) THEN RAISE EXCEPTION 'Approved active ledger missing for row %.',r.row_no;END IF;
   IF coalesce(r.values_json->>'debit','') !~ '^\d+(\.\d{1,2})?$' OR coalesce(r.values_json->>'credit','') !~ '^\d+(\.\d{1,2})?$' THEN RAISE EXCEPTION 'Finite exact opening ledger value required.';END IF;
   dr:=(r.values_json->>'debit')::numeric;cr:=(r.values_json->>'credit')::numeric;
   IF dr IS NULL OR cr IS NULL OR dr<0 OR cr<0 OR dr<>round(dr,2) OR cr<>round(cr,2) OR (dr>0 AND cr>0) OR (r.evidence_status='ZERO' AND (dr<>0 OR cr<>0)) THEN RAISE EXCEPTION 'Invalid exact opening ledger value.';END IF;
   IF p_coverage->class->>'state'='NOT_APPLICABLE' OR (p_coverage->class->>'state'='ZERO' AND (dr<>0 OR cr<>0)) THEN RAISE EXCEPTION 'Ledger values conflict with approved coverage.';END IF;
   class_totals:=jsonb_set(class_totals,ARRAY[class],to_jsonb(coalesce((class_totals->>class)::numeric,0)+dr+cr));
   class_rows:=jsonb_set(class_rows,ARRAY[class],to_jsonb(coalesce((class_rows->>class)::int,0)+1));
   total_dr:=total_dr+dr;total_cr:=total_cr+cr;
   IF class='STOCK' THEN stock_gl:=stock_gl+dr-cr;END IF;IF class='WIP' THEN wip_gl:=wip_gl+dr-cr;END IF;
   IF dr+cr>0 THEN lines:=lines||jsonb_build_array(jsonb_build_object('ledger_id',lid,'dr',dr,'cr',cr,'source_key',r.source_key,'class',class));END IF;
  ELSE
   mapping:=p_item_mapping->(r.values_json->>'item_key');iid:=(mapping->>'master_id')::uuid;
   IF iid IS NULL OR mapping->>'kind' IS NULL OR mapping->>'kind' NOT IN('MATERIAL','PRODUCT') OR nullif(trim(mapping->>'evidence_ref'),'') IS NULL OR NOT ((mapping->>'kind'='MATERIAL' AND EXISTS(SELECT 1 FROM public.rr_material_master_v805 WHERE id=iid AND is_active)) OR (mapping->>'kind'='PRODUCT' AND EXISTS(SELECT 1 FROM public.rr_product_master WHERE id=iid AND is_active))) THEN RAISE EXCEPTION 'Approved active material/product item mapping required for row %.',r.row_no;END IF;
   IF coalesce(r.values_json->>'quantity','') !~ '^\d+(\.\d+)?$' OR coalesce(r.values_json->>'value','') !~ '^\d+(\.\d{1,2})?$' THEN RAISE EXCEPTION 'Finite exact opening physical value required.';END IF;
   qty:=(r.values_json->>'quantity')::numeric;val:=(r.values_json->>'value')::numeric;
   IF qty IS NULL OR val IS NULL OR qty<0 OR val<0 OR val<>round(val,2) OR (qty=0 AND val<>0) OR (r.evidence_status='ZERO' AND (qty<>0 OR val<>0)) OR nullif(trim(r.values_json->>'unit'),'') IS NULL THEN RAISE EXCEPTION 'Invalid opening physical quantity/unit/value.';END IF;
   class:=CASE WHEN r.module='OPENING_STOCK' THEN 'STOCK' ELSE 'WIP' END;
   IF p_coverage->class->>'state'='NOT_APPLICABLE' OR (p_coverage->class->>'state'='ZERO' AND (qty<>0 OR val<>0)) THEN RAISE EXCEPTION 'Physical values conflict with approved coverage.';END IF;
   IF class='STOCK' THEN stock:=stock+val;stock_rows:=stock_rows+1;ELSE wip:=wip+val;wip_rows:=wip_rows+1;END IF;
   physical:=physical||jsonb_build_array(jsonb_build_object('source_key',r.source_key,'module',r.module,'master_id',iid,'kind',mapping->>'kind','quantity',qty,'unit',r.values_json->>'unit','value',val));
  END IF;
 END LOOP;
 FOR category IN SELECT unnest(ARRAY['CASH_BANK','RECEIVABLES','PAYABLES','ADVANCES','SALARY_PAYABLE','CLAIMS','STOCK','WIP','EQUITY','OTHER']) LOOP
  state:=p_coverage->category->>'state';
  IF state IN('KNOWN','ZERO') AND coalesce((class_rows->>category)::int,0)=0 THEN RAISE EXCEPTION 'Explicit ledger source rows required for % coverage.',category;END IF;
  IF state='KNOWN' AND coalesce((class_totals->>category)::numeric,0)=0 THEN RAISE EXCEPTION 'KNOWN financial coverage requires nonzero evidence; use explicit ZERO for %.',category;END IF;
 END LOOP;
 IF p_coverage->'STOCK'->>'state'<>'NOT_APPLICABLE' AND stock_rows=0 OR p_coverage->'WIP'->>'state'<>'NOT_APPLICABLE' AND wip_rows=0 THEN RAISE EXCEPTION 'Explicit physical STOCK/WIP opening rows required.';END IF;
 IF total_dr<>total_cr THEN RAISE EXCEPTION 'Opening GL is not balanced.';END IF;
 IF stock<>stock_gl OR wip<>wip_gl THEN RAISE EXCEPTION 'Opening physical STOCK/WIP does not reconcile to approved GL.';END IF;
 RETURN jsonb_build_object('dataset_id',p_dataset_id,'batch_id',b.id,'data_mode','TEST','source_ref',b.source_ref,'source_sha256',b.source_sha256,'cutoff',p_cutoff,'ledger_postings',lines,'physical_openings',physical,'total_debit',total_dr,'total_credit',total_cr,'stock_value',stock,'stock_gl',stock_gl,'wip_value',wip,'wip_gl',wip_gl,'reconciled',true,'cleared_for_import',false,'business_records_posted',0,'posting_gate','DOWNSTREAM_ARCHIVE_READER_AND_AGGREGATE_SCOPE_NOT_VERIFIED');
END;$$;
REVOKE ALL ON FUNCTION public.rr_opening_plan_build_test71(uuid,uuid,date,jsonb,jsonb,jsonb) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.rr_opening_approve_test71(p_dataset_id uuid,p_batch_id uuid,p_request_id uuid,p_cutoff date,p_approval_evidence_ref text,p_coverage jsonb,p_ledger_mapping jsonb,p_item_mapping jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE a public.rr_opening_approvals_test71%rowtype;b public.rr_dataset_import_batches_test71%rowtype;plan jsonb;
BEGIN
 PERFORM public.rr_import_admin_assert_test71();
 IF p_request_id IS NULL OR nullif(trim(p_approval_evidence_ref),'') IS NULL THEN RAISE EXCEPTION 'Approval request and business approval evidence reference required.';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('TEST71_OPENING_APPROVAL|'||p_dataset_id::text,0));
 SELECT * INTO b FROM public.rr_dataset_import_batches_test71 WHERE dataset_id=p_dataset_id AND id=p_batch_id FOR SHARE;
 IF b.id IS NULL THEN RAISE EXCEPTION 'Isolated source batch not found.';END IF;
 SELECT * INTO a FROM public.rr_opening_approvals_test71 WHERE dataset_id=p_dataset_id;
 IF a.id IS NOT NULL THEN
  IF a.batch_id IS DISTINCT FROM p_batch_id OR a.request_id IS DISTINCT FROM p_request_id OR a.cutoff IS DISTINCT FROM p_cutoff OR a.approval_evidence_ref IS DISTINCT FROM trim(p_approval_evidence_ref) OR a.coverage IS DISTINCT FROM p_coverage OR a.ledger_mapping IS DISTINCT FROM p_ledger_mapping OR a.item_mapping IS DISTINCT FROM p_item_mapping OR a.source_payload IS DISTINCT FROM b.source_payload THEN RAISE EXCEPTION 'Approved opening is immutable; changed source or approval requires separately reviewed source version/dataset.';END IF;
  RETURN a.posting_plan||jsonb_build_object('approval_id',a.id,'approved_by',a.approved_by,'approved_at',a.approved_at,'approval_status','APPROVED_PLAN_ONLY','already_approved',true);
 END IF;
 plan:=public.rr_opening_plan_build_test71(p_dataset_id,p_batch_id,p_cutoff,p_coverage,p_ledger_mapping,p_item_mapping);
 INSERT INTO public.rr_opening_approvals_test71(dataset_id,batch_id,request_id,source_ref,source_sha256,source_payload,cutoff,approval_evidence_ref,coverage,ledger_mapping,item_mapping,posting_plan,approved_by)
 VALUES(p_dataset_id,b.id,p_request_id,b.source_ref,b.source_sha256,b.source_payload,p_cutoff,trim(p_approval_evidence_ref),p_coverage,p_ledger_mapping,p_item_mapping,plan,auth.uid()) RETURNING * INTO a;
 RETURN plan||jsonb_build_object('approval_id',a.id,'approved_by',a.approved_by,'approved_at',a.approved_at,'approval_status','APPROVED_PLAN_ONLY','already_approved',false);
END;$$;
REVOKE ALL ON FUNCTION public.rr_opening_approve_test71(uuid,uuid,uuid,date,text,jsonb,jsonb,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_opening_approve_test71(uuid,uuid,uuid,date,text,jsonb,jsonb,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.rr_opening_approval_report_test71(p_dataset_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE a public.rr_opening_approvals_test71%rowtype;
BEGIN
 PERFORM public.rr_import_admin_assert_test71();SELECT * INTO a FROM public.rr_opening_approvals_test71 WHERE dataset_id=p_dataset_id;
 IF a.id IS NULL THEN RETURN jsonb_build_object('dataset_id',p_dataset_id,'approval_status','NOT_APPROVED','cleared_for_import',false,'business_records_posted',0);END IF;
 RETURN a.posting_plan||jsonb_build_object('approval_id',a.id,'approved_by',a.approved_by,'approved_at',a.approved_at,'approval_evidence_ref',a.approval_evidence_ref,'approval_status','APPROVED_PLAN_ONLY');
END;$$;
REVOKE ALL ON FUNCTION public.rr_opening_approval_report_test71(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_opening_approval_report_test71(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.rr_opening_post_test71(p_dataset_id uuid,p_approval_id uuid,p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
 PERFORM public.rr_import_admin_assert_test71();
 IF p_request_id IS NULL THEN RAISE EXCEPTION 'Posting request required.';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.rr_opening_approvals_test71 WHERE dataset_id=p_dataset_id AND id=p_approval_id) THEN RAISE EXCEPTION 'Approved isolated opening plan required.';END IF;
 RAISE EXCEPTION 'Opening posting blocked: downstream archive readers and financial aggregates are not verified for this dataset.' USING ERRCODE='55000';
END;$$;
REVOKE ALL ON FUNCTION public.rr_opening_post_test71(uuid,uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_opening_post_test71(uuid,uuid,uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_opening_approval_immutable_test71() RETURNS trigger LANGUAGE plpgsql SET search_path TO '' AS $$ BEGIN RAISE EXCEPTION 'Approved opening evidence is immutable.'; END;$$;
REVOKE ALL ON FUNCTION public.rr_opening_approval_immutable_test71() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER rr_opening_approval_immutable_test71 BEFORE UPDATE OR DELETE ON public.rr_opening_approvals_test71 FOR EACH ROW EXECUTE FUNCTION public.rr_opening_approval_immutable_test71();
COMMENT ON TABLE public.rr_opening_approvals_test71 IS 'Immutable TEST isolated opening approval evidence and reconciled plan only. No shared financial/stock posting.';
