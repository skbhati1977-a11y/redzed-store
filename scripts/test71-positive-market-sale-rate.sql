CREATE OR REPLACE FUNCTION public.rr_market_create_share_v9420(p_lots text[], p_customer_id uuid DEFAULT NULL::uuid, p_customer_name text DEFAULT NULL::text, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sid uuid; tok text; sc text; tries int:=0; lot text; rate numeric; begin
 perform public.rr_market_assert_sales_actor_v9420();
 if coalesce(array_length(p_lots,1),0)=0 then raise exception 'Select at least one lot.'; end if;
 if upper(coalesce(p_data_mode,'TEST'))='TEST' then
  foreach lot in array p_lots loop
   select c.sale_rate into rate from public.rr_web_window_cards_v9329(trim(lot),null,null,'TEST',150,0) c where upper(trim(c.lot_no))=upper(trim(lot)) limit 1;
   if coalesce(rate,0)<=0 then raise exception 'Lot %: Sale rate missing or zero. Complete costing and approve a positive sale rate before sharing.',lot; end if;
  end loop;
 end if;
 loop
   sc:=upper(substr(md5(random()::text || clock_timestamp()::text || coalesce(auth.uid()::text,'')),1,8));
   begin
     insert into public.rr_market_share_v9420(customer_id,customer_name,data_mode,short_code)
     values(p_customer_id,p_customer_name,upper(coalesce(p_data_mode,'TEST')),sc)
     returning id,token into sid,tok;
     exit;
   exception when unique_violation then
     tries:=tries+1; if tries>8 then raise; end if;
   end;
 end loop;
 insert into public.rr_market_share_lots_v9420(share_id,lot_no,sort_no)
 select sid,trim(x),ord from unnest(p_lots) with ordinality u(x,ord)
 where trim(x)<>'' on conflict do nothing;
 return jsonb_build_object('share_id',sid,'token',tok,'short_code',sc,'lot_count',(select count(*) from public.rr_market_share_lots_v9420 where share_id=sid));
end$function$
