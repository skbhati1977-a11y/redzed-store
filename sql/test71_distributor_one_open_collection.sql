CREATE TABLE rr_collection_rules_test71.partner_cycles(
 root_id uuid PRIMARY KEY,owner_customer_id uuid NOT NULL,partner_customer_id uuid NOT NULL,collection_no bigint NOT NULL,
 status text NOT NULL CHECK(status IN('OPEN','CLOSED')),closed_at timestamptz,close_reason text,created_at timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON rr_collection_rules_test71.partner_cycles FROM PUBLIC,anon,authenticated;
ALTER TABLE rr_collection_rules_test71.partner_cycles ENABLE ROW LEVEL SECURITY;
CREATE POLICY no_direct_access ON rr_collection_rules_test71.partner_cycles AS RESTRICTIVE FOR ALL TO PUBLIC USING(false) WITH CHECK(false);
INSERT INTO rr_collection_rules_test71.partner_cycles(root_id,owner_customer_id,partner_customer_id,collection_no,status,closed_at,close_reason)
 SELECT coalesce(pc.root_collection_id,pc.id),pc.owner_customer_id,pc.partner_customer_id,max(pc.collection_no),
 CASE WHEN bool_or(o.status NOT IN('DRAFT','SUPERSEDED') OR o.customer_closed_at IS NOT NULL OR o.distributor_pi_created_at IS NOT NULL OR o.pi_ref IS NOT NULL OR o.ci_ref IS NOT NULL) OR bool_and(pc.status='CANCELLED' OR pc.legacy_hidden_v78) THEN 'CLOSED' ELSE 'OPEN' END,
 CASE WHEN bool_or(o.status NOT IN('DRAFT','SUPERSEDED') OR o.customer_closed_at IS NOT NULL OR o.distributor_pi_created_at IS NOT NULL OR o.pi_ref IS NOT NULL OR o.ci_ref IS NOT NULL) OR bool_and(pc.status='CANCELLED' OR pc.legacy_hidden_v78) THEN now() END,
 'AUDITED_EXISTING_CUSTOMER_CLOSE_PI_CI'
 FROM public.rr_market_partner_collection_v67 pc JOIN public.rr_market_partner_customer_v67 cust ON cust.id=pc.partner_customer_id AND cust.data_mode='TEST'
 LEFT JOIN public.rr_market_partner_order_v67 o ON o.collection_id=pc.id
 GROUP BY coalesce(pc.root_collection_id,pc.id),pc.owner_customer_id,pc.partner_customer_id;
WITH ranks AS(SELECT root_id,row_number() OVER(PARTITION BY owner_customer_id,partner_customer_id ORDER BY created_at DESC,collection_no DESC,root_id DESC) rn FROM rr_collection_rules_test71.partner_cycles WHERE status='OPEN')
 UPDATE rr_collection_rules_test71.partner_cycles gate SET status='CLOSED',closed_at=now(),close_reason='LEGACY_DUPLICATE_OPEN_RECONCILED' FROM ranks r WHERE gate.root_id=r.root_id AND r.rn>1;
CREATE UNIQUE INDEX partner_one_open_cycle_unique ON rr_collection_rules_test71.partner_cycles(owner_customer_id,partner_customer_id) WHERE status='OPEN';
CREATE UNIQUE INDEX partner_collection_update_once ON public.rr_market_partner_collection_v67(owner_customer_id,partner_customer_id,root_collection_id,collection_update_no) WHERE NOT legacy_hidden_v78;

CREATE FUNCTION rr_collection_rules_test71.guard_partner_collection()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $guard$
DECLARE gate rr_collection_rules_test71.partner_cycles%rowtype; old_max bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.rr_market_partner_customer_v67 c WHERE c.id=NEW.partner_customer_id AND c.owner_customer_id=NEW.owner_customer_id AND c.data_mode='TEST') THEN RETURN NEW; END IF;
 -- Serialize each distributor/private customer independently.
 PERFORM 1 FROM public.rr_market_partner_customer_v67 WHERE id=NEW.partner_customer_id FOR UPDATE;
 IF TG_OP='UPDATE' AND OLD.root_collection_id IS NOT DISTINCT FROM NEW.root_collection_id AND OLD.collection_no IS NOT DISTINCT FROM NEW.collection_no
 AND OLD.collection_update_no IS NOT DISTINCT FROM NEW.collection_update_no AND OLD.partner_customer_id=NEW.partner_customer_id AND OLD.owner_customer_id=NEW.owner_customer_id
 AND NOT(OLD.legacy_hidden_v78 AND NOT NEW.legacy_hidden_v78) AND NOT(OLD.status='CANCELLED' AND NEW.status<>'CANCELLED') THEN RETURN NEW; END IF;
 IF NEW.root_collection_id IS NULL THEN
  SELECT * INTO gate FROM rr_collection_rules_test71.partner_cycles WHERE owner_customer_id=NEW.owner_customer_id AND partner_customer_id=NEW.partner_customer_id AND status='OPEN';
  IF gate.root_id IS NOT NULL THEN
   NEW.root_collection_id:=gate.root_id;NEW.collection_no:=gate.collection_no;
   SELECT coalesce(max(collection_update_no),-1)+1 INTO NEW.collection_update_no FROM public.rr_market_partner_collection_v67 WHERE coalesce(root_collection_id,id)=gate.root_id AND NOT legacy_hidden_v78;
  ELSE
   NEW.root_collection_id:=NEW.id;
   SELECT coalesce(max(collection_no),0)+1 INTO NEW.collection_no FROM rr_collection_rules_test71.partner_cycles WHERE owner_customer_id=NEW.owner_customer_id AND partner_customer_id=NEW.partner_customer_id;
   NEW.collection_update_no:=0;
  END IF;
 END IF;
 SELECT * INTO gate FROM rr_collection_rules_test71.partner_cycles WHERE root_id=NEW.root_collection_id FOR UPDATE;
 IF gate.root_id IS NULL THEN
  SELECT max(collection_no) INTO old_max FROM rr_collection_rules_test71.partner_cycles WHERE owner_customer_id=NEW.owner_customer_id AND partner_customer_id=NEW.partner_customer_id;
  IF old_max IS NOT NULL AND NEW.collection_no<=old_max THEN RAISE EXCEPTION 'New distributor collection must use a new higher number.'; END IF;
  INSERT INTO rr_collection_rules_test71.partner_cycles(root_id,owner_customer_id,partner_customer_id,collection_no,status) VALUES(NEW.root_collection_id,NEW.owner_customer_id,NEW.partner_customer_id,NEW.collection_no,'OPEN');
 ELSE
  IF gate.owner_customer_id<>NEW.owner_customer_id OR gate.partner_customer_id<>NEW.partner_customer_id OR gate.collection_no<>NEW.collection_no THEN RAISE EXCEPTION 'Distributor collection customer or number mismatch.'; END IF;
  IF gate.status<>'OPEN' THEN RAISE EXCEPTION 'Distributor collection is closed. Use a new collection number.'; END IF;
 END IF;
 NEW.collection_display_no:='COLLECTION '||NEW.collection_no||CASE WHEN NEW.collection_update_no>0 THEN ' · UPDATE '||NEW.collection_update_no ELSE '' END;
 RETURN NEW;
END $guard$;
REVOKE ALL ON FUNCTION rr_collection_rules_test71.guard_partner_collection() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER test71_partner_collection_guard BEFORE INSERT OR UPDATE ON public.rr_market_partner_collection_v67 FOR EACH ROW EXECUTE FUNCTION rr_collection_rules_test71.guard_partner_collection();

CREATE FUNCTION rr_collection_rules_test71.close_partner_cycle_on_order()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $guard$
DECLARE root uuid;
BEGIN
 IF NEW.data_mode='TEST' AND (NEW.customer_closed_at IS NOT NULL OR NEW.status NOT IN('DRAFT','SUPERSEDED')
 OR NEW.distributor_pi_created_at IS NOT NULL OR NEW.pi_ref IS NOT NULL OR NEW.ci_ref IS NOT NULL) THEN
  SELECT coalesce(pc.root_collection_id,pc.id) INTO root FROM public.rr_market_partner_collection_v67 pc WHERE pc.id=NEW.collection_id;
  UPDATE rr_collection_rules_test71.partner_cycles SET status='CLOSED',closed_at=coalesce(closed_at,now()),close_reason='CUSTOMER CLOSE OR DISTRIBUTOR/REDZED PI CI MADE' WHERE root_id=root AND status='OPEN';
  INSERT INTO rr_collection_rules_test71.chat_cleanup_audit(message_id,previous_row,reason)
   SELECT m.id,to_jsonb(m),'CLOSED_DISTRIBUTOR_COLLECTION_HISTORY' FROM public.rr_customer_chat_messages_v9433 m WHERE m.archived_at IS NULL AND m.payload->>'partner_collection_root_id'=root::text AND m.payload->>'source' IN('PARTNER_MARKET_WINDOW','PARTNER_MARKET_REQUIREMENT') ON CONFLICT(message_id) DO NOTHING;
  UPDATE public.rr_customer_chat_messages_v9433 SET archived_at=now(),archive_reason='ONE_OPEN_COLLECTION_RULE_CLEANUP' WHERE archived_at IS NULL AND payload->>'partner_collection_root_id'=root::text AND payload->>'source' IN('PARTNER_MARKET_WINDOW','PARTNER_MARKET_REQUIREMENT');
 END IF;RETURN NEW;
END $guard$;
REVOKE ALL ON FUNCTION rr_collection_rules_test71.close_partner_cycle_on_order() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER test71_partner_order_closes_cycle AFTER INSERT OR UPDATE ON public.rr_market_partner_order_v67 FOR EACH ROW EXECUTE FUNCTION rr_collection_rules_test71.close_partner_cycle_on_order();

CREATE FUNCTION rr_collection_rules_test71.guard_partner_requirement()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $guard$
BEGIN
 IF NEW.data_mode='TEST' AND NEW.status='DRAFT' AND EXISTS(
 SELECT 1 FROM public.rr_market_partner_collection_v67 pc JOIN rr_collection_rules_test71.partner_cycles gate ON gate.root_id=coalesce(pc.root_collection_id,pc.id)
 WHERE pc.id=NEW.collection_id AND gate.status<>'OPEN') THEN RAISE EXCEPTION 'Distributor collection is closed. Submit requirement under the new collection number.'; END IF;
 RETURN NEW;
END $guard$;
REVOKE ALL ON FUNCTION rr_collection_rules_test71.guard_partner_requirement() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER test71_partner_requirement_guard BEFORE INSERT OR UPDATE OF collection_id,status ON public.rr_market_partner_order_v67 FOR EACH ROW EXECUTE FUNCTION rr_collection_rules_test71.guard_partner_requirement();

INSERT INTO rr_collection_rules_test71.chat_cleanup_audit(message_id,previous_row,reason)
 SELECT m.id,to_jsonb(m),'CLOSED_DISTRIBUTOR_COLLECTION_HISTORY' FROM public.rr_customer_chat_messages_v9433 m JOIN rr_collection_rules_test71.partner_cycles gate ON gate.root_id::text=m.payload->>'partner_collection_root_id'
 WHERE gate.status='CLOSED' AND m.archived_at IS NULL AND m.payload->>'source' IN('PARTNER_MARKET_WINDOW','PARTNER_MARKET_REQUIREMENT') ON CONFLICT(message_id) DO NOTHING;
UPDATE public.rr_customer_chat_messages_v9433 m SET archived_at=now(),archive_reason='ONE_OPEN_COLLECTION_RULE_CLEANUP'
 FROM rr_collection_rules_test71.partner_cycles gate WHERE gate.status='CLOSED' AND gate.root_id::text=m.payload->>'partner_collection_root_id' AND m.archived_at IS NULL AND m.payload->>'source' IN('PARTNER_MARKET_WINDOW','PARTNER_MARKET_REQUIREMENT');
CREATE OR REPLACE FUNCTION public.rr_market_partner_collection_priced_create_v67(p_session_token text, p_device_id text, p_partner_customer_id uuid, p_lines jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
 v_ctx jsonb;v_owner uuid;v_creator uuid;v_share uuid;v_collection uuid:=gen_random_uuid();
 v_root uuid;v_token text;v_code text;v_name text;v_mobile text;v_tries int:=0;
 v_line jsonb;v_card record;v_lot text;v_margin numeric;v_discount numeric;v_sale numeric;v_final numeric;
 v_collection_no bigint;v_update_no integer;v_display text;v_header text;
begin
 v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
 if not(v_ctx->>'send_collection_enabled')::boolean then raise exception 'Collection sending is disabled.';end if;
 v_owner:=(v_ctx->>'owner_customer_id')::uuid;
 select private_name,private_mobile into v_name,v_mobile from public.rr_market_partner_customer_v67
 where id=p_partner_customer_id and owner_customer_id=v_owner and status='ACTIVE';
 if v_name is null then raise exception 'Private customer not found.';end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'Select at least one lot.';end if;
 v_margin:=greatest(0,coalesce((p_lines->0->>'margin_amount')::numeric,0));
 v_discount:=greatest(0,coalesce((p_lines->0->>'discount_amount')::numeric,0));
 select s.created_by into v_creator
 from public.rr_customer_session_v9590 cs join public.rr_market_share_v9420 s on s.id=cs.share_id
 where cs.session_token_hash=encode(extensions.digest(trim(p_session_token),'sha256'),'hex')
 and cs.customer_id=v_owner and cs.revoked_at is null and cs.expires_at>now()limit 1;
 if v_creator is null then raise exception 'Verified share owner is unavailable.';end if;

 perform pg_advisory_xact_lock(hashtext('RR_TEST67_GLOBAL_COLLECTION'));
 select pc.root_collection_id,pc.collection_no,max(pc.collection_update_no)+1
 into v_root,v_collection_no,v_update_no
 from public.rr_market_partner_collection_v67 pc
 where pc.owner_customer_id=v_owner and pc.partner_customer_id=p_partner_customer_id and pc.status<>'CANCELLED' and exists(select 1 from rr_collection_rules_test71.partner_cycles gate where gate.root_id=coalesce(pc.root_collection_id,pc.id) and gate.status='OPEN')
 and not exists(
  select 1 from public.rr_market_partner_collection_v67 cx
  join public.rr_market_partner_order_v67 ox on ox.collection_id=cx.id
  where cx.root_collection_id=pc.root_collection_id
  and ox.status in('READY','BATCHED','PI_PROPOSED','CONFIRMED','PARTIAL_CONFIRMED','CANCELLED','CI_FINAL','CLOSED')
 )group by pc.root_collection_id,pc.collection_no order by max(pc.created_at)desc limit 1;
 if v_root is null then
  select coalesce(max(collection_no),0)+1 into v_collection_no from public.rr_market_partner_collection_v67 where owner_customer_id=v_owner and partner_customer_id=p_partner_customer_id;
  v_root:=v_collection;v_update_no:=0;
 end if;
 v_display:='COLLECTION '||v_collection_no::text||case when v_update_no>0 then ' · UPDATE '||v_update_no::text else '' end;
 loop
  v_code:=upper(substr(md5(random()::text||clock_timestamp()::text),1,10));
  begin
   insert into public.rr_market_share_v9420(customer_id,customer_name,created_by,data_mode,status,short_code)
   values(null,v_name,v_creator,'TEST','ACTIVE',v_code)returning id,token into v_share,v_token;exit;
  exception when unique_violation then v_tries:=v_tries+1;if v_tries>8 then raise;end if;end;
 end loop;
 insert into public.rr_market_partner_collection_v67(
  id,owner_customer_id,partner_customer_id,share_id,root_collection_id,collection_no,collection_update_no,collection_display_no
 )values(v_collection,v_owner,p_partner_customer_id,v_share,v_root,v_collection_no,v_update_no,v_display);
 for v_line in select value from jsonb_array_elements(p_lines)loop
  v_lot:=nullif(trim(v_line->>'lot_no'),'');
  select * into v_card from public.rr_web_window_cards_v9329(v_lot,null,null,'TEST',10,0)where lot_no=v_lot limit 1;
  if v_card.lot_no is null then raise exception 'TEST lot % is unavailable.',v_lot;end if;
  v_sale:=coalesce(v_card.sale_rate,0)+v_margin;v_final:=greatest(0,v_sale-v_discount);
  insert into public.rr_market_share_lots_v9420(share_id,lot_no,sort_no)
  values(v_share,v_lot,(select count(*)+1 from public.rr_market_share_lots_v9420 where share_id=v_share))on conflict do nothing;
  insert into public.rr_market_partner_collection_line_v67(
   collection_id,lot_no,category,size_text,cloth_name,primary_image_url,media,stock_status,
   base_rate,margin_amount,distributor_sale_rate,discount_amount,final_customer_rate
  )values(v_collection,v_lot,coalesce(v_card.category,''),v_card.size_text,v_card.cloth_name,v_card.primary_image_url,
   coalesce(v_card.media,'[]'::jsonb),case when coalesce(v_card.available_qty,0)<=0 then 'OUT OF STOCK'
   when upper(coalesce(v_card.stock_status,''))='LOW_STOCK'then'LOW STOCK'else'STOCK-IN'end,
   coalesce(v_card.sale_rate,0),v_margin,v_sale,v_discount,v_final);
 end loop;
 update public.rr_market_partner_customer_v67 set default_margin_amount=v_margin,
 default_discount_amount=v_discount,updated_at=now()where id=p_partner_customer_id;
 v_header:=public.rr_market_partner_header_v67(v_owner,p_partner_customer_id);
 insert into public.rr_market_partner_event_v67(owner_customer_id,event_type,actor_kind,payload)
 values(v_owner,'COLLECTION_SENT_TO_CUSTOMER','DISTRIBUTOR',jsonb_build_object(
  'collection_id',v_collection,'collection_display_no',v_display,'customer_ref',
  (select customer_ref from public.rr_market_partner_customer_v67 where id=p_partner_customer_id),'channel','PRIVATE_CUSTOMER_CHAT'));
 return jsonb_build_object('collection_id',v_collection,'share_id',v_share,'token',v_token,
  'short_code',v_code,'lot_count',(select count(*)from public.rr_market_partner_collection_line_v67 where collection_id=v_collection),
  'collection_no',v_collection_no,'collection_update_no',v_update_no,'collection_display_no',v_display,
  'header_title',v_header,'customer_mobile',v_mobile,'redzed_status','NOT_SENT');
end $function$
;
CREATE OR REPLACE FUNCTION public.rr_market_partner_submit_requirement_v67(p_token text, p_customer_name text, p_mobile text, p_message text, p_lines jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_map public.rr_market_partner_collection_v67%rowtype;
  v_target public.rr_market_partner_collection_v67%rowtype;
  v_root uuid;
  v_order uuid:=gen_random_uuid();
  v_root_order uuid;
  v_line jsonb;
  v_price public.rr_market_partner_collection_line_v67%rowtype;
  v_card record;
  v_lot text;
  v_qty integer;
  v_accepted integer;
  v_requirement_no bigint;
  v_update_no integer;
  v_owner_seq bigint;
  v_prefix text;
  v_ref text;
  v_result_lines jsonb:='[]'::jsonb;
  v_inserted integer:=0;
begin
  select pc.* into v_map
  from public.rr_market_partner_collection_v67 pc
  join public.rr_market_share_v9420 s on s.id=pc.share_id
  join public.rr_market_partner_customer_v67 c on c.id=pc.partner_customer_id
  where (s.token=p_token or s.short_code=upper(p_token))
    and s.data_mode='TEST' and s.status='ACTIVE' and c.status='ACTIVE'
  order by case when s.token=p_token then 0 else 1 end limit 1 for update of pc;
  if v_map.id is null then
    return public.rr_market_submit_requirement_v9508(p_token,p_customer_name,p_mobile,p_message,p_lines,null);
  end if;
  if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then
    raise exception 'Select quantity before sending requirement.';
  end if;
  v_root:=coalesce(v_map.root_collection_id,v_map.id);
  if not exists(select 1 from rr_collection_rules_test71.partner_cycles gate where gate.root_id=v_root and gate.status='OPEN') then raise exception 'Distributor collection is closed. Use a new collection number.';end if;
  select pc.* into v_target from public.rr_market_partner_collection_v67 pc
  where coalesce(pc.root_collection_id,pc.id)=v_root
  order by pc.collection_update_no desc,pc.created_at desc limit 1 for update;
  if exists(
    select 1 from public.rr_market_partner_order_v67 o
    join public.rr_market_partner_collection_v67 pc on pc.id=o.collection_id
    where coalesce(pc.root_collection_id,pc.id)=v_root
      and o.status not in('DRAFT','SUPERSEDED')
  ) then raise exception 'Requirement is closed. Distributor will continue this order.'; end if;
  perform pg_advisory_xact_lock(hashtext('RR_TEST67_GLOBAL_REQUIREMENT'));
  select o.requirement_no,coalesce(o.root_order_id,o.id)
  into v_requirement_no,v_root_order
  from public.rr_market_partner_order_v67 o
  join public.rr_market_partner_collection_v67 pc on pc.id=o.collection_id
  where coalesce(pc.root_collection_id,pc.id)=v_root and o.requirement_no is not null
  order by o.requirement_update_no,o.created_at,o.id limit 1;
  if v_requirement_no is null then
    update public.rr_market_partner_global_sequence_v67
    set current_no=current_no+1,updated_at=now()
    where sequence_kind='REQUIREMENT' returning current_no into v_requirement_no;
    v_root_order:=v_order;
    v_update_no:=0;
  else
    select coalesce(max(o.requirement_update_no),-1)+1 into v_update_no
    from public.rr_market_partner_order_v67 o
    join public.rr_market_partner_collection_v67 pc on pc.id=o.collection_id
    where coalesce(pc.root_collection_id,pc.id)=v_root and o.requirement_no=v_requirement_no;
  end if;
  v_ref:='REQUIREMENT '||v_requirement_no::text||case when v_update_no>0 then ' · UPDATE '||v_update_no::text else '' end;
  select prefix,current_no+1 into v_prefix,v_owner_seq
  from public.rr_market_owner_sequence_v67
  where owner_key='CUSTOMER:'||v_map.owner_customer_id::text and data_mode='TEST' for update;
  if v_prefix is null then raise exception 'Distributor prefix is not configured.'; end if;
  update public.rr_market_owner_sequence_v67 set current_no=v_owner_seq,updated_at=now()
  where owner_key='CUSTOMER:'||v_map.owner_customer_id::text and data_mode='TEST';
  update public.rr_market_partner_order_v67 o set status='SUPERSEDED',updated_at=now()
  where o.status='DRAFT' and exists(
    select 1 from public.rr_market_partner_collection_v67 pc
    where pc.id=o.collection_id and coalesce(pc.root_collection_id,pc.id)=v_root
  );
  insert into public.rr_market_partner_order_v67(
    id,owner_customer_id,partner_customer_id,sequence_no,order_ref,status,linked_requirement_id,
    collection_id,root_order_id,requirement_no,requirement_update_no,requirement_display_no
  ) values(
    v_order,v_map.owner_customer_id,v_map.partner_customer_id,v_owner_seq,v_ref,'DRAFT',null,
    v_target.id,v_root_order,v_requirement_no,v_update_no,v_ref
  );
  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_lot:=nullif(trim(v_line->>'lot_no'),'');
    v_qty:=greatest(0,floor(coalesce((v_line->>'qty')::numeric,0)))::integer;
    if v_lot is null or v_qty<=0 then continue; end if;
    select l.* into v_price
    from public.rr_market_partner_collection_line_v67 l
    join public.rr_market_partner_collection_v67 pc on pc.id=l.collection_id
    where coalesce(pc.root_collection_id,pc.id)=v_root and l.lot_no=v_lot
    order by pc.collection_update_no desc,l.created_at desc limit 1;
    if v_price.collection_id is null then raise exception 'Lot % is not part of this private collection.',v_lot; end if;
    select * into v_card from public.rr_web_window_cards_v9329(v_lot,null,null,'TEST',10,0)
    where lot_no=v_lot limit 1;
    v_accepted:=least(v_qty,greatest(0,coalesce(v_card.available_qty,0))::integer);
    if v_accepted<=0 then continue; end if;
    insert into public.rr_market_partner_order_line_v67(
      order_id,lot_no,article_name,category,size_text,image_url,requested_qty,
      base_rate,rate_enhancement,customer_discount,final_customer_rate
    ) values(
      v_order,v_lot,coalesce(nullif(v_price.cloth_name,''),nullif(v_price.category,''),v_lot),
      v_price.category,v_price.size_text,v_price.primary_image_url,v_accepted,
      v_price.base_rate,v_price.margin_amount,v_price.discount_amount,v_price.final_customer_rate
    );
    v_result_lines:=v_result_lines||jsonb_build_array(jsonb_build_object(
      'lot_no',v_lot,'requested_qty',v_qty,'accepted_qty',v_accepted,
      'max_available',greatest(0,coalesce(v_card.available_qty,0))::integer
    ));
    v_inserted:=v_inserted+1;
  end loop;
  if v_inserted=0 then raise exception 'Selected lots are currently unavailable.'; end if;
  update public.rr_market_partner_collection_v67
  set order_id=v_order,status='REQUIREMENT_RECEIVED',requirement_no=v_requirement_no,
    requirement_update_no=v_update_no,requirement_display_no=v_ref,updated_at=now()
  where id=v_target.id;
  insert into public.rr_market_partner_event_v67(owner_customer_id,order_id,event_type,note,actor_kind,payload)
  values(v_map.owner_customer_id,v_order,'CUSTOMER_REQUIREMENT_DRAFT',nullif(trim(p_message),''),'CUSTOMER',
    jsonb_build_object('customer_id',v_map.partner_customer_id,'requirement_display_no',v_ref,
      'collection_no',v_target.collection_no,'collection_display_no',v_target.collection_display_no,
      'sent_to','DISTRIBUTOR'));
  return jsonb_build_object('ok',true,'requirement_id',v_order,'order_id',v_order,
    'requirement_no',v_requirement_no,'requirement_update_no',v_update_no,
    'requirement_display_no',v_ref,'collection_display_no',v_target.collection_display_no,
    'status','DRAFT','can_close',true,'sent_to','DISTRIBUTOR','lines',v_result_lines);
end
$function$
;

