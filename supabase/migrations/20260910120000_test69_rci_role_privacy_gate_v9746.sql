begin;

create or replace function public.rr_rci_assert_role_v9746()
returns void
language plpgsql
security definer
set search_path='public'
as $function$
begin
  perform public.rr_fg_assert_user_v787();
  if not exists (
    select 1 from public.rr_user_profiles p
    where p.auth_user_id=auth.uid()
      and coalesce(p.is_active,false)
      and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE'
      and lower(coalesce(p.role_code,'')) in ('owner','admin','sales','accounts')
  ) then
    raise exception 'Owner/Admin/Sales/Accounts access required.';
  end if;
end
$function$;

create or replace function public.rr_rci_assert_visible_buyer_v9746(p_buyer_id uuid)
returns void
language plpgsql
security definer
set search_path='public'
as $function$
begin
  perform public.rr_rci_assert_role_v9746();
  if p_buyer_id is null then raise exception 'Canonical RCI buyer required.'; end if;
  if exists (
    select 1 from public.rr_customer_sales_map_v9745 m
    where m.buyer_id=p_buyer_id and m.is_active
      and m.source_kind='DISTRIBUTOR_CUSTOMER'
  ) then
    raise exception 'Distributor customer accounts are private.';
  end if;
end
$function$;

revoke all on function public.rr_rci_assert_role_v9746(),public.rr_rci_assert_visible_buyer_v9746(uuid)
from public,anon,authenticated;

-- Preserve the proven settlement implementations behind non-API internal names.
alter function public.rr_rci_context_v9740(uuid) rename to rr_rci_context_internal_v9746;
alter function public.rr_rci_save_draft_v9740(uuid,uuid,uuid,text,jsonb,text,text,text) rename to rr_rci_save_draft_internal_v9746;
alter function public.rr_rci_post_standalone_v9740(uuid,jsonb,text,text,text) rename to rr_rci_post_standalone_internal_v9746;
alter function public.rr_rci_reverse_v9740(uuid,text) rename to rr_rci_reverse_internal_v9746;
alter function public.rr_rci_detail_v9740(uuid) rename to rr_rci_detail_internal_v9746;
alter function public.rr_rci_for_ci_v9740(uuid) rename to rr_rci_for_ci_internal_v9746;

revoke all on function public.rr_rci_context_internal_v9746(uuid),
 public.rr_rci_save_draft_internal_v9746(uuid,uuid,uuid,text,jsonb,text,text,text),
 public.rr_rci_post_standalone_internal_v9746(uuid,jsonb,text,text,text),
 public.rr_rci_reverse_internal_v9746(uuid,text),public.rr_rci_detail_internal_v9746(uuid),
 public.rr_rci_for_ci_internal_v9746(uuid)
from public,anon,authenticated;
grant execute on function public.rr_rci_context_internal_v9746(uuid),
 public.rr_rci_save_draft_internal_v9746(uuid,uuid,uuid,text,jsonb,text,text,text),
 public.rr_rci_post_standalone_internal_v9746(uuid,jsonb,text,text,text),
 public.rr_rci_reverse_internal_v9746(uuid,text),public.rr_rci_detail_internal_v9746(uuid),
 public.rr_rci_for_ci_internal_v9746(uuid)
to service_role;

create function public.rr_rci_context_v9740(p_pi_id uuid) returns jsonb
language plpgsql security definer set search_path='public' as $function$
declare v_buyer uuid;
begin
  select buyer_id into v_buyer from public.rr_fg_pi_v787 where id=p_pi_id;
  perform public.rr_rci_assert_visible_buyer_v9746(v_buyer);
  return public.rr_rci_context_internal_v9746(p_pi_id);
end $function$;

create function public.rr_rci_save_draft_v9740(p_rci_id uuid,p_linked_ci_id uuid,p_buyer_id uuid,p_flow_type text,p_lines jsonb,p_reason text,p_idempotency_key text,p_data_mode text default 'TEST') returns jsonb
language plpgsql security definer set search_path='public' as $function$
declare v_buyer uuid:=p_buyer_id;
begin
  if p_linked_ci_id is not null then select buyer_id into v_buyer from public.rr_fg_pi_v787 where id=p_linked_ci_id; end if;
  perform public.rr_rci_assert_visible_buyer_v9746(v_buyer);
  return public.rr_rci_save_draft_internal_v9746(p_rci_id,p_linked_ci_id,p_buyer_id,p_flow_type,p_lines,p_reason,p_idempotency_key,p_data_mode);
end $function$;

create function public.rr_rci_post_standalone_v9740(p_buyer_id uuid,p_lines jsonb,p_reason text,p_idempotency_key text,p_data_mode text default 'TEST') returns jsonb
language plpgsql security definer set search_path='public' as $function$
begin
  perform public.rr_rci_assert_visible_buyer_v9746(p_buyer_id);
  return public.rr_rci_post_standalone_internal_v9746(p_buyer_id,p_lines,p_reason,p_idempotency_key,p_data_mode);
end $function$;

create function public.rr_rci_reverse_v9740(p_rci_id uuid,p_reason text) returns jsonb
language plpgsql security definer set search_path='public' as $function$
declare v_buyer uuid;
begin
  select buyer_id into v_buyer from public.rr_rci_v9740 where id=p_rci_id;
  perform public.rr_rci_assert_visible_buyer_v9746(v_buyer);
  return public.rr_rci_reverse_internal_v9746(p_rci_id,p_reason);
end $function$;

create function public.rr_rci_detail_v9740(p_rci_id uuid) returns jsonb
language plpgsql stable security definer set search_path='public' as $function$
declare v_buyer uuid;
begin
  select buyer_id into v_buyer from public.rr_rci_v9740 where id=p_rci_id;
  perform public.rr_rci_assert_visible_buyer_v9746(v_buyer);
  return public.rr_rci_detail_internal_v9746(p_rci_id);
end $function$;

create function public.rr_rci_for_ci_v9740(p_ci_id uuid) returns jsonb
language plpgsql stable security definer set search_path='public' as $function$
declare v_buyer uuid;
begin
  select buyer_id into v_buyer from public.rr_fg_pi_v787 where id=p_ci_id;
  perform public.rr_rci_assert_visible_buyer_v9746(v_buyer);
  return public.rr_rci_for_ci_internal_v9746(p_ci_id);
end $function$;

revoke all on function public.rr_rci_context_v9740(uuid),
 public.rr_rci_save_draft_v9740(uuid,uuid,uuid,text,jsonb,text,text,text),
 public.rr_rci_post_standalone_v9740(uuid,jsonb,text,text,text),
 public.rr_rci_reverse_v9740(uuid,text),public.rr_rci_detail_v9740(uuid),
 public.rr_rci_for_ci_v9740(uuid)
from public,anon;
grant execute on function public.rr_rci_context_v9740(uuid),
 public.rr_rci_save_draft_v9740(uuid,uuid,uuid,text,jsonb,text,text,text),
 public.rr_rci_post_standalone_v9740(uuid,jsonb,text,text,text),
 public.rr_rci_reverse_v9740(uuid,text),public.rr_rci_detail_v9740(uuid),
 public.rr_rci_for_ci_v9740(uuid)
to authenticated,service_role;

create or replace function public.rr_rci_ci_search_v9745(p_search text default '',p_limit integer default 100,p_data_mode text default 'TEST') returns jsonb
language plpgsql stable security definer set search_path='public' as $function$
declare v_search text:=lower(trim(coalesce(p_search,'')));v_limit integer:=least(greatest(coalesce(p_limit,100),1),200);v_result jsonb;
begin
  perform public.rr_rci_assert_role_v9746();
  with mapped as (
    select distinct on(m.buyer_id) m.buyer_id,m.canonical_name customer_name,m.canonical_mobile mobile,m.source_kind
    from public.rr_customer_sales_map_v9745 m
    where m.is_active and m.source_kind='REDZED_CUSTOMER'
    order by m.buyer_id,m.updated_at desc
  ), parties as (
    select * from mapped
    union all
    select b.id,b.buyer_name,right(regexp_replace(coalesce(b.contact_no,''),'\D','','g'),10),'SALES_BUYER'
    from public.rr_buyers_v787 b where coalesce(b.active,true)
      and not exists(select 1 from public.rr_customer_sales_map_v9745 m where m.buyer_id=b.id and m.is_active)
  ), rows as (
    select q.buyer_id,q.customer_name,q.mobile,q.source_kind,p.id,p.cpi_no,p.pi_no,p.finalized_at,
      (p.id is not null) eligible,count(p.id) over(partition by q.buyer_id) final_ci_count
    from parties q left join public.rr_fg_pi_v787 p on p.buyer_id=q.buyer_id
      and p.status='CI_FINAL' and p.data_mode=upper(coalesce(p_data_mode,'TEST'))
  )
  select coalesce(jsonb_agg(to_jsonb(x) order by x.eligible desc,x.finalized_at desc nulls last,x.customer_name),'[]'::jsonb) into v_result
  from (select * from rows r where v_search=''
    or lower(r.customer_name) like '%'||v_search||'%'
    or replace(replace(lower(r.customer_name),'kh','k'),'ee','i') like '%'||replace(replace(v_search,'kh','k'),'ee','i')||'%'
    or lower(coalesce(r.cpi_no,'')) like '%'||v_search||'%'
    or lower(coalesce(r.pi_no,'')) like '%'||v_search||'%'
    or (length(regexp_replace(v_search,'[^0-9]','','g'))>0 and coalesce(r.mobile,'') like '%'||regexp_replace(v_search,'[^0-9]','','g')||'%')
    order by eligible desc,finalized_at desc nulls last,customer_name limit v_limit) x;
  return v_result;
end $function$;

revoke all on function public.rr_rci_ci_search_v9745(text,integer,text) from public,anon;
grant execute on function public.rr_rci_ci_search_v9745(text,integer,text) to authenticated,service_role;

-- Normalize the one canonical Reeka/Rika/Reekha party without inventing a second identity.
update public.rr_customers set customer_name='Reeka Bhati'
where right(regexp_replace(coalesce(mobile,''),'\D','','g'),10)='9873887784'
  and lower(trim(customer_name)) in ('reeka bhati','rika bhati','reekha bhati');

commit;
