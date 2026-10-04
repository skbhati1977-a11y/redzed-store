-- One CB/Art category and one effective BOM evaluation for App + Group + Personal Chat.
-- Preserve posted costs, salaries, allocation quantities, and existing component rounding.
create or replace function public.rr_lot_category_canonical_v682(p_canonical_lot_id text)
returns jsonb language plpgsql stable security definer set search_path=''
as $function$
declare l record; a record; unit_id uuid; category_id uuid; code text; origin text;
begin
 select * into l from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id;
 if not found then raise exception 'Lot not found'; end if;
 if l.source_table='rr_cutting_lots_v3' then
  select cb_unit_id into unit_id from public.rr_cutting_lots_v3 where id::text=l.source_id;
 elsif l.source_table='rr_production_lots' then
  select cb_unit_id into unit_id from public.rr_production_lots where id::text=l.source_id;
 end if;
 if unit_id is null and coalesce(l.metadata->>'cb_unit_id','') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
  unit_id:=(l.metadata->>'cb_unit_id')::uuid;
 end if;
 -- A released Lot keeps its own Art snapshot. CB is a fallback for incomplete legacy identity.
 select * into a from public.rr_art_master where id::text=l.art_id or upper(art_no)=upper(l.art_no)
  order by case when id::text=l.art_id then 0 else 1 end,updated_at desc nulls last,id limit 1;
 category_id:=a.art_category_id; origin:='LOT_ART_SNAPSHOT';
 if category_id is null and unit_id is not null then
  select am.* into a from public.rr_cb_art_assignments ca join public.rr_art_master am on am.id=ca.art_id where ca.cb_id=unit_id;
  if found then category_id:=a.art_category_id; origin:='CB_SET_ART_COMBO'; end if;
 end if;
 select lower(category_code) into code from public.rr_art_categories where id=category_id and is_active;
 -- Legacy Art labels are only a compatibility fallback, never the primary match key.
 if code is null and category_id is null then code:=public.rr_art_category_code_canonical_v682(a.category); end if;
 return jsonb_build_object('lot_no',l.lot_no,'art_no',a.art_no,'raw_category',a.category,
  'category_code',code,'category_id',category_id,'cb_unit_id',unit_id,'source',origin,
  'mapped',code is not null,'state',case when code is null then 'CATEGORY_MAPPING_REQUIRED' else 'READY' end);
end $function$;

create or replace function public.rr_material_effective_mappings_v1(p_as_of date default current_date)
returns setof public.rr_material_consumption_mapping_v655
language sql stable security invoker set search_path=''
as $function$
 select distinct on (material_id,consumption_method,upper(coalesce(category_code,'')),coalesce(consume_department_code,''),execution_decision) x.*
 from public.rr_material_consumption_mapping_v655 x
 where is_active and effective_from<=p_as_of
 order by material_id,consumption_method,upper(coalesce(category_code,'')),coalesce(consume_department_code,''),execution_decision,
  effective_from desc,updated_at desc nulls last,created_at desc,id desc
$function$;

-- Duplicate and historical configurations remain as audit data; effective selection retires duplicate runtime evaluation.

-- Retain the existing BOM quantity/rate/ledger engine; only resolve Category through CB/Art identity.
CREATE OR REPLACE FUNCTION public.rr_material_bom_apply_v662(p_canonical_lot_id text, p_good_pcs numeric, p_source_record_id text, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare l record;v_cat text;z record;m record;ratej jsonb;v_qty numeric;v_rate numeric;v_total numeric;v_done jsonb:='[]';
begin if coalesce(p_good_pcs,0)<=0 then return jsonb_build_object('ok',true,'consumed',v_done);end if;select * into l from public.rr_upm_lot_registry where canonical_lot_id=p_canonical_lot_id;if not found then raise exception 'Lot not found';end if;v_cat:=upper(public.rr_lot_category_canonical_v682(p_canonical_lot_id)->>'category_code');
for z in select distinct on(x.material_id) x.* from public.rr_material_effective_mappings_v1(current_date) x where x.is_active and x.consumption_method='BOM_AUTO' and x.effective_from<=current_date and (upper(x.category_code)='ALL' or upper(x.category_code)=v_cat) order by x.material_id,case when upper(x.category_code)=v_cat then 0 else 1 end,x.effective_from desc,x.id desc loop
 select * into m from public.rr_material_master_v805 where id=z.material_id and is_active;ratej:=public.rr_material_weighted_rate_canonical_v662(m.id,p_data_mode);v_rate:=coalesce((ratej->>'rate_per_consumption_unit')::numeric,0);if v_rate<=0 then raise exception 'Weighted purchase rate missing for BOM material %.',m.material_name;end if;v_qty:=p_good_pcs*z.qty_per_piece;v_total:=v_qty*v_rate;
 insert into public.rr_material_consumption_v805(material_id,source_module,source_record_id,lot_no,applicable_qty,consumption_qty,consumption_unit,base_qty_consumed,weighted_rate_per_base_unit,weighted_rate_per_consumption_unit,cost_per_good_piece,total_consumption_cost,consumption_basis,data_mode) values(m.id,'CATEGORY_BOM',p_source_record_id,l.lot_no,p_good_pcs,v_qty,m.consumption_unit,v_qty*coalesce(m.consumption_to_base,1),v_rate/nullif(coalesce(m.consumption_to_base,1),0),v_rate,v_total/p_good_pcs,v_total,'CATEGORY_BOM:'||coalesce(v_cat,'PROVISION'),upper(p_data_mode)) on conflict(material_id,source_module,source_record_id,data_mode) do update set applicable_qty=excluded.applicable_qty,consumption_qty=excluded.consumption_qty,base_qty_consumed=excluded.base_qty_consumed,weighted_rate_per_base_unit=excluded.weighted_rate_per_base_unit,weighted_rate_per_consumption_unit=excluded.weighted_rate_per_consumption_unit,cost_per_good_piece=excluded.cost_per_good_piece,total_consumption_cost=excluded.total_consumption_cost;
 v_done:=v_done||jsonb_build_array(jsonb_build_object('material_name',m.material_name,'qty',v_qty,'unit',m.consumption_unit,'weighted_rate',v_rate,'rate_source',ratej->>'source','cost',v_total));end loop;
return jsonb_build_object('ok',true,'version','V662_BOM_CANONICAL_RATE','category',v_cat,'consumed',v_done);end $function$
;

revoke all on function public.rr_material_effective_mappings_v1(date) from public,anon,authenticated;


-- Save replaces only the identical scope/date; pending and confirm use the same effective rows.
CREATE OR REPLACE FUNCTION public.rr_material_mapping_save_v660(p_material_id uuid, p_method text, p_category_code text DEFAULT NULL::text, p_department_code text DEFAULT NULL::text, p_execution_decision boolean DEFAULT false, p_qty_per_piece numeric DEFAULT NULL::numeric, p_effective_from date DEFAULT CURRENT_DATE, p_consumption_unit text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare m record;v_method text:=upper(trim(p_method));v_cat text:=upper(nullif(trim(coalesce(p_category_code,'')),''));v_dep text:=case when nullif(trim(coalesce(p_department_code,'')),'') is null then null else public.rr_upm_core_department_v9077(p_department_code) end;v_id uuid;v_actual_role text;v_unit text;
begin
 if auth.uid() is null then raise exception 'Login required.';end if;
 select upper(coalesce(p.role_code,'')) into v_actual_role from public.rr_user_profiles p where p.auth_user_id=auth.uid() and p.is_active and upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE' order by p.updated_at desc nulls last limit 1;
 if coalesce(v_actual_role,'') not in('OWNER','SUPER_ADMIN','ADMIN','ACCOUNTS') then raise exception 'Admin / Accounts permission required.';end if;
 select * into m from public.rr_material_master_v805 where id=p_material_id and is_active;if not found then raise exception 'Active Material required.';end if;
 if v_method not in('BOM_AUTO','WORKER_ACTUAL','DIRECT_ACTUAL','OVERHEAD') then raise exception 'Invalid Consumption Method.';end if;
 if v_method in('OVERHEAD','WORKER_ACTUAL') then v_unit:=null;if v_method='OVERHEAD' then v_dep:=null;end if;else v_unit:=upper(coalesce(nullif(trim(p_consumption_unit),''),m.consumption_unit));if not exists(select 1 from public.rr_unit_master_v606 u where upper(u.unit_code)=v_unit and u.is_active) then raise exception 'Active Consumption Unit required.';end if;end if;
 if v_method='BOM_AUTO' and(v_cat is null or p_qty_per_piece is null or p_qty_per_piece<0) then raise exception 'BOM AUTO requires ALL/Category and Qty per Piece.';end if;
 if v_method='WORKER_ACTUAL' and v_dep is null then raise exception 'WORKER ACTUAL requires Consume Department.';end if;
 if v_method='DIRECT_ACTUAL' and not coalesce(p_execution_decision,false) and v_dep is null then raise exception 'DIRECT ACTUAL requires Department or Decide At Execution.';end if;
 perform pg_advisory_xact_lock(hashtextextended('MATERIAL_MAPPING:'||p_material_id::text,0));
 update public.rr_material_consumption_mapping_v655 set is_active=false,updated_at=now()
 where material_id=p_material_id and consumption_method=v_method and is_active
 and category_code is not distinct from (case when v_method='BOM_AUTO' then v_cat end)
 and consume_department_code is not distinct from (case when v_method in('BOM_AUTO','OVERHEAD') then null else v_dep end)
 and execution_decision=(case when v_method='DIRECT_ACTUAL' then coalesce(p_execution_decision,false) else false end)
 and effective_from=coalesce(p_effective_from,current_date);
 insert into public.rr_material_consumption_mapping_v655(material_id,consumption_method,category_code,consume_department_code,execution_decision,qty_per_piece,unit,effective_from,created_by) values(p_material_id,v_method,case when v_method='BOM_AUTO' then v_cat end,case when v_method in('BOM_AUTO','OVERHEAD') then null else v_dep end,case when v_method='DIRECT_ACTUAL' then coalesce(p_execution_decision,false) else false end,case when v_method='BOM_AUTO' then p_qty_per_piece end,v_unit,coalesce(p_effective_from,current_date),auth.uid()) on conflict(material_id,consumption_method,category_code,consume_department_code,effective_from) do update set execution_decision=excluded.execution_decision,qty_per_piece=excluded.qty_per_piece,unit=excluded.unit,is_active=true,updated_at=now() returning id into v_id;
 return jsonb_build_object('ok',true,'id',v_id,'method',v_method,'unit',v_unit,'costing_head',case when v_method='OVERHEAD' then 'OVERHEAD' else null end);
end $function$
;
CREATE OR REPLACE FUNCTION public.rr_material_direct_pending_v659(p_assignment_id uuid, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a record;
begin select * into a from public.rr_upm_work_assignments_v8 where id=p_assignment_id;if not found then return jsonb_build_object('rows','[]'::jsonb);end if;
return jsonb_build_object('version','CB_COSTING_EFFECTIVE_WORKER_DIRECT_V1','rows',coalesce((select jsonb_agg(jsonb_build_object('mapping_id',x.id,'material_id',m.id,'material_name',m.material_name,'unit',m.consumption_unit,'weighted_rate',s.weighted_avg_rate_per_consumption_unit,'execution_decision',x.execution_decision,'method',x.consumption_method)) from public.rr_material_effective_mappings_v1(current_date) x join public.rr_material_master_v805 m on m.id=x.material_id left join public.rr_material_stock_v805 s on s.material_id=m.id and upper(s.data_mode)=upper(p_data_mode) where m.is_active and upper(x.consumption_method) in('DIRECT_ACTUAL','WORKER_ACTUAL') and x.effective_from<=current_date and (x.execution_decision or public.rr_upm_core_department_v9077(x.consume_department_code)=public.rr_upm_core_department_v9077(a.department_code)) and not exists(select 1 from public.rr_material_execution_consumption_v655 e where e.canonical_lot_id=a.canonical_lot_id and e.material_id=x.material_id and upper(e.data_mode)=upper(p_data_mode))),'[]'::jsonb));end $function$
;
CREATE OR REPLACE FUNCTION public.rr_material_direct_confirm_v665(p_assignment_id uuid, p_mapping_id uuid, p_consumed_qty numeric, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a record;x record;m record;ratej jsonb;v_role text;v_good numeric;v_rate numeric;v_total numeric;v_id uuid;
begin
 v_role:=upper(coalesce(public.rr_costing_user_scope_v760(null)->>'effective_role',''));if v_role not in('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN','CUTTING_MASTER','DEPARTMENT_HEAD') then raise exception 'Lineman / Manager confirmation required.';end if;if coalesce(p_consumed_qty,0)<=0 then raise exception 'Consumed Qty must be positive.';end if;
 select * into a from public.rr_upm_work_assignments_v8 where id=p_assignment_id for update;if not found then raise exception 'Assignment not found';end if;
 select * into x from public.rr_material_effective_mappings_v1(current_date) where id=p_mapping_id and is_active and upper(consumption_method) in('DIRECT_ACTUAL','WORKER_ACTUAL');if not found then raise exception 'Worker/Direct Actual mapping not found';end if;
 if not x.execution_decision and public.rr_upm_core_department_v9077(x.consume_department_code)<>public.rr_upm_core_department_v9077(a.department_code) then raise exception 'Material is not mapped to this department.';end if;
 select * into m from public.rr_material_master_v805 where id=x.material_id;ratej:=public.rr_material_weighted_rate_canonical_v662(m.id,p_data_mode);v_rate:=coalesce((ratej->>'rate_per_consumption_unit')::numeric,0);if v_rate<=0 then raise exception 'Weighted purchase rate missing for material %.',m.material_name;end if;
 v_good:=greatest(coalesce((select confirmed_qty from public.rr_upm_assignment_receipts_v9112 where assignment_id=a.id order by confirmed_at desc nulls last limit 1),0),coalesce(a.inbound_qty,0),coalesce(a.assigned_qty,0));v_total:=p_consumed_qty*v_rate;
 insert into public.rr_material_execution_consumption_v655(data_mode,canonical_lot_id,lot_no,material_id,mapping_id,assignment_id,department_code,worker_id,confirmed_by,consumed_qty,unit,weighted_rate_snapshot,total_cost,cost_per_good_piece,source_record_id) values(upper(p_data_mode),a.canonical_lot_id,a.lot_no,m.id,x.id,a.id,public.rr_upm_core_department_v9077(a.department_code),public.rr_canonical_worker_id_v264(a.worker_id),auth.uid(),p_consumed_qty,m.consumption_unit,v_rate,v_total,v_total/nullif(v_good,0),'DIRECT:'||a.canonical_lot_id||':'||m.id::text) on conflict(data_mode,canonical_lot_id,material_id) do nothing returning id into v_id;
 if v_id is null then return jsonb_build_object('ok',true,'duplicate_blocked',true,'material',m.material_name);end if;
 insert into public.rr_material_consumption_v805(material_id,source_module,source_record_id,lot_no,applicable_qty,consumption_qty,consumption_unit,base_qty_consumed,weighted_rate_per_base_unit,weighted_rate_per_consumption_unit,cost_per_good_piece,total_consumption_cost,consumption_basis,data_mode) values(m.id,'DIRECT_ACTUAL','DIRECT:'||a.canonical_lot_id||':'||m.id::text,a.lot_no,v_good,p_consumed_qty,m.consumption_unit,p_consumed_qty*coalesce(m.consumption_to_base,1),v_rate/nullif(coalesce(m.consumption_to_base,1),0),v_rate,v_total/nullif(v_good,0),v_total,'CONFIRMED_BY_'||v_role,upper(p_data_mode)) on conflict(material_id,source_module,source_record_id,data_mode) do nothing;
 return jsonb_build_object('ok',true,'version','V665_WORKER_DIRECT_CANONICAL_RATE','material',m.material_name,'consumed_qty',p_consumed_qty,'unit',m.consumption_unit,'weighted_rate',v_rate,'rate_source',ratej->>'source','total_cost',v_total,'duplicate_blocked',false);
end $function$
;
-- Old RPC names remain compatible adapters, with no independent calculation.

create or replace function public.rr_material_bom_apply_v657(p_canonical_lot_id text,p_good_pcs numeric,p_source_record_id text,p_data_mode text default 'TEST')
returns jsonb language sql security definer set search_path=''
as $function$ select public.rr_material_bom_apply_v662(p_canonical_lot_id,p_good_pcs,p_source_record_id,p_data_mode) $function$;

create or replace function public.rr_material_bom_apply_v660(p_canonical_lot_id text,p_good_pcs numeric,p_source_record_id text,p_data_mode text default 'TEST')
returns jsonb language sql security definer set search_path=''
as $function$ select public.rr_material_bom_apply_v662(p_canonical_lot_id,p_good_pcs,p_source_record_id,p_data_mode) $function$;

create or replace function public.rr_material_bom_apply_v661(p_canonical_lot_id text,p_good_pcs numeric,p_source_record_id text,p_data_mode text default 'TEST')
returns jsonb language sql security definer set search_path=''
as $function$ select public.rr_material_bom_apply_v662(p_canonical_lot_id,p_good_pcs,p_source_record_id,p_data_mode) $function$;

create or replace function public.rr_material_direct_pending_v658(p_assignment_id uuid,p_data_mode text default 'TEST')
returns jsonb language sql stable security definer set search_path=''
as $function$ select public.rr_material_direct_pending_v659(p_assignment_id,p_data_mode) $function$;

create or replace function public.rr_material_direct_confirm_v658(p_assignment_id uuid,p_mapping_id uuid,p_consumed_qty numeric,p_data_mode text default 'TEST')
returns jsonb language sql security definer set search_path=''
as $function$ select public.rr_material_direct_confirm_v665(p_assignment_id,p_mapping_id,p_consumed_qty,p_data_mode) $function$;

create or replace function public.rr_material_direct_confirm_v659(p_assignment_id uuid,p_mapping_id uuid,p_consumed_qty numeric,p_data_mode text default 'TEST')
returns jsonb language sql security definer set search_path=''
as $function$ select public.rr_material_direct_confirm_v665(p_assignment_id,p_mapping_id,p_consumed_qty,p_data_mode) $function$;
