CREATE OR REPLACE FUNCTION public.rr_material_opening_balance_v664(p_material_id uuid, p_qty_consumption numeric, p_total_value numeric, p_as_of date, p_data_mode text DEFAULT 'TEST'::text, p_reference text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m record;ref text:=coalesce(nullif(trim(p_reference),''),'OPENING-BALANCE-'||p_material_id::text||'-'||to_char(p_as_of,'YYYYMMDD'));rate numeric; prior public.rr_material_purchases_v805%rowtype;
begin
 if auth.uid() is null or not public.rr_is_owner_or_admin() then raise exception 'Owner/Admin permission required.' using errcode='42501'; end if;
 if upper(p_data_mode) not in('TEST','REAL') then raise exception 'Invalid data mode';end if;if coalesce(p_qty_consumption,0)<=0 or coalesce(p_total_value,0)<0 then raise exception 'Opening qty/value required';end if;select * into m from public.rr_material_master_v805 where id=p_material_id and is_active;if not found then raise exception 'Material not found';end if;rate:=p_total_value/p_qty_consumption;
 if p_as_of IS NULL OR p_data_mode IS NULL then raise exception 'Opening date and data mode required';end if;
 perform pg_advisory_xact_lock(hashtextextended('MATERIAL_OPENING:'||p_material_id||':'||upper(p_data_mode)||':'||ref,0));
 select * into prior from public.rr_material_purchases_v805 where material_id=p_material_id and upper(data_mode)=upper(p_data_mode) and source_record_id=ref limit 1;
 if found then
  if prior.source_module IS DISTINCT FROM 'MATERIAL_OPENING_BALANCE' OR prior.consumption_equivalent_qty IS DISTINCT FROM p_qty_consumption OR prior.total_value IS DISTINCT FROM p_total_value OR prior.bill_date IS DISTINCT FROM p_as_of then
   raise exception 'Opening reference already exists with a different quantity, value or date. Use an audited correction.';
  end if;
  return jsonb_build_object('ok',true,'duplicate_blocked',true,'reference',ref,'purchase_id',prior.id);
 end if;
 insert into public.rr_material_purchases_v805(material_id,purchase_qty,purchase_unit,base_qty,rate_per_purchase_unit,taxable_value,gst_amount,total_value,bill_no,bill_date,payment_status,paid_amount,source_module,source_record_id,data_mode,stock_qty,stock_unit,consumption_equivalent_qty,consumption_equivalent_unit,current_cost_per_consumption_unit,costing_value,running_weighted_avg_cost_per_consumption_unit)
 values(m.id,p_qty_consumption,m.consumption_unit,p_qty_consumption*coalesce(m.consumption_to_base,1),rate,p_total_value,0,p_total_value,ref,p_as_of,'OPENING',0,'MATERIAL_OPENING_BALANCE',ref,upper(p_data_mode),p_qty_consumption*coalesce(m.consumption_to_base,1),m.base_stock_unit,p_qty_consumption,m.consumption_unit,rate,p_total_value,rate);
 return jsonb_build_object('ok',true,'version','V664_MATERIAL_OPENING_BALANCE','material',m.material_name,'opening_qty',p_qty_consumption,'unit',m.consumption_unit,'opening_value',p_total_value,'opening_rate',rate,'reference',ref,'duplicate_blocked',false);
end $function$;