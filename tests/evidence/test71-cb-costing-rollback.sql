-- Run inside BEGIN/ROLLBACK; changes in this proof must never be committed.

do $test$
declare lot text; b jsonb; c jsonb; n int; expected int; actor uuid; mid uuid; aid uuid; r record; before_final jsonb; after_final jsonb;
begin
 select canonical_lot_id into lot from public.rr_upm_lot_registry lr join public.rr_art_master a on a.id::text=lr.art_id
 join public.rr_art_categories ac on ac.id=a.art_category_id where ac.category_code='flat-polo' order by lr.created_at desc limit 1;
 b:=public.rr_lot_category_canonical_v682(lot);
 if b->>'category_code'<>'flat-polo' or b->>'source'<>'LOT_ART_SNAPSHOT' then raise exception 'Released Lot category snapshot changed'; end if;
 if exists(select 1 from public.rr_material_effective_mappings_v1(current_date) where effective_from>current_date) then raise exception 'Future mapping leaked'; end if;
 select count(distinct x.material_id) into expected from public.rr_material_effective_mappings_v1(current_date) x join public.rr_material_master_v805 m on m.id=x.material_id and m.is_active
 where x.consumption_method='BOM_AUTO' and upper(x.category_code) in('ALL','FLAT-POLO');
 perform public.rr_material_bom_apply_v657(lot,108,'TEST71-COSTING-ROLLBACK-PROOF','TEST');
 perform public.rr_material_bom_apply_v660(lot,108,'TEST71-COSTING-ROLLBACK-PROOF','TEST');
 perform public.rr_material_bom_apply_v661(lot,108,'TEST71-COSTING-ROLLBACK-PROOF','TEST');
 c:=public.rr_material_bom_apply_v662(lot,108,'TEST71-COSTING-ROLLBACK-PROOF','TEST');
 select count(*) into n from public.rr_material_consumption_v805 where source_record_id='TEST71-COSTING-ROLLBACK-PROOF' and source_module='CATEGORY_BOM' and data_mode='TEST';
 if n<>expected or jsonb_array_length(c->'consumed')<>expected then raise exception 'Saved rules omitted or double counted'; end if;
 if c->>'category'<>'FLAT-POLO' then raise exception 'Canonical category code mismatch'; end if;
 for r in select x.*,m.material_name from public.rr_material_effective_mappings_v1(current_date) x join public.rr_material_master_v805 m on m.id=x.material_id
 where x.consumption_method='BOM_AUTO' and x.category_code='ALL' and not exists(
 select 1 from public.rr_material_effective_mappings_v1(current_date) s where s.material_id=x.material_id and s.consumption_method='BOM_AUTO' and upper(s.category_code)='FLAT-POLO')
 loop
  if not exists(select 1 from jsonb_array_elements(c->'consumed') z where z->>'material_name'=r.material_name and (z->>'qty')::numeric=108*r.qty_per_piece)
  then raise exception 'ALL per-piece rule broken'; end if;
 end loop;
 select auth_user_id into actor from public.rr_user_profiles where upper(role_code) in('OWNER','SUPER_ADMIN') and is_active and upper(coalesce(access_status,'ACTIVE'))='ACTIVE' order by updated_at desc nulls last limit 1;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 select material_id into mid from public.rr_material_effective_mappings_v1(current_date) where consumption_method='WORKER_ACTUAL' limit 1;
 perform public.rr_material_mapping_save_v660(mid,'WORKER_ACTUAL',null,'PACKING',false,null,current_date,null);
 perform public.rr_material_mapping_save_v660(mid,'WORKER_ACTUAL',null,'PACKING',false,null,current_date,null);
 select count(*) into n from public.rr_material_consumption_mapping_v655 where material_id=mid and consumption_method='WORKER_ACTUAL' and consume_department_code=public.rr_upm_core_department_v9077('PACKING') and effective_from=current_date and is_active;
 if n<>1 then raise exception 'Repeated Save duplicated mapping'; end if;
 select id into aid from public.rr_upm_work_assignments_v8 where public.rr_upm_core_department_v9077(department_code)='PACKING' limit 1;
 if aid is not null then
  b:=public.rr_material_direct_pending_v659(aid,'TEST'); c:=public.rr_material_direct_pending_v658(aid,'TEST');
  if b is distinct from c then raise exception 'Pending adapters differ'; end if;
 end if;
 b:=public.rr_upm_costing_context_v9300(lot,'TEST');
 c:=public.rr_upm_costing_panel_v760(lot);
 if b is distinct from (c->'costing') then raise exception 'App/rate/chat panel final-cost authority differs'; end if;
end $test$;

create temporary table cb_costing_inheritance_proof(cb_unit_id uuid,art_no text,print_no text,sleeve_type text,border_type text);
create trigger cb_costing_inheritance_proof_trg before insert on cb_costing_inheritance_proof for each row execute function public.rr_lot_inherit_cb_set_combo_v1();
do $proof$
declare u record; inherited record; n int:=0; b jsonb;
begin
 for u in select d.cb_unit_id,am.art_no from public.rr_pm_decision_status_v802 d join public.rr_cb_art_assignments ca on ca.cb_id=d.cb_unit_id
 join public.rr_art_master am on am.id=ca.art_id where d.all_decisions_complete order by d.cb_unit_id limit 10 loop
  insert into cb_costing_inheritance_proof(cb_unit_id,art_no,print_no,sleeve_type,border_type)
  values(u.cb_unit_id,'UNRELATED_ART','UNRELATED_PRINT','full','with') returning * into inherited;
  if inherited.art_no is distinct from u.art_no then raise exception 'Parent CB Art not inherited'; end if;
  n:=n+1;
 end loop;
 if n=0 then raise exception 'No complete CB fixture for inheritance proof'; end if;
end $proof$;
