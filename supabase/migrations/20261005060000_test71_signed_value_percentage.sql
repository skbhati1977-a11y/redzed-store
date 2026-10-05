-- TEST71: signed percentage adjustment stored separately from nonnegative freight/other charges.
CREATE OR REPLACE FUNCTION public.rr_fg_save_pi_value_adjustment_test71(
 p_pi_id uuid,p_customer_name text,p_dispatch_details text,p_lines jsonb,p_party_discount numeric,
 p_value_added_pct numeric,
 p_freight_amount numeric DEFAULT 0,p_packing_other numeric DEFAULT 0,p_gst_pct numeric DEFAULT 0,
 p_finalize boolean DEFAULT false,p_data_mode text DEFAULT 'TEST'
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare r jsonb; pid uuid; sub numeric; adjustment numeric; taxable numeric; gst numeric; raw numeric; grand numeric; pct numeric:=coalesce(p_value_added_pct,0);
begin
 perform public.rr_fg_assert_user_v787();
 if upper(coalesce(p_data_mode,''))<>'TEST' then raise exception 'TEST71 billing requires TEST mode.'; end if;
 if pct < -100 or pct::text in ('NaN','Infinity','-Infinity') then raise exception 'Value Added percent must be finite and at least -100.'; end if;
 r:=public.rr_fg_save_pi_party_discount_v9557(p_pi_id,p_customer_name,p_dispatch_details,p_lines,p_party_discount,
 p_freight_amount,p_packing_other,p_gst_pct,p_finalize,'TEST');
 pid:=(r->>'pi_id')::uuid;
 select sub_total into sub from public.rr_fg_pi_v787 where id=pid;
 adjustment:=sub*pct/100;
 taxable:=sub+adjustment+coalesce(p_freight_amount,0)+coalesce(p_packing_other,0);
 if taxable<0 then raise exception 'Bill total cannot be negative.'; end if;
 gst:=round(taxable*coalesce(p_gst_pct,0)/100,2);
 raw:=taxable+gst; grand:=round(raw/10)*10;
 update public.rr_fg_pi_v787 set value_added_pct=pct,taxable_amount=taxable,gst_amount=gst,
 grand_total=grand,round_off=grand-raw,updated_at=now() where id=pid;
 update public.rr_fg_pi_versions_v787 v
 set snapshot=jsonb_build_object('header',to_jsonb(p),'lines',
 (select jsonb_agg(to_jsonb(l) order by l.serial_no) from public.rr_fg_pi_lines_v787 l where l.pi_id=pid))
 from public.rr_fg_pi_v787 p where p.id=pid and v.pi_id=pid and v.version_no=p.version_no;
 return r||jsonb_build_object('value_added_pct',pct,'value_added_amount',adjustment,'taxable_amount',taxable,
 'gst_amount',gst,'grand_total',grand,'round_off',grand-raw);
end $function$;
REVOKE ALL ON FUNCTION public.rr_fg_save_pi_value_adjustment_test71(uuid,text,text,jsonb,numeric,numeric,numeric,numeric,numeric,boolean,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_fg_save_pi_value_adjustment_test71(uuid,text,text,jsonb,numeric,numeric,numeric,numeric,numeric,boolean,text) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rr_sales_pi_detail_v500(p_pi_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
 'value_added_pct',p.value_added_pct,'freight_amount',p.freight_amount,'packing_other',p.packing_other,'lines',lines_json);
end $function$
;
