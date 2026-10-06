CREATE OR REPLACE FUNCTION public.rr_rm_approve_rate_test71(p_lot_no text, p_final_rate numeric, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s record;j jsonb;r jsonb;
begin
 perform public.rr_rm_assert_operator_test71();
 if p_final_rate is null or p_final_rate<=0 or p_final_rate::text in('NaN','Infinity','-Infinity') then raise exception 'Positive final sale rate required.';end if;
 if not coalesce((public.rr_rm_market_readiness_test71(p_lot_no)->>'mapping_ready')::boolean,false) then raise exception 'Complete garment mapping in Readymade Working before approving final rate.';end if;
 if lower(public.rr_costing_user_scope_v760(null)->>'effective_role') not in('owner','super_admin','superadmin','admin') then raise exception 'Owner / Admin rate approval required.';end if;
 perform pg_advisory_xact_lock(hashtextextended('RM:'||upper(trim(p_lot_no))||':TEST',0));
 select * into s from public.rr_rm_stock_v849_2c6 where upper(trim(lot_no))=upper(trim(p_lot_no)) and data_mode='TEST' for update;
 if not found then raise exception 'Readymade lot not found.';end if;
 if s.sale_ready and exists(select 1 from public.rrq_lot_rates_v9300 q where q.lot_no=s.lot_no and q.data_mode='TEST' and q.dispatch_ready and q.final_sale_rate>0) then raise exception 'Final rate already approved; read only.';end if;
 -- Freeze full private costing under owner scope; Admin can approve but cannot read it.
 if s.costing_snapshot_test71 is null then
 if lower(public.rr_costing_user_scope_v760(null)->>'effective_role') not in('owner','super_admin','superadmin') then raise exception 'Owner must finalize Readymade costing first.';end if;
 j:=public.rr_rm_costing_test71(s.lot_no,'TEST');
 if not coalesce((j->>'costing_complete')::boolean,false) then raise exception 'Monthly weighted allocation is pending.';end if;
 update public.rr_rm_stock_v849_2c6 set costing_snapshot_test71=j||jsonb_build_object('frozen',true,'frozen_at',now()) where stock_id=s.stock_id;
 end if;
 r:=public.rrq_apply_packing_rate_core_test71(s.lot_no,p_final_rate,'TEST',p_reason);
 update public.rr_rm_stock_v849_2c6 set target_sale_rate=p_final_rate,minimum_allowed_sale_rate=greatest(0,p_final_rate-max_customer_discount_per_pc),markup_mode='DEFAULT_22',markup_per_pc=22,sale_ready=true where stock_id=s.stock_id;
 return r;
end $function$
;
