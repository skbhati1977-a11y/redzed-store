BEGIN;
CREATE OR REPLACE FUNCTION public.rr_post_mc_exchange_v1(p_gr_id uuid, p_received_qty numeric, p_received_rate numeric, p_challan_bill_no text, p_received_date date DEFAULT CURRENT_DATE, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_gr public.rr_product_gr_entries%rowtype; v_old public.rr_mc1_purchases%rowtype;
  v_fabric public.rr_mc1_fabrics%rowtype; v_account public.rr_mc1_account%rowtype;
  v_received_before numeric(18,3); v_qty numeric(18,3):=round(coalesce(p_received_qty,0),3);
  v_rate numeric(18,4); v_value numeric(18,2);
  v_f_qty numeric(18,3); v_f_value numeric(18,2); v_f_avg numeric(18,4);
  v_p_qty numeric(18,3); v_p_value numeric(18,2); v_p_avg numeric(18,4);
  v_purchase public.rr_mc1_purchases%rowtype; v_exchange public.rr_product_exchange_entries%rowtype; v_status text;
begin
  perform public.rr_product_require_admin_v1();
  if v_qty<=0 then raise exception 'Exchange received quantity must be greater than zero.'; end if;
  if nullif(trim(p_challan_bill_no),'') is null then raise exception 'Exchange Challan / Bill No. is required.'; end if;
  select * into v_gr from public.rr_product_gr_entries where id=p_gr_id and source_type='MC1' for update;
  if not found then raise exception 'MC1 GR record not found.'; end if;

  -- Serialize through the GR row; a challan identifies one received delivery for this GR.
  select * into v_exchange from public.rr_product_exchange_entries
  where gr_id=p_gr_id and source_type='MC1' and challan_bill_no=upper(trim(p_challan_bill_no))
  order by created_at limit 1;
  if found then
    if v_exchange.received_qty<>v_qty
       or v_exchange.received_rate<>round(coalesce(nullif(p_received_rate,0),v_gr.gr_rate),4)
       or v_exchange.received_date<>coalesce(p_received_date,current_date) then
      raise exception 'Exchange challan already exists with different quantity, rate or date.';
    end if;
    select * into v_purchase from public.rr_mc1_purchases where id=v_exchange.new_mc_purchase_id;
    return jsonb_build_object('exchange',to_jsonb(v_exchange),'purchase',to_jsonb(v_purchase),
      'gr_status',v_gr.status,'already_received',true);
  end if;
  if not coalesce(v_gr.exchange_expected,false) or v_gr.status not in('AWAITING_EXCHANGE','PART_EXCHANGE_RECEIVED') then
    raise exception 'GR is closed or does not await exchange.';
  end if;
  if coalesce(p_received_rate,v_gr.gr_rate)<0 then raise exception 'Exchange rate cannot be negative.'; end if;
  select * into v_old from public.rr_mc1_purchases where id=v_gr.mc_purchase_id;
  if not found then raise exception 'Original MC1 purchase not found.'; end if;
  select * into v_fabric from public.rr_mc1_fabrics where id=v_old.fabric_id for update;
  select * into v_account from public.rr_mc1_account where id=v_old.mc_account_id for update;

  select coalesce(sum(received_qty),0) into v_received_before from public.rr_product_exchange_entries where gr_id=p_gr_id;
  if v_received_before+v_qty>v_gr.gr_qty+0.0005 then raise exception 'Remaining exchange quantity is % kg.',round(v_gr.gr_qty-v_received_before,3); end if;
  v_rate:=round(coalesce(nullif(p_received_rate,0),v_gr.gr_rate),4); v_value:=round(v_qty*v_rate,2);
  v_f_qty:=round(v_fabric.current_qty+v_qty,3); v_f_value:=round(v_fabric.current_value+v_value,2);
  v_f_avg:=case when v_f_qty>0 then round(v_f_value/v_f_qty,4) else 0 end;
  v_p_qty:=round(v_account.current_qty+v_qty,3); v_p_value:=round(v_account.current_value+v_value,2);
  v_p_avg:=case when v_p_qty>0 then round(v_p_value/v_p_qty,4) else 0 end;

  insert into public.rr_mc1_purchases(mc_account_id,fabric_id,fabric_name,vendor_name,bill_no,bill_date,bill_qty,bill_value,bill_rate,
    remarks,entry_kind,source_gr_id,operation_status)
  values(v_account.id,v_fabric.id,v_fabric.fabric_name,v_old.vendor_name,upper(trim(p_challan_bill_no)),coalesce(p_received_date,current_date),
    v_qty,v_value,v_rate,concat('EXCHANGE IN against GR #',v_gr.gr_no,coalesce(' · '||nullif(trim(p_remarks),''),'')),
    'EXCHANGE',v_gr.id,'ACTIVE') returning * into v_purchase;

  update public.rr_mc1_fabrics set current_qty=v_f_qty,current_value=v_f_value,avg_rate=v_f_avg,
    total_purchase_qty=round(total_purchase_qty+v_qty,3),total_exchange_qty=round(total_exchange_qty+v_qty,3),updated_at=now()
  where id=v_fabric.id;
  update public.rr_mc1_account set current_qty=v_p_qty,current_value=v_p_value,avg_rate=v_p_avg,
    total_purchase_qty=round(total_purchase_qty+v_qty,3),updated_at=now() where id=v_account.id;

  insert into public.rr_product_exchange_entries(gr_id,source_type,received_qty,received_rate,received_value,
    challan_bill_no,received_date,new_mc_purchase_id,remarks)
  values(v_gr.id,'MC1',v_qty,v_rate,v_value,upper(trim(p_challan_bill_no)),coalesce(p_received_date,current_date),v_purchase.id,
    nullif(trim(p_remarks),'')) returning * into v_exchange;

  insert into public.rr_mc1_ledger(mc_account_id,fabric_id,entry_type,reference_id,qty_in,rate_snapshot,value_in,
    balance_qty,balance_value,avg_rate_after,fabric_balance_qty,fabric_balance_value,fabric_avg_rate_after,occurred_at,remarks)
  values(v_account.id,v_fabric.id,'EXCHANGE_IN',v_exchange.id,v_qty,v_rate,v_value,
    v_p_qty,v_p_value,v_p_avg,v_f_qty,v_f_value,v_f_avg,now(),concat(v_fabric.fabric_name,' · Exchange against GR #',v_gr.gr_no));

  v_status:=case when v_received_before+v_qty>=v_gr.gr_qty-0.0005 then 'EXCHANGE_RECEIVED' else 'PART_EXCHANGE_RECEIVED' end;
  update public.rr_product_gr_entries set status=v_status,exchange_expected=true,
    closed_at=case when v_status='EXCHANGE_RECEIVED' then now() else null end,
    closed_by=case when v_status='EXCHANGE_RECEIVED' then auth.uid() else null end where id=v_gr.id;

  return jsonb_build_object('exchange',to_jsonb(v_exchange),'purchase',to_jsonb(v_purchase),'gr_status',v_status,
    'fabric',(select to_jsonb(f) from public.rr_mc1_fabrics f where f.id=v_fabric.id),
    'card',(select to_jsonb(a) from public.rr_mc1_account a where a.id=v_account.id));
end;
$function$
;
COMMIT;

