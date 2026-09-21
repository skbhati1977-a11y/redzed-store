-- TEST71 V607: the Material Master UI and error contract call this a
-- Super Admin action. Keep the existing creator, but align only its guard
-- with the effective OWNER/SUPER_ADMIN authority already used by Unit Master.
begin;

create or replace function public.rr_material_create_v805_31(
  p_type_code text,
  p_material_name text,
  p_material_no text,
  p_purchase_unit text,
  p_stock_unit text,
  p_purchase_to_stock numeric,
  p_consumption_unit text,
  p_consumption_to_stock numeric,
  p_consumption_basis text,
  p_consumption_per_good_piece numeric,
  p_auto_consumption_event text,
  p_preferred_supplier_ledger_id uuid,
  p_applicable_to jsonb
) returns uuid
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_type text:=upper(trim(coalesce(p_type_code,'')));
  v_tid uuid;
  v_id uuid;
  v_name text:=nullif(trim(p_material_name),'');
  v_norm text;
begin
  perform public.rr_unit_master_assert_authority_v606();
  if v_type in('REGULAR_CLOTH','MATCHING_CLOTH','STICKER','METAL_ID') then
    raise exception '% is source-managed; duplicate generic creation blocked.',replace(v_type,'_',' ');
  end if;
  if v_name is null then raise exception 'Material Name required.'; end if;
  if coalesce(p_purchase_to_stock,0)<=0 then raise exception 'Purchase to Stock conversion must be greater than zero.'; end if;
  if coalesce(p_consumption_to_stock,0)<=0 then raise exception 'Consumption to Stock conversion must be greater than zero.'; end if;

  select id into v_tid from public.rr_material_types_v805 where type_code=v_type and is_active limit 1;
  if v_tid is null then raise exception 'Material Type not found.'; end if;
  v_norm:=public.rr_name_normalize_v805(v_name);
  select id into v_id from public.rr_material_master_v805
  where material_type_id=v_tid and normalized_name=v_norm and is_active limit 1;
  if v_id is not null then return v_id; end if;

  insert into public.rr_material_master_v805(
    material_no,material_type_id,material_name,normalized_name,purchase_unit,base_stock_unit,consumption_unit,
    purchase_to_base,consumption_to_base,estimated_consumption_per_good_piece,consumption_basis,applicable_to,is_active,
    consumption_per_good_piece,auto_consumption_enabled,auto_consumption_event,preferred_supplier_ledger_id,created_by,approved_by
  ) values(
    nullif(trim(p_material_no),''),v_tid,v_name,v_norm,
    public.rr_unit_require_code_v606(p_purchase_unit),
    public.rr_unit_require_code_v606(p_stock_unit),
    public.rr_unit_require_code_v606(p_consumption_unit),
    p_purchase_to_stock,p_consumption_to_stock,greatest(coalesce(p_consumption_per_good_piece,0),0),
    upper(coalesce(nullif(trim(p_consumption_basis),''),'MANUAL')),coalesce(p_applicable_to,'{}'::jsonb),true,
    nullif(p_consumption_per_good_piece,0),coalesce(nullif(trim(p_auto_consumption_event),'') is not null,false),
    nullif(upper(trim(p_auto_consumption_event)),''),p_preferred_supplier_ledger_id,auth.uid(),auth.uid()
  ) returning id into v_id;
  return v_id;
end
$function$;

revoke all on function public.rr_material_create_v805_31(text,text,text,text,text,numeric,text,numeric,text,numeric,text,uuid,jsonb) from public,anon;
grant execute on function public.rr_material_create_v805_31(text,text,text,text,text,numeric,text,numeric,text,numeric,text,uuid,jsonb) to authenticated,service_role;

commit;
