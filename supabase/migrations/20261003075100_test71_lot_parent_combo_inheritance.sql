create or replace function public.rr_lot_inherit_cb_set_combo_v1()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
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
$$;

drop trigger if exists rr_cutting_lot_inherit_cb_set_combo_trg on public.rr_cutting_lots_v3;
create trigger rr_cutting_lot_inherit_cb_set_combo_trg
before insert or update of cb_unit_id,art_no,print_no,sleeve_type,border_type
on public.rr_cutting_lots_v3
for each row execute function public.rr_lot_inherit_cb_set_combo_v1();

drop trigger if exists rr_production_lot_inherit_cb_set_combo_trg on public.rr_production_lots;
create trigger rr_production_lot_inherit_cb_set_combo_trg
before insert or update of cb_unit_id,art_no,print_no,sleeve_type,border_type
on public.rr_production_lots
for each row execute function public.rr_lot_inherit_cb_set_combo_v1();

revoke all on function public.rr_lot_inherit_cb_set_combo_v1() from public,anon,authenticated;
