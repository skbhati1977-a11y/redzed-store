begin;

-- REAL FACTORY V805.31
-- Core mapped search remains rr_material_source_search_v805_1 unchanged.

create table if not exists public.rr_material_source_supplier_map_v805_31(
  id uuid primary key default gen_random_uuid(),
  source_type text not null,
  source_id text not null,
  supplier_ledger_id uuid not null references public.rr_ledgers_v805(id),
  updated_by uuid,
  updated_at timestamptz not null default now(),
  unique(source_type,source_id)
);

create or replace function public.rr_material_source_supplier_get_v805_31(p_source_type text,p_source_id text)
returns uuid language sql stable security definer set search_path=public as $$
  select supplier_ledger_id from public.rr_material_source_supplier_map_v805_31
  where source_type=upper(trim(coalesce(p_source_type,''))) and source_id=coalesce(p_source_id,'') limit 1
$$;

create or replace function public.rr_material_source_supplier_set_v805_31(
  p_source_type text,p_source_id text,p_supplier_ledger_id uuid
) returns uuid language plpgsql security definer set search_path=public as $$
begin
  if p_supplier_ledger_id is null or nullif(trim(p_source_type),'') is null or nullif(trim(p_source_id),'') is null then return p_supplier_ledger_id; end if;
  insert into public.rr_material_source_supplier_map_v805_31(source_type,source_id,supplier_ledger_id,updated_by)
  values(upper(trim(p_source_type)),p_source_id,p_supplier_ledger_id,auth.uid())
  on conflict(source_type,source_id) do update set supplier_ledger_id=excluded.supplier_ledger_id,updated_by=auth.uid(),updated_at=now();
  return p_supplier_ledger_id;
end $$;

create or replace function public.rr_material_supplier_create_v805_31(p_supplier_name text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_name text:=nullif(trim(p_supplier_name),''); v_norm text; v_cat uuid; v_id uuid;
begin
  if not public.rr_acct_is_super_v805() then raise exception 'Super Admin permission required.'; end if;
  if v_name is null then raise exception 'Supplier name required.'; end if;
  v_norm:=public.rr_name_normalize_v805(v_name);
  select id into v_id from public.rr_ledgers_v805 where normalized_name=v_norm and is_active limit 1;
  if v_id is not null then return v_id; end if;
  select id into v_cat from public.rr_account_categories_v805 where category_code='SUPPLIER_PAYABLE' and is_active limit 1;
  if v_cat is null then raise exception 'SUPPLIER_PAYABLE category not found.'; end if;
  insert into public.rr_ledgers_v805(ledger_name,normalized_name,category_id,ledger_kind,is_active,approved_by,created_by)
  values(v_name,v_norm,v_cat,'SUPPLIER',true,auth.uid(),auth.uid()) returning id into v_id;
  return v_id;
end $$;

create or replace function public.rr_material_type_create_v805_31(
  p_type_name text,p_type_code text,p_default_purchase_unit text,p_default_consumption_unit text
) returns text language plpgsql security definer set search_path=public as $$
declare v_name text:=nullif(trim(p_type_name),''); v_code text;
begin
  if not public.rr_acct_is_super_v805() then raise exception 'Super Admin permission required.'; end if;
  if v_name is null then raise exception 'Type name required.'; end if;
  v_code:=upper(coalesce(nullif(trim(p_type_code),''),regexp_replace(v_name,'[^A-Za-z0-9]+','_','g')));
  v_code:=trim(both '_' from v_code);
  if exists(select 1 from public.rr_material_types_v805 where type_code=v_code or lower(type_name)=lower(v_name)) then
    select type_code into v_code from public.rr_material_types_v805 where type_code=v_code or lower(type_name)=lower(v_name) limit 1;
    return v_code;
  end if;
  insert into public.rr_material_types_v805(type_code,type_name,material_category,source_master,default_purchase_unit,default_consumption_unit,is_active)
  values(v_code,v_name,'OTHER',null,upper(coalesce(nullif(trim(p_default_purchase_unit),''),'PCS')),upper(coalesce(nullif(trim(p_default_consumption_unit),''),'PCS')),true);
  return v_code;
end $$;

create or replace function public.rr_material_create_v805_31(
  p_type_code text,p_material_name text,p_material_no text,
  p_purchase_unit text,p_stock_unit text,p_purchase_to_stock numeric,
  p_consumption_unit text,p_consumption_to_stock numeric,
  p_consumption_basis text,p_consumption_per_good_piece numeric,
  p_auto_consumption_event text,p_preferred_supplier_ledger_id uuid,p_applicable_to jsonb
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_type text:=upper(trim(coalesce(p_type_code,''))); v_tid uuid; v_id uuid; v_name text:=nullif(trim(p_material_name),''); v_norm text;
begin
  if not public.rr_acct_is_super_v805() then raise exception 'Super Admin permission required.'; end if;
  if v_type in('REGULAR_CLOTH','MATCHING_CLOTH','STICKER','METAL_ID') then raise exception '% is source-managed; duplicate generic creation blocked.',replace(v_type,'_',' '); end if;
  if v_name is null then raise exception 'Material Name required.'; end if;
  if coalesce(p_purchase_to_stock,0)<=0 then raise exception 'Purchase to Stock conversion must be greater than zero.'; end if;
  if coalesce(p_consumption_to_stock,0)<=0 then raise exception 'Consumption to Stock conversion must be greater than zero.'; end if;
  select id into v_tid from public.rr_material_types_v805 where type_code=v_type and is_active limit 1;
  if v_tid is null then raise exception 'Material Type not found.'; end if;
  v_norm:=public.rr_name_normalize_v805(v_name);
  select id into v_id from public.rr_material_master_v805 where material_type_id=v_tid and normalized_name=v_norm and is_active limit 1;
  if v_id is not null then return v_id; end if;
  insert into public.rr_material_master_v805(
    material_no,material_type_id,material_name,normalized_name,purchase_unit,base_stock_unit,consumption_unit,
    purchase_to_base,consumption_to_base,estimated_consumption_per_good_piece,consumption_basis,applicable_to,is_active,
    consumption_per_good_piece,auto_consumption_enabled,auto_consumption_event,preferred_supplier_ledger_id,created_by,approved_by
  ) values(
    nullif(trim(p_material_no),''),v_tid,v_name,v_norm,upper(trim(p_purchase_unit)),upper(trim(p_stock_unit)),upper(trim(p_consumption_unit)),
    p_purchase_to_stock,p_consumption_to_stock,greatest(coalesce(p_consumption_per_good_piece,0),0),
    upper(coalesce(nullif(trim(p_consumption_basis),''),'MANUAL')),coalesce(p_applicable_to,'{}'::jsonb),true,
    nullif(p_consumption_per_good_piece,0),coalesce(nullif(trim(p_auto_consumption_event),'') is not null,false),nullif(upper(trim(p_auto_consumption_event)),''),
    p_preferred_supplier_ledger_id,auth.uid(),auth.uid()
  ) returning id into v_id;
  return v_id;
end $$;

create or replace function public.rr_material_post_purchase_auto_v805_31(
  p_supplier_ledger_id uuid,p_material_id uuid,p_purchase_ledger_id uuid,
  p_purchase_qty numeric,p_rate numeric,p_bill_no text,p_bill_date date,
  p_gst_amount numeric,p_payment_status text,p_paid_amount numeric,p_cash_bank_ledger_id uuid,p_data_mode text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare m public.rr_material_master_v805%rowtype; v_stock_qty numeric; v_consumption_qty numeric; v_result jsonb;
begin
  select * into m from public.rr_material_master_v805 where id=p_material_id and is_active;
  if not found then raise exception 'Active mapped Material not found.'; end if;
  if coalesce(p_purchase_qty,0)<=0 then raise exception 'Purchase Qty required.'; end if;
  if coalesce(m.purchase_to_base,0)<=0 then raise exception 'Saved Purchase to Stock conversion missing.'; end if;
  if coalesce(m.consumption_to_base,0)<=0 then raise exception 'Saved Consumption to Stock conversion missing.'; end if;
  v_stock_qty:=round(p_purchase_qty*m.purchase_to_base,6);
  v_consumption_qty:=round(v_stock_qty/m.consumption_to_base,6);
  select public.rr_material_post_purchase_v805_1(
    p_supplier_ledger_id,p_material_id,p_purchase_ledger_id,p_purchase_qty,m.purchase_unit,
    v_stock_qty,m.base_stock_unit,v_consumption_qty,m.consumption_unit,p_rate,p_bill_no,coalesce(p_bill_date,current_date),
    coalesce(p_gst_amount,0),coalesce(p_payment_status,'CREDIT'),coalesce(p_paid_amount,0),p_cash_bank_ledger_id,upper(coalesce(p_data_mode,'TEST'))
  ) into v_result;
  if p_supplier_ledger_id is not null and m.preferred_supplier_ledger_id is null then
    update public.rr_material_master_v805 set preferred_supplier_ledger_id=p_supplier_ledger_id,updated_at=now() where id=m.id;
  end if;
  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object('backend_stock_qty',v_stock_qty,'backend_stock_unit',m.base_stock_unit,'backend_consumption_qty',v_consumption_qty,'backend_consumption_unit',m.consumption_unit);
end $$;

do $$
declare k uuid; v uuid; r uuid; s uuid;
begin
  k:=public.rr_material_supplier_create_v805_31('Krishna Material');
  v:=public.rr_material_supplier_create_v805_31('Vinayak Material');
  r:=public.rr_material_supplier_create_v805_31('Rishabh Material');
  s:=public.rr_material_supplier_create_v805_31('Sunil Supplier');

  update public.rr_material_master_v805 m set preferred_supplier_ledger_id=r,updated_at=now()
  from public.rr_material_types_v805 t
  where t.id=m.material_type_id and t.type_code in('GATTA','PANNI','PASTING_ROLL','KANDHI_TAPE') and m.preferred_supplier_ledger_id is null;

  insert into public.rr_material_source_supplier_map_v805_31(source_type,source_id,supplier_ledger_id)
  select 'STICKER_MASTER_V803',id::text,k from public.rr_sticker_master_v803 where is_active
  on conflict(source_type,source_id) do nothing;

  insert into public.rr_material_source_supplier_map_v805_31(source_type,source_id,supplier_ledger_id)
  select 'METAL_ID_MASTER_V803',id::text,v from public.rr_metal_id_master_v803 where is_active
  on conflict(source_type,source_id) do nothing;
end $$;

grant execute on function public.rr_material_source_supplier_get_v805_31(text,text) to authenticated;
grant execute on function public.rr_material_source_supplier_set_v805_31(text,text,uuid) to authenticated;
grant execute on function public.rr_material_supplier_create_v805_31(text) to authenticated;
grant execute on function public.rr_material_type_create_v805_31(text,text,text,text) to authenticated;
grant execute on function public.rr_material_create_v805_31(text,text,text,text,text,numeric,text,numeric,text,numeric,text,uuid,jsonb) to authenticated;
grant execute on function public.rr_material_post_purchase_auto_v805_31(uuid,uuid,uuid,numeric,numeric,text,date,numeric,text,numeric,uuid,text) to authenticated;

notify pgrst,'reload schema';
commit;
