begin;
create or replace function public.rr_rci_ci_search_v9745(
  p_search text default '',p_limit integer default 100,p_data_mode text default 'TEST'
) returns jsonb
language plpgsql stable security definer set search_path='public'
as $function$
declare v_search text:=lower(trim(coalesce(p_search,'')));v_limit integer:=least(greatest(coalesce(p_limit,100),1),200);v_result jsonb;
begin
  perform public.rr_fg_assert_user_v787();
  with mapped as (
    select distinct on(m.buyer_id) m.buyer_id,m.canonical_name customer_name,m.canonical_mobile mobile,m.source_kind
    from public.rr_customer_sales_map_v9745 m where m.is_active
    order by m.buyer_id,case when m.source_kind='REDZED_CUSTOMER' then 0 else 1 end,m.updated_at desc
  ), parties as (
    select * from mapped
    union all
    select b.id,b.buyer_name,right(regexp_replace(coalesce(b.contact_no,''),'\D','','g'),10),'SALES_BUYER'
    from public.rr_buyers_v787 b where coalesce(b.active,true) and not exists(select 1 from mapped m where m.buyer_id=b.id)
  ), rows as (
    select q.buyer_id,q.customer_name,q.mobile,q.source_kind,p.id,p.cpi_no,p.pi_no,p.finalized_at,
      (p.id is not null) eligible,count(p.id) over(partition by q.buyer_id) final_ci_count
    from parties q left join public.rr_fg_pi_v787 p on p.buyer_id=q.buyer_id
      and p.status='CI_FINAL' and p.data_mode=upper(coalesce(p_data_mode,'TEST'))
  )
  select coalesce(jsonb_agg(to_jsonb(x) order by x.eligible desc,x.finalized_at desc nulls last,x.customer_name),'[]'::jsonb) into v_result
  from (select * from rows r where
    v_search='' or lower(r.customer_name) like '%'||v_search||'%'
    or lower(coalesce(r.cpi_no,'')) like '%'||v_search||'%'
    or lower(coalesce(r.pi_no,'')) like '%'||v_search||'%'
    or (length(regexp_replace(v_search,'[^0-9]','','g'))>0 and coalesce(r.mobile,'') like '%'||regexp_replace(v_search,'[^0-9]','','g')||'%')
    order by eligible desc,finalized_at desc nulls last,customer_name limit v_limit) x;
  return v_result;
end $function$;
revoke all on function public.rr_rci_ci_search_v9745(text,integer,text) from public,anon;
grant execute on function public.rr_rci_ci_search_v9745(text,integer,text) to authenticated,service_role;
commit;
