-- TEST71 final hardening for CB Art & Material planning.
-- Keep CB as the only planning authority; retire duplicate helpers and prevent Cutting-side re-splitting.

-- Retire intermediate duplicate derived-refresh paths.
drop trigger if exists rr_cb_derived_after_single_cutting_v1 on public.rr_cutting_lots_v3;
drop trigger if exists rr_cb_derived_after_multi_cutting_v1 on public.rr_production_lots;
drop function if exists public.rr_cb_refresh_derived_after_cutting_v1();

-- Retire obsolete pre-send wrapper. Canonical WhatsApp action is rr_cb_requirement_send_v1().
drop function if exists public.rr_cb_requirement_send_prepare_v1(uuid,text,uuid);

-- Planned CB profiles own lot structure. Cutting saves one Lot per active profile.
create or replace function public.rr_cb_planned_profile_lot_guard_v1()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  u public.rr_cb_units%rowtype;
  plan_state text;
begin
  if new.cb_unit_id is null then
    return new;
  end if;

  select * into u
  from public.rr_cb_units
  where id=new.cb_unit_id;

  if u.id is null then
    return new;
  end if;

  select art_material_plan_state into plan_state
  from public.rr_fabric_purchases
  where id=u.purchase_id;

  if upper(coalesce(plan_state,'')) not in('SINGLE','MULTI') then
    return new;
  end if;

  if exists(select 1 from public.rr_cb_units c where c.parent_unit_id=u.id) then
    raise exception 'Parent Set is Multi Lot. Save Cutting against its child profile.';
  end if;

  if exists(select 1 from public.rr_cutting_lots_v3 x where x.cb_unit_id=u.id)
     or exists(select 1 from public.rr_production_lots x where x.cb_unit_id=u.id) then
    raise exception '% already has a saved Cutting Lot. Change Multi Lot planning in CB before Cutting save.',
      public.rr_cb_profile_label_v1(u.id);
  end if;

  return new;
end
$$;

drop trigger if exists rr_cb_planned_single_profile_lot_guard_v1 on public.rr_cutting_lots_v3;
create trigger rr_cb_planned_single_profile_lot_guard_v1
before insert on public.rr_cutting_lots_v3
for each row execute function public.rr_cb_planned_profile_lot_guard_v1();

drop trigger if exists rr_cb_planned_multi_profile_lot_guard_v1 on public.rr_production_lots;
create trigger rr_cb_planned_multi_profile_lot_guard_v1
before insert on public.rr_production_lots
for each row execute function public.rr_cb_planned_profile_lot_guard_v1();

revoke all on function public.rr_cb_planned_profile_lot_guard_v1() from public,anon,authenticated;

-- Canonical guarded Cutting actual refresh. One refresh per successful saved Lot.
drop trigger if exists rr_cb_cutting_actual_requirement_refresh_v1 on public.rr_cutting_lots_v3;
create trigger rr_cb_cutting_actual_requirement_refresh_v1
after insert or update of cb_unit_id,lot_no,planned_pcs,actual_pcs,status
on public.rr_cutting_lots_v3
for each row execute function public.rr_cb_cutting_actual_requirement_refresh_trg_v1();

drop trigger if exists rr_cb_multi_actual_requirement_refresh_v1 on public.rr_production_lots;
create trigger rr_cb_multi_actual_requirement_refresh_v1
after insert or update of cb_unit_id,lot_no,planned_pcs,actual_pcs,status
on public.rr_production_lots
for each row execute function public.rr_cb_cutting_actual_requirement_refresh_trg_v1();

-- Readable first / revised / resend WhatsApp template.
create or replace function public.rr_cb_requirement_whatsapp_send_v1(
  p_cb_id uuid,
  p_requirement_type text,
  p_source_id uuid,
  p_supplier_ledger_id uuid default null,
  p_supplier_name text default null,
  p_supplier_mobile text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_type text:=upper(trim(coalesce(p_requirement_type,'')));
  v_cb_no text;
  v_item_no text;
  v_item_name text;
  v_unit text;
  v_fulfil text;
  v_supplier_ledger uuid;
  v_supplier_name text;
  v_supplier_mobile text;
  v_revision integer:=1;
  v_total_qty numeric:=0;
  v_basis text:='YIELD';
  v_lines text:='';
  v_send_count integer:=0;
  v_last_sent_revision integer;
  v_template_kind text;
  v_header text;
  v_message text;
  v_sequence integer;
  x record;
begin
  perform public.rr_cb_department_assert_authority_v600();

  if v_type not in('MATERIAL','STICKER','METAL_ID') then
    raise exception 'Requirement type invalid.';
  end if;

  select cb_no into v_cb_no
  from public.rr_fabric_purchases
  where id=p_cb_id;

  if v_cb_no is null then raise exception 'CB not found.'; end if;

  select
    max(r.item_no),max(r.item_name),max(r.unit),max(r.fulfilment_method),
    max(r.revision_no),sum(r.required_qty),
    case when bool_or(r.basis='CUTTING_ACTUAL') then 'CUTTING_ACTUAL' else 'YIELD' end,
    min(r.supplier_ledger_id::text)::uuid,max(r.supplier_name),max(r.supplier_mobile)
  into
    v_item_no,v_item_name,v_unit,v_fulfil,v_revision,v_total_qty,v_basis,
    v_supplier_ledger,v_supplier_name,v_supplier_mobile
  from public.rr_cb_derived_requirement_v1 r
  where r.cb_id=p_cb_id
    and r.active
    and r.requirement_type=v_type
    and r.source_id=p_source_id
    and r.required_qty>0;

  if v_item_name is null then raise exception 'Active requirement not found.'; end if;

  v_supplier_ledger:=coalesce(p_supplier_ledger_id,v_supplier_ledger);
  v_supplier_name:=coalesce(nullif(trim(coalesce(p_supplier_name,'')),''),v_supplier_name);
  v_supplier_mobile:=coalesce(
    nullif(regexp_replace(coalesce(p_supplier_mobile,''),'[^0-9]','','g'),''),
    nullif(regexp_replace(coalesce(v_supplier_mobile,''),'[^0-9]','','g'),'')
  );

  if v_supplier_ledger is not null then
    select coalesce(l.ledger_name,v_supplier_name),
           coalesce(nullif(regexp_replace(l.mobile,'[^0-9]','','g'),''),v_supplier_mobile)
    into v_supplier_name,v_supplier_mobile
    from public.rr_ledgers_v805 l
    where l.id=v_supplier_ledger;
  end if;

  if v_supplier_name is null then raise exception 'Supplier required before WhatsApp send.'; end if;
  if v_supplier_mobile is null then raise exception 'Supplier WhatsApp mobile required.'; end if;

  select count(*),max(l.revision_no)
  into v_send_count,v_last_sent_revision
  from public.rr_cb_requirement_send_log_v1 l
  where l.cb_id=p_cb_id
    and l.requirement_type=v_type
    and l.source_id=p_source_id;

  if v_send_count=0 then
    v_template_kind:='FIRST';
    v_header:=case when v_fulfil='MAKING'
      then 'REDZED MAKING REQUIREMENT'
      else 'REDZED PURCHASE ORDER / REQUIREMENT' end;
  elsif coalesce(v_last_sent_revision,0)<v_revision then
    v_template_kind:='REVISED';
    v_header:=case when v_fulfil='MAKING'
      then 'REVISED MAKING REQUIREMENT'
      else 'REVISED PURCHASE ORDER / REQUIREMENT' end;
  else
    v_template_kind:='RESEND';
    v_header:=case when v_fulfil='MAKING'
      then 'REMINDER · REQUIREMENT STILL PENDING · RESENDING MAKING REQUIREMENT'
      else 'REMINDER · REQUIREMENT STILL PENDING · RESENDING PURCHASE ORDER' end;
  end if;

  v_sequence:=v_send_count+1;

  for x in
    select profile_label,basis,basis_pcs,required_qty,revision_no
    from public.rr_cb_derived_requirement_v1
    where cb_id=p_cb_id
      and active
      and requirement_type=v_type
      and source_id=p_source_id
      and required_qty>0
    order by root_set_no,profile_label
  loop
    v_lines:=v_lines||E'\n• '||x.profile_label||
      ' · '||trim(to_char(x.required_qty,'FM999999990.###'))||' '||v_unit||
      ' · '||case when x.basis='CUTTING_ACTUAL' then 'Actual Cutting ' else 'Yield ' end||
      trim(to_char(x.basis_pcs,'FM999999990.###'))||' pcs';
  end loop;

  v_message:=
    v_header||
    E'\nCB: '||v_cb_no||
    E'\nItem: '||coalesce(v_item_no||' · ','')||v_item_name||
    E'\nMode: '||coalesce(v_fulfil,'PURCHASE')||
    E'\nBasis: '||case when v_basis='CUTTING_ACTUAL' then 'CUTTING ACTUAL' else 'YIELD SHEET' end||
    E'\nTotal Required: '||trim(to_char(v_total_qty,'FM999999990.###'))||' '||v_unit||
    E'\nDetails:'||v_lines||
    E'\nRevision: '||v_revision||
    case when v_template_kind='RESEND' then E'\nResend No: '||v_sequence else '' end||
    E'\nPlease confirm availability / making status.';

  insert into public.rr_cb_requirement_send_log_v1(
    cb_id,requirement_type,source_id,supplier_ledger_id,supplier_name,supplier_mobile,
    revision_no,send_sequence,template_kind,message_text
  )
  values(
    p_cb_id,v_type,p_source_id,v_supplier_ledger,v_supplier_name,v_supplier_mobile,
    v_revision,v_sequence,v_template_kind,v_message
  );

  update public.rr_cb_derived_requirement_v1 r
  set supplier_ledger_id=coalesce(r.supplier_ledger_id,v_supplier_ledger),
      supplier_name=coalesce(r.supplier_name,v_supplier_name),
      supplier_mobile=coalesce(r.supplier_mobile,v_supplier_mobile),
      status=case when v_sequence=1 then 'SENT' else 'RESENT' end,
      last_sent_at=now(),
      last_sent_revision=v_revision,
      updated_at=now()
  where r.cb_id=p_cb_id
    and r.active
    and r.requirement_type=v_type
    and r.source_id=p_source_id;

  return jsonb_build_object(
    'ok',true,
    'cb_id',p_cb_id,
    'cb_no',v_cb_no,
    'requirement_type',v_type,
    'source_id',p_source_id,
    'supplier_ledger_id',v_supplier_ledger,
    'supplier_name',v_supplier_name,
    'supplier_mobile',v_supplier_mobile,
    'revision_no',v_revision,
    'send_sequence',v_sequence,
    'template_kind',v_template_kind,
    'message',v_message
  );
end
$$;
