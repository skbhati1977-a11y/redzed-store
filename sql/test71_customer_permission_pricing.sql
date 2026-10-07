CREATE OR REPLACE FUNCTION public.rr_collection_customer_pricing_v9637(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
 v_share rr_market_share_v9420%rowtype;
 v_discount numeric:=0;
 v_rows jsonb;
begin
 perform public.rr_customer_access_assert_test71(p_token);
 select * into v_share from rr_market_share_v9420 where token=p_token limit 1;
 if v_share.id is null then raise exception 'INVALID_COLLECTION_TOKEN'; end if;
 select coalesce(allowed_discount_per_piece,0) into v_discount from rr_customers where id=v_share.customer_id;
 with allowed_lots as (
   select distinct l.lot_no
   from rr_collection_cycle_v9586 c
   join rr_collection_send_v9586 cs on cs.collection_cycle_id=c.id
   join rr_market_share_lots_v9420 l on l.share_id=cs.share_id
   where c.customer_id=v_share.customer_id and c.chat_id is not distinct from (
     select chat_id from rr_collection_cycle_v9586 where customer_id=v_share.customer_id and status not in ('CLOSED','CANCELLED') order by created_at desc limit 1
   )
   union
   select lot_no from rr_market_share_lots_v9420 where share_id=v_share.id
 ), priced as (
   select a.lot_no,
          coalesce(
            (select r.approved_rate from rr_pi_internal_rrq_v9517 r where r.lot_no=a.lot_no and r.approved_rate is not null order by r.created_at desc limit 1),
            (select u.sale_rate from rr_universal_sale_lot_v849 u where u.lot_no=a.lot_no and u.sale_rate is not null order by u.sale_rate desc limit 1),
            (select w.sale_rate from public.rr_web_window_snapshot_test71(a.lot_no,null,null,'TEST',1,0) w where v_share.data_mode='TEST' and w.lot_no=a.lot_no)
          )::numeric as approved_rate
   from allowed_lots a
 )
 select coalesce(jsonb_agg(jsonb_build_object(
   'lot_no',lot_no,
   'approved_rate',approved_rate,
   'allowed_discount',v_discount,
   'net_rate',case when approved_rate is null then null else greatest(approved_rate-v_discount,0) end,
   'pricing_status',case when approved_rate is null then 'UNRESOLVED' else 'RESOLVED' end
 ) order by lot_no),'[]'::jsonb) into v_rows from priced;
 return jsonb_build_object('customer_id',v_share.customer_id,'allowed_discount_per_piece',v_discount,'rows',v_rows);
end $function$;
