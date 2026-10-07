CREATE OR REPLACE FUNCTION public.rr_customer_permission_cards_test71()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE result jsonb;
BEGIN
 PERFORM public.rr_chat_assert_superadmin_v9433();
 SELECT coalesce(jsonb_agg(data ORDER BY customer_name),'[]'::jsonb) INTO result FROM(
 SELECT c.customer_name,jsonb_build_object('customer_id',c.id,'customer_name',c.customer_name,'registered_mobile',right(regexp_replace(coalesce(c.mobile,''),'[^0-9]','','g'),10),'discount_per_piece',coalesce(c.allowed_discount_per_piece,0),'discount_effective_from',(SELECT h.effective_from FROM public.rr_customer_discount_history_v9420 h WHERE h.customer_id=c.id ORDER BY h.effective_from DESC,h.created_at DESC LIMIT 1),'paused',coalesce(p.paused,false),'devices',coalesce((SELECT jsonb_agg(jsonb_build_object('request_id',a.id,'requested_name',a.requested_name,'requested_mobile',a.registered_mobile,'status',a.status,'requested_at',a.requested_at,'device_label',right(a.id::text,6)) ORDER BY a.requested_at DESC) FROM rr_customer_auth_test71.login_approvals a WHERE a.customer_id=c.id),'[]'::jsonb)) data
 FROM public.rr_customers c LEFT JOIN rr_customer_auth_test71.customer_permissions p ON p.customer_id=c.id
 WHERE c.is_active AND (EXISTS(SELECT 1 FROM public.rr_customer_chat_v9433 ch WHERE ch.customer_id=c.id AND ch.data_mode='TEST') OR EXISTS(SELECT 1 FROM public.rr_market_share_v9420 s WHERE s.customer_id=c.id AND s.data_mode='TEST'))
 )q;RETURN result;
END $function$;

CREATE TABLE rr_customer_auth_test71.partner_discount_history(
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
 owner_customer_id uuid NOT NULL REFERENCES public.rr_customers(id),
 partner_customer_id uuid NOT NULL REFERENCES public.rr_market_partner_customer_v67(id),
 margin_amount numeric NOT NULL,discount_per_piece numeric NOT NULL,
 effective_from timestamptz NOT NULL DEFAULT clock_timestamp(),changed_by uuid);
ALTER TABLE rr_customer_auth_test71.partner_discount_history ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON rr_customer_auth_test71.partner_discount_history FROM PUBLIC,anon,authenticated;
CREATE FUNCTION rr_customer_auth_test71.audit_partner_discount() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
BEGIN
 IF NEW.data_mode='TEST' AND (TG_OP='INSERT' OR coalesce(OLD.default_discount_amount,0) IS DISTINCT FROM coalesce(NEW.default_discount_amount,0) OR coalesce(OLD.default_margin_amount,0) IS DISTINCT FROM coalesce(NEW.default_margin_amount,0)) THEN
 INSERT INTO rr_customer_auth_test71.partner_discount_history(owner_customer_id,partner_customer_id,margin_amount,discount_per_piece,changed_by)
 VALUES(NEW.owner_customer_id,NEW.id,coalesce(NEW.default_margin_amount,0),coalesce(NEW.default_discount_amount,0),auth.uid());
 END IF;RETURN NEW;
END $fn$;
REVOKE ALL ON FUNCTION rr_customer_auth_test71.audit_partner_discount() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER test71_partner_discount_audit AFTER INSERT OR UPDATE OF default_discount_amount,default_margin_amount ON public.rr_market_partner_customer_v67 FOR EACH ROW EXECUTE FUNCTION rr_customer_auth_test71.audit_partner_discount();

