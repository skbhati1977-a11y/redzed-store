create or replace function public.rr_cb_field_autosave_v1(
  p_cb_id uuid,
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_section text:=upper(trim(coalesce(p_patch->>'section','')));
  v_state text;
  r jsonb:=coalesce(p_patch->'row','{}'::jsonb);
  e public.rr_cb_purchase_entries%rowtype;
  v_entry_id uuid;
  v_client_key uuid;
  v_category_id uuid;
  v_req_state text;
  v_effective_state text;
  v_unit text;
  v_vendor text;
  v_fabric text;
  v_bill text;
  v_bill_date date;
  v_qty numeric;
  v_rate numeric;
  v_amount numeric;
  v_colour_id uuid;
  v_roll_id uuid;
  v_roll_no integer;
  v_colour_index integer;
  v_gsm numeric;
  v_allowed uuid[]:='{}'::uuid[];
  v_recon jsonb;
  v_map jsonb;
  v_derived jsonb;
begin
  perform public.rr_cb_department_assert_authority_v600();

  select cb_department_state
  into v_state
  from public.rr_fabric_purchases
  where id=p_cb_id
  for update;

  if v_state is null then
    raise exception 'CB not found.';
  end if;

  if v_section='REMARKS' then
    if v_state<>'OPEN' then raise exception 'Remarks are locked after CB Confirm.'; end if;
    update public.rr_fabric_purchases
    set notes=nullif(trim(coalesce(p_patch->>'value','')),''),
        updated_at=now()
    where id=p_cb_id;
    return jsonb_build_object('ok',true,'section','REMARKS','saved_at',now());
  end if;

  if v_section='REGULAR' then
    if v_state<>'OPEN' then raise exception 'Regular Cloth fields are locked after CB Confirm.'; end if;

    select * into e
    from public.rr_cb_purchase_entries
    where cb_id=p_cb_id and lower(coalesce(entry_notes,''))='regular cloth'
    order by created_at limit 1 for update;

    if e.id is null then raise exception 'Regular Cloth canonical purchase entry not found.'; end if;

    v_qty:=nullif(r->>'qty','')::numeric;
    v_rate:=nullif(r->>'rate','')::numeric;
    v_vendor:=nullif(trim(coalesce(r->>'vendor','')),'');
    v_fabric:=nullif(trim(coalesce(r->>'fabric_name','')),'');
    v_bill:=nullif(upper(trim(coalesce(r->>'bill_no',''))),'');
    v_bill_date:=nullif(r->>'bill_date','')::date;
    v_amount:=round(coalesce(v_qty,0)*coalesce(v_rate,0),2);

    update public.rr_cb_purchase_entries
    set vendor_name=v_vendor,fabric_name=v_fabric,vendor_bill_no=v_bill,bill_date=v_bill_date,
        quantity=v_qty,original_quantity=v_qty,available_quantity=v_qty,
        rate=v_rate,original_rate=v_rate,amount=v_amount,original_amount=v_amount,updated_at=now()
    where id=e.id;

    update public.rr_fabric_purchases
    set total_weight=coalesce(v_qty,0),total_amount=v_amount,bill_no=v_bill,
        total_rolls=(select count(*)::integer from public.rr_cb_purchase_rolls x
          where x.purchase_entry_id=e.id
            and coalesce(x.operation_status,'ACTIVE') not in('RETURNED','CANCELLED','VOID')
            and coalesce(x.quantity,0)>0),
        updated_at=now()
    where id=p_cb_id;

    begin v_recon:=public.rr_cb_quantity_reconciliation_get_v1(e.id);
    exception when others then v_recon:=null; end;

    return jsonb_build_object('ok',true,'section','REGULAR','purchase_entry_id',e.id,
      'qty',v_qty,'rate',v_rate,'amount',v_amount,'reconciliation',v_recon,'saved_at',now());
  end if;

  if v_section='ROLL' then
    if v_state<>'OPEN' then raise exception 'Roll quantities are locked after CB Confirm.'; end if;

    select * into e
    from public.rr_cb_purchase_entries
    where cb_id=p_cb_id and lower(coalesce(entry_notes,''))='regular cloth'
    order by created_at limit 1 for update;
    if e.id is null then raise exception 'Regular Cloth canonical purchase entry not found.'; end if;

    v_colour_index:=nullif(p_patch->>'colour_index','')::integer;
    v_roll_no:=nullif(p_patch->>'roll_no','')::integer;
    v_qty:=nullif(p_patch->>'qty','')::numeric;
    if v_colour_index is null or v_colour_index<1 then raise exception 'Colour index required.'; end if;
    if v_roll_no is null or v_roll_no<1 then raise exception 'Roll No required.'; end if;

    select id into v_colour_id from public.rr_cb_colours
    where cb_id=p_cb_id and col_no=v_colour_index limit 1;
    if v_colour_id is null then raise exception 'Colour row not found.'; end if;

    select id into v_roll_id
    from public.rr_cb_purchase_rolls
    where purchase_entry_id=e.id and cb_colour_id=v_colour_id and roll_no=v_roll_no
      and coalesce(operation_status,'ACTIVE') not in('RETURNED','CANCELLED','VOID')
    order by created_at limit 1 for update;

    if coalesce(v_qty,0)>0 then
      if v_roll_id is null then
        insert into public.rr_cb_purchase_rolls(
          purchase_entry_id,cb_colour_id,roll_no,quantity,original_quantity,operation_status
        ) values(e.id,v_colour_id,v_roll_no,v_qty,v_qty,'ACTIVE')
        returning id into v_roll_id;
      else
        update public.rr_cb_purchase_rolls
        set quantity=v_qty,original_quantity=v_qty,updated_at=now()
        where id=v_roll_id;
      end if;

      delete from public.rr_cb_purchase_rolls
      where purchase_entry_id=e.id and cb_colour_id=v_colour_id and roll_no=v_roll_no
        and id<>v_roll_id
        and coalesce(operation_status,'ACTIVE') not in('RETURNED','CANCELLED','VOID');
    else
      delete from public.rr_cb_purchase_rolls
      where purchase_entry_id=e.id and cb_colour_id=v_colour_id and roll_no=v_roll_no
        and coalesce(operation_status,'ACTIVE') not in('RETURNED','CANCELLED','VOID');
      v_roll_id:=null;
    end if;

    update public.rr_fabric_purchases
    set total_rolls=(select count(*)::integer from public.rr_cb_purchase_rolls x
      where x.purchase_entry_id=e.id
        and coalesce(x.operation_status,'ACTIVE') not in('RETURNED','CANCELLED','VOID')
        and coalesce(x.quantity,0)>0),
        updated_at=now()
    where id=p_cb_id;

    begin v_recon:=public.rr_cb_quantity_reconciliation_get_v1(e.id);
    exception when others then v_recon:=null; end;

    begin v_derived:=public.rr_cb_refresh_derived_requirements_core_v1(p_cb_id);
    exception when others then v_derived:=null; end;

    return jsonb_build_object('ok',true,'section','ROLL','roll_id',v_roll_id,
      'colour_index',v_colour_index,'roll_no',v_roll_no,'qty',v_qty,
      'reconciliation',v_recon,'derived_refresh',v_derived,'saved_at',now());
  end if;

  if v_section='GSM' then
    if v_state<>'OPEN' then raise exception 'GSM is locked after CB Confirm.'; end if;
    v_colour_index:=nullif(p_patch->>'colour_index','')::integer;
    v_gsm:=nullif(p_patch->>'gsm','')::numeric;
    if v_colour_index is null or v_colour_index<1 then raise exception 'Colour index required.'; end if;
    if v_gsm is not null and (v_gsm<20 or v_gsm>1000) then raise exception 'GSM must be between 20 and 1000.'; end if;

    update public.rr_cb_colours set gsm=v_gsm,updated_at=now()
    where cb_id=p_cb_id and col_no=v_colour_index;

    begin v_derived:=public.rr_cb_refresh_derived_requirements_core_v1(p_cb_id);
    exception when others then v_derived:=null; end;

    return jsonb_build_object('ok',true,'section','GSM','colour_index',v_colour_index,
      'gsm',v_gsm,'derived_refresh',v_derived,'saved_at',now());
  end if;

  if v_section='MATERIAL' then
    v_entry_id:=nullif(r->>'id','')::uuid;
    v_client_key:=nullif(r->>'client_key','')::uuid;
    v_category_id:=nullif(r->>'category_id','')::uuid;

    if v_entry_id is null and v_client_key is not null then
      select id into v_entry_id from public.rr_cb_purchase_entries
      where cb_id=p_cb_id and client_key=v_client_key limit 1;
    end if;

    if v_entry_id is not null then
      select * into e from public.rr_cb_purchase_entries
      where id=v_entry_id and cb_id=p_cb_id for update;
      if e.id is null then raise exception 'Material row not found.'; end if;
      v_category_id:=coalesce(v_category_id,e.material_category_id);
    end if;

    if v_category_id is null then
      return jsonb_build_object('ok',true,'saved',false,'section','MATERIAL',
        'reason','MATERIAL_CATEGORY_DUE','saved_at',now());
    end if;

    if v_state<>'OPEN' and coalesce(e.requirement_state,'')<>'DUE' then
      raise exception 'Only linked DUE Material remains editable after CB Confirm.';
    end if;

    if not exists(select 1 from public.rr_material_categories where id=v_category_id and is_active) then
      raise exception 'Active Material Master mapping required.';
    end if;

    v_req_state:=upper(coalesce(nullif(r->>'state',''),'DUE'));
    if v_req_state not in('NOT REQUIRED','DUE','CONFIRMED') then raise exception 'Invalid Material state.'; end if;

    v_unit:=upper(coalesce(nullif(r->>'unit',''),'PCS'));
    if public.rr_unit_resolve_code_v606(v_unit) is null then raise exception 'Choose a canonical Unit.'; end if;

    v_qty:=nullif(r->>'qty','')::numeric;
    v_rate:=nullif(r->>'rate','')::numeric;
    v_vendor:=nullif(trim(coalesce(r->>'vendor','')),'');
    v_fabric:=nullif(trim(coalesce(r->>'fabric_name','')),'');
    v_bill:=nullif(upper(trim(coalesce(r->>'bill_no',''))),'');
    v_bill_date:=nullif(r->>'bill_date','')::date;
    v_amount:=round(coalesce(v_qty,0)*coalesce(v_rate,0),2);

    v_effective_state:=v_req_state;
    if v_req_state='CONFIRMED' and (
      coalesce(v_qty,0)<=0 or v_vendor is null or v_bill is null
      or v_bill_date is null or coalesce(v_rate,0)<=0
    ) then
      v_effective_state:='DUE';
    end if;

    if jsonb_typeof(coalesce(r->'allowed_art_category_ids','[]'::jsonb))='array' then
      select coalesce(array_agg(value::uuid),'{}'::uuid[])
      into v_allowed
      from jsonb_array_elements_text(coalesce(r->'allowed_art_category_ids','[]'::jsonb));
    end if;

    if v_entry_id is null then
      insert into public.rr_cb_purchase_entries(
        cb_id,vendor_name,vendor_bill_no,bill_date,material_category_id,
        quantity,rate,amount,fabric_name,allocation_scope,entry_notes,
        requirement_state,unit,cutting_blocking,client_key,allowed_art_category_ids
      )
      values(
        p_cb_id,v_vendor,v_bill,v_bill_date,v_category_id,
        v_qty,v_rate,v_amount,v_fabric,'selected','CB Material',
        v_effective_state,v_unit,coalesce((r->>'cutting_blocking')::boolean,false),
        coalesce(v_client_key,gen_random_uuid()),v_allowed
      )
      returning id into v_entry_id;
    else
      update public.rr_cb_purchase_entries
      set vendor_name=case when v_req_state='NOT REQUIRED' then null else v_vendor end,
          vendor_bill_no=case when v_req_state='NOT REQUIRED' then null else v_bill end,
          bill_date=case when v_req_state='NOT REQUIRED' then null else v_bill_date end,
          material_category_id=v_category_id,
          quantity=case when v_req_state='NOT REQUIRED' then null else v_qty end,
          rate=case when v_req_state='NOT REQUIRED' then null else v_rate end,
          amount=case when v_req_state='NOT REQUIRED' then null else v_amount end,
          fabric_name=case when v_req_state='NOT REQUIRED' then null else v_fabric end,
          allocation_scope='selected',requirement_state=v_effective_state,unit=v_unit,
          cutting_blocking=coalesce((r->>'cutting_blocking')::boolean,false),
          allowed_art_category_ids=v_allowed,updated_at=now()
      where id=v_entry_id;
    end if;

    r:=r||jsonb_build_object('id',v_entry_id,'state',v_effective_state);
    v_map:=public.rr_cb_material_mapping_sync_v6(p_cb_id,jsonb_build_array(r));

    begin v_derived:=public.rr_cb_refresh_derived_requirements_core_v1(p_cb_id);
    exception when others then v_derived:=null; end;

    return jsonb_build_object('ok',true,'saved',true,'section','MATERIAL',
      'purchase_entry_id',v_entry_id,'effective_state',v_effective_state,
      'requested_state',v_req_state,'amount',v_amount,'mapping',v_map,
      'derived_refresh',v_derived,'saved_at',now());
  end if;

  raise exception 'Unsupported autosave section.';
end
$$;

revoke all on function public.rr_cb_field_autosave_v1(uuid,jsonb) from public,anon;
grant execute on function public.rr_cb_field_autosave_v1(uuid,jsonb) to authenticated;
