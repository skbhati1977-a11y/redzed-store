-- Preserve and explicitly reconcile only the verified two synthetic guard-test records.
ALTER TABLE test71_security.independent_financial_runs DROP CONSTRAINT independent_financial_runs_status_check;
ALTER TABLE test71_security.independent_financial_runs ADD CONSTRAINT independent_financial_runs_status_check CHECK(status IN('RUNNING','COMPLETE','BLOCKED','RECONCILED'));
DO $reconcile$
DECLARE n integer;
BEGIN
 IF EXISTS(SELECT 1 FROM auth.users WHERE raw_app_meta_data->>'fixture'='test71-independent-financial') OR EXISTS(SELECT 1 FROM public.rr_user_profiles WHERE access_reason LIKE 'test71-independent-financial:%') THEN RAISE EXCEPTION 'Auth/profile fixture reconciliation required before synthetic cleanup.';END IF;
 SELECT count(*) INTO n FROM test71_security.independent_financial_runs WHERE operator_user_id='893c58dd-420b-4dfa-aff7-844e20e634c5'::uuid AND status IN('COMPLETE','BLOCKED') AND proof=jsonb_build_object('roles','[]'::jsonb,'run_id',id,'complete',false);
 IF n<>2 THEN RAISE EXCEPTION 'Expected exactly two verified synthetic guard records, found %.',n;END IF;
 UPDATE test71_security.independent_financial_runs SET proof=proof||jsonb_build_object('reconciliation',jsonb_build_object('source','post_apply_synthetic_guard_test','verified_auth_fixture_count',0,'verified_profile_fixture_count',0,'original_status',status,'reconciled_at',now())),status='RECONCILED'
 WHERE operator_user_id='893c58dd-420b-4dfa-aff7-844e20e634c5'::uuid AND status IN('COMPLETE','BLOCKED') AND proof=jsonb_build_object('roles','[]'::jsonb,'run_id',id,'complete',false);
END $reconcile$;

CREATE OR REPLACE FUNCTION public.rr_test71_independent_financial_claim()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE r test71_security.independent_financial_runs%rowtype;identity jsonb;
BEGIN
 IF auth.uid() IS DISTINCT FROM '893c58dd-420b-4dfa-aff7-844e20e634c5'::uuid THEN RAISE EXCEPTION 'Permission required' USING ERRCODE='42501';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.rr_user_profiles WHERE auth_user_id=auth.uid() AND is_active AND access_status='ACTIVE' AND upper(role_code)='SUPER_ADMIN') THEN RAISE EXCEPTION 'Active Super Admin required' USING ERRCODE='42501';END IF;
 identity:=public.rr_upm_effective_identity_v200();
 IF identity->>'resolved_role' IS DISTINCT FROM 'SUPER_ADMIN' OR coalesce((identity->>'on_behalf')::boolean,true) OR identity->>'operator_user_id' IS DISTINCT FROM auth.uid()::text OR identity->>'effective_auth_user_id' IS DISTINCT FROM auth.uid()::text THEN RAISE EXCEPTION 'Independent Super Admin required' USING ERRCODE='42501';END IF;
 PERFORM pg_advisory_xact_lock(71001114430);
 SELECT * INTO r FROM test71_security.independent_financial_runs WHERE status<>'RECONCILED' ORDER BY created_at DESC LIMIT 1;
 IF FOUND THEN
  IF r.status IN('RUNNING','BLOCKED') THEN RETURN jsonb_build_object('claimed',false,'status',r.status,'run_id',r.id,'proof',r.proof);END IF;
  IF r.created_at>now()-interval '10 minutes' THEN RETURN jsonb_build_object('claimed',false,'status','CACHED','run_id',r.id,'proof',r.proof);END IF;
 END IF;
 INSERT INTO test71_security.independent_financial_runs(operator_user_id,status) VALUES(auth.uid(),'RUNNING') RETURNING * INTO r;
 RETURN jsonb_build_object('claimed',true,'status','RUNNING','run_id',r.id);
END $f$;
