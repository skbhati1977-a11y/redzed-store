CREATE TABLE rr_customer_auth_test71.customer_permissions(customer_id uuid PRIMARY KEY REFERENCES public.rr_customers(id),paused boolean NOT NULL DEFAULT false,changed_at timestamptz NOT NULL DEFAULT now(),changed_by uuid);
ALTER TABLE rr_customer_auth_test71.customer_permissions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON rr_customer_auth_test71.customer_permissions FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.rr_customer_permission_cards_test71()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE result jsonb;
BEGIN
 PERFORM public.rr_chat_assert_superadmin_v9433();
 SELECT coalesce(jsonb_agg(data ORDER BY customer_name),'[]'::jsonb) INTO result FROM(
 SELECT c.customer_name,jsonb_build_object('customer_id',c.id,'customer_name',c.customer_name,'registered_mobile',right(regexp_replace(coalesce(c.mobile,''),'[^0-9]','','g'),10),'discount_per_piece',coalesce(c.allowed_discount_per_piece,0),'paused',coalesce(p.paused,false),'devices',coalesce((SELECT jsonb_agg(jsonb_build_object('request_id',a.id,'requested_name',a.requested_name,'requested_mobile',a.registered_mobile,'status',a.status,'requested_at',a.requested_at,'device_label',right(a.id::text,6)) ORDER BY a.requested_at DESC) FROM rr_customer_auth_test71.login_approvals a WHERE a.customer_id=c.id),'[]'::jsonb)) data
 FROM public.rr_customers c LEFT JOIN rr_customer_auth_test71.customer_permissions p ON p.customer_id=c.id
 WHERE c.is_active AND (EXISTS(SELECT 1 FROM public.rr_customer_chat_v9433 ch WHERE ch.customer_id=c.id AND ch.data_mode='TEST') OR EXISTS(SELECT 1 FROM public.rr_market_share_v9420 s WHERE s.customer_id=c.id AND s.data_mode='TEST'))
 )q;RETURN result;
END $fn$;
REVOKE ALL ON FUNCTION public.rr_customer_permission_cards_test71() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_customer_permission_cards_test71() TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.rr_customer_permission_set_test71(p_customer_id uuid,p_action text,p_discount numeric DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE action text:=upper(trim(p_action));result jsonb;
BEGIN
 PERFORM public.rr_chat_assert_superadmin_v9433();
 IF NOT EXISTS(SELECT 1 FROM public.rr_customer_chat_v9433 ch WHERE ch.customer_id=p_customer_id AND ch.data_mode='TEST') AND NOT EXISTS(SELECT 1 FROM public.rr_market_share_v9420 s WHERE s.customer_id=p_customer_id AND s.data_mode='TEST') THEN RAISE EXCEPTION 'Customer is outside TEST71';END IF;
 IF action IN('PAUSE','RESUME') THEN
  INSERT INTO rr_customer_auth_test71.customer_permissions(customer_id,paused,changed_by) VALUES(p_customer_id,action='PAUSE',auth.uid()) ON CONFLICT(customer_id) DO UPDATE SET paused=excluded.paused,changed_at=clock_timestamp(),changed_by=excluded.changed_by;
 ELSIF action='REVOKE' THEN
  UPDATE rr_customer_auth_test71.login_approvals SET status='REVOKED',verified_registered_mobile=false,decided_at=clock_timestamp(),decided_by=(SELECT id FROM public.rr_user_profiles WHERE auth_user_id=auth.uid() LIMIT 1) WHERE customer_id=p_customer_id;
  UPDATE public.rr_customer_session_v9590 SET revoked_at=clock_timestamp() WHERE customer_id=p_customer_id AND data_mode='TEST' AND revoked_at IS NULL;
 ELSIF action='DISCOUNT' THEN
  result:=public.rr_market_set_customer_discount_v9423(p_customer_id,p_discount);
 ELSE RAISE EXCEPTION 'Invalid customer permission action';END IF;
 RETURN jsonb_build_object('customer_id',p_customer_id,'action',action,'discount',result);
END $fn$;
REVOKE ALL ON FUNCTION public.rr_customer_permission_set_test71(uuid,text,numeric) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_customer_permission_set_test71(uuid,text,numeric) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rr_customer_session_validate_v9590(p_session_token text, p_device_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r public.rr_customer_session_v9590%rowtype; h text; dh text;
begin
 if nullif(trim(coalesce(p_session_token,'')),'') is null then raise exception 'Customer session required.'; end if;
 h:=encode(extensions.digest(trim(p_session_token),'sha256'),'hex');
 select * into r from public.rr_customer_session_v9590 where session_token_hash=h and revoked_at is null and expires_at>now() limit 1;
 if r.id is null then raise exception 'Customer session invalid or expired.'; end if;
 if r.device_id_hash is not null then
   if nullif(trim(coalesce(p_device_id,'')),'') is null then raise exception 'Trusted device binding required.'; end if;
   dh:=encode(extensions.digest(trim(p_device_id),'sha256'),'hex');
   if dh<>r.device_id_hash then raise exception 'Trusted device does not match.'; end if;
 end if;
 if r.data_mode='TEST' and exists(select 1 from rr_customer_auth_test71.customer_permissions p where p.customer_id=r.customer_id and p.paused) then raise exception 'Customer access paused by Super Admin.';end if;
 if r.data_mode='TEST' and exists(select 1 from public.rr_market_share_v9420 s where s.id=r.share_id and public.rr_market_share_relation_v81(s.token)<>'DISTRIBUTOR_CUSTOMER') then
   if not exists(select 1 from rr_customer_auth_test71.login_approvals a join public.rr_customers c on c.id=a.customer_id and c.is_active
     where a.customer_id=r.customer_id and a.device_id_hash=r.device_id_hash and a.status='APPROVED' and a.verified_registered_mobile
       and a.registered_mobile=right(regexp_replace(coalesce(c.mobile,''),'[^0-9]','','g'),10)) then
     raise exception 'Super Admin approval required for this device.';
   end if;
 end if;
 update public.rr_customer_session_v9590 set last_seen_at=now() where id=r.id;
 return jsonb_build_object('valid',true,'customer_id',r.customer_id,'chat_id',r.chat_id,'share_id',r.share_id,'data_mode',r.data_mode,'expires_at',r.expires_at);
end$function$;
