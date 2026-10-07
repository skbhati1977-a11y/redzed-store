-- One open collection per TEST customer; all updates use it until customer close or PI.
LOCK TABLE public.rr_collection_cycle_v9586 IN SHARE ROW EXCLUSIVE MODE;
CREATE TABLE rr_collection_rules_test71.reconciliation_audit (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), collection_cycle_id uuid NOT NULL,
 retained_cycle_id uuid, previous_row jsonb NOT NULL, reason text NOT NULL,
 reconciled_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
REVOKE ALL ON rr_collection_rules_test71.reconciliation_audit FROM PUBLIC,anon,authenticated;
ALTER TABLE rr_collection_rules_test71.reconciliation_audit ENABLE ROW LEVEL SECURITY;
CREATE POLICY no_direct_access ON rr_collection_rules_test71.reconciliation_audit AS RESTRICTIVE FOR ALL TO PUBLIC USING(false) WITH CHECK(false);
-- Backfill PI closure metadata without changing PI/CI identifiers or requirements.
INSERT INTO rr_collection_rules_test71.reconciliation_audit(collection_cycle_id,previous_row,reason)
 SELECT c.id,to_jsonb(c),'PI_CI_TERMINAL_METADATA' FROM public.rr_collection_cycle_v9586 c
 WHERE c.data_mode='TEST' AND c.closed_at IS NULL AND c.status IN('PI_GENERATED','CI_GENERATED');
UPDATE public.rr_collection_cycle_v9586 c SET closed_at=coalesce(
 (SELECT min(p.created_at) FROM public.rr_collection_requirement_link_v9586 l JOIN public.rr_fg_pi_v787 p ON p.market_requirement_id=l.requirement_id WHERE l.collection_cycle_id=c.id AND p.data_mode='TEST'),now()),
 close_reason=coalesce(nullif(c.close_reason,''),'REDZED TEAM PI MADE — COLLECTION CLOSED')
 WHERE c.data_mode='TEST' AND c.closed_at IS NULL AND c.status IN('PI_GENERATED','CI_GENERATED');
-- Keep the most recently sent active cycle per customer, not the largest old number.
WITH ranked AS (
 SELECT c.*,row_number() OVER(PARTITION BY c.customer_id,c.data_mode ORDER BY greatest(c.created_at,coalesce(last_send.sent_at,c.created_at)) DESC,c.created_at DESC,c.id DESC) rn,
 first_value(c.id) OVER(PARTITION BY c.customer_id,c.data_mode ORDER BY greatest(c.created_at,coalesce(last_send.sent_at,c.created_at)) DESC,c.created_at DESC,c.id DESC) keep_id
 FROM public.rr_collection_cycle_v9586 c
 LEFT JOIN LATERAL(SELECT max(s.sent_at) sent_at FROM public.rr_collection_send_v9586 s WHERE s.collection_cycle_id=c.id) last_send ON true
 WHERE c.data_mode='TEST' AND c.closed_at IS NULL AND c.status IN('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED')
)
INSERT INTO rr_collection_rules_test71.reconciliation_audit(collection_cycle_id,retained_cycle_id,previous_row,reason)
 SELECT id,keep_id,to_jsonb(ranked)-'rn'-'keep_id','LEGACY_DUPLICATE_OPEN_RECONCILED' FROM ranked WHERE rn>1;
UPDATE public.rr_collection_cycle_v9586 c SET status='CLOSED',closed_at=now(),
 close_reason='LEGACY DUPLICATE OPEN RECONCILED — active collection '||(SELECT kept.collection_no FROM public.rr_collection_cycle_v9586 kept WHERE kept.id=a.retained_cycle_id)
 FROM rr_collection_rules_test71.reconciliation_audit a
 WHERE a.collection_cycle_id=c.id AND a.reason='LEGACY_DUPLICATE_OPEN_RECONCILED';
UPDATE public.rr_collection_update_request_v9630 r SET status='CANCELLED',closed_at=now()
 WHERE r.status='OPEN' AND EXISTS(SELECT 1 FROM rr_collection_rules_test71.reconciliation_audit a WHERE a.collection_cycle_id=r.collection_cycle_id AND a.reason='LEGACY_DUPLICATE_OPEN_RECONCILED');
CREATE UNIQUE INDEX test71_one_open_cycle_unique ON public.rr_collection_cycle_v9586(customer_id,data_mode)
 WHERE data_mode='TEST' AND closed_at IS NULL AND status IN('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED');

CREATE FUNCTION rr_collection_rules_test71.enforce_terminal_and_number()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $guard$
DECLARE previous_max integer;
BEGIN
 IF NEW.data_mode<>'TEST' THEN RETURN NEW; END IF;
 IF TG_OP='UPDATE' AND OLD.data_mode='TEST' AND (OLD.closed_at IS NOT NULL OR OLD.status IN('PI_GENERATED','CI_GENERATED','CLOSED','CLOSED_NO_RESPONSE','CANCELLED'))
  AND NEW.status IN('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED')
 THEN RAISE EXCEPTION 'Closed or PI collection cannot reopen. Send with a new collection number.'; END IF;
 IF NEW.status IN('PI_GENERATED','CI_GENERATED','CLOSED','CLOSED_NO_RESPONSE','CANCELLED') THEN
  NEW.closed_at:=coalesce(NEW.closed_at,CASE WHEN TG_OP='UPDATE' THEN OLD.closed_at END,now());
  NEW.close_reason:=coalesce(nullif(NEW.close_reason,''),CASE WHEN NEW.status IN('PI_GENERATED','CI_GENERATED') THEN 'REDZED TEAM PI MADE — COLLECTION CLOSED' ELSE 'COLLECTION CLOSED' END);
 ELSIF NEW.closed_at IS NOT NULL THEN RAISE EXCEPTION 'An open collection cannot have a closure timestamp.'; END IF;
 IF TG_OP='INSERT' AND NEW.status IN('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED') THEN
  SELECT max(collection_no) INTO previous_max FROM public.rr_collection_cycle_v9586 WHERE customer_id=NEW.customer_id AND data_mode=NEW.data_mode;
  IF previous_max IS NOT NULL AND NEW.collection_no<=previous_max THEN RAISE EXCEPTION 'New collection number must be greater than previous collection %.',previous_max; END IF;
 END IF;
 RETURN NEW;
END $guard$;
REVOKE ALL ON FUNCTION rr_collection_rules_test71.enforce_terminal_and_number() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER test71_00_terminal_and_number BEFORE INSERT OR UPDATE OF status,closed_at,data_mode,collection_no
 ON public.rr_collection_cycle_v9586 FOR EACH ROW EXECUTE FUNCTION rr_collection_rules_test71.enforce_terminal_and_number();

CREATE FUNCTION rr_collection_rules_test71.enforce_send_to_open_cycle()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $guard$
DECLARE c public.rr_collection_cycle_v9586%rowtype; s public.rr_market_share_v9420%rowtype;
BEGIN
 SELECT * INTO c FROM public.rr_collection_cycle_v9586 WHERE id=NEW.collection_cycle_id FOR UPDATE;
 IF c.data_mode<>'TEST' THEN RETURN NEW; END IF;
 IF c.closed_at IS NOT NULL OR c.status NOT IN('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED') THEN
  RAISE EXCEPTION 'Collection is closed or PI has been made. Send with a new collection number.';
 END IF;
 SELECT * INTO s FROM public.rr_market_share_v9420 WHERE id=NEW.share_id;
 IF s.customer_id IS DISTINCT FROM c.customer_id OR s.data_mode IS DISTINCT FROM c.data_mode OR (s.origin_chat_id IS NOT NULL AND s.origin_chat_id IS DISTINCT FROM c.chat_id) THEN
  RAISE EXCEPTION 'Update share must belong to this collection customer and chat.';
 END IF;
 RETURN NEW;
END $guard$;
REVOKE ALL ON FUNCTION rr_collection_rules_test71.enforce_send_to_open_cycle() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER test71_send_only_to_open_cycle BEFORE INSERT OR UPDATE OF collection_cycle_id,share_id
 ON public.rr_collection_send_v9586 FOR EACH ROW EXECUTE FUNCTION rr_collection_rules_test71.enforce_send_to_open_cycle();

CREATE FUNCTION rr_collection_rules_test71.close_cycle_when_pi_made()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $guard$
BEGIN
 IF NEW.data_mode='TEST' AND NEW.market_requirement_id IS NOT NULL THEN
  UPDATE public.rr_collection_cycle_v9586 c SET status='PI_GENERATED',closed_at=coalesce(c.closed_at,now()),
   close_reason=coalesce(nullif(c.close_reason,''),'REDZED TEAM PI MADE — COLLECTION CLOSED')
  WHERE c.data_mode='TEST' AND c.closed_at IS NULL AND c.status IN('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED')
   AND (EXISTS(SELECT 1 FROM public.rr_collection_requirement_link_v9586 l WHERE l.collection_cycle_id=c.id AND l.requirement_id=NEW.market_requirement_id)
    OR EXISTS(SELECT 1 FROM public.rr_market_requirements_v9420 r WHERE r.id=NEW.market_requirement_id AND r.collection_cycle_id=c.id));
 END IF;
 RETURN NEW;
END $guard$;
REVOKE ALL ON FUNCTION rr_collection_rules_test71.close_cycle_when_pi_made() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER test71_close_collection_when_pi_made AFTER INSERT OR UPDATE OF market_requirement_id
 ON public.rr_fg_pi_v787 FOR EACH ROW EXECUTE FUNCTION rr_collection_rules_test71.close_cycle_when_pi_made();

CREATE OR REPLACE FUNCTION public.rr_sales_collection_context_test71(p_chat_id uuid, p_requirement_id uuid DEFAULT NULL::uuid, p_collection_cycle_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ch public.rr_customer_chat_v9433%rowtype; cy public.rr_collection_cycle_v9586%rowtype;
 req public.rr_market_requirements_v9420%rowtype; cats jsonb; sent jsonb;
begin
 perform public.rr_market_assert_sales_actor_v9420();
 select * into ch from public.rr_customer_chat_v9433 where id=p_chat_id and data_mode='TEST'
  and status='OPEN' and relation_kind='DIRECT_CUSTOMER';
 if ch.id is null or not exists(select 1 from public.rr_customer_chat_members_v9433 m
 join public.rr_user_profiles p on p.id=m.profile_id where m.chat_id=ch.id and m.is_active
 and p.auth_user_id=auth.uid() and p.is_active) then raise exception 'This party chat is unavailable for your account.'; end if;
 if p_requirement_id is not null then
  select * into req from public.rr_market_requirements_v9420
   where id=p_requirement_id and customer_id=ch.customer_id;
  if req.id is null or (p_collection_cycle_id is not null and req.collection_cycle_id is distinct from p_collection_cycle_id)
   then raise exception 'Requirement does not belong to this collection.'; end if;
  p_collection_cycle_id:=req.collection_cycle_id;
 end if;
 if p_collection_cycle_id is not null then
  select * into cy from public.rr_collection_cycle_v9586
   where id=p_collection_cycle_id and chat_id=ch.id and customer_id=ch.customer_id and data_mode=ch.data_mode;
  if cy.id is null then raise exception 'Collection does not belong to this party chat.'; end if;
 else
  select * into cy from public.rr_collection_cycle_v9586
   where chat_id=ch.id and customer_id=ch.customer_id and data_mode=ch.data_mode
   and status in('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED')
   order by created_at desc,id desc limit 1;
 end if;
 -- Closed/PI cycles are history; resolve the customer's open cycle or next number.
 if cy.id is not null and (cy.closed_at is not null or cy.status not in('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED')) then
  cy:=null; req:=null;
  select * into cy from public.rr_collection_cycle_v9586
   where customer_id=ch.customer_id and chat_id=ch.id and data_mode=ch.data_mode and closed_at is null
    and status in('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED')
   order by created_at desc,id desc limit 1;
 end if;
 if cy.id is not null then
  select * into req from public.rr_market_requirements_v9420 where collection_cycle_id=cy.id
   and coalesce(lifecycle_stage,status,'') not in('SUPERSEDED','CANCELLED')
   order by submitted_at desc,id desc limit 1;
 end if;
 select coalesce(jsonb_agg(x.category order by x.category),'[]'::jsonb) into cats from (
  select distinct trim(c.category) category from public.rr_collection_update_request_v9630 r
  join public.rr_collection_update_category_v9630 c on c.update_request_id=r.id
  where r.collection_cycle_id=cy.id and r.request_kind='MORE_SAMPLES' and (r.status='OPEN' or (r.status='FULFILLED'
   and not exists(select 1 from public.rr_collection_update_request_v9630 pending where pending.collection_cycle_id=cy.id and pending.status='OPEN' and pending.request_kind='MORE_SAMPLES')
   and r.update_no=(select max(done.update_no) from public.rr_collection_update_request_v9630 done where done.collection_cycle_id=cy.id and done.status='FULFILLED' and done.request_kind='MORE_SAMPLES')))
  and nullif(trim(c.category),'') is not null
 ) x;
 select coalesce(jsonb_agg(x.lot_no order by x.lot_no),'[]'::jsonb) into sent from (
  select distinct upper(trim(l.lot_no)) lot_no from public.rr_collection_send_v9586 s
  join public.rr_market_share_lots_v9420 l on l.share_id=s.share_id where s.collection_cycle_id=cy.id
 ) x;
 return jsonb_build_object('chat_id',ch.id,'customer_id',ch.customer_id,'customer_name',ch.customer_name,
 'requirement_lines',public.rr_collection_requirement_snapshot_test71(cy.id),'update_history',public.rr_direct_cycle_history_test71(cy.id),'data_mode',ch.data_mode,'collection_status',cy.status,'collection_cycle_id',cy.id,'collection_display_no',cy.display_no,
 'requirement_id',req.id,'categories',cats,'sent_lots',sent,
 'can_send',coalesce(cy.status in('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED'),cy.id is null)
   and req.pi_generated_at is null and coalesce(req.lifecycle_stage,req.status,'') not in('PI_GENERATED','CI_FINAL','CANCELLED')
   and not exists(select 1 from public.rr_fg_pi_v787 p where p.market_requirement_id=req.id));
end $function$;

CREATE OR REPLACE FUNCTION public.rr_sales_collection_send_test71(p_chat_id uuid, p_customer_id uuid, p_lots text[], p_requirement_id uuid DEFAULT NULL::uuid, p_origin text DEFAULT NULL::text, p_collection_cycle_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_cycle public.rr_collection_cycle_v9586%rowtype;
  v_result jsonb;
  v_message uuid;
  v_profile public.rr_user_profiles%rowtype;
  v_url text;
  v_body text;
  v_update integer;
  ctx jsonb; lot text; cat text; chosen_cats text[]:=array[]::text[];
begin
  perform public.rr_market_assert_sales_actor_v9420();
  select * into v_profile from public.rr_user_profiles
  where auth_user_id=auth.uid() and is_active limit 1;
  if v_profile.id is null then raise exception 'Active staff profile required.'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_chat_id::text||'|DIRECT_COLLECTION',9684));
  ctx:=public.rr_sales_collection_context_test71(p_chat_id,p_requirement_id,p_collection_cycle_id);
  if p_customer_id is not null and p_customer_id::text is distinct from ctx->>'customer_id'
   then raise exception 'Collection belongs to another party.'; end if;
  p_customer_id:=(ctx->>'customer_id')::uuid;
  if not (ctx->>'can_send')::boolean then raise exception 'This collection is complete. Open a new collection.'; end if;
  p_requirement_id:=(ctx->>'requirement_id')::uuid;
  select * into v_cycle from public.rr_collection_cycle_v9586 where id=(ctx->>'collection_cycle_id')::uuid for update;
  if v_cycle.id is not null then
   perform pg_advisory_xact_lock(hashtextextended(v_cycle.id::text||'|DIRECT_REQUIREMENT',9714));
  end if;
  select array_agg(distinct upper(trim(x))) into p_lots from unnest(p_lots) x where nullif(trim(x),'') is not null;
  if coalesce(cardinality(p_lots),0)=0 then raise exception 'Select at least one design.'; end if;
  foreach lot in array p_lots loop
   if ctx->'sent_lots' ? lot then raise exception 'This design was already sent. Refresh the collection list.'; end if;
   select w.category into cat from public.rr_web_window_cards_v9329(lot,null,null,'TEST',1,0) w where upper(trim(w.lot_no))=lot;
   if not found then raise exception 'Selected design is unavailable. Refresh the collection list.'; end if;
   if jsonb_array_length(ctx->'categories')>0 and not exists(
    select 1 from jsonb_array_elements_text(ctx->'categories') c where lower(trim(c))=lower(trim(cat)))
    then raise exception 'Select designs from the categories requested by this party.'; end if;
   chosen_cats:=array_append(chosen_cats,lower(trim(cat)));
  end loop;

  if v_cycle.id is null then
    v_result:=public.rr_collection_create_first_v9587(p_customer_id,p_lots,'TEST');
  else
    v_result:=public.rr_collection_add_update_v9587(v_cycle.id,p_lots);
  end if;
  select * into v_cycle from public.rr_collection_cycle_v9586
  where id=(v_result->>'collection_cycle_id')::uuid;
  v_update:=greatest(coalesce((v_result->>'send_seq')::integer,1)-1,0);

  if p_origin is distinct from 'https://redzed-customer-collection.jggfab2011.chatgpt.site'
     and coalesce(p_origin,'') !~ '^https://([a-z0-9-]+\.)*(vercel\.app|github\.io)$' then
    raise exception 'Approved application origin required.';
  end if;
  v_url:=rtrim(p_origin,'/')||'/s.html?t='||(v_result->>'token')||
    case when nullif(v_result->>'short_code','') is null then ''
         else '&c='||(v_result->>'short_code') end||
    case when p_requirement_id is null then '' else '&r='||p_requirement_id::text end||'&v=9684';
  v_body:=coalesce(v_cycle.display_no,'RZ COLLECTION')||
    case when v_update>0 then ' · UPDATE '||v_update else '' end||
    ' · '||coalesce(v_result->>'lot_count','0')||' styles\nOpen collection: '||v_url;

  select m.id into v_message
  from public.rr_customer_chat_messages_v9433 m
  where m.chat_id=p_chat_id and m.channel='GROUP' and m.archived_at is null and m.message_type<>'REQUIREMENT' and coalesce(m.payload->>'source','')<>'DIRECT_CATEGORY_REQUEST_TEST71' and not (coalesce(m.payload,'{}'::jsonb) ? 'direct_requirement_root_id')
    and (
      m.payload->>'direct_collection_cycle_id'=v_cycle.id::text
      or exists(
        select 1 from public.rr_collection_send_v9586 cs
        join public.rr_market_share_v9420 s on s.id=cs.share_id
        where cs.collection_cycle_id=v_cycle.id
          and (position(s.token in coalesce(m.body,''))>0
            or position(coalesce(s.short_code,'#NO-CODE#') in coalesce(m.body,''))>0)
      )
    )
  order by m.created_at desc,m.id desc limit 1 for update;

  if v_message is null then
    insert into public.rr_customer_chat_messages_v9433(
      chat_id,channel,sender_kind,sender_profile_id,sender_name,message_type,body,payload
    ) values(
      p_chat_id,'GROUP','STAFF',v_profile.id,coalesce(nullif(trim(v_profile.full_name),''),'REDZED Staff'),
      'LINK',v_body,jsonb_build_object(
        'source','DIRECT_MARKET_WINDOW','url',v_url,'market_share_id',v_result->>'share_id',
        'direct_collection_cycle_id',v_cycle.id,'collection_no',v_cycle.collection_no,
        'collection_display_no',v_cycle.display_no,'collection_update_no',v_update,
        'lot_count',(v_result->>'lot_count')::integer
      )
    ) returning id into v_message;
  else
    update public.rr_customer_chat_messages_v9433 set
      sender_kind='STAFF',sender_profile_id=v_profile.id,
      sender_name=coalesce(nullif(trim(v_profile.full_name),''),'REDZED Staff'),
      message_type='LINK',body=v_body,
      payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object(
        'source','DIRECT_MARKET_WINDOW','url',v_url,'market_share_id',v_result->>'share_id',
        'direct_collection_cycle_id',v_cycle.id,'collection_no',v_cycle.collection_no,
        'collection_display_no',v_cycle.display_no,'collection_update_no',v_update,
        'lot_count',(v_result->>'lot_count')::integer
      ),created_at=clock_timestamp(),archived_at=null,archived_by=null,
      archive_reason=null,archive_meta='{}'::jsonb
    where id=v_message;
  end if;

  update public.rr_customer_chat_messages_v9433 m set
    archived_at=clock_timestamp(),archive_reason='DIRECT_COLLECTION_SUPERSEDED_SINGLE_CARD',
    archive_meta=coalesce(m.archive_meta,'{}'::jsonb)||jsonb_build_object('canonical_message_id',v_message,'collection_cycle_id',v_cycle.id)
  where m.chat_id=p_chat_id and m.id<>v_message and m.archived_at is null and m.message_type<>'REQUIREMENT' and coalesce(m.payload->>'source','')<>'DIRECT_CATEGORY_REQUEST_TEST71' and not (coalesce(m.payload,'{}'::jsonb) ? 'direct_requirement_root_id') and (
    m.payload->>'direct_collection_cycle_id'=v_cycle.id::text or exists(
      select 1 from public.rr_collection_send_v9586 cs
      join public.rr_market_share_v9420 s on s.id=cs.share_id
      where cs.collection_cycle_id=v_cycle.id
        and (position(s.token in coalesce(m.body,''))>0
          or position(coalesce(s.short_code,'#NO-CODE#') in coalesce(m.body,''))>0)
    )
  );
  update public.rr_collection_update_request_v9630 r set status='FULFILLED',fulfilled_at=clock_timestamp()
   where r.collection_cycle_id=v_cycle.id and r.status='OPEN' and r.request_kind='MORE_SAMPLES'
    and not exists(select 1 from public.rr_collection_update_category_v9630 c where c.update_request_id=r.id
      and not (lower(trim(c.category))=any(chosen_cats)));
  return v_result||jsonb_build_object('chat_message_id',v_message,'url',v_url,'collection_update_no',v_update);
end
$function$;

CREATE OR REPLACE FUNCTION public.rr_collection_add_update_v9587(p_collection_cycle_id uuid, p_lots text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cy public.rr_collection_cycle_v9586%rowtype;seq int;sj jsonb;sid uuid;dupes text[];actor uuid:=auth.uid();
begin
 perform public.rr_market_assert_sales_actor_v9420();
 if coalesce(array_length(p_lots,1),0)=0 then raise exception 'Select at least one lot.';end if;
 select * into cy from public.rr_collection_cycle_v9586 where id=p_collection_cycle_id for update;
 if cy.id is null then raise exception 'Collection not found.';end if;
 if cy.data_mode='TEST' and (cy.closed_at is not null or cy.status not in('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED')) then raise exception 'Collection is closed or PI has been made. Send a new collection number.';end if;
 if cy.status in('CLOSED','CLOSED_NO_RESPONSE','CANCELLED') then raise exception 'Closed/Cancelled Collection cannot be updated.';end if;
 if not exists(select 1 from public.rr_customer_chat_v9433 ch where ch.id=cy.chat_id
   and ch.customer_id=cy.customer_id and ch.relation_kind='DIRECT_CUSTOMER' and ch.status='OPEN')
 then raise exception 'Collection is not bound to the direct Customer chat.';end if;
 select array_agg(distinct trim(x)) into dupes from unnest(p_lots)x
 where trim(x)<>'' and exists(select 1 from public.rr_collection_send_v9586 s
   join public.rr_market_share_lots_v9420 l on l.share_id=s.share_id
   where s.collection_cycle_id=cy.id and l.lot_no=trim(x));
 if coalesce(array_length(dupes,1),0)>0 then raise exception 'Lot(s) already sent in this Collection: %',array_to_string(dupes,', ');end if;
 select coalesce(max(send_seq),0)+1 into seq from public.rr_collection_send_v9586 where collection_cycle_id=cy.id;
 sj:=public.rr_market_create_share_v9420(p_lots,cy.customer_id,
   (select customer_name from public.rr_customer_chat_v9433 where id=cy.chat_id),cy.data_mode);
 sid:=(sj->>'share_id')::uuid;
 update public.rr_market_share_v9420 set origin_chat_id=cy.chat_id,
   origin_relation_kind='DIRECT_CUSTOMER',origin_collection_cycle_id=cy.id,
   origin_owner_customer_id=cy.customer_id,origin_partner_customer_id=null
 where id=sid;
 insert into public.rr_collection_send_v9586(collection_cycle_id,share_id,send_seq,send_kind,sent_by)
 values(cy.id,sid,seq,'UPDATE',actor);
 return sj||jsonb_build_object('collection_cycle_id',cy.id,'collection_no',cy.collection_no,
   'collection_display_no',cy.display_no,'send_seq',seq,'send_kind','UPDATE',
   'chat_id',cy.chat_id,'relation_kind','DIRECT_CUSTOMER');
end $function$;
