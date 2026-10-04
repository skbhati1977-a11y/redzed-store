-- Preserve all cost arithmetic; refuse completeness when canonical BOM inputs are missing.
create or replace function public.rr_upm_product_cost_actual_v723(p_canonical_lot_id text,p_data_mode text default 'TEST')
returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare c jsonb:=public.rr_upm_product_cost_actual_v722(p_canonical_lot_id,p_data_mode);
rows jsonb; print_app boolean:=coalesce((c->'printing'->>'applicable')::boolean,false);
bom jsonb; reason text; missing jsonb;
begin
 select coalesce(jsonb_agg(case when x->>'component'='PRINT_CHEMICAL' and not print_app then x||jsonb_build_object('impact',false,'state','NOT_APPLICABLE','cost_per_pc',0,'reason','PRINTING_NOT_APPLICABLE') else x end),'[]')
 into rows from jsonb_array_elements(coalesce(c->'materials_resolved','[]')) x;
 c:=c||jsonb_build_object('version','V723_APPLICABILITY_CLEAN_OUTPUT','materials_resolved',rows,'applicability_rule','LEGACY MATERIAL LINEAGE CANNOT CLAIM IMPACT WHEN ITS DEPARTMENT IS NOT APPLICABLE');
 bom:=c->'bom_materials';
 if not coalesce((bom->>'ok')::boolean,false) then
  reason:=case when bom->'gatta_panni'->>'state'='CATEGORY_MAPPING_REQUIRED' then 'BOM_CATEGORY_MAPPING_REQUIRED' else 'BOM_PURCHASE_RATE_REQUIRED' end;
  missing:=coalesce(c->'missing','[]'::jsonb);
  if not missing @> jsonb_build_array(reason) then missing:=missing||jsonb_build_array(reason); end if;
  c:=c||jsonb_build_object('costing_complete',false,'missing',missing);
 end if;
 return c;
end $function$;

