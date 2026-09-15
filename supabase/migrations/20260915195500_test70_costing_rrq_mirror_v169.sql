-- TEST70 V169: legacy/present/future costing, suggestion and RRQ mirror contract.

create or replace function public.rr_upm_mirror_material_cost_v168()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_cloth jsonb;v_cut numeric:=0;v_accessory_total numeric:=0;v_mode text;
begin
 v_mode:=case when exists(select 1 from public.rr_upm_costing_inputs_v9300 where canonical_lot_id=new.canonical_lot_id and data_mode='REAL')then'REAL'else'TEST'end;
 v_cloth:=public.rr_upm_cloth_cost_context_v9300(new.canonical_lot_id);
 select coalesce(sum(cutting_qty),0)into v_cut from public.rr_upm_cut_size_rows_v726(new.lot_no);
 select coalesce(sum(total_cost),0)into v_accessory_total from public.rr_upm_costing_inputs_v9300 where canonical_lot_id=new.canonical_lot_id and data_mode=v_mode and input_type<>'OTHER_MFG_EXP';
 new.regular_fabric_cost_per_piece:=coalesce((v_cloth->>'regular_cost_per_pc')::numeric,0);new.matching_cost_per_piece:=coalesce((v_cloth->>'matching_cost_per_pc')::numeric,0);new.other_material_cost_per_piece:=round(v_accessory_total/nullif(v_cut,0),4);new.material_cost_status:=case when coalesce(v_cloth->>'status','')='MAPPED'then'ACTUAL'else'MISSING'end;return new;
end $$;

create or replace function public.rr_upm_costing_context_v9300(p_canonical_lot_id text,p_data_mode text default 'TEST')
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 v_lot record;v_cut numeric:=0;v_inputs jsonb;v_rates jsonb;v_labor jsonb;v_cloth jsonb;
 v_material numeric:=0;v_process numeric:=0;v_other numeric:=0;v_margin numeric:=22;v_base numeric:=0;v_sale numeric:=0;
 v_missing_rates jsonb:='[]'::jsonb;
begin
 select canonical_lot_id,lot_no,art_no,item_name into v_lot from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id limit 1;
 if not found then raise exception 'Lot not found.';end if;
 select coalesce(sum(cutting_qty),0)into v_cut from public.rr_upm_cut_size_rows_v726(v_lot.lot_no);
 select coalesce(jsonb_agg(to_jsonb(x)order by x.department_code,x.input_type),'[]'::jsonb),coalesce(sum(case when x.input_type<>'OTHER_MFG_EXP'then x.total_cost else 0 end),0),coalesce(sum(case when x.input_type='OTHER_MFG_EXP'then x.total_cost else 0 end),0)
 into v_inputs,v_material,v_other from public.rr_upm_costing_inputs_v9300 x where x.canonical_lot_id=p_canonical_lot_id and x.data_mode=upper(coalesce(p_data_mode,'TEST'));
 v_cloth:=public.rr_upm_cloth_cost_context_v9300(p_canonical_lot_id);
 v_material:=v_material+coalesce((v_cloth->>'regular_total')::numeric,0)+coalesce((v_cloth->>'matching_total')::numeric,0);

 with depts as(
  select public.rr_costing_canonical_department_v760(a.department_code) department_code,
         sum(greatest(coalesce(a.assigned_qty,0),1)) weight_qty,
         sum(coalesce(a.actual_rate,0)*greatest(coalesce(a.assigned_qty,0),1))/nullif(sum(case when coalesce(a.actual_rate,0)>0 then greatest(coalesce(a.assigned_qty,0),1)else 0 end),0) assignment_weighted_rate
  from public.rr_upm_work_assignments_v8 a
  where a.canonical_lot_id=p_canonical_lot_id and upper(coalesce(a.status,''))<>'CANCELLED'
    and public.rr_costing_is_real_department_v760(a.department_code)
  group by 1
 ),effective as(
  select d.department_code,
    coalesce((select r.actual_rate from public.rr_upm_department_rates_v2 r where r.canonical_lot_id=p_canonical_lot_id and public.rr_costing_canonical_department_v760(r.department_code)=d.department_code and r.actual_rate>0 order by r.updated_at desc limit 1),d.assignment_weighted_rate) actual_rate,
    case when exists(select 1 from public.rr_upm_department_rates_v2 r where r.canonical_lot_id=p_canonical_lot_id and public.rr_costing_canonical_department_v760(r.department_code)=d.department_code and r.actual_rate>0)then'DEPARTMENT_HEAD_ACTUAL'when d.assignment_weighted_rate>0 then'ASSIGNMENT_WEIGHTED_ACTUAL'else'ACTUAL_RATE_MISSING'end rate_source
  from depts d
 )
 select coalesce(jsonb_agg(jsonb_build_object('department_code',department_code,'actual_rate',round(actual_rate,4),'rate_source',rate_source)order by department_code),'[]'::jsonb),
        coalesce(sum(actual_rate),0),
        coalesce(jsonb_agg(department_code order by department_code)filter(where coalesce(actual_rate,0)<=0),'[]'::jsonb)
 into v_rates,v_process,v_missing_rates from effective;

 select coalesce(jsonb_agg(to_jsonb(l)),'[]'::jsonb)into v_labor from public.rr_upm_department_labor_cost_v9160 l where l.canonical_lot_id=p_canonical_lot_id and coalesce(l.data_mode,'TEST')=upper(coalesce(p_data_mode,'TEST'));
 select coalesce(numeric_value,22)into v_margin from public.rr_costing_universal_settings_v760 where setting_key='OWNER_MARGIN_FLAT_PER_PCS';
 v_base:=round((v_material+v_other)/nullif(v_cut,0)+v_process,4);v_sale:=round(v_base+coalesce(v_margin,22),2);
 return jsonb_build_object('ok',true,'version','V169','sale_rate_rounding','WHOLE_RUPEE','lot',jsonb_build_object('canonical_lot_id',v_lot.canonical_lot_id,'lot_no',v_lot.lot_no,'art_no',v_lot.art_no,'item_name',v_lot.item_name),'cut_qty',v_cut,'inputs',v_inputs,'cloth',v_cloth,'department_rates',v_rates,'missing_department_rates',v_missing_rates,'labor',v_labor,'material_total',v_material,'process_total',v_process,'other_mfg_total',v_other,'owner_margin_per_pc',coalesce(v_margin,22),'base_cost_per_pc',v_base,'final_sale_rate',v_sale);
end $$;

create or replace function public.rr_pack_rate_context_universal_v9405(p_lot_no text,p_data_mode text default 'TEST')
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_lot text:=trim(p_lot_no);v_mode text:=upper(coalesce(p_data_mode,'TEST'));v_canonical text;v_old jsonb;v_cloth jsonb;v_qty numeric:=0;v_source numeric:=0;v_base numeric:=0;v_margin numeric:=0;v_sale numeric:=0;v_material_pc numeric:=0;v_process_pc numeric:=0;v_other_pc numeric:=0;v_complete boolean:=false;v_missing jsonb:='[]'::jsonb;v_materials jsonb:='[]'::jsonb;v_missing_rates jsonb:='[]'::jsonb;
begin
 perform public.rr_fg_assert_user_v787();select canonical_lot_id into v_canonical from public.rr_upm_lot_registry where upper(trim(lot_no))=upper(v_lot)limit 1;
 if v_canonical is not null then begin
  v_old:=public.rr_upm_costing_context_v9300(v_canonical,v_mode);v_qty:=coalesce((v_old->>'cut_qty')::numeric,0);v_cloth:=coalesce(v_old->'cloth','{}'::jsonb);v_missing_rates:=coalesce(v_old->'missing_department_rates','[]'::jsonb);
  v_material_pc:=round(coalesce((v_old->>'material_total')::numeric,0)/nullif(v_qty,0),4);v_process_pc:=coalesce((v_old->>'process_total')::numeric,0);v_other_pc:=round(coalesce((v_old->>'other_mfg_total')::numeric,0)/nullif(v_qty,0),4);v_margin:=coalesce((v_old->>'owner_margin_per_pc')::numeric,22);v_base:=round(v_material_pc+v_process_pc+v_other_pc,4);v_sale:=round(v_base+v_margin,2);
  v_complete:=coalesce(v_cloth->>'status','')='MAPPED'and jsonb_array_length(v_missing_rates)=0;
  if coalesce(v_cloth->>'status','')<>'MAPPED'then v_missing:=v_missing||jsonb_build_array('MAIN_FABRIC');end if;
  if jsonb_array_length(v_missing_rates)>0 then v_missing:=v_missing||jsonb_build_array('DEPARTMENT_ACTUAL_RATE');end if;
  v_materials:=coalesce(v_cloth->'components','[]'::jsonb)||coalesce((select jsonb_agg(jsonb_build_object('category',x.input_type,'label',initcap(replace(x.input_type,'_',' ')),'department',x.department_code,'qty',x.qty,'unit',x.unit,'rate',x.weighted_rate,'total',x.total_cost,'cost_per_pc',round(x.total_cost/nullif(v_qty,0),4),'source',coalesce(x.source_note,'MAPPED_INPUT'),'required',false,'mapped',x.total_cost>0)order by x.department_code,x.input_type)from public.rr_upm_costing_inputs_v9300 x where x.canonical_lot_id=v_canonical and x.data_mode=v_mode and x.input_type<>'OTHER_MFG_EXP'),'[]'::jsonb);
 exception when others then v_qty:=0;v_complete:=false;v_missing:=v_missing||jsonb_build_array('COSTING_CONTEXT');end;
 if v_qty<=0 then select coalesce(max(ready_qty),0)into v_qty from public.rr_fg_packing_assignments_v788 where data_mode=v_mode and upper(trim(lot_no))=upper(v_lot);end if;
 if v_sale>0 and v_qty>0 then return jsonb_build_object('ok',v_complete,'costing_complete',v_complete,'missing',v_missing,'missing_department_rates',v_missing_rates,'path','UPM_WEIGHTED_ACTUAL_V169','canonical_lot_id',v_canonical,'qty',v_qty,'material_cost_per_pc',round(v_material_pc,2),'process_cost_per_pc',round(v_process_pc,2),'other_mfg_cost_per_pc',round(v_other_pc,2),'base_cost_per_pc',round(v_base,2),'owner_margin_per_pc',round(v_margin,2),'calculated_sale_rate',round(v_sale,2),'source_rate',round(v_sale,0),'approval_rounding','WHOLE_RUPEE','cloth',v_cloth,'material_breakdown',v_materials,'department_rates',coalesce(v_old->'department_rates','[]'::jsonb),'inputs',coalesce(v_old->'inputs','[]'::jsonb));end if;
 end if;
 select coalesce(nullif(base_sale_rate,0),nullif(final_sale_rate,0)),qty_snapshot,canonical_lot_id into v_source,v_qty,v_canonical from public.rrq_lot_rates_v9300 where data_mode=v_mode and upper(trim(lot_no))=upper(v_lot)and qty_snapshot>0 and coalesce(nullif(base_sale_rate,0),nullif(final_sale_rate,0))>0 order by updated_at desc nulls last limit 1;
 if coalesce(v_source,0)>0 and coalesce(v_qty,0)>0 then return jsonb_build_object('ok',true,'costing_complete',true,'path','RRQ_LEGACY','canonical_lot_id',v_canonical,'qty',v_qty,'calculated_sale_rate',v_source,'source_rate',round(v_source,0),'approval_rounding','WHOLE_RUPEE');end if;
 select source_rate,qty_snapshot into v_source,v_qty from public.rr_pack_rate_approval_v9340 where data_mode=v_mode and upper(trim(lot_no))=upper(v_lot)and source_rate>0 and qty_snapshot>0 order by updated_at desc nulls last limit 1;
 if coalesce(v_source,0)>0 and coalesce(v_qty,0)>0 then return jsonb_build_object('ok',true,'costing_complete',true,'path','APPROVAL_HISTORY','canonical_lot_id',v_canonical,'qty',v_qty,'calculated_sale_rate',v_source,'source_rate',round(v_source,0),'approval_rounding','WHOLE_RUPEE');end if;return jsonb_build_object('ok',false,'costing_complete',false,'path','NONE','canonical_lot_id',v_canonical,'qty',0,'source_rate',0);
end $$;

create or replace function public.rr_pack_rate_suggest_v9340(p_lot_no text,p_suggested_rate numeric,p_data_mode text default 'TEST')returns jsonb language plpgsql security definer set search_path=public as $$
declare v_role text:=lower(coalesce(public.rr_current_role(),''));v_kind text;
begin
 if v_role not in('owner','admin','accounts','sales')then raise exception 'Sales/Admin access required';end if;
 if p_suggested_rate is null or p_suggested_rate<=0 or p_suggested_rate<>round(p_suggested_rate,0)then raise exception 'Suggested rate must be whole rupee';end if;
 v_kind:=case when v_role='sales'then'SALES'else'ADMIN'end;
 update public.rr_pack_rate_approval_v9340 set sales_suggested_rate=case when v_kind='SALES'then p_suggested_rate else sales_suggested_rate end,sales_suggested_by=case when v_kind='SALES'then auth.uid()else sales_suggested_by end,sales_suggested_at=case when v_kind='SALES'then now()else sales_suggested_at end,admin_suggested_rate=case when v_kind='ADMIN'then p_suggested_rate else admin_suggested_rate end,admin_suggested_by=case when v_kind='ADMIN'then auth.uid()else admin_suggested_by end,admin_suggested_at=case when v_kind='ADMIN'then now()else admin_suggested_at end,suggested_rate=p_suggested_rate,suggested_by=auth.uid(),suggested_at=now(),status='SUGGESTED',updated_at=now()where data_mode=upper(p_data_mode)and lot_no=trim(p_lot_no)and status<>'APPROVED';
 if not found then raise exception 'Rate request not found or already approved';end if;return jsonb_build_object('ok',true,'suggestion_type',v_kind,'suggested_rate',p_suggested_rate);
end $$;

create or replace function public.rr_pack_rate_approve_v9340(p_lot_no text,p_final_rate numeric,p_data_mode text default 'TEST')returns jsonb language plpgsql security definer set search_path=public as $$
declare v_role text:=lower(coalesce(public.rr_current_role(),''));r record;v_apply jsonb;v_delta numeric;v_impact numeric;v_ctx jsonb;
begin
 if v_role not in('owner','admin')then raise exception 'Admin/Super Admin approval required';end if;
 if p_final_rate is null or p_final_rate<=0 or p_final_rate<>round(p_final_rate,0)then raise exception 'Final rate must be whole rupee';end if;
 v_ctx:=public.rr_pack_rate_context_universal_v9405(trim(p_lot_no),upper(p_data_mode));if coalesce((v_ctx->>'costing_complete')::boolean,false)is not true then raise exception 'Material ya department actual costing incomplete';end if;
 select * into r from public.rr_pack_rate_approval_v9340 where data_mode=upper(p_data_mode)and lot_no=trim(p_lot_no)for update;if not found then raise exception 'Rate request not found';end if;
 v_apply:=public.rrq_apply_packing_rate_v9300(trim(p_lot_no),p_final_rate,upper(p_data_mode),'Packing final rate approved from mirrored App/Real Chat review');v_delta:=p_final_rate-round((v_ctx->>'source_rate')::numeric,0);v_impact:=v_delta*r.qty_snapshot;
 update public.rr_pack_rate_approval_v9340 set source_rate=round((v_ctx->>'source_rate')::numeric,0),final_rate=p_final_rate,reserve_delta_per_pc=v_delta,reserve_quota_impact=v_impact,status='APPROVED',approved_by=auth.uid(),approved_at=now(),updated_at=now()where id=r.id;
 return jsonb_build_object('ok',true,'lot_no',r.lot_no,'mapped_cost_per_pc',v_ctx->'base_cost_per_pc','mapped_sale_suggestion',v_ctx->'source_rate','final_rate',p_final_rate,'art_code',public.rr_pack_art_code_v9340(p_final_rate),'reserve_delta_per_pc',v_delta,'reserve_quota_impact',v_impact,'rrq',v_apply);
end $$;

create or replace function public.rr_upm_cost_source_change_v169()returns trigger language plpgsql security definer set search_path=public as $$
declare v_id text;
begin
 v_id:=case when tg_op='DELETE'then old.canonical_lot_id else new.canonical_lot_id end;
 if v_id is not null and exists(select 1 from public.rr_upm_lot_registry where canonical_lot_id=v_id)then perform public.rr_upm_refresh_lot_costing_v760(v_id);end if;
 if tg_op='DELETE'then return old;else return new;end if;
end $$;
drop trigger if exists rr_rate_cost_refresh_v169 on public.rr_upm_department_rates_v2;create trigger rr_rate_cost_refresh_v169 after insert or update or delete on public.rr_upm_department_rates_v2 for each row execute function public.rr_upm_cost_source_change_v169();
drop trigger if exists rr_input_cost_refresh_v169 on public.rr_upm_costing_inputs_v9300;create trigger rr_input_cost_refresh_v169 after insert or update or delete on public.rr_upm_costing_inputs_v9300 for each row execute function public.rr_upm_cost_source_change_v169();
drop trigger if exists rr_assignment_cost_refresh_v169 on public.rr_upm_work_assignments_v8;create trigger rr_assignment_cost_refresh_v169 after insert or update or delete on public.rr_upm_work_assignments_v8 for each row execute function public.rr_upm_cost_source_change_v169();

create or replace function public.rr_pack_rate_admin_notify_v169()returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.status in('REQUESTED','SUGGESTED')and(tg_op='INSERT'or old.status is distinct from new.status or old.source_rate is distinct from new.source_rate)then
  insert into public.rr_notifications(user_id,role_code,department_code,title,message,is_read,created_at)
  select p.id,'admin','packing','Packing Final Rate Review','Lot '||new.lot_no||' · mapped suggestion ₹'||new.source_rate||' · Sales suggestion '||coalesce('₹'||new.sales_suggested_rate::text,'pending')||' · Final rate approval required.',false,now()
  from public.rr_user_profiles p where p.is_active and lower(p.role_code)='admin'
  and not exists(select 1 from public.rr_notifications n where n.user_id=p.id and not n.is_read and n.title='Packing Final Rate Review'and n.message like 'Lot '||new.lot_no||' ·%');
 end if;return new;
end $$;
drop trigger if exists rr_pack_rate_admin_notify_v169 on public.rr_pack_rate_approval_v9340;
create trigger rr_pack_rate_admin_notify_v169 after insert or update on public.rr_pack_rate_approval_v9340 for each row execute function public.rr_pack_rate_admin_notify_v169();

do $$declare x record;begin for x in select distinct l.canonical_lot_id from public.rr_upm_lot_registry l join public.rr_upm_work_assignments_v8 a on a.canonical_lot_id=l.canonical_lot_id loop perform public.rr_upm_refresh_lot_costing_v760(x.canonical_lot_id);end loop;end $$;

update public.rr_pack_rate_approval_v9340 r set source_rate=round(c.final_sale_price,0),updated_at=now()from public.rr_upm_lot_costing_v760 c where c.lot_no=r.lot_no and r.status<>'APPROVED'and c.material_cost_status='ACTUAL'and c.final_sale_price>0;
revoke all on function public.rr_upm_costing_context_v9300(text,text)from public,anon;revoke all on function public.rr_pack_rate_context_universal_v9405(text,text)from public,anon;revoke all on function public.rr_pack_rate_suggest_v9340(text,numeric,text)from public,anon;revoke all on function public.rr_pack_rate_approve_v9340(text,numeric,text)from public,anon;revoke all on function public.rr_upm_cost_source_change_v169()from public,anon,authenticated;
revoke all on function public.rr_pack_rate_admin_notify_v169()from public,anon,authenticated;
grant execute on function public.rr_upm_costing_context_v9300(text,text)to authenticated;grant execute on function public.rr_pack_rate_context_universal_v9405(text,text)to authenticated;grant execute on function public.rr_pack_rate_suggest_v9340(text,numeric,text)to authenticated;grant execute on function public.rr_pack_rate_approve_v9340(text,numeric,text)to authenticated;
