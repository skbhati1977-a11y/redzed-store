-- TEST direct-customer approval; production and distributor authorities remain unchanged.
CREATE SCHEMA IF NOT EXISTS rr_customer_auth_test71;
REVOKE ALL ON SCHEMA rr_customer_auth_test71 FROM PUBLIC,anon,authenticated;
CREATE TABLE IF NOT EXISTS rr_customer_auth_test71.login_approvals (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 customer_id uuid NOT NULL REFERENCES public.rr_customers(id),
 device_id_hash text NOT NULL,
 registered_mobile text NOT NULL,
 requested_name text NOT NULL,
 share_id uuid NOT NULL REFERENCES public.rr_market_share_v9420(id),
 status text NOT NULL DEFAULT 'PENDING' CHECK(status IN('PENDING','APPROVED','REJECTED','REVOKED')),
 requested_at timestamptz NOT NULL DEFAULT now(),
 decided_at timestamptz,
 decided_by uuid REFERENCES public.rr_user_profiles(id),
 verified_registered_mobile boolean NOT NULL DEFAULT false,
 UNIQUE(customer_id,device_id_hash)
);
ALTER TABLE rr_customer_auth_test71.login_approvals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON rr_customer_auth_test71.login_approvals FROM PUBLIC,anon,authenticated;
CREATE INDEX IF NOT EXISTS login_approvals_pending_idx ON rr_customer_auth_test71.login_approvals(status,requested_at);

CREATE OR REPLACE FUNCTION public.rr_customer_login_hint_test71(p_token text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE s public.rr_market_share_v9420%rowtype; c public.rr_customers%rowtype;
BEGIN
 SELECT * INTO s FROM public.rr_market_share_v9420 WHERE (token=p_token OR short_code=upper(trim(p_token))) AND status='ACTIVE' LIMIT 1;
 IF s.id IS NULL THEN RAISE EXCEPTION 'Collection link unavailable.'; END IF;
 SELECT * INTO c FROM public.rr_customers WHERE id=s.customer_id AND is_active;
 RETURN jsonb_build_object('customer_name',coalesce(c.customer_name,s.customer_name),'approval_required',s.data_mode='TEST');
END $fn$;

CREATE OR REPLACE FUNCTION public.rr_customer_login_request_test71(p_token text,p_customer_name text,p_mobile text,p_device_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE s public.rr_market_share_v9420%rowtype; c public.rr_customers%rowtype;
 a rr_customer_auth_test71.login_approvals%rowtype;
 mobile text:=regexp_replace(coalesce(p_mobile,''),'[^0-9]','','g'); dh text;
BEGIN
 SELECT * INTO s FROM public.rr_market_share_v9420 WHERE (token=p_token OR short_code=upper(trim(p_token))) AND status='ACTIVE' ORDER BY CASE WHEN token=p_token THEN 0 ELSE 1 END LIMIT 1;
 IF s.id IS NULL THEN RAISE EXCEPTION 'Collection link unavailable.'; END IF;
 IF s.data_mode<>'TEST' OR public.rr_market_share_relation_v81(p_token)='DISTRIBUTOR_CUSTOMER' THEN RAISE EXCEPTION 'This login uses a different customer authority.'; END IF;
 SELECT * INTO c FROM public.rr_customers WHERE id=s.customer_id AND is_active;
 IF c.id IS NULL THEN RAISE EXCEPTION 'Super Admin must assign this link to a registered customer first.'; END IF;
 IF length(mobile)=12 AND left(mobile,2)='91' THEN mobile:=right(mobile,10); END IF;
 IF length(mobile)<>10 OR mobile IS DISTINCT FROM right(regexp_replace(coalesce(c.mobile,''),'[^0-9]','','g'),10) THEN
  RAISE EXCEPTION 'Mobile does not match this customer. Use the original registered number.';
 END IF;
 IF length(trim(coalesce(p_device_id,''))) NOT BETWEEN 24 AND 256 THEN RAISE EXCEPTION 'Trusted device binding required.'; END IF;
 IF nullif(trim(coalesce(p_customer_name,'')),'') IS NULL THEN RAISE EXCEPTION 'Customer name required.'; END IF;
 dh:=encode(extensions.digest(trim(p_device_id),'sha256'),'hex');
 INSERT INTO rr_customer_auth_test71.login_approvals(customer_id,device_id_hash,registered_mobile,requested_name,share_id)
 VALUES(c.id,dh,mobile,left(trim(p_customer_name),120),s.id)
 ON CONFLICT(customer_id,device_id_hash) DO UPDATE SET
  status=CASE WHEN login_approvals.registered_mobile<>excluded.registered_mobile THEN 'PENDING' ELSE login_approvals.status END,
  verified_registered_mobile=CASE WHEN login_approvals.registered_mobile<>excluded.registered_mobile THEN false ELSE login_approvals.verified_registered_mobile END,
  decided_at=CASE WHEN login_approvals.registered_mobile<>excluded.registered_mobile THEN null ELSE login_approvals.decided_at END,
  decided_by=CASE WHEN login_approvals.registered_mobile<>excluded.registered_mobile THEN null ELSE login_approvals.decided_by END,
  requested_at=CASE WHEN login_approvals.registered_mobile<>excluded.registered_mobile THEN now() ELSE login_approvals.requested_at END,
  registered_mobile=excluded.registered_mobile
 RETURNING * INTO a;
 RETURN jsonb_build_object('approval_status',a.status,'request_id',a.id,'customer_name',c.customer_name,'mobile',mobile,'customer_id',c.id,'share_id',s.id);
END $fn$;

CREATE OR REPLACE FUNCTION public.rr_customer_login_status_test71(p_request_id uuid,p_device_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE a rr_customer_auth_test71.login_approvals%rowtype;
BEGIN
 SELECT * INTO a FROM rr_customer_auth_test71.login_approvals WHERE id=p_request_id AND device_id_hash=encode(extensions.digest(trim(coalesce(p_device_id,'')),'sha256'),'hex');
 IF a.id IS NULL THEN RAISE EXCEPTION 'Login request unavailable for this device.'; END IF;
 RETURN jsonb_build_object('approval_status',a.status,'request_id',a.id);
END $fn$;

CREATE OR REPLACE FUNCTION public.rr_customer_login_approval_list_test71()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE result jsonb;
BEGIN
 PERFORM public.rr_chat_assert_superadmin_v9433();
 SELECT coalesce(jsonb_agg(q.data ORDER BY q.requested_at DESC),'[]'::jsonb) INTO result FROM (
  SELECT a.requested_at,jsonb_build_object('request_id',a.id,'customer_name',c.customer_name,'requested_name',a.requested_name,
   'registered_mobile',right(regexp_replace(coalesce(c.mobile,''),'[^0-9]','','g'),10),'requested_mobile',a.registered_mobile,
   'status',a.status,'requested_at',a.requested_at,'decided_at',a.decided_at,'device_label',right(a.id::text,6)) data
  FROM rr_customer_auth_test71.login_approvals a JOIN public.rr_customers c ON c.id=a.customer_id
  ORDER BY (a.status='PENDING') DESC,a.requested_at DESC LIMIT 100
 ) q;
 RETURN result;
END $fn$;

CREATE OR REPLACE FUNCTION public.rr_customer_login_approval_decide_test71(p_request_id uuid,p_decision text,p_mobile_verified boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE a rr_customer_auth_test71.login_approvals%rowtype; actor uuid; decision text:=upper(trim(p_decision)); mobile text;
BEGIN
 PERFORM public.rr_chat_assert_superadmin_v9433();
 SELECT id INTO actor FROM public.rr_user_profiles WHERE auth_user_id=auth.uid() AND is_active AND upper(coalesce(access_status,'ACTIVE'))='ACTIVE' LIMIT 1;
 IF decision NOT IN('APPROVED','REJECTED','REVOKED') THEN RAISE EXCEPTION 'Invalid approval decision.'; END IF;
 SELECT * INTO a FROM rr_customer_auth_test71.login_approvals WHERE id=p_request_id FOR UPDATE;
 IF a.id IS NULL THEN RAISE EXCEPTION 'Login request unavailable.'; END IF;
 SELECT right(regexp_replace(coalesce(c.mobile,''),'[^0-9]','','g'),10) INTO mobile FROM public.rr_customers c WHERE c.id=a.customer_id AND c.is_active;
 IF decision='APPROVED' AND (NOT coalesce(p_mobile_verified,false) OR mobile IS DISTINCT FROM a.registered_mobile) THEN
  RAISE EXCEPTION 'Verify the original registered mobile before approving this device.';
 END IF;
 UPDATE rr_customer_auth_test71.login_approvals SET status=decision,decided_at=now(),decided_by=actor,verified_registered_mobile=(decision='APPROVED') WHERE id=a.id;
 RETURN jsonb_build_object('request_id',a.id,'approval_status',decision);
END $fn$;

CREATE OR REPLACE FUNCTION public.rr_customer_access_assert_test71(p_token text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE s public.rr_market_share_v9420%rowtype; headers jsonb; sx jsonb;
BEGIN
 SELECT * INTO s FROM public.rr_market_share_v9420 WHERE (token=p_token OR short_code=upper(trim(p_token))) AND status='ACTIVE' LIMIT 1;
 IF s.id IS NULL THEN RAISE EXCEPTION 'Collection link unavailable.'; END IF;
 IF s.data_mode<>'TEST' OR public.rr_market_share_relation_v81(p_token)='DISTRIBUTOR_CUSTOMER' THEN RETURN; END IF;
 -- Staff access still requires an active ERP identity and membership or ownership.
 IF auth.uid() IS NOT NULL AND EXISTS(SELECT 1 FROM public.rr_user_profiles p WHERE p.auth_user_id=auth.uid() AND p.is_active AND upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE' AND (
  upper(coalesce(p.role_code,'')) IN('SUPER_ADMIN','OWNER') OR EXISTS(SELECT 1 FROM public.rr_customer_chat_members_v9433 m JOIN public.rr_customer_chat_v9433 ch ON ch.id=m.chat_id WHERE m.profile_id=p.id AND m.is_active AND ch.customer_id=s.customer_id AND ch.data_mode=s.data_mode AND (s.origin_chat_id IS NULL OR ch.id=s.origin_chat_id))
 )) THEN RETURN; END IF;
 headers:=coalesce(nullif(current_setting('request.headers',true),''),'{}')::jsonb;
 sx:=public.rr_customer_session_validate_v9590(headers->>'x-rr-customer-session',headers->>'x-rr-customer-device');
 IF (sx->>'customer_id')::uuid IS DISTINCT FROM s.customer_id OR sx->>'data_mode' IS DISTINCT FROM s.data_mode OR (s.origin_chat_id IS NOT NULL AND (sx->>'chat_id')::uuid IS DISTINCT FROM s.origin_chat_id) THEN
  RAISE EXCEPTION 'Approved session belongs to a different customer.';
 END IF;
END $fn$;

REVOKE ALL ON FUNCTION public.rr_customer_login_hint_test71(text),public.rr_customer_login_request_test71(text,text,text,text),public.rr_customer_login_status_test71(uuid,text),public.rr_customer_login_approval_list_test71(),public.rr_customer_login_approval_decide_test71(uuid,text,boolean),public.rr_customer_access_assert_test71(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rr_customer_login_hint_test71(text),public.rr_customer_login_request_test71(text,text,text,text),public.rr_customer_login_status_test71(uuid,text) TO anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rr_customer_login_approval_list_test71(),public.rr_customer_login_approval_decide_test71(uuid,text,boolean) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION rr_customer_auth_test71.issue_session_legacy(p_token text, p_customer_name text, p_mobile text, p_device_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare s public.rr_market_share_v9420%rowtype; b jsonb; cid uuid; ch uuid; raw text; h text; dh text;
begin
 select * into s from public.rr_market_share_v9420 where (token=p_token or short_code=upper(p_token)) and status='ACTIVE' order by case when token=p_token then 0 else 1 end limit 1;
 if s.id is null then raise exception 'Share link unavailable.'; end if;
 b:=rr_customer_auth_test71.bootstrap_legacy(p_token,p_customer_name,p_mobile);
 cid:=(b->>'customer_id')::uuid; ch:=(b->>'chat_id')::uuid;
 if s.customer_id is not null and s.customer_id<>cid then raise exception 'This secure Collection link belongs to a different customer.'; end if;
 raw:=encode(extensions.gen_random_bytes(32),'hex'); h:=encode(extensions.digest(raw,'sha256'),'hex');
 if nullif(trim(coalesce(p_device_id,'')),'') is not null then dh:=encode(extensions.digest(trim(p_device_id),'sha256'),'hex'); end if;
 insert into public.rr_customer_session_v9590(session_token_hash,customer_id,chat_id,share_id,data_mode,device_id_hash) values(h,cid,ch,s.id,s.data_mode,dh);
 return b||jsonb_build_object('session_token',raw,'expires_in_seconds',2592000,'share_id',s.id);
end$function$
;
REVOKE ALL ON FUNCTION rr_customer_auth_test71.issue_session_legacy(text,text,text,text) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.rr_customer_session_issue_v9590(p_token text,p_customer_name text,p_mobile text,p_device_id text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE s public.rr_market_share_v9420%rowtype; approval jsonb;
BEGIN
 SELECT * INTO s FROM public.rr_market_share_v9420 WHERE (token=p_token OR short_code=upper(trim(p_token))) AND status='ACTIVE' LIMIT 1;
 IF s.data_mode='TEST' AND public.rr_market_share_relation_v81(p_token)<>'DISTRIBUTOR_CUSTOMER' THEN
  approval:=public.rr_customer_login_request_test71(p_token,p_customer_name,p_mobile,p_device_id);
  IF approval->>'approval_status'<>'APPROVED' THEN RETURN approval; END IF;
  RETURN rr_customer_auth_test71.issue_session_legacy(p_token,approval->>'customer_name',approval->>'mobile',p_device_id)||jsonb_build_object('approval_status','APPROVED','customer_name',approval->>'customer_name');
 END IF;
 RETURN rr_customer_auth_test71.issue_session_legacy(p_token,p_customer_name,p_mobile,p_device_id);
END $fn$;

CREATE OR REPLACE FUNCTION public.rr_customer_session_issue_bound_v9680(p_token text, p_customer_name text, p_mobile text, p_device_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_share public.rr_market_share_v9420%rowtype;
  v_customer public.rr_customers%rowtype;
  v_mobile text := right(regexp_replace(coalesce(p_mobile, ''), '[^0-9]', '', 'g'), 10);
  v_result jsonb;
begin
  if exists(select 1 from public.rr_market_share_v9420 where (token=p_token or short_code=upper(trim(p_token))) and status='ACTIVE' and data_mode='TEST') and public.rr_market_share_relation_v81(p_token)<>'DISTRIBUTOR_CUSTOMER' then
    return public.rr_customer_session_issue_v9590(p_token,p_customer_name,p_mobile,p_device_id);
  end if;
  select s.* into v_share
  from public.rr_market_share_v9420 s
  where (s.token = p_token or s.short_code = upper(trim(p_token)))
    and s.status = 'ACTIVE'
  order by case when s.token = p_token then 0 else 1 end
  limit 1;

  if v_share.id is null then
    raise exception 'Collection link unavailable.';
  end if;
  if length(v_mobile) <> 10 then
    raise exception 'Valid 10 digit registered mobile required.';
  end if;

  if v_share.customer_id is not null then
    select c.* into v_customer
    from public.rr_customers c
    where c.id = v_share.customer_id and c.is_active;

    if v_customer.id is null then
      raise exception 'Collection customer is inactive or unavailable.';
    end if;
    if right(regexp_replace(coalesce(v_customer.mobile, ''), '[^0-9]', '', 'g'), 10) <> v_mobile
       and not exists (
         select 1 from public.rr_customer_contact_phone_v67 p
         where p.customer_id = v_customer.id
           and right(regexp_replace(coalesce(p.mobile, ''), '[^0-9]', '', 'g'), 10) = v_mobile
           and p.data_mode = 'TEST'
       ) then
      raise exception 'Mobile does not match the customer assigned to this collection.';
    end if;
  else
    select c.* into v_customer
    from public.rr_customers c
    where c.is_active
      and right(regexp_replace(coalesce(c.mobile, ''), '[^0-9]', '', 'g'), 10) = v_mobile
    order by c.updated_at desc
    limit 1;
  end if;

  v_result := public.rr_customer_session_issue_v9590(
    p_token,
    coalesce(nullif(trim(v_customer.customer_name), ''), nullif(trim(p_customer_name), '')),
    coalesce(nullif(trim(v_customer.mobile), ''), p_mobile),
    p_device_id
  );

  return coalesce(v_result, '{}'::jsonb) || jsonb_build_object(
    'customer_id', v_customer.id,
    'customer_name', coalesce(nullif(trim(v_customer.customer_name), ''), nullif(trim(p_customer_name), '')),
    'share_id', v_share.id
  );
end
$function$
;

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
 if r.data_mode='TEST' and exists(select 1 from public.rr_market_share_v9420 s where s.id=r.share_id and public.rr_market_share_relation_v81(s.token)<>'DISTRIBUTOR_CUSTOMER') then
   if not exists(select 1 from rr_customer_auth_test71.login_approvals a join public.rr_customers c on c.id=a.customer_id and c.is_active
     where a.customer_id=r.customer_id and a.device_id_hash=r.device_id_hash and a.status='APPROVED' and a.verified_registered_mobile
       and a.registered_mobile=right(regexp_replace(coalesce(c.mobile,''),'[^0-9]','','g'),10)) then
     raise exception 'Super Admin approval required for this device.';
   end if;
 end if;
 update public.rr_customer_session_v9590 set last_seen_at=now() where id=r.id;
 return jsonb_build_object('valid',true,'customer_id',r.customer_id,'chat_id',r.chat_id,'share_id',r.share_id,'data_mode',r.data_mode,'expires_at',r.expires_at);
end$function$
;

-- Existing rr_market_share_snapshot_test71 retains its domain logic; only add the access gate.
CREATE OR REPLACE FUNCTION public.rr_market_share_snapshot_test71(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  s public.rr_market_share_v9420%rowtype;
  v_map public.rr_market_partner_collection_v67%rowtype;
  v_current public.rr_market_partner_collection_v67%rowtype;
  v_latest public.rr_market_partner_order_v67%rowtype;
  v_root uuid;
  rows jsonb;
  v_header text;
  v_collections jsonb;
  v_requirements jsonb;
  v_requirement jsonb;
  v_pi jsonb;
  v_ci jsonb;
begin
 perform public.rr_customer_access_assert_test71(p_token);
  select * into s from public.rr_market_share_v9420
  where (token=p_token or short_code=upper(p_token)) and status='ACTIVE'
  order by case when token=p_token then 0 else 1 end limit 1;
  if not found then raise exception 'Share link unavailable.'; end if;
  update public.rr_market_share_v9420 set last_opened_at=now() where id=s.id;
  select * into v_map from public.rr_market_partner_collection_v67 where share_id=s.id;
  if v_map.id is null then
    select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object(
      'cloth_name',r.cloth_name,'category',r.category,'size_text',r.size_text,'item_name',r.item_name
    ) order by l.sort_no),'[]'::jsonb) into rows
    from public.rr_market_share_lots_v9420 l
    cross join lateral public.rr_web_window_snapshot_test71(l.lot_no,null,null,s.data_mode,1,0)c
    cross join lateral public.rr_web_lot_fields_resolve_v9624(l.lot_no,s.data_mode)r
    where l.share_id=s.id and c.lot_no=l.lot_no;
    return jsonb_build_object('share_id',s.id,'customer_name',s.customer_name,'created_at',s.created_at,
      'rows',rows,'header_title','REDZED · COLLECTION','collections','[]'::jsonb,
      'requirements','[]'::jsonb,'requirement_locked',false);
  end if;

  v_root:=coalesce(v_map.root_collection_id,v_map.id);
  select pc.* into v_current from public.rr_market_partner_collection_v67 pc
  where coalesce(pc.root_collection_id,pc.id)=v_root
  order by pc.collection_update_no desc,pc.created_at desc limit 1;
  v_header:=public.rr_market_partner_header_v67(v_map.owner_customer_id,v_map.partner_customer_id);
  select o.* into v_latest from public.rr_market_partner_order_v67 o
  join public.rr_market_partner_collection_v67 pc on pc.id=o.collection_id
  where coalesce(pc.root_collection_id,pc.id)=v_root and o.status<>'SUPERSEDED'
  order by o.requirement_update_no desc,o.created_at desc limit 1;

  with latest_line as(
    select distinct on(l.lot_no) l.*,pc.collection_update_no
    from public.rr_market_partner_collection_v67 pc
    join public.rr_market_partner_collection_line_v67 l on l.collection_id=pc.id
    where coalesce(pc.root_collection_id,pc.id)=v_root
    order by l.lot_no,pc.collection_update_no desc,l.created_at desc
  )
  select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object(
    'cloth_name',coalesce(pl.cloth_name,r.cloth_name),'category',coalesce(pl.category,r.category),
    'size_text',coalesce(pl.size_text,r.size_text),'item_name',r.item_name,'media',pl.media,
    'sale_rate',pl.final_customer_rate,'display_sale_rate',pl.distributor_sale_rate,
    'discount_amount',pl.discount_amount,'stock_status',pl.stock_status,'hide_exact_stock',true
  ) order by pl.collection_update_no desc,pl.created_at desc),'[]'::jsonb) into rows
  from latest_line pl
  cross join lateral public.rr_web_window_snapshot_test71(pl.lot_no,null,null,'TEST',1,0)c
  cross join lateral public.rr_web_lot_fields_resolve_v9624(pl.lot_no,'TEST')r
  where c.lot_no=pl.lot_no;

  v_collections:=jsonb_build_array(jsonb_build_object(
    'id',v_root,'display_no','COLLECTION '||v_current.collection_no::text||
      case when v_current.collection_update_no>0 then ' · UPDATE '||v_current.collection_update_no::text else '' end,
    'created_at',v_current.created_at,'lines',(
      with latest_line as(
        select distinct on(l.lot_no) l.*,pc.collection_update_no
        from public.rr_market_partner_collection_v67 pc
        join public.rr_market_partner_collection_line_v67 l on l.collection_id=pc.id
        where coalesce(pc.root_collection_id,pc.id)=v_root
        order by l.lot_no,pc.collection_update_no desc,l.created_at desc
      ) select coalesce(jsonb_agg(jsonb_build_object(
        'lot_no',l.lot_no,'category',l.category,'size_text',l.size_text,
        'image_url',l.primary_image_url,'stock_status',l.stock_status,
        'sale_rate',l.distributor_sale_rate,'discount',l.discount_amount,
        'final_rate',l.final_customer_rate
      ) order by l.collection_update_no desc,l.created_at desc),'[]'::jsonb) from latest_line l
    )
  ));
  if v_latest.id is not null then
    v_requirements:=jsonb_build_array(jsonb_build_object(
      'id',v_latest.id,'display_no',v_latest.requirement_display_no,'status',v_latest.status,
      'created_at',v_latest.created_at,'closed_at',v_latest.customer_closed_at,
      'redzed_pushed_at',v_latest.redzed_pushed_at,'lines',(
        select coalesce(jsonb_agg(jsonb_build_object(
          'id',l.id,'lot_no',l.lot_no,'category',l.category,'size_text',l.size_text,
          'image_url',l.image_url,'qty',l.requested_qty,'rate',l.final_customer_rate
        ) order by l.lot_no),'[]'::jsonb)
        from public.rr_market_partner_order_line_v67 l where l.order_id=v_latest.id
      )
    ));
    v_requirement:=jsonb_build_object('id',v_latest.id,'display_no',v_latest.requirement_display_no,
      'status',v_latest.status,'can_update',v_latest.status='DRAFT','can_close',v_latest.status='DRAFT',
      'customer_closed_at',v_latest.customer_closed_at,'redzed_pushed_at',v_latest.redzed_pushed_at);
    if v_latest.customer_pi_visible and v_latest.pi_ref is not null then
      v_pi:=(select jsonb_build_object('ref',o.pi_ref,'status',o.customer_pi_status,'note',o.customer_pi_note,
        'lines',(select jsonb_agg(jsonb_build_object(
          'id',l.id,'lot_no',l.lot_no,'category',l.category,'size_text',l.size_text,
          'image_url',l.image_url,'requested_qty',l.requested_qty,
          'proposed_qty',coalesce(l.proposed_qty,l.requested_qty),'rate',l.final_customer_rate,
          'decision',l.customer_pi_decision,'customer_qty',l.customer_pi_qty
        ) order by l.lot_no) from public.rr_market_partner_order_line_v67 l where l.order_id=o.id))
      from public.rr_market_partner_order_v67 o where o.id=v_latest.id);
    end if;
    if v_latest.customer_ci_visible and v_latest.ci_ref is not null then
      v_ci:=(select jsonb_build_object('ref',o.ci_ref,'pi_ref',o.pi_ref,
        'lines',(select jsonb_agg(jsonb_build_object(
          'lot_no',l.lot_no,'category',l.category,'size_text',l.size_text,'image_url',l.image_url,
          'qty',coalesce(l.confirmed_qty,l.customer_pi_qty,l.proposed_qty,l.requested_qty),
          'rate',l.final_customer_rate
        ) order by l.lot_no) from public.rr_market_partner_order_line_v67 l where l.order_id=o.id))
      from public.rr_market_partner_order_v67 o where o.id=v_latest.id);
    end if;
  else
    v_requirements:='[]'::jsonb;
  end if;
  return jsonb_build_object('share_id',s.id,'customer_name',s.customer_name,'created_at',s.created_at,
    'rows',rows,'header_title',v_header,'collection_display_no',v_current.collection_display_no,
    'collections',v_collections,'requirements',v_requirements,'requirement',v_requirement,
    'pi',v_pi,'ci',v_ci,'requirement_locked',coalesce(v_latest.status<>'DRAFT',false));
end
$function$
;

-- Existing rr_collection_current_state_v9633 retains its domain logic; only add the access gate.
CREATE OR REPLACE FUNCTION public.rr_collection_current_state_v9633(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cyid uuid; cy public.rr_collection_cycle_v9586%rowtype; n integer; cn integer; rn integer;
begin
 perform public.rr_customer_access_assert_test71(p_token);
  cyid:=public.rr_collection_cycle_for_share_v9631(p_token);
  select * into cy from public.rr_collection_cycle_v9586 where id=cyid;
  if cy.data_mode='TEST' and exists(select 1 from public.rr_customer_chat_v9433 ch where ch.id=cy.chat_id and ch.customer_id=cy.customer_id and ch.relation_kind='DIRECT_CUSTOMER') then
    select newest.id into cyid from public.rr_collection_cycle_v9586 newest left join lateral (select max(s.created_at) sent_at from public.rr_collection_send_v9586 cs join public.rr_market_share_v9420 s on s.id=cs.share_id where cs.collection_cycle_id=newest.id) latest on true where newest.chat_id=cy.chat_id and newest.customer_id=cy.customer_id and newest.data_mode='TEST' order by greatest(newest.created_at,coalesce(latest.sent_at,newest.created_at)) desc,newest.id desc limit 1;
    select * into cy from public.rr_collection_cycle_v9586 where id=cyid;
  end if;
  select greatest(
    coalesce((select max(update_no) from public.rr_collection_activity_v9633 where collection_cycle_id=cyid),0),
    coalesce((select max(update_no) from public.rr_collection_update_request_v9630 where collection_cycle_id=cyid),0)
  ) into n;
  select greatest(coalesce(max(send_seq),1)-1,0) into cn
  from public.rr_collection_send_v9586 where collection_cycle_id=cyid;
  select coalesce(max(r.requirement_update_no),0) into rn
  from public.rr_market_requirements_v9420 r where r.collection_cycle_id=cyid;
  return jsonb_build_object('collection_cycle_id',cy.id,'collection_display_no',cy.display_no,
    'collection_status',cy.status,'update_no',n,'collection_update_no',cn,'requirement_update_no',rn,'requirement_response_collection_update_no',coalesce((select greatest(coalesce((select max(cs.send_seq) from public.rr_collection_send_v9586 cs where cs.collection_cycle_id=cy.id and cs.sent_at<=a.created_at),1)-1,0) from public.rr_collection_activity_v9633 a where a.collection_cycle_id=cy.id and a.activity_kind in('REQUIREMENT','REQUIREMENT_UPDATE') order by a.created_at desc,a.update_no desc limit 1),-1),'update_history',public.rr_direct_cycle_history_test71(cy.id))||public.rr_direct_cycle_live_meta_test71(cy.id)||jsonb_build_object('latest_collection_token',(select s.token from public.rr_collection_send_v9586 cs join public.rr_market_share_v9420 s on s.id=cs.share_id where cs.collection_cycle_id=cy.id and s.status='ACTIVE' order by cs.send_seq desc limit 1));
end $function$
;

-- Existing rr_collection_customer_requirement_summary_v9778 retains its domain logic; only add the access gate.
CREATE OR REPLACE FUNCTION public.rr_collection_customer_requirement_summary_v9778(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_share public.rr_market_share_v9420%rowtype; v_cycle uuid; v_lines jsonb;
begin
 perform public.rr_customer_access_assert_test71(p_token);
  select * into v_share from public.rr_market_share_v9420 where (token=p_token or short_code=upper(p_token)) and status='ACTIVE'
  order by case when token=p_token then 0 else 1 end limit 1;
  if v_share.id is null then raise exception 'INVALID_COLLECTION_TOKEN'; end if;
  select cs.collection_cycle_id into v_cycle from public.rr_collection_send_v9586 cs where cs.share_id=v_share.id limit 1;
  v_cycle:=coalesce(v_cycle,v_share.origin_collection_cycle_id);
  if v_cycle is null then return jsonb_build_object('collection_cycle_id',null,'lines','[]'::jsonb); end if;
  v_lines:=public.rr_collection_requirement_snapshot_test71(v_cycle);
  return jsonb_build_object('collection_cycle_id',v_cycle,'lines',v_lines);
end $function$
;

-- Existing rr_collection_customer_pricing_v9637 retains its domain logic; only add the access gate.
CREATE OR REPLACE FUNCTION public.rr_collection_customer_pricing_v9637(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
 v_share rr_market_share_v9420%rowtype;
 v_discount numeric:=0;
 v_rows jsonb;
begin
 perform public.rr_customer_access_assert_test71(p_token);
 select * into v_share from rr_market_share_v9420 where token=p_token limit 1;
 if v_share.id is null then raise exception 'INVALID_COLLECTION_TOKEN'; end if;
 select coalesce(allowed_discount_per_piece,0) into v_discount from rr_customers where id=v_share.customer_id;
 with allowed_lots as (
   select distinct l.lot_no
   from rr_collection_cycle_v9586 c
   join rr_collection_send_v9586 cs on cs.collection_cycle_id=c.id
   join rr_market_share_lots_v9420 l on l.share_id=cs.share_id
   where c.customer_id=v_share.customer_id and c.chat_id is not distinct from (
     select chat_id from rr_collection_cycle_v9586 where customer_id=v_share.customer_id and status not in ('CLOSED','CANCELLED') order by created_at desc limit 1
   )
   union
   select lot_no from rr_market_share_lots_v9420 where share_id=v_share.id
 ), priced as (
   select a.lot_no,
          coalesce(
            (select r.approved_rate from rr_pi_internal_rrq_v9517 r where r.lot_no=a.lot_no and r.approved_rate is not null order by r.created_at desc limit 1),
            (select u.sale_rate from rr_universal_sale_lot_v849 u where u.lot_no=a.lot_no and u.sale_rate is not null order by u.sale_rate desc limit 1)
          )::numeric as approved_rate
   from allowed_lots a
 )
 select coalesce(jsonb_agg(jsonb_build_object(
   'lot_no',lot_no,
   'approved_rate',approved_rate,
   'allowed_discount',v_discount,
   'net_rate',case when approved_rate is null then null else greatest(approved_rate-v_discount,0) end,
   'pricing_status',case when approved_rate is null then 'UNRESOLVED' else 'RESOLVED' end
 ) order by lot_no),'[]'::jsonb) into v_rows from priced;
 return jsonb_build_object('customer_id',v_share.customer_id,'allowed_discount_per_piece',v_discount,'rows',v_rows);
end $function$
;

-- Existing rr_collection_customer_ci_history_v9641 retains its domain logic; only add the access gate.
CREATE OR REPLACE FUNCTION public.rr_collection_customer_ci_history_v9641(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  s public.rr_market_share_v9420%rowtype;
  c public.rr_customers%rowtype;
  v_name text;
  v_mobile text;
  v_buyer_ids uuid[];
  v_ci_count integer:=0;
  v_qty numeric:=0;
  v_value numeric:=0;
  v_unresolved boolean:=false;
begin
 perform public.rr_customer_access_assert_test71(p_token);
  select * into s
  from public.rr_market_share_v9420
  where (token=p_token or short_code=upper(p_token)) and status='ACTIVE'
  order by case when token=p_token then 0 else 1 end
  limit 1;
  if s.id is null then raise exception 'Share link unavailable.'; end if;
  if s.customer_id is null then
    return jsonb_build_object('status','CUSTOMER_UNRESOLVED','history_ci_count',0,'history_qty',null,'history_net_value',null,'history_avg_per_pc',null);
  end if;

  select * into c from public.rr_customers where id=s.customer_id limit 1;
  if c.id is null then
    return jsonb_build_object('status','CUSTOMER_UNRESOLVED','history_ci_count',0,'history_qty',null,'history_net_value',null,'history_avg_per_pc',null);
  end if;

  v_name:=regexp_replace(lower(trim(coalesce(c.customer_name,''))),'\s+',' ','g');
  v_mobile:=regexp_replace(coalesce(c.mobile,''),'\D','','g');

  select array_agg(distinct b.id) into v_buyer_ids
  from public.rr_buyers_v787 b
  where exists (
          select 1 from public.rr_fg_pi_v787 p
          where p.buyer_id=b.id and p.status='CI_FINAL' and upper(coalesce(p.data_mode,''))=upper(coalesce(s.data_mode,''))
            and coalesce(p.buyer_snapshot->>'contact_customer_id','')=c.id::text
        )
     or (
          length(v_mobile)>=10
          and right(regexp_replace(coalesce(b.contact_no,''),'\D','','g'),10)=right(v_mobile,10)
        )
     or (
          v_name<>''
          and regexp_replace(lower(trim(coalesce(b.buyer_name,''))),'\s+',' ','g')=v_name
          and (select count(*) from public.rr_buyers_v787 bx where bx.active is true and regexp_replace(lower(trim(coalesce(bx.buyer_name,''))),'\s+',' ','g')=v_name)=1
          and (select count(*) from public.rr_customers cx where regexp_replace(lower(trim(coalesce(cx.customer_name,''))),'\s+',' ','g')=v_name)=1
        );

  if coalesce(array_length(v_buyer_ids,1),0)=0 then
    return jsonb_build_object('status','NO_CI_HISTORY','history_ci_count',0,'history_qty',null,'history_net_value',null,'history_avg_per_pc',null);
  end if;

  with ci as (
    select p.id
    from public.rr_fg_pi_v787 p
    where p.status='CI_FINAL'
      and upper(coalesce(p.data_mode,''))=upper(coalesce(s.data_mode,''))
      and p.buyer_id=any(v_buyer_ids)
  ), lines as (
    select ci.id as ci_id,
           greatest(coalesce(l.qty,0)-coalesce(l.returned_qty,0),0)::numeric as net_qty,
           l.final_rate
    from ci
    join public.rr_fg_pi_lines_v787 l on l.pi_id=ci.id
  )
  select (select count(*) from ci),
         coalesce(sum(net_qty),0),
         coalesce(sum(case when final_rate is not null then net_qty*final_rate else 0 end),0),
         coalesce(bool_or(net_qty>0 and final_rate is null),false)
  into v_ci_count,v_qty,v_value,v_unresolved
  from lines;

  if v_ci_count=0 or v_qty<=0 then
    return jsonb_build_object('status','NO_CI_HISTORY','history_ci_count',v_ci_count,'history_qty',null,'history_net_value',null,'history_avg_per_pc',null);
  end if;
  if v_unresolved then
    return jsonb_build_object('status','UNRESOLVED_CI_PRICING','history_ci_count',v_ci_count,'history_qty',v_qty,'history_net_value',null,'history_avg_per_pc',null);
  end if;

  return jsonb_build_object(
    'status','RESOLVED',
    'history_ci_count',v_ci_count,
    'history_qty',v_qty,
    'history_net_value',v_value,
    'history_avg_per_pc',round(v_value/nullif(v_qty,0),2)
  );
end $function$
;

-- Existing rr_collection_cycle_share_view_v9686 retains its domain logic; only add the access gate.
CREATE OR REPLACE FUNCTION public.rr_collection_cycle_share_view_v9686(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_cycle public.rr_collection_cycle_v9586%rowtype; v_data jsonb;
 v_rows jsonb:='[]'::jsonb; v_update integer:=0; x record; summary jsonb; newest uuid;
begin
 perform public.rr_customer_access_assert_test71(p_token);
 select c.* into v_cycle from public.rr_market_share_v9420 s
 join public.rr_collection_send_v9586 cs on cs.share_id=s.id
 join public.rr_collection_cycle_v9586 c on c.id=cs.collection_cycle_id
 where (s.token=p_token or s.short_code=upper(p_token)) and s.status='ACTIVE'
 order by case when s.token=p_token then 0 else 1 end limit 1;
 if v_cycle.id is null then return public.rr_market_share_view_v9420(p_token); end if;
 for x in select s.token,cs.send_seq from public.rr_collection_send_v9586 cs
  join public.rr_market_share_v9420 s on s.id=cs.share_id
  where cs.collection_cycle_id=v_cycle.id and s.status='ACTIVE' order by cs.send_seq
 loop
  v_data:=public.rr_market_share_view_v9420(x.token);
  v_rows:=v_rows||coalesce(v_data->'rows','[]'::jsonb);
  v_update:=greatest(v_update,x.send_seq-1);
 end loop;

 summary:=public.rr_collection_customer_requirement_summary_v9778(p_token);
 select cs.share_id into newest from public.rr_collection_send_v9586 cs where cs.collection_cycle_id=v_cycle.id
 order by cs.send_seq desc limit 1;
 select coalesce(jsonb_agg(q.val||jsonb_build_object('requested_qty',coalesce(r.qty,0))
  order by case when exists(select 1 from public.rr_market_share_lots_v9420 l where l.share_id=newest and l.lot_no=q.val->>'lot_no') then 0
   when coalesce(r.qty,0)>0 then 1 else 2 end,q.ord),'[]'::jsonb) into v_rows from (
  select distinct on (e.value->>'lot_no') e.value val,e.ordinality ord
  from jsonb_array_elements(v_rows) with ordinality e(value,ordinality)
  order by e.value->>'lot_no',e.ordinality desc
 ) q left join lateral (
  select (l->>'requested_qty')::integer qty from jsonb_array_elements(summary->'lines') l
   where l->>'lot_no'=q.val->>'lot_no' limit 1
 ) r on true;
 return coalesce(v_data,'{}'::jsonb)||jsonb_build_object('rows',v_rows,
  'collection_cycle_id',v_cycle.id,'collection_no',v_cycle.collection_no,
  'collection_display_no',v_cycle.display_no,'collection_update_no',v_update);
end $function$
;

-- Existing rr_direct_collection_submit_requirement_v9684 retains its domain logic; only add the access gate.
CREATE OR REPLACE FUNCTION public.rr_direct_collection_submit_requirement_v9684(p_token text, p_customer_name text, p_mobile text, p_message text, p_lines jsonb, p_requirement_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_result jsonb;v_req public.rr_market_requirements_v9420%rowtype;v_cycle public.rr_collection_cycle_v9586%rowtype;
 v_share public.rr_market_share_v9420%rowtype;v_effective uuid:=p_requirement_id;v_root uuid;v_message uuid;v_body text;
begin
 perform public.rr_customer_access_assert_test71(p_token);
 select * into v_share from public.rr_market_share_v9420 s
 where(s.token=p_token or s.short_code=upper(p_token))and s.status='ACTIVE'
 order by case when s.token=p_token then 0 else 1 end limit 1 for update;
 if v_share.id is null then raise exception 'Share link unavailable.';end if;
 -- Adopt a verified TEST outside share into the existing direct Collection flow.
 -- Never adopt distributor links, another customer's share, or a conflicting route.
 if v_share.data_mode='TEST' and v_share.origin_relation_kind is null then
   if exists(select 1 from public.rr_market_partner_collection_v67 pc where pc.share_id=v_share.id) then
     raise exception 'This collection belongs to the distributor flow.';
   end if;
   declare cj jsonb; cid uuid; ch uuid; cn integer;
   begin
     cj:=public.rr_market_register_customer_v9423(p_customer_name,p_mobile);
     cid:=(cj->>'customer_id')::uuid;
     if cid is null or (v_share.customer_id is not null and v_share.customer_id<>cid) then
       raise exception 'Collection belongs to another customer.';
     end if;
     select id into ch from public.rr_customer_chat_v9433
       where customer_id=cid and data_mode='TEST' and status='OPEN' and relation_kind='DIRECT_CUSTOMER'
       order by created_at asc limit 1;
     if ch is null or (v_share.origin_chat_id is not null and v_share.origin_chat_id<>ch) then
       raise exception 'Collection is not bound to this Customer chat.';
     end if;
     select c.* into v_cycle from public.rr_collection_send_v9586 cs
       join public.rr_collection_cycle_v9586 c on c.id=cs.collection_cycle_id where cs.share_id=v_share.id limit 1;
     if v_cycle.id is not null and (v_cycle.customer_id<>cid or v_cycle.chat_id<>ch or v_cycle.data_mode<>'TEST') then
       raise exception 'Collection customer route mismatch.';
     end if;
     if v_cycle.id is null then
       perform pg_advisory_xact_lock(hashtextextended(cid::text||'|TEST|COLLECTION_ADOPT',9628));
       select coalesce(max(collection_no),0)+1 into cn from public.rr_collection_cycle_v9586
         where customer_id=cid and data_mode='TEST';
       insert into public.rr_collection_cycle_v9586(customer_id,chat_id,data_mode,collection_no,display_no,status,opened_at,created_by)
         values(cid,ch,'TEST',cn,'RZ COLLECTION '||lpad(cn::text,2,'0'),'OPENED_NO_RESPONSE',now(),auth.uid())
         returning * into v_cycle;
       insert into public.rr_collection_send_v9586(collection_cycle_id,share_id,send_seq,send_kind,sent_by)
         values(v_cycle.id,v_share.id,1,'FIRST',auth.uid());
     end if;
     update public.rr_market_share_v9420 set customer_id=cid,origin_relation_kind='DIRECT_CUSTOMER',origin_chat_id=ch
       where id=v_share.id returning * into v_share;
   end;
 end if;
 select c.* into v_cycle from public.rr_collection_send_v9586 cs
 join public.rr_collection_cycle_v9586 c on c.id=cs.collection_cycle_id where cs.share_id=v_share.id limit 1;
 if v_cycle.id is null or v_share.origin_relation_kind is distinct from 'DIRECT_CUSTOMER'
   or v_share.origin_chat_id is distinct from v_cycle.chat_id
 then raise exception 'Direct Collection routing is unavailable.';end if;
 perform pg_advisory_xact_lock(hashtextextended(v_cycle.id::text||'|DIRECT_REQUIREMENT',9714));
 if v_effective is null then
   select r.id into v_effective from public.rr_collection_requirement_link_v9586 l
   join public.rr_market_requirements_v9420 r on r.id=l.requirement_id
   where l.collection_cycle_id=v_cycle.id
     and coalesce(r.lifecycle_stage,r.status,'') not in('SUPERSEDED','CI_FINAL','CANCELLED')
     and r.pi_generated_at is null
   order by r.submitted_at desc,r.id desc limit 1;
 end if;
 v_result:=public.rr_collection_submit_requirement_v9588(
   p_token,p_customer_name,p_mobile,p_message,p_lines,v_effective);
 select * into v_cycle from public.rr_collection_cycle_v9586 where id=(v_result->>'collection_cycle_id')::uuid;

 update public.rr_collection_activity_v9633 a set payload=coalesce(a.payload,'{}')||jsonb_build_object(
  'previous_lines',v_result->'previous_lines','requirement_lines',v_result->'lines')
 where a.collection_cycle_id=v_cycle.id and a.reference_id=(v_result->>'requirement_id')::uuid
  and a.update_no=(v_result->>'update_no')::integer;
 v_req:=public.rr_direct_requirement_identity_v9685((v_result->>'requirement_id')::uuid,v_cycle.id,v_effective is not null);
 if v_req.id is null or v_cycle.id is null or v_req.customer_id<>v_cycle.customer_id then raise exception 'Canonical Requirement cycle unavailable.';end if;
 v_root:=coalesce(v_req.root_requirement_id,v_req.id);
 v_body:='[REQ:'||v_req.id::text||'] '||v_req.requirement_display_no||' · '||coalesce(v_result->>'lot_count','0')||' styles · '||coalesce(v_result->>'total_qty','0')||' pcs';
 select m.id into v_message from public.rr_customer_chat_messages_v9433 m
 where m.chat_id=v_cycle.chat_id and m.channel='GROUP' and m.archived_at is null
   and(m.payload->>'direct_collection_cycle_id'=v_cycle.id::text or m.payload->>'direct_requirement_root_id'=v_root::text)
 order by m.created_at desc,m.id desc limit 1 for update;
 if v_message is null then
   insert into public.rr_customer_chat_messages_v9433(chat_id,channel,sender_kind,sender_customer_id,sender_name,message_type,body,payload)
   values(v_cycle.chat_id,'GROUP','CUSTOMER',v_req.customer_id,v_req.customer_name,'REQUIREMENT',v_body,
    jsonb_build_object('source','DIRECT_MARKET_REQUIREMENT','requirement_id',v_req.id,'direct_requirement_root_id',v_root,
     'direct_collection_cycle_id',v_cycle.id,'requirement_display_no',v_req.requirement_display_no,
     'requirement_update_no',v_req.requirement_update_no,'lot_count',(v_result->>'lot_count')::integer,
     'total_qty',(v_result->>'total_qty')::integer)) returning id into v_message;
 else
   update public.rr_customer_chat_messages_v9433 set body=v_body,message_type='REQUIREMENT',
    payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object('source','DIRECT_MARKET_REQUIREMENT','requirement_id',v_req.id,
     'direct_requirement_root_id',v_root,'direct_collection_cycle_id',v_cycle.id,'requirement_display_no',v_req.requirement_display_no,
     'requirement_update_no',v_req.requirement_update_no,'lot_count',(v_result->>'lot_count')::integer,
     'total_qty',(v_result->>'total_qty')::integer),created_at=clock_timestamp(),archived_at=null,archive_reason=null,archive_meta='{}'::jsonb
   where id=v_message;
 end if;
 update public.rr_customer_chat_messages_v9433 m set archived_at=clock_timestamp(),archive_reason='DIRECT_REQUIREMENT_SUPERSEDED_SINGLE_CARD',
  archive_meta=coalesce(m.archive_meta,'{}'::jsonb)||jsonb_build_object('canonical_message_id',v_message,'collection_cycle_id',v_cycle.id)
 where m.chat_id=v_cycle.chat_id and m.id<>v_message and m.archived_at is null and m.message_type='REQUIREMENT'
   and(m.payload->>'direct_collection_cycle_id'=v_cycle.id::text or m.payload->>'requirement_id'=v_req.id::text);
 return v_result||jsonb_build_object('chat_message_id',v_message,'requirement_root_id',v_root,
   'requirement_display_no',v_req.requirement_display_no,'requirement_update_no',v_req.requirement_update_no,
   'relation_kind','DIRECT_CUSTOMER','chat_id',v_cycle.chat_id);
end $function$
;

-- Existing rr_collection_customer_close_v9630 retains its domain logic; only add the access gate.
CREATE OR REPLACE FUNCTION public.rr_collection_customer_close_v9630(p_token text, p_reason text DEFAULT 'CUSTOMER CLOSE REQUIREMENT'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  cy public.rr_collection_cycle_v9586%rowtype; has_pi boolean; cyid uuid;
begin
 perform public.rr_customer_access_assert_test71(p_token);
  cyid:=public.rr_collection_cycle_for_share_v9631(p_token);
  select * into cy from public.rr_collection_cycle_v9586 where id=cyid for update;
  select exists(select 1 from public.rr_collection_requirement_link_v9586 l join public.rr_fg_pi_v787 p on p.market_requirement_id=l.requirement_id where l.collection_cycle_id=cy.id) into has_pi;
  if has_pi then raise exception 'PI already exists. Close/cancel from the highest stage.'; end if;
  update public.rr_collection_cycle_v9586 set status='CLOSED',closed_at=now(),close_reason=coalesce(nullif(trim(p_reason),''),'CUSTOMER CLOSE REQUIREMENT') where id=cy.id;
  update public.rr_collection_update_request_v9630 set status='CANCELLED',closed_at=now() where collection_cycle_id=cy.id and status='OPEN';
  return jsonb_build_object('collection_cycle_id',cy.id,'collection_display_no',cy.display_no,'status','CLOSED','close_reason',coalesce(nullif(trim(p_reason),''),'CUSTOMER CLOSE REQUIREMENT'));
end;
$function$
;

-- Existing rr_collection_more_samples_request_v9630 retains its domain logic; only add the access gate.
CREATE OR REPLACE FUNCTION public.rr_collection_more_samples_request_v9630(p_token text, p_categories text[], p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cy public.rr_collection_cycle_v9586%rowtype; v_no integer; v_id uuid; c text; cyid uuid; msg uuid; txt text; cats text[];
begin
 perform public.rr_customer_access_assert_test71(p_token);
  cyid:=public.rr_collection_cycle_for_share_v9631(p_token);
  select * into cy from public.rr_collection_cycle_v9586 where id=cyid for update;
  if cy.status in ('CLOSED','CLOSED_NO_RESPONSE','CANCELLED','CI_GENERATED','PI_GENERATED') then raise exception 'Collection is already closed.'; end if;
  if coalesce(array_length(p_categories,1),0)=0 then raise exception 'Select at least one category.'; end if;

  if cy.data_mode='TEST' and exists(select 1 from unnest(p_categories) picked where not exists(
    select 1 from public.rr_collection_categories_v9630() available
    where lower(trim(available.category))=lower(trim(picked))))
   then raise exception 'Choose categories from the available collection list.'; end if;
  v_no:=public.rr_collection_next_update_v9633(cy.id);
  insert into public.rr_collection_update_request_v9630(collection_cycle_id,update_no,request_kind,requested_by,note)
  values(cy.id,v_no,'MORE_SAMPLES','CUSTOMER',nullif(trim(coalesce(p_note,'')),'')) returning id into v_id;
  foreach c in array p_categories loop
    c:=trim(coalesce(c,''));
    if c<>'' then insert into public.rr_collection_update_category_v9630(update_request_id,category) values(v_id,c) on conflict do nothing; end if;
  end loop;
  if not exists(select 1 from public.rr_collection_update_category_v9630 where update_request_id=v_id) then raise exception 'Select at least one valid category.'; end if;
  insert into public.rr_collection_activity_v9633(collection_cycle_id,update_no,activity_kind,actor_kind,reference_id,payload)
  values(cy.id,v_no,'MORE_SAMPLES','CUSTOMER',v_id,jsonb_build_object('categories',p_categories,'note',nullif(trim(coalesce(p_note,'')),'')));

  if cy.data_mode='TEST' and exists(select 1 from public.rr_customer_chat_v9433 ch where ch.id=cy.chat_id and ch.relation_kind='DIRECT_CUSTOMER') then
    select array_agg(category order by category) into cats from public.rr_collection_update_category_v9630 where update_request_id=v_id;
    txt:=cy.display_no||' · CATEGORY REQUEST · UPDATE '||v_no||E'\n'||array_to_string(cats,' / ')||case when nullif(trim(p_note),'') is null then '' else E'\n'||trim(p_note) end;
    select id into msg from public.rr_customer_chat_messages_v9433 where chat_id=cy.chat_id and channel='GROUP' and archived_at is null
     and payload->>'source'='DIRECT_CATEGORY_REQUEST_TEST71' and payload->>'direct_collection_cycle_id'=cy.id::text limit 1 for update;
    if msg is null then
      insert into public.rr_customer_chat_messages_v9433(chat_id,channel,sender_kind,sender_customer_id,sender_name,message_type,body,payload)
      select cy.chat_id,'GROUP','CUSTOMER',cy.customer_id,ch.customer_name,'TEXT',txt,
      jsonb_build_object('source','DIRECT_CATEGORY_REQUEST_TEST71','direct_collection_cycle_id',cy.id,'sample_request_update_no',v_no,'requested_categories',cats,'update_request_id',v_id)
      from public.rr_customer_chat_v9433 ch where ch.id=cy.chat_id returning id into msg;
    else
      update public.rr_customer_chat_messages_v9433 set body=txt,created_at=clock_timestamp(),payload=payload||jsonb_build_object('sample_request_update_no',v_no,'requested_categories',cats,'update_request_id',v_id) where id=msg;
    end if;
  end if;
  return jsonb_build_object('collection_cycle_id',cy.id,'collection_display_no',cy.display_no,'collection_status',cy.status,'update_request_id',v_id,'update_no',v_no,'request_kind','MORE_SAMPLES');
end$function$
;

-- Existing rr_collection_submit_requirement_v9588 retains its domain logic; only add the access gate.
CREATE OR REPLACE FUNCTION public.rr_collection_submit_requirement_v9588(p_token text, p_customer_name text, p_mobile text, p_message text, p_lines jsonb, p_requirement_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  s public.rr_market_share_v9420%rowtype; cy public.rr_collection_cycle_v9586%rowtype;
  outj jsonb; rid uuid; req public.rr_market_requirements_v9420%rowtype;
  existing_cycle uuid; req_seq int; ch uuid; cn int; dm text; v_update int; v_kind text;
begin
 perform public.rr_customer_access_assert_test71(p_token);
  select * into s from public.rr_market_share_v9420
  where (token=p_token or short_code=upper(p_token)) and status='ACTIVE'
  order by case when token=p_token then 0 else 1 end limit 1;
  if s.id is null then raise exception 'Share link unavailable.'; end if;
  select c.* into cy from public.rr_collection_send_v9586 cs
  join public.rr_collection_cycle_v9586 c on c.id=cs.collection_cycle_id
  where cs.share_id=s.id limit 1;
  if cy.id is null then
    if s.customer_id is null then raise exception 'Permanent customer identity is required before Requirement submit.'; end if;
    dm:=upper(coalesce(nullif(trim(s.data_mode),''),'TEST'));
    select id into ch from public.rr_customer_chat_v9433
    where customer_id=s.customer_id and data_mode=dm and status='OPEN'
    order by created_at asc limit 1;
    if ch is null then raise exception 'Permanent customer chat is required before Requirement submit.'; end if;
    perform pg_advisory_xact_lock(hashtextextended(s.customer_id::text||'|'||dm||'|COLLECTION_ADOPT',9628));
    select c.* into cy from public.rr_collection_send_v9586 cs
    join public.rr_collection_cycle_v9586 c on c.id=cs.collection_cycle_id
    where cs.share_id=s.id limit 1;
    if cy.id is null then
      select coalesce(max(collection_no),0)+1 into cn from public.rr_collection_cycle_v9586
      where customer_id=s.customer_id and data_mode=dm;
      insert into public.rr_collection_cycle_v9586(
        customer_id,chat_id,data_mode,collection_no,display_no,status,opened_at,created_by
      ) values(s.customer_id,ch,dm,cn,'RZ COLLECTION '||lpad(cn::text,2,'0'),'OPENED_NO_RESPONSE',now(),auth.uid())
      returning * into cy;
      insert into public.rr_collection_send_v9586(collection_cycle_id,share_id,send_seq,send_kind,sent_by)
      values(cy.id,s.id,1,'FIRST',auth.uid());
    end if;
  end if;
  if cy.status in('CLOSED','CLOSED_NO_RESPONSE','CANCELLED') then raise exception 'Collection is closed/cancelled.'; end if;
  if p_requirement_id is not null then
    select collection_cycle_id into existing_cycle from public.rr_collection_requirement_link_v9586
    where requirement_id=p_requirement_id;
    if existing_cycle is null or existing_cycle<>cy.id then raise exception 'Requirement is not linked to this Collection flow.'; end if;
  end if;
  outj:=public.rr_market_submit_requirement_v9508(
    p_token,p_customer_name,p_mobile,p_message,p_lines,p_requirement_id
  );
  rid:=(outj->>'requirement_id')::uuid;
  select * into req from public.rr_market_requirements_v9420 where id=rid;
  if req.id is null then raise exception 'Requirement submit failed.'; end if;
  if req.customer_id is distinct from cy.customer_id then raise exception 'Requirement customer does not match Collection customer.'; end if;
  if p_requirement_id is null then
    perform pg_advisory_xact_lock(hashtextextended(cy.id::text||'|REQ',9588));
    select coalesce(max(requirement_seq),0)+1 into req_seq
    from public.rr_collection_requirement_link_v9586 where collection_cycle_id=cy.id;
    insert into public.rr_collection_requirement_link_v9586(
      collection_cycle_id,requirement_id,requirement_seq,is_primary
    ) values(cy.id,rid,req_seq,true);
    v_kind:='REQUIREMENT';
  else
    select requirement_seq into req_seq from public.rr_collection_requirement_link_v9586
    where requirement_id=rid;
    v_kind:='REQUIREMENT_UPDATE';
  end if;
  v_update:=public.rr_collection_next_update_v9633(cy.id);
  insert into public.rr_collection_activity_v9633(
    collection_cycle_id,update_no,activity_kind,actor_kind,reference_id,payload
  ) values(cy.id,v_update,v_kind,'CUSTOMER',rid,jsonb_build_object(
    'requirement_no',req.requirement_no,'lot_count',outj->'lot_count','total_qty',outj->'total_qty'
  ));
  update public.rr_customer_chat_messages_v9433 set
    archived_at=coalesce(archived_at,clock_timestamp()),
    archive_reason=coalesce(archive_reason,'DIRECT_REQUIREMENT_TECHNICAL_AUDIT'),
    archive_meta=coalesce(archive_meta,'{}'::jsonb)||jsonb_build_object('requirement_id',rid,'collection_cycle_id',cy.id)
  where chat_id=cy.chat_id and message_type='REQUIREMENT'
    and payload->>'requirement_id'=rid::text;
  update public.rr_collection_cycle_v9586 set status='REQUIREMENT_RECEIVED'
  where id=cy.id and status not in('PI_GENERATED','CI_GENERATED','CLOSED','CLOSED_NO_RESPONSE','CANCELLED');
  return outj||jsonb_build_object(
    'collection_cycle_id',cy.id,'collection_no',cy.collection_no,'collection_display_no',cy.display_no,
    'requirement_seq',req_seq,'requirement_no',req.requirement_no,'update_no',v_update,
    'collection_status',(select status from public.rr_collection_cycle_v9586 where id=cy.id)
  );
end
$function$
;

-- Existing rr_chat_customer_context_v9434 retains its domain logic; only add the access gate.
CREATE OR REPLACE FUNCTION public.rr_chat_customer_context_v9434(p_token text, p_mobile text)
 RETURNS TABLE(share_id uuid, customer_id uuid, chat_id uuid, data_mode text, customer_name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.rr_market_share_v9420%rowtype;c public.rr_customers%rowtype;ch public.rr_customer_chat_v9433%rowtype;
 norm text:=regexp_replace(coalesce(p_mobile,''),'\\D','','g');
begin
 perform public.rr_customer_access_assert_test71(p_token);
 select ms.* into s from public.rr_market_share_v9420 ms where(ms.token=p_token or ms.short_code=upper(p_token))and ms.status='ACTIVE' order by case when ms.token=p_token then 0 else 1 end limit 1;
 if s.id is null then raise exception 'Share link unavailable.';end if;
 if s.customer_id is not null then select cu.* into c from public.rr_customers cu where cu.id=s.customer_id and cu.is_active limit 1;end if;
 if c.id is null and norm<>'' then select cu.* into c from public.rr_customers cu where regexp_replace(coalesce(cu.mobile,''),'\\D','','g')=norm and cu.is_active order by cu.updated_at desc nulls last limit 1;end if;
 if c.id is null then select cu.* into c from public.rr_market_requirements_v9420 r join public.rr_customers cu on cu.id=r.customer_id and cu.is_active where r.share_id=s.id order by r.submitted_at desc limit 1;end if;
 if c.id is null then raise exception 'Customer identity required.';end if;
 select cc.* into ch from public.rr_customer_chat_v9433 cc where cc.customer_id=c.id and cc.data_mode=s.data_mode and cc.relation_kind='DIRECT_CUSTOMER' order by cc.created_at limit 1;
 if ch.id is null then raise exception 'Customer chat not started.';end if;
 return query select s.id,c.id,ch.id,s.data_mode,c.customer_name;
end $function$
;


CREATE OR REPLACE FUNCTION rr_customer_auth_test71.bootstrap_legacy(p_token text, p_customer_name text, p_mobile text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.rr_market_share_v9420%rowtype;cj jsonb;cid uuid;ch uuid;creator_profile uuid;pair jsonb;
begin
 select * into s from public.rr_market_share_v9420 where(token=p_token or short_code=upper(p_token))and status='ACTIVE' order by case when token=p_token then 0 else 1 end limit 1;
 if s.id is null then raise exception 'Share link unavailable.';end if;
 cj:=public.rr_market_register_customer_v9423(p_customer_name,p_mobile);cid:=(cj->>'customer_id')::uuid;
 pair:=public.rr_ensure_contact_relation_chats_v9704(cid);ch:=(pair->>'customer_chat_id')::uuid;
 select id into creator_profile from public.rr_user_profiles where auth_user_id=s.created_by and is_active and upper(coalesce(access_status,'ACTIVE'))='ACTIVE' order by updated_at desc nulls last limit 1;
 if creator_profile is not null then insert into public.rr_customer_chat_members_v9433(chat_id,profile_id,is_active,added_by)values(ch,creator_profile,true,creator_profile)on conflict(chat_id,profile_id)do update set is_active=true;end if;
 return jsonb_build_object('chat_id',ch,'customer_id',cid,'customer_name',cj->>'customer_name','mobile',cj->>'mobile','distributor_chat_id',pair->>'distributor_chat_id');
end $function$

;
REVOKE ALL ON FUNCTION rr_customer_auth_test71.bootstrap_legacy(text,text,text) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.rr_chat_customer_bootstrap_v9434(p_token text, p_customer_name text, p_mobile text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.rr_market_share_v9420%rowtype;cj jsonb;cid uuid;ch uuid;creator_profile uuid;pair jsonb;
begin
 select * into s from public.rr_market_share_v9420 where(token=p_token or short_code=upper(p_token))and status='ACTIVE' order by case when token=p_token then 0 else 1 end limit 1;
 if s.id is null then raise exception 'Share link unavailable.';end if;
 if s.data_mode='TEST' and public.rr_market_share_relation_v81(p_token)<>'DISTRIBUTOR_CUSTOMER' then
  perform public.rr_customer_access_assert_test71(p_token);
  if not exists(select 1 from public.rr_customers c where c.id=s.customer_id and c.is_active and right(regexp_replace(coalesce(c.mobile,''),'[^0-9]','','g'),10)=right(regexp_replace(coalesce(p_mobile,''),'[^0-9]','','g'),10)) then raise exception 'Mobile does not match this customer.';end if;
 end if;
 cj:=public.rr_market_register_customer_v9423(p_customer_name,p_mobile);cid:=(cj->>'customer_id')::uuid;
 pair:=public.rr_ensure_contact_relation_chats_v9704(cid);ch:=(pair->>'customer_chat_id')::uuid;
 select id into creator_profile from public.rr_user_profiles where auth_user_id=s.created_by and is_active and upper(coalesce(access_status,'ACTIVE'))='ACTIVE' order by updated_at desc nulls last limit 1;
 if creator_profile is not null then insert into public.rr_customer_chat_members_v9433(chat_id,profile_id,is_active,added_by)values(ch,creator_profile,true,creator_profile)on conflict(chat_id,profile_id)do update set is_active=true;end if;
 return jsonb_build_object('chat_id',ch,'customer_id',cid,'customer_name',cj->>'customer_name','mobile',cj->>'mobile','distributor_chat_id',pair->>'distributor_chat_id');
end $function$

;
GRANT EXECUTE ON FUNCTION public.rr_chat_customer_bootstrap_v9434(text,text,text) TO PUBLIC,anon,authenticated,service_role;
