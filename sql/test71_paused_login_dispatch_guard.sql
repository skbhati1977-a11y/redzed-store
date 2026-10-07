CREATE OR REPLACE FUNCTION public.rr_customer_login_push_pending_test71(p_request_id uuid,p_recipient_worker_id uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $fn$
SELECT EXISTS(SELECT 1 FROM rr_customer_auth_test71.login_approvals a WHERE a.id=p_request_id AND a.status='PENDING' AND NOT EXISTS(SELECT 1 FROM rr_customer_auth_test71.customer_permissions cp WHERE cp.customer_id=a.customer_id AND cp.paused)) AND EXISTS(SELECT 1 FROM public.rr_user_profiles p WHERE p.is_active AND upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE' AND upper(p.role_code) IN('SUPER_ADMIN','OWNER') AND coalesce(public.rr_push_worker_id_v712(p.id),p.auth_user_id)=p_recipient_worker_id);
$fn$;
REVOKE ALL ON FUNCTION public.rr_customer_login_push_pending_test71(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rr_customer_login_push_pending_test71(uuid,uuid) TO service_role;
