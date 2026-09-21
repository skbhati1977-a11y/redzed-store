-- TEST71 CB Department canonical flow.
-- Extends the existing CB/Purchase records; no replacement CB, Material, Art,
-- Cutting, or Real Chat workflow engine is introduced.
begin;

alter table public.rr_fabric_purchases
  add column if not exists cb_department_state text,
  add column if not exists cb_reviewed_at timestamptz,
  add column if not exists cb_reviewed_by uuid;

update public.rr_fabric_purchases fp
set cb_department_state=case
  when exists(
    select 1 from public.rr_cb_units u
    where u.purchase_id=fp.id and coalesce(u.is_final,true)
  ) and not exists(
    select 1 from public.rr_cb_units u
    where u.purchase_id=fp.id and coalesce(u.is_final,true)
      and not exists(
        select 1 from public.rr_cutting_lots_v3 s
        where s.cb_unit_id=u.id and upper(coalesce(s.status,'')) not in('CANCELLED','CANCELED')
        union all
        select 1 from public.rr_production_lots m
        where m.cb_unit_id=u.id and upper(coalesce(m.status,'')) not in('CANCELLED','CANCELED')
      )
  ) then 'CLOSE'
  else 'WORKING'
end
where cb_department_state is null;

alter table public.rr_fabric_purchases
  alter column cb_department_state set default 'OPEN',
  alter column cb_department_state set not null;

alter table public.rr_fabric_purchases drop constraint if exists rr_fabric_purchases_cb_department_state_chk;
alter table public.rr_fabric_purchases add constraint rr_fabric_purchases_cb_department_state_chk
  check(cb_department_state in('OPEN','WORKING','CLOSE'));

alter table public.rr_cb_purchase_entries
  add column if not exists requirement_state text,
  add column if not exists unit text,
  add column if not exists cutting_blocking boolean,
  add column if not exists client_key uuid;

update public.rr_cb_purchase_entries p
set requirement_state=coalesce(p.requirement_state,'CONFIRMED'),
    unit=upper(coalesce(nullif(p.unit,''),mc.unit,'KG')),
    cutting_blocking=coalesce(p.cutting_blocking,false),
    client_key=coalesce(p.client_key,p.id)
from public.rr_material_categories mc
where mc.id=p.material_category_id
  and (p.requirement_state is null or p.unit is null or p.cutting_blocking is null or p.client_key is null);

alter table public.rr_cb_purchase_entries
  alter column requirement_state set default 'CONFIRMED',
  alter column requirement_state set not null,
  alter column cutting_blocking set default false,
  alter column cutting_blocking set not null,
  alter column client_key set default gen_random_uuid(),
  alter column client_key set not null,
  alter column vendor_name drop not null,
  alter column vendor_bill_no drop not null,
  alter column bill_date drop not null,
  alter column quantity drop not null,
  alter column rate drop not null,
  alter column original_quantity drop not null,
  alter column original_rate drop not null,
  alter column original_amount drop not null,
  alter column available_quantity drop not null;

alter table public.rr_cb_purchase_entries drop constraint if exists rr_cb_purchase_entries_requirement_state_chk;
alter table public.rr_cb_purchase_entries add constraint rr_cb_purchase_entries_requirement_state_chk
  check(requirement_state in('NOT REQUIRED','DUE','CONFIRMED'));
alter table public.rr_cb_purchase_entries drop constraint if exists rr_cb_purchase_entries_unit_chk;
alter table public.rr_cb_purchase_entries add constraint rr_cb_purchase_entries_unit_chk
  check(unit is null or unit in('KG','PCS','ROLL','CONE','MTR','SET','BOX'));
create unique index if not exists rr_cb_purchase_entries_client_key_uq
  on public.rr_cb_purchase_entries(client_key);

-- Correct the canonical Material Master mappings that were reproduced live as
-- KG-for-everything. Existing confirmed entry snapshots retain their saved unit.
update public.rr_material_categories set unit='pcs',updated_at=now()
where lower(category_code)='zip' and lower(coalesce(unit,''))<>'pcs';
update public.rr_material_categories set unit='roll',updated_at=now()
where lower(category_code) in('elastic','tape') and lower(coalesce(unit,''))<>'roll';

create table if not exists public.rr_cb_department_audit_v600(
  id uuid primary key default gen_random_uuid(),
  action_id uuid not null unique,
  cb_id uuid not null references public.rr_fabric_purchases(id) on delete restrict,
  action_code text not null,
  actual_actor_id uuid,
  effective_actor_id uuid,
  effective_name text,
  effective_role text,
  previous_state text,
  new_state text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
alter table public.rr_cb_department_audit_v600 enable row level security;
revoke all on public.rr_cb_department_audit_v600 from public,anon,authenticated;
grant all on public.rr_cb_department_audit_v600 to service_role;

create or replace function public.rr_cb_department_assert_authority_v600()
returns jsonb language plpgsql stable security definer set search_path='public' as $function$
declare v jsonb:=public.rr_upm_effective_identity_v200(); r text;
begin
  perform public.rr_assert_active_user_v1();
  r:=upper(coalesce(v->>'role_code',v->>'resolved_role',''));
  if r not in('OWNER','SUPER_ADMIN','ADMIN') then
    raise exception 'CB Department edit requires Owner/Admin authority.' using errcode='42501';
  end if;
  return v;
end $function$;
revoke all on function public.rr_cb_department_assert_authority_v600() from public,anon,authenticated;
grant execute on function public.rr_cb_department_assert_authority_v600() to service_role;

create or replace function public.rr_cb_purchase_set_original_v7203()
returns trigger language plpgsql set search_path='public' as $function$
begin
  if upper(coalesce(new.requirement_state,'CONFIRMED'))='CONFIRMED' then
    new.original_quantity:=coalesce(new.original_quantity,new.quantity);
    new.original_rate:=coalesce(new.original_rate,new.rate);
    new.original_amount:=coalesce(new.original_amount,round(new.quantity*new.rate,2));
    new.available_quantity:=coalesce(new.available_quantity,new.quantity);
  end if;
  return new;
end $function$;

-- DUE/NOT REQUIRED rows belong to the CB Department card.  They must not be
-- projected as completed legacy CB_PURCHASE chat events.
create or replace function public.rr_real_chat_purchase_trigger_v90()
returns trigger language plpgsql security definer set search_path='public','pg_temp' as $function$
begin
  if upper(coalesce(new.requirement_state,'CONFIRMED'))<>'CONFIRMED' then return new; end if;
  perform public.rr_real_chat_sync_purchase_v90(new.id);
  return new;
exception when others then
  raise warning 'Purchase chat sync deferred: %',sqlerrm;
  return new;
end $function$;

create or replace function public.rr_protect_cb_purchase_entry_links()
returns trigger language plpgsql set search_path='public' as $function$
declare v_draft boolean:=coalesce(current_setting('redzed.cb_draft_edit',true),'')='on';
begin
  if v_draft and exists(
    select 1 from public.rr_fabric_purchases fp
    where fp.id=old.cb_id and fp.cb_department_state='OPEN'
  ) then return new; end if;
  if exists(select 1 from public.rr_cb_purchase_rolls where purchase_entry_id=old.id)
     and new.cb_id is distinct from old.cb_id then
    raise exception 'CB cannot change after colour-wise rolls are saved';
  end if;
  if exists(select 1 from public.rr_cb_material_allocations where purchase_entry_id=old.id)
     and (new.cb_id is distinct from old.cb_id
       or new.material_category_id is distinct from old.material_category_id
       or new.quantity is distinct from old.quantity or new.rate is distinct from old.rate) then
    raise exception 'CB, material, quantity or rate cannot change after division allocation';
  end if;
  return new;
end $function$;

create or replace function public.rr_cb_department_save_v600(
  p_cb_id uuid,
  p_action_id uuid,
  p_confirm boolean,
  p_payload jsonb
) returns jsonb
language plpgsql security definer set search_path='public' as $function$
declare
  ident jsonb:=public.rr_cb_department_assert_authority_v600();
  role_code text:=upper(coalesce(ident->>'role_code',ident->>'resolved_role',''));
  cb uuid:=p_cb_id;
  v_cb_no text:=upper(trim(coalesce(p_payload->>'cb_no','')));
  v_div_count integer:=coalesce((p_payload->>'division_count')::integer,0);
  v_colour_count integer:=coalesce((p_payload->>'colour_count')::integer,0);
  reg jsonb:=coalesce(p_payload->'regular','{}'::jsonb);
  reg_qty numeric:=nullif(reg->>'qty','')::numeric;
  reg_rate numeric:=nullif(reg->>'rate','')::numeric;
  reg_amount numeric:=nullif(reg->>'amount','')::numeric;
  old_state text;
  new_state text;
  entry_row jsonb;
  entry_id uuid;
  cat record;
  unit_code text;
  req_state text;
  colour_row jsonb;
  colour_id uuid;
  roll_row jsonb;
  selected_ids uuid[];
  due_blocking integer;
  existing jsonb;
  closed_mode boolean:=false;
  restricted_mode boolean:=false;
begin
  if p_action_id is null then raise exception 'Action ID required.'; end if;
  select jsonb_build_object('ok',true,'duplicate_blocked',true,'cb_id',a.cb_id,
    'state',a.new_state,'action_id',a.action_id) into existing
  from public.rr_cb_department_audit_v600 a where a.action_id=p_action_id;
  if existing is not null then return existing; end if;
  if v_cb_no='' then raise exception 'CB No required.'; end if;
  if v_div_count<1 or v_div_count>50 then raise exception 'Division count must be 1–50.'; end if;
  if v_colour_count<1 or v_colour_count>20 then raise exception 'Colour count must be 1–20.'; end if;
  if reg_qty is null or reg_qty<=0 then raise exception 'Regular Cloth Qty required.'; end if;
  if reg_rate is null or reg_rate<=0 then raise exception 'Regular Cloth Rate required.'; end if;
  reg_amount:=coalesce(reg_amount,round(reg_qty*reg_rate,2));

  perform set_config('redzed.cb_draft_edit','on',true);
  if cb is null then
    cb:=public.rr_create_cb_v713(
      v_cb_no,v_div_count,v_colour_count,reg_qty,reg_amount,
      coalesce(jsonb_array_length(coalesce(reg->'rolls','[]'::jsonb)),0),
      coalesce(nullif(trim(reg->>'fabric_name'),''),v_cb_no),
      (select array_agg(i) from generate_series(1,v_div_count)i),
      nullif(trim(p_payload->>'remarks'),'')
    );
    update public.rr_fabric_purchases set cb_department_state='OPEN' where id=cb;
  else
    select cb_department_state into old_state from public.rr_fabric_purchases where id=cb for update;
    if not found then raise exception 'CB not found.'; end if;
    if old_state<>'OPEN'
       and exists(select 1 from public.rr_cb_units u where u.purchase_id=cb and coalesce(u.is_final,true))
       and not exists(
         select 1 from public.rr_cb_units u where u.purchase_id=cb and coalesce(u.is_final,true)
           and not exists(
             select 1 from public.rr_cutting_lots_v3 s where s.cb_unit_id=u.id and upper(coalesce(s.status,'')) not in('CANCELLED','CANCELED')
             union all
             select 1 from public.rr_production_lots m where m.cb_unit_id=u.id and upper(coalesce(m.status,'')) not in('CANCELLED','CANCELED')
           )
       ) then
      old_state:='CLOSE';
      update public.rr_fabric_purchases set cb_department_state='CLOSE',updated_at=now() where id=cb;
    end if;
    closed_mode:=old_state='CLOSE';
    restricted_mode:=old_state in('WORKING','CLOSE');
    if restricted_mode and p_confirm then raise exception 'CB review is already confirmed.'; end if;
    if exists(select 1 from public.rr_cb_units where purchase_id=cb and division_count<>v_div_count) then
      raise exception 'Division Count cannot change after CB identity creation.';
    end if;
    update public.rr_fabric_purchases
      set cb_no=v_cb_no,colour_count=v_colour_count,notes=nullif(trim(p_payload->>'remarks'),''),updated_at=now()
      where id=cb and not restricted_mode;
  end if;
  select cb_department_state into old_state from public.rr_fabric_purchases where id=cb;

  -- Same CB colours: stable (cb_id,col_no), never duplicate on retry/edit.
  for colour_row in select value from jsonb_array_elements(coalesce(p_payload->'colours','[]'::jsonb)) where not restricted_mode loop
    insert into public.rr_cb_colours(cb_id,col_no,colour_order,colour_name,image_url,media_id,is_confirmed)
    values(cb,(colour_row->>'index')::integer,(colour_row->>'index')::integer,
      coalesce(nullif(colour_row->>'name',''),'Colour '||(colour_row->>'index')),
      nullif(colour_row->>'image_url',''),nullif(colour_row->>'media_id','')::uuid,
      coalesce((colour_row->>'confirmed')::boolean,false))
    on conflict(cb_id,col_no) do update set
      colour_order=excluded.colour_order,colour_name=excluded.colour_name,
      image_url=coalesce(excluded.image_url,rr_cb_colours.image_url),
      media_id=coalesce(excluded.media_id,rr_cb_colours.media_id),
      is_confirmed=coalesce(excluded.is_confirmed,rr_cb_colours.is_confirmed),updated_at=now();
  end loop;

  -- Regular Cloth remains the existing canonical purchase entry.
  select id into entry_id from public.rr_cb_purchase_entries
  where cb_id=cb and lower(coalesce(entry_notes,''))='regular cloth'
  order by created_at limit 1;
  if entry_id is null and not restricted_mode then
    insert into public.rr_cb_purchase_entries(
      cb_id,vendor_name,vendor_bill_no,bill_date,material_category_id,fabric_name,
      allocation_scope,quantity,rate,amount,entry_notes,requirement_state,unit,cutting_blocking,client_key
    ) values(
      cb,nullif(trim(reg->>'vendor'),''),nullif(upper(trim(reg->>'bill_no')),''),nullif(reg->>'bill_date','')::date,
      (reg->>'category_id')::uuid,nullif(trim(reg->>'fabric_name'),''),'all',reg_qty,reg_rate,reg_amount,
      'Regular Cloth','CONFIRMED','KG',true,coalesce(nullif(reg->>'client_key','')::uuid,gen_random_uuid())
    ) returning id into entry_id;
  elsif not restricted_mode then
    update public.rr_cb_purchase_entries set
      vendor_name=nullif(trim(reg->>'vendor'),''),vendor_bill_no=nullif(upper(trim(reg->>'bill_no')),''),
      bill_date=nullif(reg->>'bill_date','')::date,material_category_id=(reg->>'category_id')::uuid,
      fabric_name=nullif(trim(reg->>'fabric_name'),''),quantity=reg_qty,rate=reg_rate,amount=reg_amount,
      original_quantity=reg_qty,original_rate=reg_rate,original_amount=reg_amount,
      available_quantity=reg_qty,requirement_state='CONFIRMED',unit='KG',cutting_blocking=true
    where id=entry_id;
  end if;
  if not restricted_mode then delete from public.rr_cb_purchase_rolls where purchase_entry_id=entry_id; end if;
  for roll_row in select value from jsonb_array_elements(coalesce(reg->'rolls','[]'::jsonb)) where not restricted_mode loop
    select id into colour_id from public.rr_cb_colours
      where cb_id=cb and col_no=(roll_row->>'colour_index')::integer;
    if colour_id is not null and nullif(roll_row->>'qty','')::numeric>0 then
      insert into public.rr_cb_purchase_rolls(purchase_entry_id,cb_colour_id,roll_no,quantity,original_quantity)
      values(entry_id,colour_id,(roll_row->>'roll_no')::integer,(roll_row->>'qty')::numeric,(roll_row->>'qty')::numeric);
    end if;
  end loop;
  if not restricted_mode then delete from public.rr_cb_material_allocations where purchase_entry_id=entry_id; end if;
  select array_agg(id order by division_index) into selected_ids from public.rr_cb_units where purchase_id=cb and coalesce(is_final,true);
  if not restricted_mode then perform public.rr_allocate_cb_purchase_entry(entry_id,selected_ids); end if;

  for entry_row in select value from jsonb_array_elements(coalesce(p_payload->'materials','[]'::jsonb)) loop
    select * into cat from public.rr_material_categories where id=(entry_row->>'category_id')::uuid and is_active;
    if not found then raise exception 'Active Material Master mapping required.'; end if;
    unit_code:=upper(coalesce(nullif(cat.unit,''),nullif(entry_row->>'unit','')));
    if unit_code is null or unit_code not in('KG','PCS','ROLL','CONE','MTR','SET','BOX') then
      raise exception '%: define/select canonical Unit before Confirmed purchase.',cat.category_name;
    end if;
    req_state:=upper(coalesce(entry_row->>'state','NOT REQUIRED'));
    if req_state not in('NOT REQUIRED','DUE','CONFIRMED') then raise exception 'Invalid Material state.'; end if;
    if req_state='CONFIRMED' and (
      nullif(entry_row->>'qty','') is null or nullif(entry_row->>'qty','')::numeric<=0
      or nullif(trim(entry_row->>'vendor'),'') is null or nullif(trim(entry_row->>'bill_no'),'') is null
      or nullif(entry_row->>'bill_date','') is null or nullif(entry_row->>'rate','')::numeric<=0
    ) then raise exception '%: Qty, Unit, Supplier, Bill, Date and Rate required before CONFIRMED.',cat.category_name; end if;

    entry_id:=nullif(entry_row->>'id','')::uuid;
    if entry_id is null then
      select id into entry_id from public.rr_cb_purchase_entries
      where cb_id=cb and client_key=nullif(entry_row->>'client_key','')::uuid limit 1;
    end if;
    if restricted_mode and entry_id is not null and exists(
      select 1 from public.rr_cb_purchase_entries p
      where p.id=entry_id and p.cb_id=cb and p.requirement_state<>'DUE'
    ) then continue; end if;
    if restricted_mode and (entry_id is null or not exists(
      select 1 from public.rr_cb_purchase_entries p
      where p.id=entry_id and p.cb_id=cb and p.requirement_state='DUE'
    )) then raise exception 'Confirmed CB allows only its existing DUE Material to be completed.'; end if;
    if restricted_mode and req_state not in('DUE','CONFIRMED') then
      raise exception 'Existing DUE Material may remain DUE or become CONFIRMED.';
    end if;
    if entry_id is null then
      insert into public.rr_cb_purchase_entries(
        cb_id,vendor_name,vendor_bill_no,bill_date,material_category_id,fabric_name,allocation_scope,
        quantity,rate,amount,entry_notes,requirement_state,unit,cutting_blocking,client_key
      ) values(
        cb,nullif(trim(entry_row->>'vendor'),''),nullif(upper(trim(entry_row->>'bill_no')),''),nullif(entry_row->>'bill_date','')::date,
        cat.id,coalesce(nullif(trim(entry_row->>'fabric_name'),''),cat.category_name),'all',
        nullif(entry_row->>'qty','')::numeric,nullif(entry_row->>'rate','')::numeric,nullif(entry_row->>'amount','')::numeric,
        'CB Material',req_state,unit_code,coalesce((entry_row->>'cutting_blocking')::boolean,false),
        coalesce(nullif(entry_row->>'client_key','')::uuid,gen_random_uuid())
      ) returning id into entry_id;
    else
      update public.rr_cb_purchase_entries set
        vendor_name=nullif(trim(entry_row->>'vendor'),''),vendor_bill_no=nullif(upper(trim(entry_row->>'bill_no')),''),
        bill_date=nullif(entry_row->>'bill_date','')::date,material_category_id=cat.id,
        fabric_name=coalesce(nullif(trim(entry_row->>'fabric_name'),''),cat.category_name),
        quantity=nullif(entry_row->>'qty','')::numeric,rate=nullif(entry_row->>'rate','')::numeric,
        amount=nullif(entry_row->>'amount','')::numeric,requirement_state=req_state,unit=unit_code,
        cutting_blocking=coalesce((entry_row->>'cutting_blocking')::boolean,false),
        original_quantity=case when req_state='CONFIRMED' then nullif(entry_row->>'qty','')::numeric else null end,
        original_rate=case when req_state='CONFIRMED' then nullif(entry_row->>'rate','')::numeric else null end,
        original_amount=case when req_state='CONFIRMED' then nullif(entry_row->>'amount','')::numeric else null end,
        available_quantity=case when req_state='CONFIRMED' then nullif(entry_row->>'qty','')::numeric else null end
      where id=entry_id and cb_id=cb;
    end if;
    delete from public.rr_cb_material_allocations where purchase_entry_id=entry_id;
    if req_state='CONFIRMED' then perform public.rr_allocate_cb_purchase_entry(entry_id,selected_ids); end if;
  end loop;

  if p_confirm then
    select count(*) into due_blocking from public.rr_cb_purchase_entries
    where cb_id=cb and requirement_state='DUE' and cutting_blocking;
    if due_blocking>0 then raise exception 'Cutting-blocking DUE Material must be confirmed first.'; end if;
    if exists(select 1 from public.rr_cb_colours where cb_id=cb and (image_url is null or not coalesce(is_confirmed,false)))
       or (select count(*) from public.rr_cb_colours where cb_id=cb)<v_colour_count then
      raise exception 'All Colour photos must be saved before Save & Confirm.';
    end if;
    update public.rr_fabric_purchases set cb_department_state='WORKING',cb_reviewed_at=now(),
      cb_reviewed_by=auth.uid(),updated_at=now() where id=cb and cb_department_state='OPEN';
  end if;
  select cb_department_state into new_state from public.rr_fabric_purchases where id=cb;
  insert into public.rr_cb_department_audit_v600(
    action_id,cb_id,action_code,actual_actor_id,effective_actor_id,effective_name,effective_role,
    previous_state,new_state,payload
  ) values(
    p_action_id,cb,case when p_confirm then 'SAVE_CONFIRM' when restricted_mode then 'MATERIAL_UPDATE' else 'DRAFT_SAVE' end,auth.uid(),
    nullif(ident->>'effective_auth_user_id','')::uuid,ident->>'display_name',role_code,
    old_state,new_state,jsonb_build_object('source','CB_DEPARTMENT','materials',jsonb_array_length(coalesce(p_payload->'materials','[]'::jsonb)))
  );
  return jsonb_build_object('ok',true,'duplicate_blocked',false,'cb_id',cb,'cb_no',v_cb_no,
    'state',new_state,'action_id',p_action_id);
end $function$;
revoke all on function public.rr_cb_department_save_v600(uuid,uuid,boolean,jsonb) from public,anon;
grant execute on function public.rr_cb_department_save_v600(uuid,uuid,boolean,jsonb) to authenticated,service_role;

create or replace function public.rr_cb_department_detail_v600(p_cb_id uuid)
returns jsonb language plpgsql stable security definer set search_path='public' as $function$
declare v jsonb;
begin
  perform public.rr_cb_department_assert_authority_v600();
  select jsonb_build_object(
    'cb_id',fp.id,'cb_no',fp.cb_no,'state',case when fp.cb_department_state='OPEN' then 'OPEN'
      when not exists(select 1 from public.rr_cb_units u where u.purchase_id=fp.id and coalesce(u.is_final,true)
        and not exists(select 1 from public.rr_cutting_lots_v3 s where s.cb_unit_id=u.id and upper(coalesce(s.status,'')) not in('CANCELLED','CANCELED')
          union all select 1 from public.rr_production_lots m where m.cb_unit_id=u.id and upper(coalesce(m.status,'')) not in('CANCELLED','CANCELED'))) then 'CLOSE' else 'WORKING' end,
    'division_count',fp.division_count,'colour_count',fp.colour_count,'remarks',fp.notes,
    'colours',coalesce((select jsonb_agg(jsonb_build_object('index',c.col_no,'name',c.colour_name,'image_url',c.image_url,'media_id',c.media_id,'confirmed',c.is_confirmed) order by c.col_no) from public.rr_cb_colours c where c.cb_id=fp.id),'[]'::jsonb),
    'entries',coalesce((select jsonb_agg(jsonb_build_object(
      'id',p.id,'client_key',p.client_key,'category_id',p.material_category_id,'category_name',mc.category_name,
      'category_code',mc.category_code,'vendor',p.vendor_name,'bill_no',p.vendor_bill_no,'bill_date',p.bill_date,
      'fabric_name',p.fabric_name,'qty',p.quantity,'rate',p.rate,'amount',p.amount,'state',p.requirement_state,
      'unit',p.unit,'cutting_blocking',p.cutting_blocking,'entry_notes',p.entry_notes,
      'rolls',coalesce((select jsonb_agg(jsonb_build_object('colour_index',c.col_no,'roll_no',r.roll_no,'qty',r.quantity) order by c.col_no,r.roll_no) from public.rr_cb_purchase_rolls r join public.rr_cb_colours c on c.id=r.cb_colour_id where r.purchase_entry_id=p.id),'[]'::jsonb)
    ) order by p.created_at) from public.rr_cb_purchase_entries p join public.rr_material_categories mc on mc.id=p.material_category_id where p.cb_id=fp.id),'[]'::jsonb)
  ) into v from public.rr_fabric_purchases fp where fp.id=p_cb_id;
  if v is null then raise exception 'CB not found.'; end if;
  return v;
end $function$;
revoke all on function public.rr_cb_department_detail_v600(uuid) from public,anon;
grant execute on function public.rr_cb_department_detail_v600(uuid) to authenticated;

create or replace function public.rr_cb_department_cards_v600(p_state text default null,p_search text default null)
returns jsonb language plpgsql stable security definer set search_path='public' as $function$
declare cards jsonb; ident jsonb:=public.rr_upm_effective_identity_v200(); worker uuid:=public.rr_upm_current_worker_id_v9112(); role_code text;
begin
  perform public.rr_assert_active_user_v1();
  role_code:=upper(coalesce(ident->>'role_code',ident->>'resolved_role',''));
  if role_code not in('OWNER','SUPER_ADMIN','ADMIN') and not exists(
    select 1 from public.rr_real_chat_department_membership_v70 m
    where m.worker_id=worker and m.is_active
      and public.rr_real_chat_canonical_department_v83(m.department_code)='PURCHASE'
  ) then raise exception 'CB Department membership required.' using errcode='42501'; end if;
  with base as(
    select fp.*,
      case when fp.cb_department_state='OPEN' then 'OPEN'
        when exists(select 1 from public.rr_cb_units u where u.purchase_id=fp.id and coalesce(u.is_final,true))
         and not exists(select 1 from public.rr_cb_units u where u.purchase_id=fp.id and coalesce(u.is_final,true)
          and not exists(select 1 from public.rr_cutting_lots_v3 s where s.cb_unit_id=u.id and upper(coalesce(s.status,'')) not in('CANCELLED','CANCELED')
            union all select 1 from public.rr_production_lots m where m.cb_unit_id=u.id and upper(coalesce(m.status,'')) not in('CANCELLED','CANCELED'))) then 'CLOSE'
        else 'WORKING' end resolved_state
    from public.rr_fabric_purchases fp where upper(coalesce(fp.operation_status,'ACTIVE'))='ACTIVE'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'event_key','CB_DEPARTMENT:'||b.id,'source_module','CB_DEPARTMENT','card_type','CB_DEPARTMENT',
    'cb_id',b.id,'cb_no',b.cb_no,'lot_no',b.cb_no,'department_code','PURCHASE','department_name','CB Department',
    'source_status',b.resolved_state,'canonical_state',b.resolved_state,'division_count',b.division_count,
    'colour_count',b.colour_count,'quantity',coalesce(r.quantity,b.total_weight),'quantity_unit','KG',
    'supplier',r.vendor_name,'fabric_name',r.fabric_name,'bill_no',r.vendor_bill_no,'bill_date',r.bill_date,
    'roll_count',coalesce((select count(*) from public.rr_cb_purchase_rolls z where z.purchase_entry_id=r.id),0),
    'amount',r.amount,'actual_rate',r.rate,'pending_material_count',(select count(*) from public.rr_cb_purchase_entries p where p.cb_id=b.id and p.requirement_state='DUE'),
    'materials',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',mc.category_name,'state',p.requirement_state,'qty',p.quantity,'unit',p.unit,'cutting_blocking',p.cutting_blocking) order by mc.sort_order,mc.category_name) from public.rr_cb_purchase_entries p join public.rr_material_categories mc on mc.id=p.material_category_id where p.cb_id=b.id and lower(coalesce(p.entry_notes,''))<>'regular cloth'),'[]'::jsonb),
    'art_status',case when exists(select 1 from public.rr_cb_units u where u.purchase_id=b.id and coalesce(u.is_final,true) and not exists(select 1 from public.rr_cb_art_assignments a where a.cb_id=u.id)) then 'DUE' else 'COMPLETE' end,
    'art_combo_status',case when exists(select 1 from public.rr_cb_units u where u.purchase_id=b.id and coalesce(u.combo_mode,'single')<>'single') then 'MULTI / COMBO' else 'SINGLE' end,
    'message',case b.resolved_state when 'OPEN' then 'CB created · Final review pending' when 'WORKING' then 'Art / Art Combo decision active' else 'SENT TO CUTTING' end,
    'event_at',b.updated_at,'edit_href','real-cb-new-v9130-fix2.html?cb_id='||b.id||'&from=CB_DEPARTMENT',
    'read_only',b.resolved_state='CLOSE'
  ) order by b.updated_at desc),'[]'::jsonb) into cards
  from base b left join lateral(
    select p.* from public.rr_cb_purchase_entries p where p.cb_id=b.id and lower(coalesce(p.entry_notes,''))='regular cloth' order by p.created_at limit 1
  )r on true
  where (p_state is null or upper(p_state)=b.resolved_state)
    and (nullif(trim(coalesce(p_search,'')),'') is null or b.cb_no ilike '%'||trim(p_search)||'%'
      or coalesce(r.fabric_name,'') ilike '%'||trim(p_search)||'%');
  return jsonb_build_object('cards',cards,'department_code','PURCHASE','department_name','CB Department');
end $function$;
revoke all on function public.rr_cb_department_cards_v600(text,text) from public,anon;
grant execute on function public.rr_cb_department_cards_v600(text,text) to authenticated;

create or replace function public.rr_real_chat_directory_v600()
returns jsonb language plpgsql stable security definer set search_path='public' as $function$
declare d jsonb:=public.rr_real_chat_directory_v85(); deps jsonb;
begin
  select coalesce(jsonb_agg(case when x->>'department_code'='PURCHASE'
    then jsonb_set(x,'{department_name}',to_jsonb('CB'::text),true) else x end),'[]'::jsonb)
  into deps from jsonb_array_elements(coalesce(d->'departments','[]'::jsonb)) x;
  return jsonb_set(d,'{departments}',deps,true);
end $function$;
revoke all on function public.rr_real_chat_directory_v600() from public,anon;
grant execute on function public.rr_real_chat_directory_v600() to authenticated;

comment on function public.rr_cb_department_save_v600(uuid,uuid,boolean,jsonb) is
  'Canonical same-CB Draft Save / Save & Confirm / late DUE Material mutation; V600.';
comment on function public.rr_cb_department_cards_v600(text,text) is
  'Direct App/Backend/Real Chat CB Department projection; technical PURCHASE code preserved.';

-- Reversible live proof for the same canonical CB.  All fixture rows and
-- trigger side effects are rolled back inside the RPC before it returns.
create or replace function public.rr_test_cb_department_flow_v600()
returns jsonb language plpgsql security definer set search_path='public' as $function$
declare
  v_actual_role text;
  v_actual_name text;
  v_regular uuid;
  v_zip uuid;
  v_collar uuid;
  v_cb uuid;
  v_cb_no text:='TEST71-CB-DEPT-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
  v_zip_key uuid:=gen_random_uuid();
  v_collar_key uuid:=gen_random_uuid();
  v_regular_key uuid:=gen_random_uuid();
  v_draft_action uuid:=gen_random_uuid();
  v_payload jsonb;
  v_draft jsonb;
  v_retry jsonb;
  v_confirm jsonb;
  v_late jsonb;
  v_card jsonb;
  v_counts jsonb;
  v_result jsonb:='{}'::jsonb;
  v_persisted boolean;
begin
  select upper(coalesce(role_code,'')),coalesce(full_name,'') into v_actual_role,v_actual_name
  from public.rr_user_profiles where auth_user_id=auth.uid() and is_active
  order by updated_at desc nulls last limit 1;
  if v_actual_role not in('OWNER','SUPER_ADMIN') or lower(v_actual_name) not like '%test%e2e%' then
    raise exception 'TEST71 E2E Super Admin session required.';
  end if;
  select id into v_regular from public.rr_material_categories where lower(category_code)='regular-cloth' and is_active limit 1;
  select id into v_zip from public.rr_material_categories where lower(category_code)='zip' and is_active limit 1;
  select id into v_collar from public.rr_material_categories where lower(category_code) in('cuff-collar','collar-cuff') and is_active order by sort_order limit 1;
  if v_regular is null or v_zip is null or v_collar is null then raise exception 'Canonical Material Master fixture mappings unavailable.'; end if;

  begin
    v_payload:=jsonb_build_object(
      'cb_no',v_cb_no,'division_count',1,'colour_count',1,'remarks','TEST71 CB Department rollback fixture',
      'colours',jsonb_build_array(jsonb_build_object('index',1,'name','Colour 1','image_url','https://example.invalid/test71-cb-dept.jpg','confirmed',true)),
      'regular',jsonb_build_object('client_key',v_regular_key,'category_id',v_regular,'vendor','TEST71 Supplier','bill_no','TEST71-RC-1','bill_date',current_date,'fabric_name','TEST71 Regular Cloth','qty',500,'rate',10,'amount',5000,'rolls',jsonb_build_array(jsonb_build_object('colour_index',1,'roll_no',1,'qty',500))),
      'materials',jsonb_build_array(
        jsonb_build_object('client_key',v_zip_key,'category_id',v_zip,'state','DUE','unit','PCS','cutting_blocking',false,'fabric_name','Zip','qty',null),
        jsonb_build_object('client_key',v_collar_key,'category_id',v_collar,'state','DUE','unit','KG','cutting_blocking',false,'fabric_name','Collar','qty',null)
      )
    );
    v_draft:=public.rr_cb_department_save_v600(null,v_draft_action,false,v_payload);
    v_cb:=(v_draft->>'cb_id')::uuid;
    v_retry:=public.rr_cb_department_save_v600(v_cb,v_draft_action,false,v_payload);
    perform public.rr_cb_department_save_v600(v_cb,gen_random_uuid(),false,jsonb_set(v_payload,'{remarks}',to_jsonb('TEST71 second draft persisted'::text)));
    v_confirm:=public.rr_cb_department_save_v600(v_cb,gen_random_uuid(),true,v_payload);
    select value into v_card from jsonb_array_elements(public.rr_cb_department_cards_v600('WORKING',v_cb_no)->'cards') where value->>'cb_id'=v_cb::text;
    v_payload:=jsonb_set(v_payload,'{materials,0}',jsonb_build_object(
      'client_key',v_zip_key,'category_id',v_zip,'state','CONFIRMED','unit','PCS','cutting_blocking',false,
      'fabric_name','Zip','qty',216,'vendor','TEST71 Zip Supplier','bill_no','TEST71-ZIP-1','bill_date',current_date,'rate',2,'amount',432
    ));
    v_late:=public.rr_cb_department_save_v600(v_cb,gen_random_uuid(),false,v_payload);
    select jsonb_build_object(
      'cb_rows',count(distinct fp.id),'purchase_rows',count(distinct pe.id),
      'regular_rows',count(distinct pe.id) filter(where lower(coalesce(pe.entry_notes,''))='regular cloth'),
      'material_rows',count(distinct pe.id) filter(where lower(coalesce(pe.entry_notes,''))='cb material'),
      'roll_rows',count(distinct pr.id),'due_rows',count(distinct pe.id) filter(where pe.requirement_state='DUE'),
      'zip_confirmed',bool_or(lower(mc.category_code)='zip' and pe.requirement_state='CONFIRMED' and pe.quantity=216 and pe.unit='PCS')
    ) into v_counts
    from public.rr_fabric_purchases fp
    left join public.rr_cb_purchase_entries pe on pe.cb_id=fp.id
    left join public.rr_material_categories mc on mc.id=pe.material_category_id
    left join public.rr_cb_purchase_rolls pr on pr.purchase_entry_id=pe.id
    where fp.id=v_cb;
    v_result:=jsonb_build_object(
      'fixture',v_cb_no,'cb_id',v_cb,'draft',v_draft,'retry',v_retry,'confirm',v_confirm,'late_material',v_late,
      'working_card',v_card,'counts',v_counts,
      'open_to_working',v_draft->>'state'='OPEN' and v_confirm->>'state'='WORKING',
      'due_survived_confirm',coalesce((v_card->>'pending_material_count')::integer,0)=2
    );
    raise exception using errcode='P6001',message='TEST71_CB_DEPARTMENT_ROLLBACK';
  exception when sqlstate 'P6001' then
    if sqlerrm<>'TEST71_CB_DEPARTMENT_ROLLBACK' then raise; end if;
  end;
  select exists(select 1 from public.rr_fabric_purchases where cb_no=v_cb_no) into v_persisted;
  return v_result||jsonb_build_object('rolled_back',not v_persisted,'persisted',v_persisted);
end $function$;
revoke all on function public.rr_test_cb_department_flow_v600() from public,anon;
grant execute on function public.rr_test_cb_department_flow_v600() to authenticated;

commit;
