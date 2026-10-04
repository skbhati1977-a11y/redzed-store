BEGIN;
DO $audit$
declare actor uuid;r record;a jsonb;b jsonb;gp jsonb;g numeric;p numeric;n int:=0;k int:=0;unmapped jsonb:='[]';line_count int:=0;
begin
select auth_user_id into actor from public.rr_user_profiles where upper(role_code) in('OWNER','SUPER_ADMIN') and is_active and upper(coalesce(access_status,'ACTIVE'))='ACTIVE' order by updated_at desc nulls last limit 1;
perform set_config('request.jwt.claim.sub',actor::text,true);
perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
for r in select distinct x.canonical_lot_id,x.lot_no,x.total_qty from public.rr_upm_lot_registry x join (
select 'rr_cutting_lots_v3' source_table,id::text source_id,cb_unit_id from public.rr_cutting_lots_v3
union all select 'rr_production_lots',id::text,cb_unit_id from public.rr_production_lots
) s on s.source_table=x.source_table and s.source_id=x.source_id join public.rr_cb_art_assignments ca on ca.cb_id=s.cb_unit_id loop
a:=public.rr_lot_category_canonical_v682(r.canonical_lot_id);
if not coalesce((a->>'mapped')::boolean,false) then unmapped:=unmapped||jsonb_build_array(jsonb_build_object('lot_no',r.lot_no,'art_no',a->>'art_no'));else
gp:=public.rr_bom_gatta_panni_context_v684(r.canonical_lot_id,r.total_qty);
g:=(gp->'gatta'->>'raw_cost_per_garment')::numeric;p:=(gp->'panni'->>'raw_cost_per_garment')::numeric;
if (gp->>'raw_material_per_garment')::numeric is distinct from g+p then raise exception 'BOM per piece mismatch %',r.lot_no;end if;
if (gp->'gatta'->>'lot_cost')::numeric is distinct from g*r.total_qty or (gp->'panni'->>'lot_cost')::numeric is distinct from p*r.total_qty then raise exception 'Lot quantity/rate mismatch %',r.lot_no;end if;line_count:=line_count+1;
end if;
a:=public.rr_upm_costing_context_v9300(r.canonical_lot_id,'TEST');b:=public.rr_upm_costing_panel_v760(r.canonical_lot_id);
if a is distinct from b->'costing' then raise exception 'App/chat costing mismatch %',r.canonical_lot_id;end if;n:=n+1;
end loop;
for r in select w.id from public.rr_upm_work_assignments_v8 w where exists(
select 1 from public.rr_material_effective_mappings_v1(current_date) m where m.consumption_method in('WORKER_ACTUAL','DIRECT_ACTUAL') and public.rr_upm_core_department_v9077(m.consume_department_code)=public.rr_upm_core_department_v9077(w.department_code)
) order by w.id limit 100 loop
a:=public.rr_material_direct_pending_v659(r.id,'TEST');b:=public.rr_material_direct_pending_v658(r.id,'TEST');
if a is distinct from b then raise exception 'Worker/direct pending link mismatch';end if;k:=k+1;
end loop;
perform set_config('test71.audit',jsonb_build_object('app_chat_lots',n,'bom_rate_qty_lots',line_count,'unmapped',unmapped,'worker_direct_assignments',k)::text,true);
end $audit$;
select current_setting('test71.audit')::jsonb result;
ROLLBACK;
