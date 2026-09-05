-- TEST67 runtime correction: customer_rate is generated from base_rate + enhancement.
create or replace function public.rr_market_partner_submit_requirement_v67(
  p_token text,p_customer_name text,p_mobile text,p_message text,p_lines jsonb
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
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
$$;

revoke all on function public.rr_market_partner_submit_requirement_v67(text,text,text,text,jsonb) from public;
grant execute on function public.rr_market_partner_submit_requirement_v67(text,text,text,text,jsonb) to anon,authenticated,service_role;
