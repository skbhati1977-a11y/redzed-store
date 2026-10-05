CREATE OR REPLACE FUNCTION public.rr_sales_pi_detail_v500(p_pi_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
declare p public.rr_fg_pi_v787%rowtype; lines_json jsonb;
begin
 perform public.rr_market_assert_sales_actor_v9420();
 select * into p from public.rr_fg_pi_v787 where id=p_pi_id and data_mode='TEST';
 if p.id is null then raise exception 'Canonical PI not found.'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('lot_no',l.lot_no,'qty',l.qty,
 'rate',coalesce(l.gross_rate,l.original_rate),'discount',coalesce(l.party_discount_per_piece,l.discount_amount,0),
 'category',l.short_item_name,'stock_type',l.stock_type) order by l.serial_no,l.id),'[]'::jsonb)
 into lines_json from public.rr_fg_pi_lines_v787 l where l.pi_id=p.id;
 return jsonb_build_object('pi_id',p.id,'pi_no',p.pi_no,'customer_name',coalesce(p.buyer_snapshot->>'customer_name',p.buyer_snapshot->>'buyer_name'),
 'dispatch_details',p.dispatch_details,'requirement_id',p.market_requirement_id,'status',p.status,
 'freight_amount',p.freight_amount,'packing_other',p.packing_other,'lines',lines_json);
end $function$;
