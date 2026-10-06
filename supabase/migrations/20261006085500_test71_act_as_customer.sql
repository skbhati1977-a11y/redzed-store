-- Owner-only customer testing uses the existing bound customer session engine.
create or replace function public.rr_test_customer_source_test71() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not exists(select 1 from public.rr_user_profiles where auth_user_id=auth.uid() and is_active and upper(role_code) in ('OWNER','SUPER_ADMIN')) then raise exception 'Super Admin only.';end if;
 return (select coalesce(jsonb_agg(to_jsonb(x) order by x.customer_name),'[]') from (
 select c.id customer_id,c.customer_name,s.token is not null as has_collection
 from public.rr_customers c left join lateral(select token from public.rr_market_share_v9420 where customer_id=c.id and data_mode='TEST' and status='ACTIVE' and origin_relation_kind='DIRECT_CUSTOMER' order by created_at desc,id desc limit 1)s on true where c.is_active
 )x);
end $$;
create or replace function public.rr_test_act_as_customer_test71(p_customer_id uuid,p_device_id text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c public.rr_customers%rowtype;s public.rr_market_share_v9420%rowtype;r jsonb;
begin
 if not exists(select 1 from public.rr_user_profiles where auth_user_id=auth.uid() and is_active and upper(role_code) in ('OWNER','SUPER_ADMIN')) then raise exception 'Super Admin only.';end if;
 select * into c from public.rr_customers where id=p_customer_id and is_active;
 if c.id is null then raise exception 'Customer unavailable.';end if;
 select * into s from public.rr_market_share_v9420 where customer_id=c.id and data_mode='TEST' and status='ACTIVE' and origin_relation_kind='DIRECT_CUSTOMER' order by created_at desc,id desc limit 1;
 if s.id is null then raise exception 'Send a TEST collection to this customer first.';end if;
 r:=public.rr_customer_session_issue_bound_v9680(s.token,c.customer_name,c.mobile,p_device_id);
 return r||jsonb_build_object('share_token',s.token,'customer_name',c.customer_name,'data_mode','TEST');
end $$;
revoke all on function public.rr_test_customer_source_test71() from public,anon;
revoke all on function public.rr_test_act_as_customer_test71(uuid,text) from public,anon;
grant execute on function public.rr_test_customer_source_test71() to authenticated;
grant execute on function public.rr_test_act_as_customer_test71(uuid,text) to authenticated;
