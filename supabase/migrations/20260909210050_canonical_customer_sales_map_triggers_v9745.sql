begin;
create or replace function public.rr_customer_sales_map_customer_trg_v9745()
returns trigger language plpgsql security definer set search_path='public' as $function$
begin
 perform public.rr_customer_sales_map_sync_v9745('REDZED_CUSTOMER',new.id,new.customer_name,new.mobile,new.is_active);return new;
end $function$;
create or replace function public.rr_customer_sales_map_partner_trg_v9745()
returns trigger language plpgsql security definer set search_path='public' as $function$
begin
 perform public.rr_customer_sales_map_sync_v9745('DISTRIBUTOR_CUSTOMER',new.id,new.private_name,new.private_mobile,new.status='ACTIVE');return new;
end $function$;
revoke all on function public.rr_customer_sales_map_customer_trg_v9745() from public,anon,authenticated;
revoke all on function public.rr_customer_sales_map_partner_trg_v9745() from public,anon,authenticated;
drop trigger if exists rr_customer_sales_map_customer_v9745 on public.rr_customers;
create trigger rr_customer_sales_map_customer_v9745 after insert or update of customer_name,mobile,is_active on public.rr_customers for each row execute function public.rr_customer_sales_map_customer_trg_v9745();
drop trigger if exists rr_customer_sales_map_partner_v9745 on public.rr_market_partner_customer_v67;
create trigger rr_customer_sales_map_partner_v9745 after insert or update of private_name,private_mobile,status on public.rr_market_partner_customer_v67 for each row execute function public.rr_customer_sales_map_partner_trg_v9745();
do $block$ declare x record;begin
 for x in select id,customer_name,mobile,is_active from public.rr_customers loop perform public.rr_customer_sales_map_sync_v9745('REDZED_CUSTOMER',x.id,x.customer_name,x.mobile,x.is_active);end loop;
 for x in select id,private_name,private_mobile,status from public.rr_market_partner_customer_v67 loop perform public.rr_customer_sales_map_sync_v9745('DISTRIBUTOR_CUSTOMER',x.id,x.private_name,x.private_mobile,x.status='ACTIVE');end loop;
end $block$;
commit;
