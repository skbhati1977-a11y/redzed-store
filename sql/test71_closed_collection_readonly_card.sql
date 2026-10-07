CREATE OR REPLACE FUNCTION rr_collection_rules_test71.close_partner_cycle_on_order()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE root uuid;
BEGIN
 IF NEW.data_mode='TEST' AND (NEW.customer_closed_at IS NOT NULL OR NEW.status NOT IN('DRAFT','SUPERSEDED')
 OR NEW.distributor_pi_created_at IS NOT NULL OR NEW.pi_ref IS NOT NULL OR NEW.ci_ref IS NOT NULL) THEN
  SELECT coalesce(pc.root_collection_id,pc.id) INTO root FROM public.rr_market_partner_collection_v67 pc WHERE pc.id=NEW.collection_id;
  UPDATE rr_collection_rules_test71.partner_cycles SET status='CLOSED',closed_at=coalesce(closed_at,now()),close_reason='CUSTOMER CLOSE OR DISTRIBUTOR/REDZED PI CI MADE' WHERE root_id=root AND status='OPEN';
 END IF;RETURN NEW;
END $function$;


CREATE OR REPLACE FUNCTION rr_collection_rules_test71.archive_cycle_chat_on_close() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$ BEGIN IF NEW.data_mode='TEST' AND (NEW.closed_at IS NOT NULL OR NEW.status IN('PI_GENERATED','CI_GENERATED','CLOSED','CLOSED_NO_RESPONSE','CANCELLED')) THEN UPDATE public.rr_customer_chat_messages_v9433 m SET payload=coalesce(m.payload,'{}'::jsonb)||jsonb_build_object('read_only',true,'collection_status',NEW.status) WHERE m.archived_at IS NULL AND m.payload->>'direct_collection_cycle_id'=NEW.id::text AND m.chat_id=NEW.chat_id AND m.message_type IN('LINK','REQUIREMENT','ATTACHMENT') AND coalesce(m.payload->>'source','')<>'DIRECT_CATEGORY_REQUEST_TEST71'; END IF; RETURN NEW; END $fn$;

CREATE OR REPLACE FUNCTION rr_collection_rules_test71.archive_partner_cycle_history() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$ BEGIN IF NEW.status='CLOSED' THEN UPDATE public.rr_customer_chat_messages_v9433 m SET payload=coalesce(m.payload,'{}'::jsonb)||jsonb_build_object('read_only',true,'collection_status',NEW.status) WHERE m.archived_at IS NULL AND m.payload->>'source' IN('PARTNER_MARKET_WINDOW','PARTNER_MARKET_REQUIREMENT','PARTNER_CUSTOMER_REQUIREMENT') AND (m.payload->>'partner_collection_root_id'=NEW.root_id::text OR EXISTS(SELECT 1 FROM public.rr_market_partner_order_v67 o JOIN public.rr_market_partner_collection_v67 pc ON pc.id=o.collection_id WHERE o.id::text=m.payload->>'partner_order_id' AND coalesce(pc.root_collection_id,pc.id)=NEW.root_id)); END IF; RETURN NEW; END $fn$;

CREATE OR REPLACE FUNCTION rr_collection_rules_test71.hide_previous_closed_direct() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE c public.rr_collection_cycle_v9586%rowtype;
BEGIN
 SELECT * INTO c FROM public.rr_collection_cycle_v9586 WHERE id=NEW.collection_cycle_id;
 IF c.data_mode<>'TEST' THEN RETURN NEW;END IF;
 INSERT INTO rr_collection_rules_test71.chat_cleanup_audit(message_id,previous_row,reason)
 SELECT m.id,to_jsonb(m),'REPLACED_CLOSED_COLLECTION_HISTORY' FROM public.rr_customer_chat_messages_v9433 m JOIN public.rr_collection_cycle_v9586 oldc ON oldc.id::text=m.payload->>'direct_collection_cycle_id'
 WHERE oldc.customer_id=c.customer_id AND oldc.data_mode='TEST' AND oldc.id<>c.id AND oldc.closed_at IS NOT NULL AND oldc.collection_no<c.collection_no AND m.archived_at IS NULL AND m.message_type IN('LINK','REQUIREMENT','ATTACHMENT') AND coalesce(m.payload->>'source','')<>'DIRECT_CATEGORY_REQUEST_TEST71' ON CONFLICT(message_id) DO NOTHING;
 UPDATE public.rr_customer_chat_messages_v9433 m SET archived_at=now(),archive_reason='REPLACED_CLOSED_COLLECTION_HISTORY',archive_meta=coalesce(m.archive_meta,'{}'::jsonb)||jsonb_build_object('history_preserved',true,'replaced_by_collection_cycle_id',c.id)
 FROM public.rr_collection_cycle_v9586 oldc WHERE oldc.id::text=m.payload->>'direct_collection_cycle_id' AND oldc.customer_id=c.customer_id AND oldc.data_mode='TEST' AND oldc.id<>c.id AND oldc.closed_at IS NOT NULL AND oldc.collection_no<c.collection_no AND m.archived_at IS NULL AND m.message_type IN('LINK','REQUIREMENT','ATTACHMENT') AND coalesce(m.payload->>'source','')<>'DIRECT_CATEGORY_REQUEST_TEST71';
 RETURN NEW;
END $fn$;
CREATE TRIGGER test71_hide_replaced_closed_direct AFTER INSERT ON public.rr_collection_send_v9586 FOR EACH ROW EXECUTE FUNCTION rr_collection_rules_test71.hide_previous_closed_direct();
CREATE OR REPLACE FUNCTION rr_collection_rules_test71.hide_previous_closed_partner() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.rr_market_share_v9420 s WHERE s.id=NEW.share_id AND s.data_mode='TEST') THEN RETURN NEW;END IF;
 INSERT INTO rr_collection_rules_test71.chat_cleanup_audit(message_id,previous_row,reason)
 SELECT m.id,to_jsonb(m),'REPLACED_CLOSED_DISTRIBUTOR_HISTORY' FROM public.rr_customer_chat_messages_v9433 m
 WHERE m.archived_at IS NULL AND m.payload->>'source' IN('PARTNER_MARKET_WINDOW','PARTNER_MARKET_REQUIREMENT','PARTNER_CUSTOMER_REQUIREMENT') AND EXISTS(SELECT 1 FROM rr_collection_rules_test71.partner_cycles g WHERE g.owner_customer_id=NEW.owner_customer_id AND g.partner_customer_id=NEW.partner_customer_id AND g.status='CLOSED' AND g.collection_no<NEW.collection_no AND (m.payload->>'partner_collection_root_id'=g.root_id::text OR EXISTS(SELECT 1 FROM public.rr_market_partner_order_v67 o JOIN public.rr_market_partner_collection_v67 pc ON pc.id=o.collection_id WHERE o.id::text=m.payload->>'partner_order_id' AND coalesce(pc.root_collection_id,pc.id)=g.root_id))) ON CONFLICT(message_id) DO NOTHING;
 UPDATE public.rr_customer_chat_messages_v9433 m SET archived_at=now(),archive_reason='REPLACED_CLOSED_DISTRIBUTOR_HISTORY',archive_meta=coalesce(m.archive_meta,'{}'::jsonb)||jsonb_build_object('history_preserved',true,'replaced_by_partner_root',coalesce(NEW.root_collection_id,NEW.id))
 WHERE m.archived_at IS NULL AND m.payload->>'source' IN('PARTNER_MARKET_WINDOW','PARTNER_MARKET_REQUIREMENT','PARTNER_CUSTOMER_REQUIREMENT') AND EXISTS(SELECT 1 FROM rr_collection_rules_test71.partner_cycles g WHERE g.owner_customer_id=NEW.owner_customer_id AND g.partner_customer_id=NEW.partner_customer_id AND g.status='CLOSED' AND g.collection_no<NEW.collection_no AND (m.payload->>'partner_collection_root_id'=g.root_id::text OR EXISTS(SELECT 1 FROM public.rr_market_partner_order_v67 o JOIN public.rr_market_partner_collection_v67 pc ON pc.id=o.collection_id WHERE o.id::text=m.payload->>'partner_order_id' AND coalesce(pc.root_collection_id,pc.id)=g.root_id)));
 RETURN NEW;
END $fn$;
CREATE TRIGGER test71_hide_replaced_closed_partner AFTER INSERT ON public.rr_market_partner_collection_v67 FOR EACH ROW EXECUTE FUNCTION rr_collection_rules_test71.hide_previous_closed_partner();
REVOKE ALL ON FUNCTION rr_collection_rules_test71.hide_previous_closed_direct(),rr_collection_rules_test71.hide_previous_closed_partner() FROM PUBLIC,anon,authenticated;


CREATE OR REPLACE FUNCTION public.rr_sales_collection_cycle_status_test71(p_chat_id uuid, p_collection_cycle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ctx jsonb;c public.rr_collection_cycle_v9586%rowtype;ro boolean;
begin
 ctx:=public.rr_sales_collection_context_test71(p_chat_id,null,p_collection_cycle_id);
 if p_collection_cycle_id is null then return public.rr_sales_collection_live_status_test71(p_chat_id);end if;
 select * into c from public.rr_collection_cycle_v9586 where id=p_collection_cycle_id and chat_id=p_chat_id and data_mode='TEST';
 if c.id is null then raise exception 'COLLECTION NOT FOUND IN THIS CHAT';end if;
 ro:=c.closed_at is not null or c.status not in('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED');
 return ctx||public.rr_direct_cycle_live_meta_test71(c.id)||jsonb_build_object('collection_cycle_id',c.id,'collection_no',c.collection_no,'collection_display_no',c.display_no,'collection_status',c.status,'closed_at',c.closed_at,'read_only',ro,'can_send',not ro);
end $function$;


CREATE OR REPLACE FUNCTION public.rr_sales_collection_live_status_test71(p_chat_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cy uuid;ctx jsonb;
begin
 ctx:=public.rr_sales_collection_context_test71(p_chat_id);
 select c.id into cy from public.rr_collection_cycle_v9586 c
 left join lateral (select max(s.created_at) sent_at from public.rr_collection_send_v9586 cs join public.rr_market_share_v9420 s on s.id=cs.share_id where cs.collection_cycle_id=c.id) latest on true
 where c.chat_id=p_chat_id and c.data_mode='TEST'
 order by greatest(c.created_at,coalesce(latest.sent_at,c.created_at)) desc,c.id desc limit 1;
 if cy is null then return ctx;end if;
 return public.rr_sales_collection_cycle_status_test71(p_chat_id,cy);
end $function$;


CREATE OR REPLACE FUNCTION public.rr_chat_requirement_detail_v9508(p_chat_id uuid, p_requirement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.rr_market_requirements_v9420%rowtype; outj jsonb; pi jsonb;cy public.rr_collection_cycle_v9586%rowtype;ro boolean;
begin
 perform public.rr_chat_internal_assert_v9495();
 if not exists(select 1 from public.rr_customer_chat_members_v9433 m join public.rr_user_profiles p on p.id=m.profile_id where m.chat_id=p_chat_id and m.is_active and p.auth_user_id=auth.uid()) then raise exception 'CHAT ACCESS DENIED'; end if;
 select q.* into r from public.rr_market_requirements_v9420 q join public.rr_customer_chat_v9433 c on c.customer_id=q.customer_id where q.id=p_requirement_id and c.id=p_chat_id;
 if not found then raise exception 'REQUIREMENT NOT FOUND IN THIS CHAT'; end if;
 select jsonb_build_object('id',p.id,'pi_no',p.pi_no,'ci_no',p.cpi_no,'status',p.status,'version_no',p.version_no) into pi
 from public.rr_fg_pi_v787 p where p.market_requirement_id=r.id order by p.created_at desc limit 1;
 select * into cy from public.rr_collection_cycle_v9586 where id=r.collection_cycle_id;
 ro:=cy.closed_at is not null or (cy.id is not null and cy.status not in('DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED'));
 select jsonb_build_object(
   'id',r.id,'requirement_no',coalesce(r.requirement_display_no,r.requirement_no),
   'requirement_display_no',coalesce(r.requirement_display_no,r.requirement_no),
   'requirement_update_no',coalesce(r.requirement_update_no,0),
   'collection_cycle_id',r.collection_cycle_id,'collection_no',r.collection_no,
   'collection_display_no',coalesce(r.collection_display_no,'COLLECTION'),
   'collection_update_no',coalesce(r.collection_update_no,0),
   'customer_name',r.customer_name,'mobile',r.mobile,'message',r.message,
   'status',coalesce(r.lifecycle_stage,r.status),'submitted_at',r.submitted_at,'share_id',r.share_id,
   'pi',pi,'can_prepare_pi',(pi is null and coalesce(r.lifecycle_stage,r.status) not in('SUPERSEDED','CI_FINAL')),
   'read_only',ro,'collection_status',cy.status,'can_add_update',(not ro and pi is null and coalesce(r.lifecycle_stage,r.status) not in('SUPERSEDED','CI_FINAL')),
   'lines',coalesce(jsonb_agg(jsonb_build_object('lot_no',l.lot_no,'requested_qty',l.requested_qty,'accepted_qty',l.accepted_qty,'max_available',l.max_available_at_submit,'card',to_jsonb(ca)) order by l.created_at),'[]'::jsonb)
 ) into outj
 from public.rr_market_requirement_lines_v9420 l
 left join lateral public.rr_web_window_cards_v9329(l.lot_no,null,null,'TEST',1,0) ca on true
 where l.requirement_id=r.id and l.requested_qty>0;
 return outj||jsonb_build_object('update_history',public.rr_direct_cycle_history_test71(r.collection_cycle_id),
 'current_collection_update_no',greatest(coalesce((select max(cs.send_seq) from public.rr_collection_send_v9586 cs where cs.collection_cycle_id=r.collection_cycle_id),1)-1,0));
end $function$;


CREATE OR REPLACE FUNCTION public.rr_market_partner_customer_current_state_v80(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_ctx jsonb;
  v_owner uuid;
  v_customer uuid;
  v_root uuid;
  v_collection public.rr_market_partner_collection_v67%rowtype;
  v_order public.rr_market_partner_order_v67%rowtype;
  v_requested_update integer;
  v_update integer;
  v_status text;
begin
  v_ctx := public.rr_market_partner_customer_context_v80(p_token);
  v_owner := (v_ctx ->> 'owner_customer_id')::uuid;
  v_customer := (v_ctx ->> 'partner_customer_id')::uuid;
  v_root := (v_ctx ->> 'root_collection_id')::uuid;

  select pc.*
  into v_collection
  from public.rr_market_partner_collection_v67 pc
  where coalesce(pc.root_collection_id, pc.id) = v_root
    and pc.owner_customer_id = v_owner
    and pc.partner_customer_id = v_customer
    and pc.status <> 'CANCELLED'
    and not pc.legacy_hidden_v78
  order by pc.collection_update_no desc, pc.created_at desc
  limit 1;

  select o.*
  into v_order
  from public.rr_market_partner_order_v67 o
  join public.rr_market_partner_collection_v67 pc on pc.id = o.collection_id
  where coalesce(pc.root_collection_id, pc.id) = v_root
    and o.owner_customer_id = v_owner
    and o.partner_customer_id = v_customer
    and o.data_mode = 'TEST'
    and o.status <> 'SUPERSEDED'
  order by o.requirement_update_no desc, o.created_at desc
  limit 1;

  select max(
    case
      when e.payload ->> 'requested_update_no' ~ '^[0-9]+$'
        then (e.payload ->> 'requested_update_no')::integer
      else null
    end
  )
  into v_requested_update
  from public.rr_market_partner_event_v67 e
  where e.owner_customer_id = v_owner
    and e.event_type = 'CHAT_MESSAGE'
    and e.payload ->> 'action' = 'MORE_SAMPLES_REQUESTED'
    and e.payload ->> 'customer_id' = v_customer::text
    and e.payload ->> 'root_collection_id' = v_root::text;

  v_update := greatest(
    coalesce(v_collection.collection_update_no, 0),
    coalesce(v_requested_update, 0)
  );
  v_status := case
    when v_order.id is null or v_order.status = 'DRAFT' then 'OPEN'
    when v_order.status = 'CI_FINAL' then 'CI_GENERATED'
    when v_order.distributor_pi_ref is not null then 'PI_GENERATED'
    else 'CLOSED'
  end;

  if exists(select 1 from rr_collection_rules_test71.partner_cycles g where g.root_id=v_root and g.status='CLOSED') and v_status='OPEN' then v_status:='CLOSED';end if;
  return jsonb_build_object(
    'collection_cycle_id', v_root,
    'collection_display_no', 'COLLECTION ' || v_collection.collection_no::text,
    'collection_status', v_status,
    'update_no', coalesce(v_collection.collection_update_no,0),
    'collection_update_no',coalesce(v_collection.collection_update_no,0),
    'read_only',v_status<>'OPEN',
    'latest_collection_token',(select s.token from public.rr_market_share_v9420 s where s.id=v_collection.share_id),
    'requirement_display_no', v_order.requirement_display_no,
    'requirement_status', v_order.status,
    'sent_to', 'DISTRIBUTOR'
  );
end;
$function$;

-- Customer visibility is separate from sent history and saved requirement quantities.
CREATE TABLE rr_collection_rules_test71.customer_hidden_items(collection_cycle_id uuid NOT NULL,lot_no text NOT NULL,hidden_at timestamptz NOT NULL DEFAULT now(),PRIMARY KEY(collection_cycle_id,lot_no));
ALTER TABLE rr_collection_rules_test71.customer_hidden_items ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON rr_collection_rules_test71.customer_hidden_items FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.rr_customer_collection_hidden_items_test71(p_token text,p_lot_no text DEFAULT NULL,p_hidden boolean DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE st jsonb;v uuid;d jsonb;q jsonb;result jsonb;partner boolean;
BEGIN
 PERFORM public.rr_customer_access_assert_test71(p_token);
 partner:=public.rr_market_share_relation_v81(p_token)='DISTRIBUTOR_CUSTOMER';
 IF partner THEN st:=public.rr_market_partner_customer_current_state_v80(p_token);ELSE st:=public.rr_collection_current_state_v9633(p_token);END IF;
 v:=(st->>'collection_cycle_id')::uuid;
 IF v IS NULL THEN RAISE EXCEPTION 'Collection not found';END IF;
 IF p_lot_no IS NOT NULL THEN
  IF coalesce(st->>'collection_status','') NOT IN('OPEN','DRAFT','SENT_NOT_OPENED','OPENED_NO_RESPONSE','REQUIREMENT_RECEIVED') THEN RAISE EXCEPTION 'Closed collection is view only';END IF;
  d:=public.rr_collection_cycle_share_view_v9686(coalesce(st->>'latest_collection_token',p_token));
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(d->'rows') x WHERE x->>'lot_no'=p_lot_no) THEN RAISE EXCEPTION 'Item is not in this collection';END IF;
  IF p_hidden THEN
   IF partner THEN
    IF EXISTS(SELECT 1 FROM public.rr_market_partner_order_line_v67 l JOIN public.rr_market_partner_order_v67 o ON o.id=l.order_id JOIN public.rr_market_partner_collection_v67 pc ON pc.id=o.collection_id WHERE coalesce(pc.root_collection_id,pc.id)=v AND o.status<>'SUPERSEDED' AND l.lot_no=p_lot_no AND l.requested_qty>0) THEN RAISE EXCEPTION 'Required item cannot be hidden';END IF;
   ELSE
    q:=public.rr_collection_customer_requirement_summary_v9637(coalesce(st->>'latest_collection_token',p_token));
    IF EXISTS(SELECT 1 FROM jsonb_array_elements(q->'lines') l WHERE l->>'lot_no'=p_lot_no AND (l->>'requested_qty')::numeric>0) THEN RAISE EXCEPTION 'Required item cannot be hidden';END IF;
   END IF;
   INSERT INTO rr_collection_rules_test71.customer_hidden_items(collection_cycle_id,lot_no) VALUES(v,p_lot_no) ON CONFLICT DO NOTHING;
  ELSE DELETE FROM rr_collection_rules_test71.customer_hidden_items WHERE collection_cycle_id=v AND lot_no=p_lot_no;END IF;
 END IF;
 SELECT coalesce(jsonb_agg(lot_no),'[]'::jsonb) INTO result FROM rr_collection_rules_test71.customer_hidden_items WHERE collection_cycle_id=v;
 RETURN jsonb_build_object('collection_cycle_id',v,'hidden_lots',result);
END $fn$;
REVOKE ALL ON FUNCTION public.rr_customer_collection_hidden_items_test71(text,text,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rr_customer_collection_hidden_items_test71(text,text,boolean) TO anon,authenticated;
