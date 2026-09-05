-- TEST67 final distributor directory + private customer flow corrections.
-- MAIN/REAL objects and rows are intentionally untouched.

create or replace function public.rr_market_partner_customer_group_sync_v67()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_group uuid:=new.group_id;
  v_name text;
begin
  if new.data_mode<>'TEST' then return new; end if;
  v_name:=upper(regexp_replace(trim(new.private_name),'\s+',' ','g'))||' GROUP';
  if exists(
    select 1 from public.rr_market_partner_group_v67 g
    where g.owner_customer_id=new.owner_customer_id and g.data_mode='TEST'
      and upper(g.group_name)=upper(v_name) and g.id is distinct from v_group
  ) then
    v_name:=v_name||' · '||new.customer_ref;
  end if;
  if v_group is null then
    insert into public.rr_market_partner_group_v67(
      owner_customer_id,group_name,group_info,status,data_mode
    ) values(
      new.owner_customer_id,v_name,null,new.status,'TEST'
    )
    on conflict(owner_customer_id,group_name,data_mode)
    do update set status=excluded.status,updated_at=now()
    returning id into v_group;
    update public.rr_market_partner_customer_v67
      set group_id=v_group,updated_at=now() where id=new.id;
  else
    update public.rr_market_partner_group_v67
      set group_name=v_name,group_info=null,status=new.status,updated_at=now()
      where id=v_group and owner_customer_id=new.owner_customer_id and data_mode='TEST';
  end if;
  if new.status='ACTIVE' then
    insert into public.rr_market_partner_staff_group_v67(staff_id,group_id,owner_customer_id)
    select s.id,v_group,new.owner_customer_id
    from public.rr_market_partner_staff_v67 s
    where s.owner_customer_id=new.owner_customer_id and s.data_mode='TEST' and s.status='ACTIVE'
    on conflict do nothing;
  else
    delete from public.rr_market_partner_staff_group_v67
    where group_id=v_group and owner_customer_id=new.owner_customer_id;
  end if;
  return new;
end
$$;

drop trigger if exists rr_market_partner_customer_private_group_v67 on public.rr_market_partner_customer_v67;
drop trigger if exists rr_market_partner_customer_group_sync_v67 on public.rr_market_partner_customer_v67;
create trigger rr_market_partner_customer_group_sync_v67
after insert or update of private_name,status on public.rr_market_partner_customer_v67
for each row execute function public.rr_market_partner_customer_group_sync_v67();

update public.rr_market_partner_customer_v67
set private_name=private_name
where data_mode='TEST';

create or replace function public.rr_market_partner_contact_save_v67(
  p_session_token text,
  p_device_id text,
  p_contact_kind text,
  p_name text,
  p_mobile text,
  p_role text default null,
  p_active boolean default true
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_ctx jsonb;
  v_owner uuid;
  v_kind text:=upper(trim(coalesce(p_contact_kind,'')));
  v_name text:=nullif(regexp_replace(trim(coalesce(p_name,'')),'\s+',' ','g'),'');
  v_mobile text:=nullif(regexp_replace(coalesce(p_mobile,''),'[^0-9+]','','g'),'');
  v_status text:=case when coalesce(p_active,true) then 'ACTIVE' else 'INACTIVE' end;
  v_id uuid;
  v_group uuid;
  v_ref text;
  v_prefix text;
  v_no bigint;
  v_created boolean:=false;
begin
  v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
  v_owner:=(v_ctx->>'owner_customer_id')::uuid;
  if v_kind not in('CUSTOMER','STAFF') then raise exception 'Choose CUSTOMER or STAFF.'; end if;
  if v_name is null then raise exception 'Contact name is required.'; end if;
  if v_mobile is null then raise exception 'Mobile number is required.'; end if;
  perform pg_advisory_xact_lock(hashtext('RR_TEST67_CONTACT:'||v_owner::text||':'||v_kind||':'||v_mobile));

  if v_kind='CUSTOMER' then
    if not (v_ctx->>'customer_groups_enabled')::boolean then raise exception 'Customer creation is disabled.'; end if;
    select c.id into v_id
    from public.rr_market_partner_customer_v67 c
    where c.owner_customer_id=v_owner and c.data_mode='TEST'
      and regexp_replace(coalesce(c.private_mobile,''),'[^0-9+]','','g')=v_mobile
    order by c.created_at limit 1 for update;
    if v_id is null then
      select prefix into v_prefix from public.rr_market_owner_sequence_v67
      where owner_key='CUSTOMER:'||v_owner::text and data_mode='TEST';
      if v_prefix is null then raise exception 'Distributor prefix is not configured.'; end if;
      select coalesce(max((regexp_match(customer_ref,'([0-9]+)$'))[1]::bigint),0)+1
      into v_no from public.rr_market_partner_customer_v67
      where owner_customer_id=v_owner and data_mode='TEST';
      v_ref:=v_prefix||'-C-'||lpad(v_no::text,4,'0');
      insert into public.rr_market_partner_customer_v67(
        owner_customer_id,customer_ref,private_name,private_mobile,status,data_mode
      ) values(v_owner,v_ref,v_name,v_mobile,v_status,'TEST') returning id,group_id into v_id,v_group;
      v_created:=true;
    else
      update public.rr_market_partner_customer_v67
      set private_name=v_name,private_mobile=v_mobile,status=v_status,updated_at=now()
      where id=v_id
      returning customer_ref,group_id into v_ref,v_group;
    end if;
    select group_id into v_group from public.rr_market_partner_customer_v67 where id=v_id;
    return jsonb_build_object('ok',true,'kind',v_kind,'id',v_id,'customer_ref',v_ref,
      'name',v_name,'mobile',v_mobile,'status',v_status,'group_id',v_group,'created',v_created);
  end if;

  if not (v_ctx->>'staff_management_enabled')::boolean then raise exception 'Staff management is disabled.'; end if;
  select s.id into v_id
  from public.rr_market_partner_staff_v67 s
  where s.owner_customer_id=v_owner and s.data_mode='TEST'
    and regexp_replace(coalesce(s.private_mobile,''),'[^0-9+]','','g')=v_mobile
  order by s.created_at limit 1 for update;
  if v_id is null then
    insert into public.rr_market_partner_staff_v67(
      owner_customer_id,staff_name,private_mobile,staff_role,status,data_mode
    ) values(v_owner,v_name,v_mobile,upper(coalesce(nullif(trim(p_role),''),'STAFF')),v_status,'TEST')
    returning id into v_id;
    v_created:=true;
  else
    update public.rr_market_partner_staff_v67
    set staff_name=v_name,private_mobile=v_mobile,
      staff_role=upper(coalesce(nullif(trim(p_role),''),staff_role)),status=v_status,updated_at=now()
    where id=v_id;
  end if;
  if v_status='ACTIVE' then
    insert into public.rr_market_partner_staff_group_v67(staff_id,group_id,owner_customer_id)
    select v_id,c.group_id,v_owner
    from public.rr_market_partner_customer_v67 c
    where c.owner_customer_id=v_owner and c.data_mode='TEST' and c.status='ACTIVE' and c.group_id is not null
    on conflict do nothing;
  else
    delete from public.rr_market_partner_staff_group_v67
    where staff_id=v_id and owner_customer_id=v_owner;
  end if;
  return jsonb_build_object('ok',true,'kind',v_kind,'id',v_id,'name',v_name,'mobile',v_mobile,
    'role',upper(coalesce(nullif(trim(p_role),''),'STAFF')),'status',v_status,
    'group_count',(select count(*) from public.rr_market_partner_staff_group_v67 where staff_id=v_id),
    'created',v_created);
end
$$;

create or replace function public.rr_market_partner_contact_bulk_v67(
  p_session_token text,p_device_id text,p_contact_kind text,p_contacts jsonb,p_active boolean default true
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_row jsonb;v_saved int:=0;v_skipped int:=0;
begin
  if jsonb_typeof(p_contacts)<>'array' then raise exception 'VCF contacts must be an array.'; end if;
  for v_row in select value from jsonb_array_elements(p_contacts) loop
    begin
      perform public.rr_market_partner_contact_save_v67(
        p_session_token,p_device_id,p_contact_kind,v_row->>'name',v_row->>'mobile',v_row->>'role',p_active
      );
      v_saved:=v_saved+1;
    exception when others then
      v_skipped:=v_skipped+1;
    end;
  end loop;
  return jsonb_build_object('saved',v_saved,'skipped',v_skipped,'total',jsonb_array_length(p_contacts));
end
$$;

create or replace function public.rr_market_partner_customer_status_set_v67(
  p_session_token text,p_device_id text,p_partner_customer_id uuid,p_active boolean
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_ctx jsonb;v_owner uuid;v_status text;
begin
  v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
  v_owner:=(v_ctx->>'owner_customer_id')::uuid;
  v_status:=case when coalesce(p_active,false) then 'ACTIVE' else 'INACTIVE' end;
  update public.rr_market_partner_customer_v67
  set status=v_status,updated_at=now()
  where id=p_partner_customer_id and owner_customer_id=v_owner and data_mode='TEST';
  if not found then raise exception 'Distributor customer is unavailable.'; end if;
  return jsonb_build_object('ok',true,'customer_id',p_partner_customer_id,'status',v_status);
end
$$;

create or replace function public.rr_market_partner_customer_create_v67(
  p_session_token text,p_device_id text,p_name text,p_mobile text default null
) returns jsonb
language sql
security definer
set search_path=''
as $$
  select public.rr_market_partner_contact_save_v67(
    p_session_token,p_device_id,'CUSTOMER',p_name,p_mobile,null,true
  );
$$;

create or replace function public.rr_market_partner_staff_create_v67(
  p_session_token text,p_device_id text,p_name text,p_mobile text,p_role text default 'SALES'
) returns jsonb
language sql
security definer
set search_path=''
as $$
  select public.rr_market_partner_contact_save_v67(
    p_session_token,p_device_id,'STAFF',p_name,p_mobile,p_role,true
  );
$$;

create or replace function public.rr_market_partner_customer_bulk_vcf_v67(
  p_session_token text,p_device_id text,p_contacts jsonb
) returns jsonb
language sql
security definer
set search_path=''
as $$
  select public.rr_market_partner_contact_bulk_v67(
    p_session_token,p_device_id,'CUSTOMER',p_contacts,true
  );
$$;

-- Customer token is the identity.  A distributor-customer requirement is kept
-- entirely inside TEST67 until the distributor explicitly pushes the closed row.
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

-- Keep every token in a collection chain current: one collection card, latest
-- update label, and unique lots ordered with fresh samples first.
create or replace function public.rr_market_share_view_v9420(p_token text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
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
    cross join lateral public.rr_web_window_cards_v9329(l.lot_no,null,null,s.data_mode,1,0)c
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
  cross join lateral public.rr_web_window_cards_v9329(pl.lot_no,null,null,'TEST',1,0)c
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
$$;

revoke all on function public.rr_market_partner_customer_group_sync_v67() from public,anon,authenticated;
revoke all on function public.rr_market_partner_contact_save_v67(text,text,text,text,text,text,boolean) from public;
revoke all on function public.rr_market_partner_contact_bulk_v67(text,text,text,jsonb,boolean) from public;
revoke all on function public.rr_market_partner_customer_status_set_v67(text,text,uuid,boolean) from public;
revoke all on function public.rr_market_partner_customer_create_v67(text,text,text,text) from public;
revoke all on function public.rr_market_partner_staff_create_v67(text,text,text,text,text) from public;
revoke all on function public.rr_market_partner_customer_bulk_vcf_v67(text,text,jsonb) from public;
revoke all on function public.rr_market_partner_submit_requirement_v67(text,text,text,text,jsonb) from public;
revoke all on function public.rr_market_share_view_v9420(text) from public;

grant execute on function public.rr_market_partner_contact_save_v67(text,text,text,text,text,text,boolean) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_contact_bulk_v67(text,text,text,jsonb,boolean) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_status_set_v67(text,text,uuid,boolean) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_create_v67(text,text,text,text) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_staff_create_v67(text,text,text,text,text) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_customer_bulk_vcf_v67(text,text,jsonb) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_submit_requirement_v67(text,text,text,text,jsonb) to anon,authenticated,service_role;
grant execute on function public.rr_market_share_view_v9420(text) to anon,authenticated,service_role;
