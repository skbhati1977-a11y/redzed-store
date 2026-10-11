-- No business transaction changes. Private coordination for six bounded TEST Auth fixtures.
CREATE SCHEMA IF NOT EXISTS test71_security;
REVOKE ALL ON SCHEMA test71_security FROM PUBLIC,anon,authenticated;
CREATE TABLE IF NOT EXISTS test71_security.independent_financial_runs(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 operator_user_id uuid NOT NULL,
 status text NOT NULL CHECK(status IN('RUNNING','COMPLETE','BLOCKED')),
 created_at timestamptz NOT NULL DEFAULT now(),
 completed_at timestamptz,
 proof jsonb
);
ALTER TABLE test71_security.independent_financial_runs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON test71_security.independent_financial_runs FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.rr_test71_independent_financial_claim()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE r test71_security.independent_financial_runs%rowtype;identity jsonb;
BEGIN
 IF auth.uid() IS DISTINCT FROM '893c58dd-420b-4dfa-aff7-844e20e634c5'::uuid THEN RAISE EXCEPTION 'Permission required' USING ERRCODE='42501';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.rr_user_profiles WHERE auth_user_id=auth.uid() AND is_active AND access_status='ACTIVE' AND upper(role_code)='SUPER_ADMIN') THEN RAISE EXCEPTION 'Active Super Admin required' USING ERRCODE='42501';END IF;
 identity:=public.rr_upm_effective_identity_v200();
 IF identity->>'resolved_role' IS DISTINCT FROM 'SUPER_ADMIN' OR coalesce((identity->>'on_behalf')::boolean,true) OR identity->>'operator_user_id' IS DISTINCT FROM auth.uid()::text OR identity->>'effective_auth_user_id' IS DISTINCT FROM auth.uid()::text THEN RAISE EXCEPTION 'Independent Super Admin required' USING ERRCODE='42501';END IF;
 PERFORM pg_advisory_xact_lock(71001114430);
 SELECT * INTO r FROM test71_security.independent_financial_runs ORDER BY created_at DESC LIMIT 1;
 IF FOUND THEN
  IF r.status IN('RUNNING','BLOCKED') THEN RETURN jsonb_build_object('claimed',false,'status',r.status,'run_id',r.id,'proof',r.proof);END IF;
  IF r.created_at>now()-interval '10 minutes' THEN RETURN jsonb_build_object('claimed',false,'status','CACHED','run_id',r.id,'proof',r.proof);END IF;
 END IF;
 INSERT INTO test71_security.independent_financial_runs(operator_user_id,status) VALUES(auth.uid(),'RUNNING') RETURNING * INTO r;
 RETURN jsonb_build_object('claimed',true,'status','RUNNING','run_id',r.id);
END $f$;
CREATE OR REPLACE FUNCTION public.rr_test71_independent_financial_finish(p_run_id uuid,p_blocked boolean,p_proof jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE n integer;identity jsonb;
BEGIN
 IF auth.uid() IS DISTINCT FROM '893c58dd-420b-4dfa-aff7-844e20e634c5'::uuid THEN RAISE EXCEPTION 'Permission required' USING ERRCODE='42501';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.rr_user_profiles WHERE auth_user_id=auth.uid() AND is_active AND access_status='ACTIVE' AND upper(role_code)='SUPER_ADMIN') THEN RAISE EXCEPTION 'Active Super Admin required' USING ERRCODE='42501';END IF;
 identity:=public.rr_upm_effective_identity_v200();
 IF identity->>'resolved_role' IS DISTINCT FROM 'SUPER_ADMIN' OR coalesce((identity->>'on_behalf')::boolean,true) OR identity->>'operator_user_id' IS DISTINCT FROM auth.uid()::text OR identity->>'effective_auth_user_id' IS DISTINCT FROM auth.uid()::text THEN RAISE EXCEPTION 'Independent Super Admin required' USING ERRCODE='42501';END IF;
 IF p_blocked IS NULL OR p_proof IS NULL OR octet_length(p_proof::text)>65536 OR jsonb_typeof(p_proof) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Invalid TEST proof';END IF;
 IF p_proof->>'run_id' IS DISTINCT FROM p_run_id::text OR jsonb_typeof(p_proof->'roles') IS DISTINCT FROM 'array' OR jsonb_array_length(p_proof->'roles')>6 THEN RAISE EXCEPTION 'Invalid TEST proof';END IF;
 UPDATE test71_security.independent_financial_runs SET status=CASE WHEN p_blocked THEN 'BLOCKED' ELSE 'COMPLETE' END,completed_at=now(),proof=p_proof WHERE id=p_run_id AND operator_user_id=auth.uid() AND status='RUNNING';
 GET DIAGNOSTICS n=ROW_COUNT;IF n<>1 THEN RAISE EXCEPTION 'Active TEST run required';END IF;
 RETURN jsonb_build_object('stored',true,'blocked',p_blocked);
END $f$;
REVOKE ALL ON FUNCTION public.rr_test71_independent_financial_claim() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.rr_test71_independent_financial_finish(uuid,boolean,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_test71_independent_financial_claim() TO authenticated;
GRANT EXECUTE ON FUNCTION public.rr_test71_independent_financial_finish(uuid,boolean,jsonb) TO authenticated;
