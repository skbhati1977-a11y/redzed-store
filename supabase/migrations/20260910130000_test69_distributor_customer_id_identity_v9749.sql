begin;

create or replace function public.rr_customer_sales_map_sync_v9745(
  p_source_kind text,p_source_id uuid,p_name text,p_mobile text,p_active boolean default true
) returns uuid
language plpgsql security definer set search_path='public'
as $function$
declare
  v_kind text:=upper(trim(coalesce(p_source_kind,'')));
  v_name text:=trim(coalesce(p_name,''));
  v_mobile text:=right(regexp_replace(coalesce(p_mobile,''),'\D','','g'),10);
  v_buyer_name text;v_buyer uuid;v_basis text;
begin
  if v_kind not in('REDZED_CUSTOMER','DISTRIBUTOR_CUSTOMER') or p_source_id is null or v_name='' then
    raise exception 'Canonical party source, id and name required.';
  end if;

  if v_kind='REDZED_CUSTOMER' then
    select buyer_id into v_buyer from public.rr_customer_sales_map_v9745 where customer_id=p_source_id;
  else
    select buyer_id into v_buyer from public.rr_customer_sales_map_v9745 where partner_customer_id=p_source_id;
  end if;
  if v_buyer is not null then v_basis:='CUSTOMER_ID'; end if;

  -- Only Redzed's own customers may reuse a legacy sales buyer by mobile/name.
  -- Distributor customers are always identified by their immutable source ID.
  if v_kind='REDZED_CUSTOMER' and v_buyer is null and length(v_mobile)=10 then
    select id into v_buyer from public.rr_buyers_v787
    where right(regexp_replace(coalesce(contact_no,''),'\D','','g'),10)=v_mobile
      and not exists(select 1 from public.rr_customer_sales_map_v9745 m where m.buyer_id=rr_buyers_v787.id and m.source_kind='DISTRIBUTOR_CUSTOMER')
    order by active desc nulls last,id limit 1;
    if v_buyer is not null then v_basis:='MOBILE'; end if;
  end if;
  if v_kind='REDZED_CUSTOMER' and v_buyer is null then
    select id into v_buyer from public.rr_buyers_v787
    where lower(trim(buyer_name))=lower(v_name)
      and not exists(select 1 from public.rr_customer_sales_map_v9745 m where m.buyer_id=rr_buyers_v787.id and m.source_kind='DISTRIBUTOR_CUSTOMER')
    order by active desc nulls last,id limit 1;
    if v_buyer is not null then v_basis:='EXACT_NAME'; end if;
  end if;

  v_buyer_name:=case when v_kind='DISTRIBUTOR_CUSTOMER'
    then v_name||' · DC-'||left(p_source_id::text,8) else v_name end;
  if v_buyer is null then
    insert into public.rr_buyers_v787(buyer_name,contact_no,discount_type,discount_value,active)
    values(v_buyer_name,nullif(p_mobile,''),'PER_PIECE',0,coalesce(p_active,true)) returning id into v_buyer;
    v_basis:='CREATED';
  else
    update public.rr_buyers_v787 set buyer_name=v_buyer_name,
      contact_no=coalesce(nullif(p_mobile,''),contact_no),active=coalesce(p_active,true)
    where id=v_buyer;
  end if;

  if v_kind='REDZED_CUSTOMER' then
    insert into public.rr_customer_sales_map_v9745(source_kind,customer_id,buyer_id,canonical_name,canonical_mobile,match_basis,is_active)
    values(v_kind,p_source_id,v_buyer,v_name,nullif(v_mobile,''),v_basis,coalesce(p_active,true))
    on conflict(customer_id) where customer_id is not null do update set buyer_id=excluded.buyer_id,canonical_name=excluded.canonical_name,
      canonical_mobile=excluded.canonical_mobile,match_basis=excluded.match_basis,is_active=excluded.is_active,updated_at=now();
  else
    insert into public.rr_customer_sales_map_v9745(source_kind,partner_customer_id,buyer_id,canonical_name,canonical_mobile,match_basis,is_active)
    values(v_kind,p_source_id,v_buyer,v_name,nullif(v_mobile,''),v_basis,coalesce(p_active,true))
    on conflict(partner_customer_id) where partner_customer_id is not null do update set buyer_id=excluded.buyer_id,canonical_name=excluded.canonical_name,
      canonical_mobile=excluded.canonical_mobile,match_basis=excluded.match_basis,is_active=excluded.is_active,updated_at=now();
  end if;
  return v_buyer;
end
$function$;

revoke all on function public.rr_customer_sales_map_sync_v9745(text,uuid,text,text,boolean) from public,anon,authenticated;
grant execute on function public.rr_customer_sales_map_sync_v9745(text,uuid,text,text,boolean) to service_role;

commit;
