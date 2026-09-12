begin;

do $block$
declare r record;v_new_buyer uuid;
begin
  for r in
    select m.id,m.canonical_name,m.canonical_mobile,m.is_active,b.discount_type,b.discount_value
    from public.rr_customer_sales_map_v9745 m
    join public.rr_buyers_v787 b on b.id=m.buyer_id
    where m.source_kind='DISTRIBUTOR_CUSTOMER'
      and exists(select 1 from public.rr_customer_sales_map_v9745 x where x.buyer_id=m.buyer_id and x.id<>m.id)
    order by m.id
  loop
    insert into public.rr_buyers_v787(buyer_name,contact_no,discount_type,discount_value,active)
    values(r.canonical_name||' · DC-'||left(r.id::text,8),r.canonical_mobile,coalesce(r.discount_type,'PER_PIECE'),coalesce(r.discount_value,0),r.is_active)
    returning id into v_new_buyer;
    update public.rr_customer_sales_map_v9745
    set buyer_id=v_new_buyer,match_basis='CREATED',updated_at=now()
    where id=r.id;
  end loop;
end $block$;

create unique index if not exists rr_customer_sales_map_one_source_buyer_v9748
on public.rr_customer_sales_map_v9745(buyer_id);

commit;
