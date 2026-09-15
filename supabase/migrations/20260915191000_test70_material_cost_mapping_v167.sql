-- TEST70 V167: canonical Main Fabric, Matching Cloth and accessory costing map.
create or replace function public.rr_upm_cloth_cost_context_v9300(p_canonical_lot_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_lot record;v_qty numeric:=0;v_rate numeric:=0;v_regular numeric:=0;v_match_qty numeric:=0;v_match_rate numeric:=0;v_match numeric:=0;v_cut numeric:=0;v_unit_cut numeric:=0;v_unit_weight numeric:=0;v_unit_amount numeric:=0;v_status text:='MAPPED';v_source text:='';
begin
 select * into v_lot from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id limit 1;
 if not found then raise exception 'Lot not found.';end if;
 select coalesce(sum(cutting_qty),0) into v_cut from public.rr_upm_cut_size_rows_v726(v_lot.lot_no);
 if v_lot.source_table='rr_cutting_lots_v3' then
  select coalesce(l.fabric_used,0),coalesce(nullif(u.divided_amount,0)/nullif(u.divided_weight,0),nullif(p.total_amount,0)/nullif(p.total_weight,0),0),coalesce(l.matching_qty,0),coalesce(l.matching_avg_cost,0),coalesce(l.matching_amount,0)
  into v_qty,v_rate,v_match_qty,v_match_rate,v_match from public.rr_cutting_lots_v3 l left join public.rr_cb_units u on u.id=l.cb_unit_id left join public.rr_fabric_purchases p on p.id=l.cb_purchase_id where l.id=v_lot.source_id::uuid;
  v_source:='CUTTING_ACTUAL_USAGE';
 elsif v_lot.source_table='rr_production_lots' then
  select coalesce(l.matching_qty,0),coalesce(l.matching_amount,0),coalesce(nullif(l.matching_amount,0)/nullif(l.matching_qty,0),l.matching_avg_cost,0),coalesce(u.divided_weight,0),coalesce(u.divided_amount,0)
  into v_match_qty,v_match,v_match_rate,v_unit_weight,v_unit_amount from public.rr_production_lots l left join public.rr_cb_units u on u.id=l.cb_unit_id where l.id=v_lot.source_id::uuid;
  select coalesce(sum(x.cut_qty),0) into v_unit_cut from public.rr_production_lots p cross join lateral(select coalesce(sum(s.cutting_qty),0) cut_qty from public.rr_upm_cut_size_rows_v726(p.lot_no)s)x where p.cb_unit_id=(select cb_unit_id from public.rr_production_lots where id=v_lot.source_id::uuid);
  if v_cut>0 and v_unit_cut>0 and v_unit_weight>0 and v_unit_amount>0 then v_qty:=v_unit_weight*v_cut/v_unit_cut;v_regular:=v_unit_amount*v_cut/v_unit_cut;v_rate:=v_unit_amount/v_unit_weight;v_source:='CB_UNIT_PRO_RATA_BY_ACTUAL_CUT_PCS';
  else v_status:='REGULAR_CLOTH_MAPPING_PENDING';v_source:='CB_UNIT_ALLOCATION_PENDING';end if;
 end if;
 if v_regular<=0 then v_regular:=v_qty*v_rate;end if;if v_match<=0 then v_match:=v_match_qty*v_match_rate;end if;
 if v_qty<=0 or v_rate<=0 or v_regular<=0 then v_status:='REGULAR_CLOTH_MAPPING_PENDING';end if;
 return jsonb_build_object('status',v_status,'allocation_source',v_source,'regular_qty_kg',round(v_qty,4),'regular_rate_per_kg',round(v_rate,4),'regular_total',round(v_regular,2),'regular_cost_per_pc',round(v_regular/nullif(v_cut,0),4),'matching_qty_kg',round(v_match_qty,4),'matching_rate_per_kg',round(v_match_rate,4),'matching_total',round(v_match,2),'matching_cost_per_pc',round(v_match/nullif(v_cut,0),4),'components',jsonb_build_array(
  jsonb_build_object('category','MAIN_FABRIC','label','Main Fabric','qty',round(v_qty,4),'unit','KG','rate',round(v_rate,4),'total',round(v_regular,2),'cost_per_pc',round(v_regular/nullif(v_cut,0),4),'source',v_source,'required',true,'mapped',v_status='MAPPED'),
  jsonb_build_object('category','MATCHING_CLOTH','label','Matching Cloth','qty',round(v_match_qty,4),'unit','KG','rate',round(v_match_rate,4),'total',round(v_match,2),'cost_per_pc',round(v_match/nullif(v_cut,0),4),'source','LOT_MATCHING_ACTUAL','required',false,'mapped',v_match>0)));
end $$;

create or replace function public.rr_upm_costing_context_v9300(p_canonical_lot_id text,p_data_mode text default 'TEST')returns jsonb language plpgsql security definer set search_path=public as $$
declare v_lot record;v_cut numeric:=0;v_inputs jsonb;v_rates jsonb;v_labor jsonb;v_cloth jsonb;v_material numeric:=0;v_process numeric:=0;v_other numeric:=0;v_margin numeric:=22;v_base numeric:=0;v_sale numeric:=0;
begin
 select canonical_lot_id,lot_no,art_no,item_name into v_lot from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id limit 1;if not found then raise exception 'Lot not found.';end if;
 select coalesce(sum(cutting_qty),0)into v_cut from public.rr_upm_cut_size_rows_v726(v_lot.lot_no);
 select coalesce(jsonb_agg(to_jsonb(x)order by x.department_code,x.input_type),'[]'::jsonb),coalesce(sum(case when x.input_type<>'OTHER_MFG_EXP'then x.total_cost else 0 end),0),coalesce(sum(case when x.input_type='OTHER_MFG_EXP'then x.total_cost else 0 end),0)into v_inputs,v_material,v_other from public.rr_upm_costing_inputs_v9300 x where x.canonical_lot_id=p_canonical_lot_id and x.data_mode=upper(coalesce(p_data_mode,'TEST'));
 v_cloth:=public.rr_upm_cloth_cost_context_v9300(p_canonical_lot_id);v_material:=v_material+coalesce((v_cloth->>'regular_total')::numeric,0)+coalesce((v_cloth->>'matching_total')::numeric,0);
 select coalesce(jsonb_agg(to_jsonb(r)order by r.department_code),'[]'::jsonb),coalesce(sum(r.actual_rate),0)into v_rates,v_process from public.rr_upm_department_rates_v2 r where r.canonical_lot_id=p_canonical_lot_id;
 select coalesce(jsonb_agg(to_jsonb(l)),'[]'::jsonb)into v_labor from public.rr_upm_department_labor_cost_v9160 l where l.canonical_lot_id=p_canonical_lot_id and coalesce(l.data_mode,'TEST')=upper(coalesce(p_data_mode,'TEST'));
 select coalesce(numeric_value,22)into v_margin from public.rr_costing_universal_settings_v760 where setting_key='OWNER_MARGIN_FLAT_PER_PCS';v_base:=round((v_material+v_other)/nullif(v_cut,0)+v_process,4);v_sale:=round(v_base+coalesce(v_margin,22),2);
 return jsonb_build_object('ok',true,'version','V167','sale_rate_rounding','WHOLE_RUPEE','lot',jsonb_build_object('canonical_lot_id',v_lot.canonical_lot_id,'lot_no',v_lot.lot_no,'art_no',v_lot.art_no,'item_name',v_lot.item_name),'cut_qty',v_cut,'inputs',v_inputs,'cloth',v_cloth,'department_rates',v_rates,'labor',v_labor,'material_total',v_material,'process_total',v_process,'other_mfg_total',v_other,'owner_margin_per_pc',coalesce(v_margin,22),'base_cost_per_pc',v_base,'final_sale_rate',v_sale);
end $$;

create or replace function public.rr_pack_rate_context_universal_v9405(p_lot_no text,p_data_mode text default 'TEST')returns jsonb language plpgsql security definer set search_path=public as $$
declare v_lot text:=trim(p_lot_no);v_mode text:=upper(coalesce(p_data_mode,'TEST'));v_canonical text;v_old jsonb;v_cloth jsonb;v_qty numeric:=0;v_source numeric:=0;v_base numeric:=0;v_margin numeric:=0;v_sale numeric:=0;v_material_pc numeric:=0;v_process_pc numeric:=0;v_other_pc numeric:=0;v_complete boolean:=false;v_missing jsonb:='[]'::jsonb;v_materials jsonb:='[]'::jsonb;
begin
 perform public.rr_fg_assert_user_v787();select canonical_lot_id into v_canonical from public.rr_upm_lot_registry where upper(trim(lot_no))=upper(v_lot)limit 1;
 if v_canonical is not null then begin
  v_old:=public.rr_upm_costing_context_v9300(v_canonical,v_mode);v_qty:=coalesce((v_old->>'cut_qty')::numeric,0);v_cloth:=coalesce(v_old->'cloth','{}'::jsonb);v_material_pc:=round(coalesce((v_old->>'material_total')::numeric,0)/nullif(v_qty,0),4);v_process_pc:=coalesce((v_old->>'process_total')::numeric,0);v_other_pc:=round(coalesce((v_old->>'other_mfg_total')::numeric,0)/nullif(v_qty,0),4);v_margin:=coalesce((v_old->>'owner_margin_per_pc')::numeric,22);v_base:=round(v_material_pc+v_process_pc+v_other_pc,4);v_sale:=round(v_base+v_margin,2);v_complete:=coalesce(v_cloth->>'status','')='MAPPED';if not v_complete then v_missing:=v_missing||jsonb_build_array('MAIN_FABRIC');end if;
  v_materials:=coalesce(v_cloth->'components','[]'::jsonb)||coalesce((select jsonb_agg(jsonb_build_object('category',x.input_type,'label',initcap(replace(x.input_type,'_',' ')),'department',x.department_code,'qty',x.qty,'unit',x.unit,'rate',x.weighted_rate,'total',x.total_cost,'cost_per_pc',round(x.total_cost/nullif(v_qty,0),4),'source',coalesce(x.source_note,'MAPPED_INPUT'),'required',false,'mapped',x.total_cost>0)order by x.department_code,x.input_type)from public.rr_upm_costing_inputs_v9300 x where x.canonical_lot_id=v_canonical and x.data_mode=v_mode and x.input_type<>'OTHER_MFG_EXP'),'[]'::jsonb);
 exception when others then v_qty:=0;v_complete:=false;v_missing:=v_missing||jsonb_build_array('COSTING_CONTEXT');end;
 if v_qty<=0 then select coalesce(max(ready_qty),0)into v_qty from public.rr_fg_packing_assignments_v788 where data_mode=v_mode and upper(trim(lot_no))=upper(v_lot);end if;
 if v_sale>0 and v_qty>0 then return jsonb_build_object('ok',v_complete,'costing_complete',v_complete,'missing',v_missing,'path','UPM_MATERIAL_MAPPING_V167','canonical_lot_id',v_canonical,'qty',v_qty,'material_cost_per_pc',round(v_material_pc,2),'process_cost_per_pc',round(v_process_pc,2),'other_mfg_cost_per_pc',round(v_other_pc,2),'base_cost_per_pc',round(v_base,2),'owner_margin_per_pc',round(v_margin,2),'calculated_sale_rate',round(v_sale,2),'source_rate',round(v_sale,0),'approval_rounding','WHOLE_RUPEE','cloth',v_cloth,'material_breakdown',v_materials,'department_rates',coalesce(v_old->'department_rates','[]'::jsonb),'inputs',coalesce(v_old->'inputs','[]'::jsonb));end if;
 end if;
 select coalesce(nullif(base_sale_rate,0),nullif(final_sale_rate,0)),qty_snapshot,canonical_lot_id into v_source,v_qty,v_canonical from public.rrq_lot_rates_v9300 where data_mode=v_mode and upper(trim(lot_no))=upper(v_lot)and qty_snapshot>0 and coalesce(nullif(base_sale_rate,0),nullif(final_sale_rate,0))>0 order by updated_at desc nulls last limit 1;
 if coalesce(v_source,0)>0 and coalesce(v_qty,0)>0 then return jsonb_build_object('ok',true,'path','RRQ','canonical_lot_id',v_canonical,'qty',v_qty,'calculated_sale_rate',v_source,'source_rate',round(v_source,0),'approval_rounding','WHOLE_RUPEE');end if;
 select source_rate,qty_snapshot into v_source,v_qty from public.rr_pack_rate_approval_v9340 where data_mode=v_mode and upper(trim(lot_no))=upper(v_lot)and source_rate>0 and qty_snapshot>0 order by updated_at desc nulls last limit 1;
 if coalesce(v_source,0)>0 and coalesce(v_qty,0)>0 then return jsonb_build_object('ok',true,'path','APPROVAL_HISTORY','canonical_lot_id',v_canonical,'qty',v_qty,'calculated_sale_rate',v_source,'source_rate',round(v_source,0),'approval_rounding','WHOLE_RUPEE');end if;return jsonb_build_object('ok',false,'path','NONE','canonical_lot_id',v_canonical,'qty',0,'source_rate',0);
end $$;
revoke all on function public.rr_upm_cloth_cost_context_v9300(text)from public,anon;revoke all on function public.rr_upm_costing_context_v9300(text,text)from public,anon;revoke all on function public.rr_pack_rate_context_universal_v9405(text,text)from public,anon;
grant execute on function public.rr_upm_cloth_cost_context_v9300(text)to authenticated;grant execute on function public.rr_upm_costing_context_v9300(text,text)to authenticated;grant execute on function public.rr_pack_rate_context_universal_v9405(text,text)to authenticated;
comment on function public.rr_upm_cloth_cost_context_v9300(text)is 'V167: single-lot actual fabric usage and multi-lot CB-unit cost pro-rata by actual cut PCS.';
