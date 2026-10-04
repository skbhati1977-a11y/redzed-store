-- TEST71: CB Appx Sheet keeps the original Appx PCS beside actual Cutting PCS.
-- Also keeps root Set physical weights aligned with their assigned Regular Cloth rolls.

alter table public.rr_cb_derived_requirement_v1
  add column if not exists appx_pcs numeric,
  add column if not exists cutting_pcs numeric;

create or replace function public.rr_cb_actual_cutting_pcs_v1(p_cb_unit_id uuid)
returns numeric
language sql
stable
security definer
set search_path to 'public'
as $function$
  with raw as (
    select coalesce(nullif(trim(lot_no),''),id::text) lot_key,
           greatest(coalesce(actual_pcs,0),0)::numeric actual_pcs
    from public.rr_cutting_lots_v3
    where cb_unit_id=p_cb_unit_id
      and upper(coalesce(status,'')) not in('CANCELLED','CANCELED')
      and coalesce(actual_pcs,0)>0
    union all
    select coalesce(nullif(trim(lot_no),''),id::text) lot_key,
           greatest(coalesce(actual_pcs,0),0)::numeric actual_pcs
    from public.rr_production_lots
    where cb_unit_id=p_cb_unit_id
      and upper(coalesce(status,'')) not in('CANCELLED','CANCELED')
      and coalesce(actual_pcs,0)>0
  ),
  dedup as (
    select lot_key,max(actual_pcs) actual_pcs
    from raw
    group by lot_key
  )
  select coalesce(sum(actual_pcs),0)::numeric from dedup
$function$;

revoke all on function public.rr_cb_actual_cutting_pcs_v1(uuid) from public, anon, authenticated;

create or replace function public.rr_cb_sync_unit_physical_weights_v1(p_cb_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_roll_count integer:=0;
  v_assigned_count integer:=0;
  v_rate numeric:=0;
  v_updated integer:=0;
begin
  select count(*),
         count(r.division_id),
         max(coalesce(nullif(e.original_rate,0),e.rate,0))
    into v_roll_count,v_assigned_count,v_rate
  from public.rr_cb_purchase_rolls r
  join public.rr_cb_purchase_entries e on e.id=r.purchase_entry_id
  join public.rr_material_categories mc on mc.id=e.material_category_id
  where e.cb_id=p_cb_id
    and lower(mc.category_code)='regular-cloth'
    and coalesce(r.operation_status,'ACTIVE') not in('RETURNED','CANCELLED','VOID')
    and coalesce(r.quantity,0)>0;

  if v_roll_count=0 or v_assigned_count<>v_roll_count then
    return jsonb_build_object(
      'ok',false,
      'reason',case when v_roll_count=0 then 'NO_ACTIVE_ROLLS' else 'ROLL_DIVISION_PENDING' end,
      'roll_count',v_roll_count,
      'assigned_count',v_assigned_count
    );
  end if;

  perform set_config('redzed.allow_locked_cb_balance_update','on',true);

  with roll_by_root as (
    select coalesce(du.parent_unit_id,du.id) root_id,
           round(sum(r.quantity),3) qty
    from public.rr_cb_purchase_rolls r
    join public.rr_cb_purchase_entries e on e.id=r.purchase_entry_id
    join public.rr_material_categories mc on mc.id=e.material_category_id
    join public.rr_cb_units du on du.id=r.division_id and du.purchase_id=p_cb_id
    where e.cb_id=p_cb_id
      and lower(mc.category_code)='regular-cloth'
      and coalesce(r.operation_status,'ACTIVE') not in('RETURNED','CANCELLED','VOID')
      and coalesce(r.quantity,0)>0
    group by coalesce(du.parent_unit_id,du.id)
  ),
  src as (
    select u.id,
           coalesce(r.qty,0)::numeric qty
    from public.rr_cb_units u
    left join roll_by_root r on r.root_id=u.id
    where u.purchase_id=p_cb_id
      and u.parent_unit_id is null
  )
  update public.rr_cb_units u
     set divided_weight=src.qty,
         divided_amount=round(src.qty*coalesce(v_rate,0),2),
         updated_at=now()
    from src
   where u.id=src.id
     and (
       u.divided_weight is distinct from src.qty
       or u.divided_amount is distinct from round(src.qty*coalesce(v_rate,0),2)
     );

  get diagnostics v_updated=row_count;

  perform set_config('redzed.allow_locked_cb_balance_update','off',true);

  return jsonb_build_object(
    'ok',true,
    'updated_units',v_updated,
    'roll_count',v_roll_count,
    'rate',v_rate
  );
exception when others then
  perform set_config('redzed.allow_locked_cb_balance_update','off',true);
  raise;
end
$function$;

revoke all on function public.rr_cb_sync_unit_physical_weights_v1(uuid) from public, anon, authenticated;

create or replace function public.rr_cb_roll_sync_units_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_entry_id uuid;
  v_cb_id uuid;
  v_code text;
begin
  v_entry_id:=case when tg_op='DELETE' then old.purchase_entry_id else new.purchase_entry_id end;

  select e.cb_id,lower(coalesce(mc.category_code,''))
    into v_cb_id,v_code
  from public.rr_cb_purchase_entries e
  left join public.rr_material_categories mc on mc.id=e.material_category_id
  where e.id=v_entry_id;

  if v_cb_id is not null and v_code='regular-cloth' then
    perform public.rr_cb_sync_unit_physical_weights_v1(v_cb_id);
  end if;

  return case when tg_op='DELETE' then old else new end;
end
$function$;

revoke all on function public.rr_cb_roll_sync_units_trigger_v1() from public, anon, authenticated;

drop trigger if exists rr_cb_roll_sync_units_v1 on public.rr_cb_purchase_rolls;
create trigger rr_cb_roll_sync_units_v1
after insert or update or delete on public.rr_cb_purchase_rolls
for each row execute function public.rr_cb_roll_sync_units_trigger_v1();

create or replace function public.rr_cb_upsert_derived_requirement_v1(
  p_cb_id uuid,
  p_cb_unit_id uuid,
  p_root_set_no integer,
  p_profile_label text,
  p_requirement_type text,
  p_source_id uuid,
  p_item_no text,
  p_item_name text,
  p_unit text,
  p_fulfilment_method text,
  p_basis text,
  p_basis_pcs numeric,
  p_qty_per_piece numeric,
  p_required_qty numeric
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  ex public.rr_cb_derived_requirement_v1%rowtype;
  supplier jsonb;
  sid uuid;
  sname text;
  smobile text;
  changed boolean:=false;
  new_rev integer:=1;
  new_status text:='READY';
  sent_exists boolean:=false;
  out_id uuid;
  v_py jsonb;
  v_appx_pcs numeric:=0;
  v_cutting_pcs numeric:=0;
  v_appx_store numeric:=0;
begin
  select * into ex
  from public.rr_cb_derived_requirement_v1
  where cb_unit_id=p_cb_unit_id
    and requirement_type=upper(p_requirement_type)
    and source_id=p_source_id
  for update;

  v_py:=public.rr_cb_profile_yield_v1(p_cb_unit_id);
  v_appx_pcs:=coalesce((v_py->>'estimated_pcs')::numeric,0);
  v_cutting_pcs:=coalesce(public.rr_cb_actual_cutting_pcs_v1(p_cb_unit_id),0);

  supplier:=public.rr_cb_auto_supplier_v1(p_cb_id,upper(p_requirement_type),p_source_id);
  sid:=nullif(supplier->>'supplier_ledger_id','')::uuid;
  sname:=nullif(supplier->>'supplier_name','');
  smobile:=nullif(supplier->>'supplier_mobile','');

  if ex.id is not null then
    changed:=abs(coalesce(ex.required_qty,0)-coalesce(p_required_qty,0))>0.0001
             or coalesce(ex.basis,'')<>coalesce(p_basis,'');

    new_rev:=case when changed then ex.revision_no+1 else ex.revision_no end;

    select exists(
      select 1 from public.rr_cb_requirement_send_log_v1 l
      where l.cb_id=p_cb_id
        and l.requirement_type=upper(p_requirement_type)
        and l.source_id=p_source_id
    ) into sent_exists;

    new_status:=case
      when ex.status='FULFILLED' and not changed then 'FULFILLED'
      when changed and sent_exists then 'REVISED'
      when changed then 'READY'
      else ex.status
    end;

    v_appx_store:=case
      when coalesce(ex.cutting_pcs,0)>0 or v_cutting_pcs>0
        then coalesce(nullif(ex.appx_pcs,0),v_appx_pcs)
      else v_appx_pcs
    end;

    update public.rr_cb_derived_requirement_v1
    set root_set_no=p_root_set_no,
        profile_label=p_profile_label,
        item_no=p_item_no,
        item_name=p_item_name,
        unit=upper(coalesce(p_unit,'PCS')),
        fulfilment_method=upper(coalesce(p_fulfilment_method,'PURCHASE')),
        basis=upper(p_basis),
        basis_pcs=coalesce(p_basis_pcs,0),
        appx_pcs=v_appx_store,
        cutting_pcs=nullif(v_cutting_pcs,0),
        qty_per_piece=coalesce(p_qty_per_piece,1),
        required_qty=coalesce(p_required_qty,0),
        revision_no=new_rev,
        status=new_status,
        supplier_ledger_id=case when ex.supplier_override then ex.supplier_ledger_id else coalesce(sid,ex.supplier_ledger_id) end,
        supplier_name=case when ex.supplier_override then ex.supplier_name else coalesce(sname,ex.supplier_name) end,
        supplier_mobile=case when ex.supplier_override then ex.supplier_mobile else coalesce(smobile,ex.supplier_mobile) end,
        active=true,
        updated_at=now()
    where id=ex.id
    returning id into out_id;
  else
    insert into public.rr_cb_derived_requirement_v1(
      cb_id,cb_unit_id,root_set_no,profile_label,requirement_type,source_id,
      item_no,item_name,unit,fulfilment_method,basis,basis_pcs,appx_pcs,cutting_pcs,
      qty_per_piece,required_qty,revision_no,status,
      supplier_ledger_id,supplier_name,supplier_mobile,active
    ) values(
      p_cb_id,p_cb_unit_id,p_root_set_no,p_profile_label,upper(p_requirement_type),p_source_id,
      p_item_no,p_item_name,upper(coalesce(p_unit,'PCS')),upper(coalesce(p_fulfilment_method,'PURCHASE')),
      upper(p_basis),coalesce(p_basis_pcs,0),v_appx_pcs,nullif(v_cutting_pcs,0),
      coalesce(p_qty_per_piece,1),coalesce(p_required_qty,0),
      1,'READY',sid,sname,smobile,true
    ) returning id into out_id;
  end if;

  return out_id;
end
$function$;

create or replace function public.rr_cb_refresh_derived_requirements_core_v1(p_cb_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  u record;
  mat record;
  s record;
  m record;
  am record;
  py jsonb;
  basis_pcs numeric;
  basis text;
  gpp numeric;
  rule_unit text;
  garment_key text;
  material_id uuid;
  fulfil text;
  req_count integer:=0;
  entry_id uuid;
  allowed uuid[];
  set_nos int[];
  total_qty numeric;
  auto_supplier jsonb;
begin
  if not exists(select 1 from public.rr_fabric_purchases where id=p_cb_id) then
    raise exception 'CB not found.';
  end if;

  update public.rr_cb_derived_requirement_v1
  set active=false,updated_at=now()
  where cb_id=p_cb_id and active;

  for u in
    select cu.id,
           coalesce(parent.division_index,cu.division_index) root_set_no,
           public.rr_cb_profile_label_v1(cu.id) profile_label,
           sr.art_category_id,
           ca.id assignment_id,
           ca.art_id
    from public.rr_cb_units cu
    left join public.rr_cb_units parent on parent.id=cu.parent_unit_id
    left join public.rr_cb_set_requirement_v1 sr on sr.cb_unit_id=cu.id
    left join public.rr_cb_art_assignments ca on ca.cb_id=cu.id
    where cu.purchase_id=p_cb_id
      and coalesce(cu.is_final,true)
    order by coalesce(parent.division_index,cu.division_index),coalesce(cu.batch_index,0),cu.division_index
  loop
    if u.assignment_id is null or u.art_id is null then
      continue;
    end if;

    select a.id,a.art_no,a.art_category_id,ac.category_code,ac.category_name
    into am
    from public.rr_art_master a
    left join public.rr_art_categories ac on ac.id=a.art_category_id
    where a.id=u.art_id;

    basis_pcs:=coalesce(public.rr_cb_actual_cutting_pcs_v1(u.id),0);

    if basis_pcs>0 then
      basis:='CUTTING_ACTUAL';
    else
      py:=public.rr_cb_profile_yield_v1(u.id);
      basis_pcs:=coalesce((py->>'estimated_pcs')::numeric,0);
      basis:='YIELD';
    end if;

    garment_key:=case
      when lower(coalesce(am.category_code,''))='flat-polo' then 'FLAT COLLAR'
      when lower(coalesce(am.category_code,'')) in('crew-neck','drop-shoulder') then 'ROUND NECK'
      else upper(coalesce(am.category_name,am.category_code,''))
    end;

    for mat in
      select distinct mc.id,mc.category_code,mc.category_name,coalesce(mc.unit,'KG') unit
      from public.rr_material_art_category_rule_v1 r
      join public.rr_material_categories mc on mc.id=r.material_category_id
      where r.is_active
        and r.art_category_id=am.art_category_id
        and mc.is_active
        and lower(mc.category_code) in('collar-cuff','rib')
    loop
      select cr.grams_per_piece,coalesce(nullif(cr.material_category_code,''),mat.category_code)
      into gpp,rule_unit
      from public.rr_material_consumption_rule_v1 cr
      where cr.is_active
        and lower(replace(cr.material_category_code,'&',''))=lower(replace(mat.category_code,'&',''))
        and upper(trim(cr.garment_category))=upper(trim(garment_key))
      limit 1;

      gpp:=coalesce(gpp,0);

      perform public.rr_cb_upsert_derived_requirement_v1(
        p_cb_id,u.id,u.root_set_no,u.profile_label,'MATERIAL',mat.id,
        upper(mat.category_code),mat.category_name,coalesce(mat.unit,'KG'),'PURCHASE',
        basis,basis_pcs,gpp,round((basis_pcs*gpp/1000.0)::numeric,3)
      );
      req_count:=req_count+1;
    end loop;

    for s in
      select sm.id master_id,sm.sticker_no item_no,
             coalesce(sm.sticker_name,sm.sticker_no) item_name
      from public.rr_cb_sticker_assignments a
      join public.rr_art_sticker_instructions i on i.id=a.sticker_instruction_id and i.is_active
      join public.rr_sticker_master_v803 sm on sm.id=i.sticker_master_id and sm.is_active
      where a.assignment_id=u.assignment_id
    loop
      select mm.id,
             coalesce(
               (select max(cm.qty_per_piece) from public.rr_material_consumption_mapping_v655 cm
                where cm.material_id=mm.id and cm.is_active and cm.consumption_method='BOM_AUTO'),
               mm.consumption_per_good_piece,
               mm.estimated_consumption_per_good_piece,
               1
             )
      into material_id,gpp
      from public.rr_material_master_v805 mm
      where mm.external_master_type='STICKER'
        and mm.external_master_id=s.master_id::text
        and mm.is_active
      limit 1;

      select coalesce(p.fulfilment_method,'IN_HOUSE')
      into fulfil
      from public.rr_accessory_execution_policy_v681 p
      where p.master_type='STICKER' and p.master_id=s.master_id;

      fulfil:=coalesce(fulfil,'IN_HOUSE');

      perform public.rr_cb_upsert_derived_requirement_v1(
        p_cb_id,u.id,u.root_set_no,u.profile_label,'STICKER',s.master_id,
        s.item_no,s.item_name,'PCS',
        case when upper(fulfil)='OUTSOURCE' then 'PURCHASE' else 'MAKING' end,
        basis,basis_pcs,coalesce(gpp,1),round((basis_pcs*coalesce(gpp,1))::numeric,0)
      );
      req_count:=req_count+1;
    end loop;

    for m in
      select mm.id master_id,mm.metal_id_no item_no,
             coalesce(mm.metal_id_name,mm.metal_id_no) item_name
      from public.rr_cb_metal_id_assignments_v801 a
      join public.rr_art_metal_id_instructions_v801 i on i.id=a.metal_id_instruction_id and i.is_active
      join public.rr_metal_id_master_v803 mm on mm.id=i.metal_id_master_id and mm.is_active
      where a.assignment_id=u.assignment_id
    loop
      select mm.id,
             coalesce(
               (select max(cm.qty_per_piece) from public.rr_material_consumption_mapping_v655 cm
                where cm.material_id=mm.id and cm.is_active and cm.consumption_method='BOM_AUTO'),
               mm.consumption_per_good_piece,
               mm.estimated_consumption_per_good_piece,
               1
             )
      into material_id,gpp
      from public.rr_material_master_v805 mm
      where mm.external_master_type='METAL_ID'
        and mm.external_master_id=m.master_id::text
        and mm.is_active
      limit 1;

      select coalesce(p.fulfilment_method,'OUTSOURCE')
      into fulfil
      from public.rr_accessory_execution_policy_v681 p
      where p.master_type='METAL_ID' and p.master_id=m.master_id;

      fulfil:=coalesce(fulfil,'OUTSOURCE');

      perform public.rr_cb_upsert_derived_requirement_v1(
        p_cb_id,u.id,u.root_set_no,u.profile_label,'METAL_ID',m.master_id,
        m.item_no,m.item_name,'PCS',
        case when upper(fulfil)='IN_HOUSE' then 'MAKING' else 'PURCHASE' end,
        basis,basis_pcs,coalesce(gpp,1),round((basis_pcs*coalesce(gpp,1))::numeric,0)
      );
      req_count:=req_count+1;
    end loop;
  end loop;

  update public.rr_cb_purchase_entries e
  set requirement_state='NOT REQUIRED',quantity=0,updated_at=now()
  where e.cb_id=p_cb_id
    and e.entry_notes='AUTO ART COMBO MATERIAL'
    and not exists(
      select 1 from public.rr_cb_derived_requirement_v1 r
      where r.cb_id=p_cb_id and r.active and r.requirement_type='MATERIAL'
        and r.source_id=e.material_category_id and r.required_qty>0
    )
    and e.requirement_state='DUE';

  for mat in
    select r.source_id material_category_id,
           max(r.item_name) item_name,
           max(r.unit) unit,
           sum(r.required_qty) total_qty,
           array_agg(distinct r.root_set_no order by r.root_set_no) set_nos
    from public.rr_cb_derived_requirement_v1 r
    where r.cb_id=p_cb_id and r.active and r.requirement_type='MATERIAL'
      and r.required_qty>0
    group by r.source_id
  loop
    total_qty:=mat.total_qty;
    set_nos:=mat.set_nos;

    select id into entry_id
    from public.rr_cb_purchase_entries
    where cb_id=p_cb_id and material_category_id=mat.material_category_id
    order by case when entry_notes='AUTO ART COMBO MATERIAL' then 0 else 1 end,created_at
    limit 1;

    auto_supplier:=public.rr_cb_auto_supplier_v1(p_cb_id,'MATERIAL',mat.material_category_id);

    select array_agg(r.art_category_id order by r.priority)
    into allowed
    from public.rr_material_art_category_rule_v1 r
    where r.material_category_id=mat.material_category_id and r.is_active;

    if entry_id is null then
      insert into public.rr_cb_purchase_entries(
        cb_id,vendor_name,material_category_id,quantity,fabric_name,allocation_scope,
        entry_notes,entry_kind,requirement_state,unit,cutting_blocking,allowed_art_category_ids
      ) values(
        p_cb_id,nullif(auto_supplier->>'supplier_name',''),mat.material_category_id,total_qty,
        mat.item_name,'selected','AUTO ART COMBO MATERIAL','PURCHASE','DUE',
        coalesce(mat.unit,'KG'),false,coalesce(allowed,'{}'::uuid[])
      ) returning id into entry_id;
    else
      update public.rr_cb_purchase_entries
      set quantity=case when entry_notes='AUTO ART COMBO MATERIAL' and requirement_state<>'CONFIRMED' then total_qty else quantity end,
          vendor_name=coalesce(vendor_name,nullif(auto_supplier->>'supplier_name','')),
          fabric_name=coalesce(fabric_name,mat.item_name),
          unit=coalesce(unit,mat.unit),
          allowed_art_category_ids=coalesce(allowed,allowed_art_category_ids),
          requirement_state=case when requirement_state='NOT REQUIRED' then 'DUE' else requirement_state end,
          allocation_scope='selected',
          updated_at=now()
      where id=entry_id;
    end if;

    delete from public.rr_cb_material_allocations where purchase_entry_id=entry_id;
    delete from public.rr_cb_material_usage_v1 where purchase_entry_id=entry_id;

    insert into public.rr_cb_material_allocations(
      purchase_entry_id,division_id,material_category_id,allowed_art_category_ids
    )
    select distinct entry_id,r.cb_unit_id,mat.material_category_id,coalesce(allowed,'{}'::uuid[])
    from public.rr_cb_derived_requirement_v1 r
    where r.cb_id=p_cb_id and r.active and r.requirement_type='MATERIAL'
      and r.source_id=mat.material_category_id and r.required_qty>0;
  end loop;

  return jsonb_build_object('ok',true,'cb_id',p_cb_id,'active_requirements',req_count);
end
$function$;

create or replace function public.rr_cb_requirement_context_v1(p_cb_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
with active as (
  select r.*
  from public.rr_cb_derived_requirement_v1 r
  where r.cb_id=p_cb_id and r.active and r.required_qty>0
),
groups as (
  select
    r.requirement_type,
    r.source_id,
    case r.requirement_type
      when 'MATERIAL' then 'MATERIAL'
      when 'STICKER' then 'STICKER'
      else 'METAL ID'
    end requirement_label,
    max(r.item_no) item_no,
    max(r.item_name) item_name,
    max(r.unit) unit,
    max(r.fulfilment_method) fulfilment_method,
    max(r.revision_no) revision_no,
    max(coalesce(r.last_sent_revision,0)) last_sent_revision,
    case when bool_or(r.basis='CUTTING_ACTUAL') then 'CUTTING_ACTUAL' else 'YIELD' end basis,
    sum(r.basis_pcs) basis_pcs,
    sum(coalesce(r.appx_pcs,case when r.basis='YIELD' then r.basis_pcs else 0 end)) appx_pcs,
    sum(coalesce(r.cutting_pcs,case when r.basis='CUTTING_ACTUAL' then r.basis_pcs else 0 end)) cutting_pcs,
    sum(r.required_qty) required_qty,
    min(r.supplier_ledger_id::text)::uuid supplier_ledger_id,
    max(r.supplier_name) supplier_name,
    max(r.supplier_mobile) supplier_mobile,
    array_agg(distinct r.profile_label order by r.profile_label) profile_labels,
    max(r.status) status,
    (
      select count(*)
      from public.rr_cb_requirement_send_log_v1 l
      where l.cb_id=p_cb_id
        and l.requirement_type=r.requirement_type
        and l.source_id=r.source_id
    ) send_count
  from active r
  group by r.requirement_type,r.source_id
),
supplier_rows as (
  select distinct
    m.supplier_ledger_id ledger_id,
    coalesce(l.ledger_name,s.supplier_name,'Supplier') name,
    coalesce(nullif(l.mobile,''),s.mobile) mobile
  from public.rr_supplier_accounts_map_v9763 m
  left join public.rr_ledgers_v805 l on l.id=m.supplier_ledger_id
  left join public.rr_suppliers s on s.id=m.supplier_id
  where m.is_active
),
colour_rows as (
  select col_no colour_no,colour_name,image_url thumbnail_url
  from public.rr_cb_colours
  where cb_id=p_cb_id
  order by col_no
)
select jsonb_build_object(
  'ok',true,
  'cb_id',p_cb_id,
  'groups',coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'requirement_type',g.requirement_type,
        'requirement_label',g.requirement_label,
        'source_id',g.source_id,
        'item_no',g.item_no,
        'item_name',g.item_name,
        'unit',g.unit,
        'fulfilment_method',g.fulfilment_method,
        'revision_no',g.revision_no,
        'last_sent_revision',g.last_sent_revision,
        'revised_pending',(g.send_count>0 and g.revision_no>g.last_sent_revision),
        'basis',g.basis,
        'basis_pcs',g.basis_pcs,
        'appx_pcs',g.appx_pcs,
        'cutting_pcs',g.cutting_pcs,
        'required_qty',g.required_qty,
        'supplier_ledger_id',g.supplier_ledger_id,
        'supplier_name',g.supplier_name,
        'supplier_mobile',g.supplier_mobile,
        'profile_labels',to_jsonb(g.profile_labels),
        'status',g.status,
        'send_count',g.send_count
      )
      order by case g.requirement_type when 'MATERIAL' then 1 when 'STICKER' then 2 else 3 end,g.item_name
    )
    from groups g
  ),'[]'::jsonb),
  'suppliers',coalesce((
    select jsonb_agg(jsonb_build_object(
      'ledger_id',ledger_id,
      'name',name,
      'supplier_name',name,
      'mobile',mobile
    ) order by name)
    from supplier_rows
  ),'[]'::jsonb),
  'colours',coalesce((
    select jsonb_agg(to_jsonb(colour_rows) order by colour_no)
    from colour_rows
  ),'[]'::jsonb)
)
$function$;

update public.rr_cb_derived_requirement_v1 r
set appx_pcs=coalesce(
      nullif(r.appx_pcs,0),
      nullif((public.rr_cb_profile_yield_v1(r.cb_unit_id)->>'estimated_pcs')::numeric,0),
      case when r.basis='YIELD' then r.basis_pcs else null end,
      0
    ),
    cutting_pcs=nullif(public.rr_cb_actual_cutting_pcs_v1(r.cb_unit_id),0),
    updated_at=now()
where r.active;

do $block$
declare v_cb_id uuid;
begin
  select id into v_cb_id
  from public.rr_fabric_purchases
  where cb_no='1011'
  order by updated_at desc
  limit 1;

  if v_cb_id is not null then
    perform public.rr_cb_sync_unit_physical_weights_v1(v_cb_id);
    perform public.rr_cb_refresh_derived_requirements_core_v1(v_cb_id);
  end if;
end
$block$;
