-- TEST67 collection creator hotfix.
-- Bind every downstream collection share to the verified creator of the distributor session.

create or replace function public.rr_market_partner_collection_create_v67(
  p_session_token text,
  p_device_id text,
  p_partner_customer_id uuid,
  p_lots text[]
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_ctx jsonb;
  v_owner uuid;
  v_creator uuid;
  v_share uuid;
  v_token text;
  v_code text;
  v_name text;
  v_tries int:=0;
begin
  v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
  if not (v_ctx->>'send_collection_enabled')::boolean then
    raise exception 'Collection sending is disabled.';
  end if;
  v_owner:=(v_ctx->>'owner_customer_id')::uuid;

  select s.created_by into v_creator
  from public.rr_customer_session_v9590 cs
  join public.rr_market_share_v9420 s on s.id=cs.share_id
  where cs.session_token_hash=encode(extensions.digest(trim(p_session_token),'sha256'),'hex')
    and cs.customer_id=v_owner
    and cs.revoked_at is null
    and cs.expires_at>now()
  limit 1;
  if v_creator is null then raise exception 'Verified share owner is unavailable.';end if;

  select private_name into v_name
  from public.rr_market_partner_customer_v67
  where id=p_partner_customer_id and owner_customer_id=v_owner and status='ACTIVE';
  if v_name is null then raise exception 'Private customer not found.';end if;
  if coalesce(array_length(p_lots,1),0)=0 then raise exception 'Select at least one lot.';end if;

  loop
    v_code:=upper(substr(md5(random()::text||clock_timestamp()::text),1,10));
    begin
      insert into public.rr_market_share_v9420(customer_id,customer_name,created_by,data_mode,status,short_code)
      values(null,v_name,v_creator,'TEST','ACTIVE',v_code)
      returning id,token into v_share,v_token;
      exit;
    exception when unique_violation then
      v_tries:=v_tries+1;
      if v_tries>8 then raise;end if;
    end;
  end loop;

  insert into public.rr_market_share_lots_v9420(share_id,lot_no,sort_no)
  select v_share,trim(x),ord
  from unnest(p_lots) with ordinality u(x,ord)
  where trim(x)<>''
  on conflict do nothing;
  if not exists(select 1 from public.rr_market_share_lots_v9420 where share_id=v_share) then
    raise exception 'Selected TEST lots are unavailable.';
  end if;
  insert into public.rr_market_partner_collection_v67(owner_customer_id,partner_customer_id,share_id)
  values(v_owner,p_partner_customer_id,v_share);
  return jsonb_build_object(
    'share_id',v_share,'token',v_token,'short_code',v_code,
    'lot_count',(select count(*) from public.rr_market_share_lots_v9420 where share_id=v_share)
  );
end $$;

create or replace function public.rr_market_partner_collection_priced_create_v67(
  p_session_token text,
  p_device_id text,
  p_partner_customer_id uuid,
  p_lines jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_ctx jsonb;
  v_owner uuid;
  v_creator uuid;
  v_share uuid;
  v_collection uuid;
  v_token text;
  v_code text;
  v_name text;
  v_tries int:=0;
  v_line jsonb;
  v_card record;
  v_lot text;
  v_margin numeric;
  v_discount numeric;
  v_sale numeric;
  v_final numeric;
begin
  v_ctx:=public.rr_market_partner_context_v67(p_session_token,p_device_id);
  if not (v_ctx->>'send_collection_enabled')::boolean then
    raise exception 'Collection sending is disabled.';
  end if;
  v_owner:=(v_ctx->>'owner_customer_id')::uuid;

  select s.created_by into v_creator
  from public.rr_customer_session_v9590 cs
  join public.rr_market_share_v9420 s on s.id=cs.share_id
  where cs.session_token_hash=encode(extensions.digest(trim(p_session_token),'sha256'),'hex')
    and cs.customer_id=v_owner
    and cs.revoked_at is null
    and cs.expires_at>now()
  limit 1;
  if v_creator is null then raise exception 'Verified share owner is unavailable.';end if;

  select private_name into v_name
  from public.rr_market_partner_customer_v67
  where id=p_partner_customer_id and owner_customer_id=v_owner and status='ACTIVE';
  if v_name is null then raise exception 'Private customer not found.';end if;
  if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then
    raise exception 'Select at least one lot.';
  end if;

  loop
    v_code:=upper(substr(md5(random()::text||clock_timestamp()::text),1,10));
    begin
      insert into public.rr_market_share_v9420(customer_id,customer_name,created_by,data_mode,status,short_code)
      values(null,v_name,v_creator,'TEST','ACTIVE',v_code)
      returning id,token into v_share,v_token;
      exit;
    exception when unique_violation then
      v_tries:=v_tries+1;
      if v_tries>8 then raise;end if;
    end;
  end loop;

  insert into public.rr_market_partner_collection_v67(owner_customer_id,partner_customer_id,share_id)
  values(v_owner,p_partner_customer_id,v_share)
  returning id into v_collection;

  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_lot:=nullif(trim(v_line->>'lot_no'),'');
    v_margin:=greatest(0,coalesce((v_line->>'margin_amount')::numeric,0));
    v_discount:=greatest(0,coalesce((v_line->>'discount_amount')::numeric,0));
    select * into v_card
    from public.rr_web_window_cards_v9329(v_lot,null,null,'TEST',10,0)
    where lot_no=v_lot
    limit 1;
    if v_card.lot_no is null then raise exception 'TEST lot % is unavailable.',v_lot;end if;
    v_sale:=coalesce(v_card.sale_rate,0)+v_margin;
    v_final:=greatest(0,v_sale-v_discount);

    insert into public.rr_market_share_lots_v9420(share_id,lot_no,sort_no)
    values(
      v_share,
      v_lot,
      (select count(*)+1 from public.rr_market_share_lots_v9420 where share_id=v_share)
    ) on conflict do nothing;
    insert into public.rr_market_partner_collection_line_v67(
      collection_id,lot_no,category,cloth_name,primary_image_url,media,stock_status,
      base_rate,margin_amount,distributor_sale_rate,discount_amount,final_customer_rate
    ) values(
      v_collection,v_lot,coalesce(v_card.category,''),v_card.cloth_name,
      v_card.primary_image_url,coalesce(v_card.media,'[]'::jsonb),
      case
        when coalesce(v_card.available_qty,0)<=0 then 'OUT OF STOCK'
        when upper(coalesce(v_card.stock_status,''))='LOW_STOCK' then 'LOW STOCK'
        else 'STOCK-IN'
      end,
      coalesce(v_card.sale_rate,0),v_margin,v_sale,v_discount,v_final
    );
  end loop;

  return jsonb_build_object(
    'collection_id',v_collection,'share_id',v_share,'token',v_token,
    'short_code',v_code,
    'lot_count',(select count(*) from public.rr_market_partner_collection_line_v67 where collection_id=v_collection)
  );
end $$;

revoke all on function public.rr_market_partner_collection_create_v67(text,text,uuid,text[]) from public;
revoke all on function public.rr_market_partner_collection_priced_create_v67(text,text,uuid,jsonb) from public;
grant execute on function public.rr_market_partner_collection_create_v67(text,text,uuid,text[]) to anon,authenticated,service_role;
grant execute on function public.rr_market_partner_collection_priced_create_v67(text,text,uuid,jsonb) to anon,authenticated,service_role;
