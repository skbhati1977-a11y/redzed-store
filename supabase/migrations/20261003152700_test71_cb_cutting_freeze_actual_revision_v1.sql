-- TEST71: Cutting Lot save freezes only the exact Set/profile after Lot No + PCS exist.
-- Child lots inherit the parent CB profile combo; actual cutting revises Yield-based requirements.

CREATE OR REPLACE FUNCTION public.rr_lot_inherit_cb_set_combo_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_assignment public.rr_cb_art_assignments%rowtype;
  v_req public.rr_cb_set_requirement_v1%rowtype;
  v_art_no text;
  v_print_no text;
begin
  if new.cb_unit_id is null then return new; end if;

  select * into v_assignment
  from public.rr_cb_art_assignments
  where cb_id=new.cb_unit_id
  limit 1;

  if v_assignment.id is null then
    raise exception 'Parent CB Set Art Combo is required before Lot release.';
  end if;

  select * into v_req
  from public.rr_cb_set_requirement_v1
  where cb_unit_id=new.cb_unit_id;

  select art_no into v_art_no
  from public.rr_art_master
  where id=v_assignment.art_id;

  if nullif(trim(coalesce(v_art_no,'')),'') is null then
    raise exception 'Parent CB Set Art is required before Lot release.';
  end if;

  new.art_no:=v_art_no;
  new.sleeve_type:=lower(coalesce(nullif(v_req.sleeve_type,''),'HALF'));
  new.border_type:=case
    when coalesce(v_req.border_pounchi,'WITHOUT_BORDER_POUNCHI')='WITH_BORDER_POUNCHI' then 'with'
    else 'without'
  end;

  if coalesce(v_assignment.print_not_applicable,false) then
    new.print_no:='N/A';
  elsif coalesce(v_assignment.print_due,false) then
    raise exception 'Parent CB Set Print decision is still DUE.';
  else
    select string_agg(pm.print_no,', ' order by pa.sequence_no)
    into v_print_no
    from public.rr_cb_print_assignments pa
    join public.rr_print_master pm on pm.id=pa.print_id
    where pa.assignment_id=v_assignment.id;

    if nullif(trim(coalesce(v_print_no,'')),'') is null then
      raise exception 'Parent CB Set Print decision is required before Lot release.';
    end if;
    new.print_no:=v_print_no;
  end if;

  return new;
end
$function$;


CREATE OR REPLACE FUNCTION public.rr_cb_cutting_actual_requirement_refresh_trg_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  cb_id uuid;
begin
  if new.cb_unit_id is null then return new; end if;

  if nullif(trim(coalesce(new.lot_no,'')),'') is null
     or coalesce(nullif(new.actual_pcs,0),new.planned_pcs,0)<=0 then
    return new;
  end if;

  select purchase_id into cb_id
  from public.rr_cb_units
  where id=new.cb_unit_id;

  if cb_id is not null then
    perform public.rr_cb_refresh_derived_requirements_core_v1(cb_id);
  end if;

  return new;
end $function$


CREATE OR REPLACE FUNCTION public.rr_cb_cutting_saved_finalize_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  purchase_id uuid;
  pcs numeric;
begin
  if new.cb_unit_id is null then return new; end if;

  pcs:=greatest(coalesce(new.actual_pcs,0),coalesce(new.planned_pcs,0));
  if nullif(trim(coalesce(new.lot_no,'')),'') is null or pcs<=0 then
    return new;
  end if;

  update public.rr_cb_units
  set is_locked=true,
      locked_at=coalesce(locked_at,now()),
      status='cutting',
      updated_at=now()
  where id=new.cb_unit_id
  returning rr_cb_units.purchase_id into purchase_id;

  if purchase_id is not null then
    perform public.rr_cb_refresh_derived_requirements_core_v1(purchase_id);
  end if;

  return new;
end $function$

-- Normalize parent-combo inheritance trigger names from earlier TEST71 iterations.
drop trigger if exists rr_cutting_lot_inherit_cb_set_combo_trg on public.rr_cutting_lots_v3;
drop trigger if exists rr_production_lot_inherit_cb_set_combo_trg on public.rr_production_lots;
drop trigger if exists rr_000_cb_set_combo_inherit_v1 on public.rr_cutting_lots_v3;
drop trigger if exists rr_000_cb_set_combo_inherit_v1 on public.rr_production_lots;

create trigger rr_000_cb_set_combo_inherit_v1
before insert or update of cb_unit_id,art_no,print_no,sleeve_type,border_type
on public.rr_cutting_lots_v3
for each row execute function public.rr_lot_inherit_cb_set_combo_v1();

create trigger rr_000_cb_set_combo_inherit_v1
before insert or update of cb_unit_id,art_no,print_no,sleeve_type,border_type
on public.rr_production_lots
for each row execute function public.rr_lot_inherit_cb_set_combo_v1();

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

drop trigger if exists rr_cb_cutting_saved_finalize_v1 on public.rr_cutting_lots_v3;
create trigger rr_cb_cutting_saved_finalize_v1
after insert or update of cb_unit_id,lot_no,planned_pcs,actual_pcs
on public.rr_cutting_lots_v3
for each row execute function public.rr_cb_cutting_saved_finalize_v1();

drop trigger if exists rr_cb_production_saved_finalize_v1 on public.rr_production_lots;
create trigger rr_cb_production_saved_finalize_v1
after insert or update of cb_unit_id,lot_no,planned_pcs,actual_pcs
on public.rr_production_lots
for each row execute function public.rr_cb_cutting_saved_finalize_v1();

revoke all on function public.rr_lot_inherit_cb_set_combo_v1() from public,anon,authenticated;
revoke all on function public.rr_cb_cutting_actual_requirement_refresh_trg_v1() from public,anon,authenticated;
revoke all on function public.rr_cb_cutting_saved_finalize_v1() from public,anon,authenticated;
