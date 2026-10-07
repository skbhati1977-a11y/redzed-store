-- Deny direct client access to approval records.
DO $policy$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='rr_customer_auth_test71' AND tablename='login_approvals' AND policyname='no_direct_access') THEN
 CREATE POLICY no_direct_access ON rr_customer_auth_test71.login_approvals AS RESTRICTIVE FOR ALL TO PUBLIC USING(false) WITH CHECK(false);
 END IF;
END $policy$;
-- Protect direct TEST customer rows even when a client skips the RPC layer.
CREATE OR REPLACE FUNCTION public.rr_customer_row_access_test71(p_share_id uuid,p_write boolean DEFAULT false)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $row$
DECLARE s public.rr_market_share_v9420%rowtype;
BEGIN
 SELECT * INTO s FROM public.rr_market_share_v9420 WHERE id=p_share_id;
 IF s.id IS NULL THEN RETURN false; END IF;
 IF s.data_mode<>'TEST' OR public.rr_market_share_relation_v81(s.token)='DISTRIBUTOR_CUSTOMER' THEN RETURN true; END IF;
 IF p_write THEN
  RETURN auth.uid() IS NOT NULL AND EXISTS(SELECT 1 FROM public.rr_user_profiles p WHERE p.auth_user_id=auth.uid() AND p.is_active AND upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE' AND (
   upper(coalesce(p.role_code,'')) IN('SUPER_ADMIN','OWNER') OR EXISTS(SELECT 1 FROM public.rr_customer_chat_members_v9433 m JOIN public.rr_customer_chat_v9433 ch ON ch.id=m.chat_id WHERE m.profile_id=p.id AND m.is_active AND ch.customer_id=s.customer_id AND ch.data_mode=s.data_mode AND (s.origin_chat_id IS NULL OR ch.id=s.origin_chat_id))));
 END IF;
 PERFORM public.rr_customer_access_assert_test71(s.token);
 RETURN true;
EXCEPTION WHEN others THEN RETURN false;
END $row$;
CREATE OR REPLACE FUNCTION public.rr_customer_requirement_row_access_test71(p_requirement_id uuid,p_write boolean DEFAULT false)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path TO '' AS $row$
 SELECT coalesce((SELECT public.rr_customer_row_access_test71(r.share_id,p_write) FROM public.rr_market_requirements_v9420 r WHERE r.id=p_requirement_id),false)
$row$;
REVOKE ALL ON FUNCTION public.rr_customer_row_access_test71(uuid,boolean),public.rr_customer_requirement_row_access_test71(uuid,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rr_customer_row_access_test71(uuid,boolean),public.rr_customer_requirement_row_access_test71(uuid,boolean) TO anon,authenticated,service_role;
ALTER TABLE public.rr_market_share_v9420 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rr_market_share_lots_v9420 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rr_market_requirements_v9420 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rr_market_requirement_lines_v9420 ENABLE ROW LEVEL SECURITY;
DO $policies$
DECLARE t text; expression text; write_expression text;
BEGIN
 FOREACH t IN ARRAY ARRAY['rr_market_share_v9420','rr_market_share_lots_v9420','rr_market_requirements_v9420','rr_market_requirement_lines_v9420'] LOOP
  expression:=CASE WHEN t='rr_market_share_v9420' THEN 'public.rr_customer_row_access_test71(id,false)'
    WHEN t='rr_market_requirement_lines_v9420' THEN 'public.rr_customer_requirement_row_access_test71(requirement_id,false)'
    ELSE 'public.rr_customer_row_access_test71(share_id,false)' END;
  write_expression:=replace(expression,',false)',',true)');
  EXECUTE format('CREATE POLICY customer_test71_read ON public.%I FOR SELECT TO anon,authenticated USING (%s)',t,expression);
  EXECUTE format('CREATE POLICY customer_test71_insert ON public.%I FOR INSERT TO anon,authenticated WITH CHECK (%s)',t,write_expression);
  EXECUTE format('CREATE POLICY customer_test71_update ON public.%I FOR UPDATE TO anon,authenticated USING (%s) WITH CHECK (%s)',t,write_expression,write_expression);
  EXECUTE format('CREATE POLICY customer_test71_delete ON public.%I FOR DELETE TO anon,authenticated USING (%s)',t,write_expression);
 END LOOP;
END $policies$;
