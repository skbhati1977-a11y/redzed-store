-- TEST68: canonical RedZed clientele bridge for DIRECT_SALE PI.
-- Additive only: existing customer, buyer, PI/CI and accounts objects stay canonical.

create or replace function public.rr_sales_customer_search_v68(
  p_search text default '', p_limit integer default 30
) returns table(
  customer_id uuid, customer_name text, mobile text, address text, gstin text,
  dispatch_details text, allowed_discount_per_piece numeric, source_labels text[], chat_id uuid
) language plpgsql security definer set search_path=public as $$
declare v_q text:=lower(trim(coalesce(p_search,'')));
begin
  perform public.rr_assert_active_user_v1();
  return query
  with canonical as (
    select c.id customer_id,c.customer_name,c.mobile,c.address,c.gstin,
      coalesce(b.dispatch_details,'') dispatch_details,
      coalesce(c.allowed_discount_per_piece,0) allowed_discount_per_piece,
      array_remove(array[
        case when ch.id is not null then 'WINDOW/CHAT' end,
        case when b.id is not null then 'DIRECT/BUYER' end
      ],null)::text[] source_labels,ch.id chat_id
    from public.rr_customers c
    left join lateral (
      select bx.* from public.rr_buyers_v787 bx
      where regexp_replace(coalesce(bx.contact_no,''),'\D','','g')=right(regexp_replace(coalesce(c.mobile,''),'\D','','g'),10)
         or lower(trim(bx.buyer_name))=lower(trim(c.customer_name))
      order by case when regexp_replace(coalesce(bx.contact_no,''),'\D','','g')=right(regexp_replace(coalesce(c.mobile,''),'\D','','g'),10) then 0 else 1 end
      limit 1
    ) b on true
    left join lateral (
      select cx.id from public.rr_customer_chat_v9433 cx
      where cx.customer_id=c.id and cx.status='OPEN'
      order by cx.updated_at desc,cx.id limit 1
    ) ch on true
    where c.is_active
  ), orphan_buyers as (
    select null::uuid customer_id,b.buyer_name customer_name,b.contact_no mobile,b.address,
      b.gst_no gstin,coalesce(b.dispatch_details,'') dispatch_details,
      coalesce(b.discount_value,0) allowed_discount_per_piece,array['DIRECT/BUYER']::text[] source_labels,null::uuid chat_id
    from public.rr_buyers_v787 b
    where coalesce(b.active,true) and not exists(
      select 1 from canonical c where
        (regexp_replace(coalesce(c.mobile,''),'\D','','g')<>'' and regexp_replace(coalesce(c.mobile,''),'\D','','g')=right(regexp_replace(coalesce(b.contact_no,''),'\D','','g'),10))
        or lower(trim(c.customer_name))=lower(trim(b.buyer_name))
    )
  ), all_clients as (select * from canonical union all select * from orphan_buyers)
  select a.* from all_clients a
  where v_q='' or lower(a.customer_name) like '%'||v_q||'%'
    or (regexp_replace(v_q,'\D','','g')<>'' and regexp_replace(coalesce(a.mobile,''),'\D','','g') like '%'||regexp_replace(v_q,'\D','','g')||'%')
  order by a.customer_name limit greatest(1,least(coalesce(p_limit,30),100));
end $$;

create or replace function public.rr_sales_customer_upsert_v68(
  p_customer_id uuid, p_customer_name text, p_mobile text, p_address text default null,
  p_city text default null, p_state text default null, p_gstin text default null,
  p_dispatch_details text default null, p_discount_per_piece numeric default 0
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_role text;v_id uuid;v_mobile text:=right(regexp_replace(coalesce(p_mobile,''),'\D','','g'),10);v_buyer uuid;
begin
  perform public.rr_assert_active_user_v1();
  select upper(coalesce(role_code,'')) into v_role from public.rr_user_profiles where auth_user_id=auth.uid() and is_active limit 1;
  if v_role not in ('SUPER_ADMIN','OWNER','ADMIN') then raise exception 'Admin or Super Admin permission required.';end if;
  if nullif(trim(p_customer_name),'') is null or length(v_mobile)<10 then raise exception 'Customer name and valid mobile required.';end if;
  if coalesce(p_discount_per_piece,0)<0 then raise exception 'Discount cannot be negative.';end if;
  select id into v_id from public.rr_customers where is_active and right(regexp_replace(coalesce(mobile,''),'\D','','g'),10)=v_mobile order by updated_at desc limit 1;
  if p_customer_id is not null then
    if v_id is not null and v_id<>p_customer_id then raise exception 'This mobile is already mapped to another customer.';end if;
    v_id:=p_customer_id;
    update public.rr_customers set customer_name=trim(p_customer_name),mobile=p_mobile,address=nullif(trim(p_address),''),city=nullif(trim(p_city),''),state=nullif(trim(p_state),''),gstin=nullif(trim(p_gstin),''),allowed_discount_per_piece=coalesce(p_discount_per_piece,0),updated_at=now() where id=v_id and is_active;
    if not found then raise exception 'Active customer not found.';end if;
  elsif v_id is null then
    insert into public.rr_customers(customer_name,mobile,address,city,state,gstin,allowed_discount_per_piece)
    values(trim(p_customer_name),p_mobile,nullif(trim(p_address),''),nullif(trim(p_city),''),nullif(trim(p_state),''),nullif(trim(p_gstin),''),coalesce(p_discount_per_piece,0)) returning id into v_id;
  else
    update public.rr_customers set customer_name=trim(p_customer_name),address=coalesce(nullif(trim(p_address),''),address),city=coalesce(nullif(trim(p_city),''),city),state=coalesce(nullif(trim(p_state),''),state),gstin=coalesce(nullif(trim(p_gstin),''),gstin),allowed_discount_per_piece=coalesce(p_discount_per_piece,0),updated_at=now() where id=v_id;
  end if;
  select id into v_buyer from public.rr_buyers_v787 where lower(trim(buyer_name))=lower(trim(p_customer_name)) or right(regexp_replace(coalesce(contact_no,''),'\D','','g'),10)=v_mobile order by id limit 1;
  if v_buyer is null then
    insert into public.rr_buyers_v787(buyer_name,contact_no,address,gst_no,dispatch_details,discount_type,discount_value)
    values(trim(p_customer_name),p_mobile,nullif(trim(p_address),''),nullif(trim(p_gstin),''),nullif(trim(p_dispatch_details),''),'PER_PIECE',coalesce(p_discount_per_piece,0));
  else
    update public.rr_buyers_v787 set buyer_name=trim(p_customer_name),contact_no=p_mobile,address=nullif(trim(p_address),''),gst_no=nullif(trim(p_gstin),''),dispatch_details=nullif(trim(p_dispatch_details),''),discount_type='PER_PIECE',discount_value=coalesce(p_discount_per_piece,0),active=true where id=v_buyer;
  end if;
  insert into public.rr_customer_discount_history_v9420(customer_id,discount_per_piece,effective_from,changed_by)
  values(v_id,coalesce(p_discount_per_piece,0),now(),auth.uid());
  return jsonb_build_object('customer_id',v_id,'customer_name',trim(p_customer_name),'mobile',p_mobile,'discount_per_piece',coalesce(p_discount_per_piece,0));
end $$;

revoke all on function public.rr_sales_customer_search_v68(text,integer) from public,anon;
revoke all on function public.rr_sales_customer_upsert_v68(uuid,text,text,text,text,text,text,text,numeric) from public,anon;
grant execute on function public.rr_sales_customer_search_v68(text,integer) to authenticated,service_role;
grant execute on function public.rr_sales_customer_upsert_v68(uuid,text,text,text,text,text,text,text,numeric) to authenticated,service_role;
