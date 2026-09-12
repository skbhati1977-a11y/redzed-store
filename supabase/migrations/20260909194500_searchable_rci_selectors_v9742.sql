begin;

create or replace function public.rr_rci_ci_search_v9742(
  p_search text default '',
  p_limit integer default 50,
  p_data_mode text default 'TEST'
) returns jsonb
language plpgsql
stable
security invoker
set search_path='public'
as $function$
declare
  v_search text:=lower(trim(coalesce(p_search,'')));
  v_limit integer:=least(greatest(coalesce(p_limit,50),1),100);
  v_result jsonb;
begin
  perform public.rr_fg_assert_user_v787();
  select coalesce(jsonb_agg(to_jsonb(x) order by x.finalized_at desc),'[]'::jsonb)
  into v_result
  from (
    select p.id,p.cpi_no,p.pi_no,p.buyer_id,p.finalized_at,
      coalesce(nullif(p.buyer_snapshot->>'buyer_name',''),nullif(p.buyer_snapshot->>'customer_name',''),'Party') customer_name,
      coalesce(p.buyer_snapshot->>'mobile',p.buyer_snapshot->>'contact_no','') mobile
    from public.rr_fg_pi_v787 p
    where p.status='CI_FINAL'
      and p.data_mode=upper(coalesce(p_data_mode,'TEST'))
      and (
        v_search=''
        or lower(coalesce(p.buyer_snapshot->>'buyer_name','')) like '%'||v_search||'%'
        or lower(coalesce(p.buyer_snapshot->>'customer_name','')) like '%'||v_search||'%'
        or lower(coalesce(p.cpi_no,'')) like '%'||v_search||'%'
        or lower(coalesce(p.pi_no,'')) like '%'||v_search||'%'
        or (length(regexp_replace(v_search,'[^0-9]','','g'))>0 and
          regexp_replace(coalesce(p.buyer_snapshot->>'mobile',p.buyer_snapshot->>'contact_no',''),'[^0-9]','','g') like '%'||regexp_replace(v_search,'[^0-9]','','g')||'%')
      )
    order by p.finalized_at desc nulls last
    limit v_limit
  ) x;
  return v_result;
end
$function$;

revoke all on function public.rr_rci_ci_search_v9742(text,integer,text) from public,anon;
grant execute on function public.rr_rci_ci_search_v9742(text,integer,text) to authenticated;

commit;
