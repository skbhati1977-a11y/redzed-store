begin;

-- ============================================================
-- REAL FACTORY V804 ACCESSORY FRONTEND BACKEND
-- Sticker + Metal ID Master / Purchase / Product Mapping
-- Builds only on already verified V803/V804 objects.
-- ============================================================

-- 0) Sticker legacy instruction constraint: preserve old values + add OTHER.
do $$
begin
  if exists (
    select 1 from pg_constraint
    where conname='rr_art_sticker_instructions_work_type_check'
      and conrelid='public.rr_art_sticker_instructions'::regclass
  ) then
    alter table public.rr_art_sticker_instructions
      drop constraint rr_art_sticker_instructions_work_type_check;
  end if;

  alter table public.rr_art_sticker_instructions
    add constraint rr_art_sticker_instructions_work_type_check
    check (lower(work_type) in ('dtf','hd','vinyl','other','metal_id'));
exception when duplicate_object then null;
end $$;

-- 1) Owner/Admin Master save RPCs.
create or replace function public.rr_upsert_sticker_master_v804(
  p_id uuid default null,
  p_sticker_no text default null,
  p_sticker_name text default null,
  p_sticker_quality text default null,
  p_is_active boolean default true
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id uuid;
  v_no text:=nullif(trim(p_sticker_no),'');
  v_quality text:=upper(trim(coalesce(p_sticker_quality,'')));
begin
  if not public.rr_is_owner_or_admin() then raise exception 'Owner/Admin permission required.'; end if;
  if v_no is null then raise exception 'Sticker No required.'; end if;
  if v_quality not in ('HD','DTF','VINYL','OTHER') then raise exception 'Sticker Quality must be HD, DTF, VINYL or OTHER.'; end if;

  if p_id is null then
    insert into public.rr_sticker_master_v803(sticker_no,sticker_name,sticker_quality,is_active,updated_at)
    values(v_no,nullif(trim(p_sticker_name),''),v_quality,coalesce(p_is_active,true),now())
    returning id into v_id;
  else
    update public.rr_sticker_master_v803
       set sticker_no=v_no,
           sticker_name=nullif(trim(p_sticker_name),''),
           sticker_quality=v_quality,
           is_active=coalesce(p_is_active,true),
           updated_at=now()
     where id=p_id
     returning id into v_id;
    if v_id is null then raise exception 'Sticker Master item not found.'; end if;
  end if;
  return v_id;
end;
$$;

create or replace function public.rr_upsert_metal_id_master_v804(
  p_id uuid default null,
  p_metal_id_no text default null,
  p_metal_id_name text default null,
  p_id_size text default null,
  p_is_active boolean default true
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id uuid;
  v_no text:=nullif(trim(p_metal_id_no),'');
  v_size text:=upper(trim(coalesce(p_id_size,'')));
begin
  if not public.rr_is_owner_or_admin() then raise exception 'Owner/Admin permission required.'; end if;
  if v_no is null then raise exception 'Metal ID No required.'; end if;
  if v_size not in ('SMALL','MEDIUM','BIG') then raise exception 'ID Size must be SMALL, MEDIUM or BIG.'; end if;

  if p_id is null then
    insert into public.rr_metal_id_master_v803(metal_id_no,metal_id_name,id_size,is_active,updated_at)
    values(v_no,nullif(trim(p_metal_id_name),''),v_size,coalesce(p_is_active,true),now())
    returning id into v_id;
  else
    update public.rr_metal_id_master_v803
       set metal_id_no=v_no,
           metal_id_name=nullif(trim(p_metal_id_name),''),
           id_size=v_size,
           is_active=coalesce(p_is_active,true),
           updated_at=now()
     where id=p_id
     returning id into v_id;
    if v_id is null then raise exception 'Metal ID Master item not found.'; end if;
  end if;
  return v_id;
end;
$$;

-- 2) Purchase entry RPC. Purchase trigger already auto-syncs V804 inventory.
create or replace function public.rr_post_accessory_purchase_v804(
  p_data_mode text,
  p_item_type text,
  p_master_id uuid,
  p_vendor_name text,
  p_bill_no text,
  p_bill_date date,
  p_qty numeric,
  p_rate_per_piece numeric,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id uuid;
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_type text:=upper(trim(coalesce(p_item_type,'')));
begin
  if not public.rr_is_owner_or_admin() then raise exception 'Owner/Admin permission required.'; end if;
  if v_mode not in ('TEST','REAL') then raise exception 'Data Mode must be TEST or REAL.'; end if;
  if v_type not in ('STICKER','METAL_ID') then raise exception 'Item Type must be STICKER or METAL_ID.'; end if;
  if p_master_id is null then raise exception 'Master item required.'; end if;
  if coalesce(p_qty,0)<=0 then raise exception 'Purchase Qty must be greater than 0.'; end if;
  if coalesce(p_rate_per_piece,0)<0 then raise exception 'Rate cannot be negative.'; end if;

  insert into public.rr_accessory_purchase_ledger_v804(
    data_mode,item_type,sticker_master_id,metal_id_master_id,entry_type,
    vendor_name,bill_no,bill_date,qty,rate_per_piece,notes
  ) values(
    v_mode,v_type,
    case when v_type='STICKER' then p_master_id else null end,
    case when v_type='METAL_ID' then p_master_id else null end,
    'PURCHASE',nullif(trim(p_vendor_name),''),nullif(trim(p_bill_no),''),p_bill_date,
    p_qty,p_rate_per_piece,nullif(trim(p_notes),'')
  ) returning id into v_id;

  return v_id;
end;
$$;

-- 3) Build / reuse Art-specific instruction rows from reusable Masters.
create or replace function public.rr_sticker_instruction_for_master_v804(
  p_art_id uuid,
  p_master_id uuid,
  p_sequence_no integer default 1
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id uuid;
  m public.rr_sticker_master_v803%rowtype;
begin
  select * into m from public.rr_sticker_master_v803 where id=p_master_id and is_active;
  if not found then raise exception 'Active Sticker Master item not found.'; end if;

  select id into v_id
  from public.rr_art_sticker_instructions
  where art_id=p_art_id and sticker_master_id=p_master_id and is_active
  order by sequence_no,id limit 1;

  if v_id is null then
    insert into public.rr_art_sticker_instructions(
      art_id,sequence_no,work_type,work_name,hidden_rate,notes,is_active,sticker_master_id
    ) values(
      p_art_id,coalesce(p_sequence_no,1),lower(m.sticker_quality),
      coalesce(nullif(trim(m.sticker_name),''),m.sticker_no),0,
      'Master Sticker '||m.sticker_no,true,m.id
    ) returning id into v_id;
  end if;
  return v_id;
end;
$$;

create or replace function public.rr_metal_id_instruction_for_master_v804(
  p_art_id uuid,
  p_master_id uuid,
  p_sequence_no integer default 1
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id uuid;
  m public.rr_metal_id_master_v803%rowtype;
begin
  select * into m from public.rr_metal_id_master_v803 where id=p_master_id and is_active;
  if not found then raise exception 'Active Metal ID Master item not found.'; end if;

  select id into v_id
  from public.rr_art_metal_id_instructions_v801
  where art_id=p_art_id and metal_id_master_id=p_master_id and is_active
  order by sequence_no,id limit 1;

  if v_id is null then
    insert into public.rr_art_metal_id_instructions_v801(
      art_id,sequence_no,work_name,hidden_rate,notes,is_active,metal_id_master_id,updated_at
    ) values(
      p_art_id,coalesce(p_sequence_no,1),
      coalesce(nullif(trim(m.metal_id_name),''),m.metal_id_no),0,
      'Master Metal ID '||m.metal_id_no||' · '||m.id_size,true,m.id,now()
    ) returning id into v_id;
  end if;
  return v_id;
end;
$$;

-- 4) Sync accessory requirements for one released lot using current Product Master decision.
create or replace function public.rr_sync_accessory_requirements_for_lot_v804(
  p_lot_no text,
  p_data_mode text default 'TEST'
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_lot text:=nullif(trim(p_lot_no),'');
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_unit_id uuid;
  v_assignment_id uuid;
  v_cut numeric:=0;
  r record;
  v_sticker_count int:=0;
  v_metal_count int:=0;
begin
  if v_lot is null then raise exception 'Lot No required.'; end if;
  if v_mode not in ('TEST','REAL') then raise exception 'Data Mode must be TEST or REAL.'; end if;

  select coalesce(sum(coalesce(cutting_qty,0)),0)
    into v_cut
  from public.rr_upm_cut_size_rows_v726(v_lot);

  if v_cut<=0 then
    return jsonb_build_object('ok',true,'lot_no',v_lot,'status','WAITING_FOR_CUT_QTY');
  end if;

  -- Resolve CB/D by dynamic JSON so old/new lot schemas both remain safe.
  if to_regclass('public.rr_cutting_lots_v3') is not null then
    execute $q$
      select public.rr_try_uuid_v797_5(
        coalesce(to_jsonb(x)->>'cb_unit_id',to_jsonb(x)->>'division_id')
      )
      from public.rr_cutting_lots_v3 x
      where upper(trim(coalesce(to_jsonb(x)->>'lot_no','')))=upper(trim($1))
      limit 1
    $q$ into v_unit_id using v_lot;
  end if;

  if v_unit_id is null and to_regclass('public.rr_production_lots') is not null then
    execute $q$
      select public.rr_try_uuid_v797_5(
        coalesce(to_jsonb(x)->>'cb_unit_id',to_jsonb(x)->>'division_id')
      )
      from public.rr_production_lots x
      where upper(trim(coalesce(to_jsonb(x)->>'lot_no','')))=upper(trim($1))
      limit 1
    $q$ into v_unit_id using v_lot;
  end if;

  if v_unit_id is null then
    return jsonb_build_object('ok',true,'lot_no',v_lot,'status','NO_CB_UNIT_LINK');
  end if;

  select id into v_assignment_id from public.rr_cb_art_assignments where cb_id=v_unit_id limit 1;
  if v_assignment_id is null then
    return jsonb_build_object('ok',true,'lot_no',v_lot,'status','NO_PRODUCT_DECISION');
  end if;

  -- Release old Sticker requirements no longer selected.
  update public.rr_accessory_lot_requirements_v804 q
     set released_qty=greatest(q.required_qty-q.consumed_qty,0),
         requirement_status='RELEASED',updated_at=now()
   where q.data_mode=v_mode and upper(trim(q.lot_no))=upper(v_lot) and q.item_type='STICKER'
     and not exists(
       select 1
       from public.rr_cb_sticker_assignments a
       join public.rr_art_sticker_instructions i on i.id=a.sticker_instruction_id
       where a.assignment_id=v_assignment_id and i.sticker_master_id=q.sticker_master_id
     );

  for r in
    select distinct i.sticker_master_id as master_id
    from public.rr_cb_sticker_assignments a
    join public.rr_art_sticker_instructions i on i.id=a.sticker_instruction_id
    where a.assignment_id=v_assignment_id and i.sticker_master_id is not null and i.is_active
  loop
    perform public.rr_refresh_accessory_requirement_v804(v_mode,v_lot,'STICKER',r.master_id,1);
    update public.rr_accessory_lot_requirements_v804
       set released_qty=0, updated_at=now()
     where data_mode=v_mode and upper(trim(lot_no))=upper(v_lot)
       and item_type='STICKER' and sticker_master_id=r.master_id;
    v_sticker_count:=v_sticker_count+1;
  end loop;

  -- Release old Metal ID requirements no longer selected.
  update public.rr_accessory_lot_requirements_v804 q
     set released_qty=greatest(q.required_qty-q.consumed_qty,0),
         requirement_status='RELEASED',updated_at=now()
   where q.data_mode=v_mode and upper(trim(q.lot_no))=upper(v_lot) and q.item_type='METAL_ID'
     and not exists(
       select 1
       from public.rr_cb_metal_id_assignments_v801 a
       join public.rr_art_metal_id_instructions_v801 i on i.id=a.metal_id_instruction_id
       where a.assignment_id=v_assignment_id and i.metal_id_master_id=q.metal_id_master_id
     );

  for r in
    select distinct i.metal_id_master_id as master_id
    from public.rr_cb_metal_id_assignments_v801 a
    join public.rr_art_metal_id_instructions_v801 i on i.id=a.metal_id_instruction_id
    where a.assignment_id=v_assignment_id and i.metal_id_master_id is not null and i.is_active
  loop
    perform public.rr_refresh_accessory_requirement_v804(v_mode,v_lot,'METAL_ID',r.master_id,1);
    update public.rr_accessory_lot_requirements_v804
       set released_qty=0, updated_at=now()
     where data_mode=v_mode and upper(trim(lot_no))=upper(v_lot)
       and item_type='METAL_ID' and metal_id_master_id=r.master_id;
    v_metal_count:=v_metal_count+1;
  end loop;

  perform public.rr_sync_accessory_low_stock_alerts_v804(v_mode);

  return jsonb_build_object(
    'ok',true,'lot_no',v_lot,'cut_qty',v_cut,'cb_unit_id',v_unit_id,
    'sticker_items',v_sticker_count,'metal_id_items',v_metal_count,'status','SYNCED'
  );
end;
$$;

-- 5) Product Master wrapper: Masters -> existing instruction/assignment chain.
create or replace function public.rr_pm_save_decision_bundle_v804(
  p_cb_unit_id uuid,
  p_art_id uuid,
  p_print_mode text default 'NA',
  p_print_ids uuid[] default '{}'::uuid[],
  p_sticker_mode text default 'NA',
  p_sticker_master_ids uuid[] default '{}'::uuid[],
  p_metal_id_mode text default 'NA',
  p_metal_id_master_ids uuid[] default '{}'::uuid[],
  p_data_mode text default 'TEST'
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_sticker_instruction_ids uuid[]:='{}'::uuid[];
  v_metal_instruction_ids uuid[]:='{}'::uuid[];
  v_id uuid;
  v_result jsonb;
  v_lot record;
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  i integer:=0;
begin
  if not public.rr_is_owner_or_admin() then raise exception 'Owner/Admin permission required.'; end if;
  if v_mode not in ('TEST','REAL') then raise exception 'Data Mode must be TEST or REAL.'; end if;

  if upper(trim(coalesce(p_sticker_mode,'NA')))='SELECTED' then
    foreach v_id in array coalesce(p_sticker_master_ids,'{}'::uuid[]) loop
      i:=i+1;
      v_sticker_instruction_ids:=array_append(
        v_sticker_instruction_ids,
        public.rr_sticker_instruction_for_master_v804(p_art_id,v_id,i)
      );
    end loop;
  end if;

  i:=0;
  if upper(trim(coalesce(p_metal_id_mode,'NA')))='SELECTED' then
    foreach v_id in array coalesce(p_metal_id_master_ids,'{}'::uuid[]) loop
      i:=i+1;
      v_metal_instruction_ids:=array_append(
        v_metal_instruction_ids,
        public.rr_metal_id_instruction_for_master_v804(p_art_id,v_id,i)
      );
    end loop;
  end if;

  v_result:=public.rr_pm_save_decision_bundle_v802_2(
    p_cb_unit_id,p_art_id,p_print_mode,p_print_ids,
    p_sticker_mode,v_sticker_instruction_ids,
    p_metal_id_mode,v_metal_instruction_ids
  );

  -- Existing released lots under the same CB/D get requirements immediately.
  if to_regclass('public.rr_cutting_lots_v3') is not null then
    for v_lot in execute $q$
      select distinct to_jsonb(x)->>'lot_no' as lot_no
      from public.rr_cutting_lots_v3 x
      where public.rr_try_uuid_v797_5(
        coalesce(to_jsonb(x)->>'cb_unit_id',to_jsonb(x)->>'division_id')
      )=$1
        and nullif(trim(coalesce(to_jsonb(x)->>'lot_no','')),'') is not null
    $q$ using p_cb_unit_id
    loop
      perform public.rr_sync_accessory_requirements_for_lot_v804(v_lot.lot_no,v_mode);
    end loop;
  end if;

  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'sticker_master_ids',coalesce(p_sticker_master_ids,'{}'::uuid[]),
    'metal_id_master_ids',coalesce(p_metal_id_master_ids,'{}'::uuid[]),
    'data_mode',v_mode
  );
end;
$$;

-- 6) Release-time auto sync: no manual requirement action after Cutting release.
create or replace function public.rr_accessory_lot_release_sync_trigger_v804()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_lot text;
  v_mode text:='TEST';
begin
  v_lot:=coalesce(to_jsonb(new)->>'lot_no','');
  if nullif(trim(v_lot),'') is null then return new; end if;

  begin
    if to_regprocedure('public.rr_app_data_mode_state_v786()') is not null then
      v_mode:=coalesce(public.rr_app_data_mode_state_v786()->>'default_mode','TEST');
    end if;
    perform public.rr_sync_accessory_requirements_for_lot_v804(v_lot,v_mode);
  exception when others then
    -- Never block Cutting release because an accessory requirement is still waiting for mapping.
    null;
  end;
  return new;
end;
$$;

do $$
begin
  if to_regclass('public.rr_cutting_lots_v3') is not null
     and not exists(select 1 from pg_trigger where tgname='rr_accessory_cutting_release_sync_v804') then
    execute 'create trigger rr_accessory_cutting_release_sync_v804 after insert or update on public.rr_cutting_lots_v3 for each row execute function public.rr_accessory_lot_release_sync_trigger_v804()';
  end if;
  if to_regclass('public.rr_production_lots') is not null
     and not exists(select 1 from pg_trigger where tgname='rr_accessory_multi_release_sync_v804') then
    execute 'create trigger rr_accessory_multi_release_sync_v804 after insert or update on public.rr_production_lots for each row execute function public.rr_accessory_lot_release_sync_trigger_v804()';
  end if;
end $$;

-- 7) Permissions.
grant execute on function public.rr_upsert_sticker_master_v804(uuid,text,text,text,boolean) to authenticated;
grant execute on function public.rr_upsert_metal_id_master_v804(uuid,text,text,text,boolean) to authenticated;
grant execute on function public.rr_post_accessory_purchase_v804(text,text,uuid,text,text,date,numeric,numeric,text) to authenticated;
grant execute on function public.rr_sticker_instruction_for_master_v804(uuid,uuid,integer) to authenticated;
grant execute on function public.rr_metal_id_instruction_for_master_v804(uuid,uuid,integer) to authenticated;
grant execute on function public.rr_sync_accessory_requirements_for_lot_v804(text,text) to authenticated;
grant execute on function public.rr_pm_save_decision_bundle_v804(uuid,uuid,text,uuid[],text,uuid[],text,uuid[],text) to authenticated;

commit;
