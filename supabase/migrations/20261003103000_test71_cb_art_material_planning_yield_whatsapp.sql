
-- TEST71: CB Art & Material planning, Single/Multi profiles, Yield-derived procurement and WhatsApp resend/revision.
-- Targeted migration. Existing production history is not rewritten.

alter table public.rr_fabric_purchases
  add column if not exists art_material_plan_state text not null default 'PENDING';

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conrelid='public.rr_fabric_purchases'::regclass
      and conname='rr_fabric_purchases_art_material_plan_state_chk'
  ) then
    alter table public.rr_fabric_purchases
      add constraint rr_fabric_purchases_art_material_plan_state_chk
      check (art_material_plan_state in ('PENDING','DUE','SINGLE','MULTI'));
  end if;
end $$;

alter table public.rr_cb_units
  add column if not exists planning_share_pct numeric;

update public.rr_cb_units
set planning_share_pct=100
where parent_unit_id is null and planning_share_pct is null;

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conrelid='public.rr_cb_units'::regclass
      and conname='rr_cb_units_planning_share_pct_chk'
  ) then
    alter table public.rr_cb_units
      add constraint rr_cb_units_planning_share_pct_chk
      check (planning_share_pct is null or (planning_share_pct>0 and planning_share_pct<=100));
  end if;
end $$;

create table if not exists public.rr_cb_category_construction_defaults_v1(
  art_category_id uuid primary key references public.rr_art_categories(id) on delete cascade,
  default_sleeve_type text not null default 'HALF',
  default_sleeve_finish text not null default 'CUFF',
  default_border_pounchi text not null default 'WITHOUT_BORDER_POUNCHI',
  default_size_family text not null default 'L,XL,XXL',
  updated_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  constraint rr_cb_cat_def_sleeve_chk check(default_sleeve_type in('HALF','FULL')),
  constraint rr_cb_cat_def_finish_chk check(default_sleeve_finish in('PLAIN','CUFF','RIB')),
  constraint rr_cb_cat_def_border_chk check(default_border_pounchi in('WITH_BORDER_POUNCHI','WITHOUT_BORDER_POUNCHI')),
  constraint rr_cb_cat_def_size_chk check(default_size_family in('L,XL,XXL','2XL,3XL,4XL','3XL,4XL,5XL','M,L,XL,XXL','M,L,XL','L,XL','L,XXL','FREE SIZE'))
);

alter table public.rr_cb_category_construction_defaults_v1 enable row level security;
revoke all on table public.rr_cb_category_construction_defaults_v1 from public,anon,authenticated;

insert into public.rr_cb_category_construction_defaults_v1(
  art_category_id,default_sleeve_type,default_sleeve_finish,default_border_pounchi,default_size_family
)
select id,'HALF',
       case when lower(category_code) in('crew-neck','drop-shoulder') then 'PLAIN' else 'CUFF' end,
       'WITHOUT_BORDER_POUNCHI','L,XL,XXL'
from public.rr_art_categories
where is_active
on conflict(art_category_id) do nothing;

create table if not exists public.rr_cb_derived_requirement_v1(
  id uuid primary key default gen_random_uuid(),
  cb_id uuid not null references public.rr_fabric_purchases(id) on delete cascade,
  cb_unit_id uuid not null references public.rr_cb_units(id) on delete cascade,
  root_set_no integer not null,
  profile_label text not null,
  requirement_type text not null,
  source_id uuid not null,
  item_no text,
  item_name text not null,
  unit text not null,
  fulfilment_method text not null default 'PURCHASE',
  basis text not null default 'YIELD',
  basis_pcs numeric not null default 0,
  qty_per_piece numeric not null default 1,
  required_qty numeric not null default 0,
  revision_no integer not null default 1,
  status text not null default 'READY',
  supplier_ledger_id uuid,
  supplier_name text,
  supplier_mobile text,
  supplier_override boolean not null default false,
  active boolean not null default true,
  last_sent_at timestamptz,
  last_sent_revision integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint rr_cb_derived_req_type_chk check(requirement_type in('MATERIAL','STICKER','METAL_ID')),
  constraint rr_cb_derived_req_basis_chk check(basis in('YIELD','CUTTING_ACTUAL')),
  constraint rr_cb_derived_req_status_chk check(status in('READY','SENT','RESENT','REVISED','FULFILLED','CANCELLED')),
  unique(cb_unit_id,requirement_type,source_id)
);
alter table public.rr_cb_derived_requirement_v1 enable row level security;
revoke all on table public.rr_cb_derived_requirement_v1 from public,anon,authenticated;
create index if not exists rr_cb_derived_req_cb_idx
  on public.rr_cb_derived_requirement_v1(cb_id,active,requirement_type);

create table if not exists public.rr_cb_requirement_send_log_v1(
  id uuid primary key default gen_random_uuid(),
  cb_id uuid not null references public.rr_fabric_purchases(id) on delete cascade,
  requirement_type text not null,
  source_id uuid not null,
  supplier_ledger_id uuid,
  supplier_name text,
  supplier_mobile text,
  revision_no integer not null,
  send_sequence integer not null,
  template_kind text not null,
  message_text text not null,
  sent_by uuid default auth.uid(),
  sent_at timestamptz not null default now(),
  constraint rr_cb_req_send_type_chk check(requirement_type in('MATERIAL','STICKER','METAL_ID')),
  constraint rr_cb_req_send_template_chk check(template_kind in('FIRST','RESEND','REVISED'))
);
alter table public.rr_cb_requirement_send_log_v1 enable row level security;
revoke all on table public.rr_cb_requirement_send_log_v1 from public,anon,authenticated;
create index if not exists rr_cb_req_send_lookup_idx
  on public.rr_cb_requirement_send_log_v1(cb_id,requirement_type,source_id,sent_at desc);

-- Retire duplicate/early planning helpers from intermediate TEST71 iterations.
drop trigger if exists rr_cb_derived_after_single_cutting_v1 on public.rr_cutting_lots_v3;
drop trigger if exists rr_cb_derived_after_multi_cutting_v1 on public.rr_production_lots;
drop function if exists public.rr_cb_refresh_derived_after_cutting_v1();
drop function if exists public.rr_cb_requirement_prepare_send_v1(uuid,text,uuid,uuid);
drop function if exists public.rr_cb_requirement_supplier_set_v1(uuid,uuid,text,text);

CREATE OR REPLACE FUNCTION public.rr_cb_root_set_no_v1(p_cb_unit_id uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
select coalesce(p.division_index,u.division_index)
from public.rr_cb_units u
left join public.rr_cb_units p on p.id=u.parent_unit_id
where u.id=p_cb_unit_id
$function$;

CREATE OR REPLACE FUNCTION public.rr_cb_profile_label_v1(p_cb_unit_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
select 'S'||coalesce(p.division_index,u.division_index)::text||
       case when u.parent_unit_id is not null then '-'||chr(64+coalesce(u.batch_index,1)) else '' end
from public.rr_cb_units u
left join public.rr_cb_units p on p.id=u.parent_unit_id
where u.id=p_cb_unit_id
$function$;

CREATE OR REPLACE FUNCTION public.rr_cb_unit_has_final_cutting_v1(p_cb_unit_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
select
  exists(
    select 1
    from public.rr_cutting_lots_v3
    where cb_unit_id=p_cb_unit_id
      and nullif(trim(coalesce(lot_no,'')),'') is not null
      and coalesce(nullif(actual_pcs,0),planned_pcs,0)>0
  )
  or exists(
    select 1
    from public.rr_production_lots
    where cb_unit_id=p_cb_unit_id
      and nullif(trim(coalesce(lot_no,'')),'') is not null
      and coalesce(nullif(actual_pcs,0),planned_pcs,0)>0
  )
  or exists(
    select 1
    from public.rr_lots_core_v403
    where cb_id=p_cb_unit_id
      and nullif(trim(coalesce(lot_no,'')),'') is not null
      and coalesce(
        nullif(total_cut_pcs,0),
        nullif(cut_qty,0),
        nullif(total_planned_pcs,0),
        planned_qty,
        0
      )>0
  )
$function$;

CREATE OR REPLACE FUNCTION public.rr_cb_category_defaults_get_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
select jsonb_build_object(
 'ok',true,
 'rows',coalesce(jsonb_agg(jsonb_build_object(
   'art_category_id',c.id,
   'category_code',c.category_code,
   'category_name',c.category_name,
   'default_sleeve_type',coalesce(d.default_sleeve_type,'HALF'),
   'default_sleeve_finish',coalesce(d.default_sleeve_finish,case when lower(c.category_code) in('crew-neck','drop-shoulder') then 'PLAIN' else 'CUFF' end),
   'default_border_pounchi',coalesce(d.default_border_pounchi,'WITHOUT_BORDER_POUNCHI'),
   'default_size_family',coalesce(d.default_size_family,'L,XL,XXL')
 ) order by c.category_name),'[]'::jsonb)
)
from public.rr_art_categories c
left join public.rr_cb_category_construction_defaults_v1 d on d.art_category_id=c.id
where c.is_active
$function$;

CREATE OR REPLACE FUNCTION public.rr_cb_category_defaults_set_v1(p_art_category_id uuid, p_sleeve_type text, p_sleeve_finish text, p_border_pounchi text, p_size_family text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
 st text:=upper(trim(coalesce(p_sleeve_type,'')));
 sf text:=public.rr_cb_normalize_sleeve_finish_v1(p_sleeve_finish);
 bp text:=upper(trim(coalesce(p_border_pounchi,'')));
 sz text:=replace(upper(trim(coalesce(p_size_family,''))),' ','');
begin
 perform public.rr_cb_department_assert_authority_v600();
 if not exists(select 1 from public.rr_art_categories where id=p_art_category_id and is_active) then raise exception 'Active Art Category not found.'; end if;
 if st not in('HALF','FULL') then raise exception 'Default Sleeve must be HALF or FULL.'; end if;
 if sf not in('PLAIN','CUFF','RIB') then raise exception 'Default Finish invalid.'; end if;
 if bp not in('WITH_BORDER_POUNCHI','WITHOUT_BORDER_POUNCHI') then raise exception 'Default Border invalid.'; end if;
 if sz not in('L,XL,XXL','2XL,3XL,4XL','3XL,4XL,5XL','M,L,XL,XXL','M,L,XL','L,XL','L,XXL','FREE SIZE') then raise exception 'Default Size invalid.'; end if;
 insert into public.rr_cb_category_construction_defaults_v1(
   art_category_id,default_sleeve_type,default_sleeve_finish,default_border_pounchi,default_size_family,updated_by,updated_at
 ) values(p_art_category_id,st,sf,bp,sz,auth.uid(),now())
 on conflict(art_category_id) do update set
   default_sleeve_type=excluded.default_sleeve_type,
   default_sleeve_finish=excluded.default_sleeve_finish,
   default_border_pounchi=excluded.default_border_pounchi,
   default_size_family=excluded.default_size_family,
   updated_by=auth.uid(),updated_at=now();
 return jsonb_build_object('ok',true,'art_category_id',p_art_category_id,'default_sleeve_type',st,'default_sleeve_finish',sf,'default_border_pounchi',bp,'default_size_family',sz);
end $function$;

CREATE OR REPLACE FUNCTION public.rr_cb_copy_combo_v1(p_from_unit_id uuid, p_to_unit_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  a public.rr_cb_art_assignments%rowtype;
  new_a uuid;
begin
  perform public.rr_cb_department_assert_authority_v600();

  delete from public.rr_cb_material_allocations where division_id=p_to_unit_id;
  delete from public.rr_cb_material_usage_v1 where division_id=p_to_unit_id;
  delete from public.rr_cb_art_assignments where cb_id=p_to_unit_id;

  insert into public.rr_cb_set_requirement_v1(
    cb_unit_id,art_id,art_category_id,sleeve_type,size_family,sleeve_finish,border_pounchi,updated_at
  )
  select p_to_unit_id,art_id,art_category_id,sleeve_type,size_family,sleeve_finish,border_pounchi,now()
  from public.rr_cb_set_requirement_v1
  where cb_unit_id=p_from_unit_id
  on conflict(cb_unit_id) do update set
    art_id=excluded.art_id,
    art_category_id=excluded.art_category_id,
    sleeve_type=excluded.sleeve_type,
    size_family=excluded.size_family,
    sleeve_finish=excluded.sleeve_finish,
    border_pounchi=excluded.border_pounchi,
    updated_at=now();

  select * into a from public.rr_cb_art_assignments where cb_id=p_from_unit_id limit 1;
  if a.id is not null then
    insert into public.rr_cb_art_assignments(
      cb_id,art_id,assigned_by,status,bypass_reason,bypassed_by,bypassed_at,
      print_not_applicable,sticker_not_applicable,metal_id_not_applicable,
      print_due,sticker_due,metal_id_due,updated_at
    ) values(
      p_to_unit_id,a.art_id,coalesce(a.assigned_by,auth.uid()),a.status,a.bypass_reason,a.bypassed_by,a.bypassed_at,
      a.print_not_applicable,a.sticker_not_applicable,a.metal_id_not_applicable,
      a.print_due,a.sticker_due,a.metal_id_due,now()
    ) returning id into new_a;

    insert into public.rr_cb_print_assignments(assignment_id,print_id,sequence_no)
    select new_a,print_id,sequence_no from public.rr_cb_print_assignments where assignment_id=a.id;

    insert into public.rr_cb_sticker_assignments(assignment_id,sticker_instruction_id,sequence_no)
    select new_a,sticker_instruction_id,sequence_no from public.rr_cb_sticker_assignments where assignment_id=a.id;

    insert into public.rr_cb_metal_id_assignments_v801(assignment_id,metal_id_instruction_id,sequence_no)
    select new_a,metal_id_instruction_id,sequence_no from public.rr_cb_metal_id_assignments_v801 where assignment_id=a.id;
  end if;

  return jsonb_build_object('ok',true,'from_unit_id',p_from_unit_id,'to_unit_id',p_to_unit_id,'assignment_id',new_a);
end $function$;

CREATE OR REPLACE FUNCTION public.rr_cb_set_lot_plan_v1(p_parent_unit_id uuid, p_mode text, p_child_count integer DEFAULT 2, p_share_percents jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  parent public.rr_cb_units%rowtype;
  child record;
  first_child public.rr_cb_units%rowtype;
  mode text:=upper(trim(coalesce(p_mode,'')));
  cnt integer:=greatest(2,least(coalesce(p_child_count,2),4));
  existing_count integer;
  max_di integer;
  i integer;
  pct numeric;
  pct_total numeric:=0;
  wt numeric;
  amt numeric;
  rolls numeric;
  used_wt numeric:=0;
  used_amt numeric:=0;
  used_rolls numeric:=0;
  child_id uuid;
  child_ids uuid[]:='{}'::uuid[];
begin
  perform public.rr_cb_department_assert_authority_v600();

  select * into parent
  from public.rr_cb_units
  where id=p_parent_unit_id
  for update;

  if parent.id is null then raise exception 'Set not found.'; end if;
  if parent.parent_unit_id is not null then raise exception 'Lot plan must be changed from the parent Set.'; end if;
  if mode not in('SINGLE','MULTI') then raise exception 'Set Lot Mode must be SINGLE or MULTI.'; end if;

  if public.rr_cb_unit_has_final_cutting_v1(parent.id)
     or exists(
       select 1 from public.rr_cb_units c
       where c.parent_unit_id=parent.id
         and public.rr_cb_unit_has_final_cutting_v1(c.id)
     )
  then
    raise exception 'Set Lot structure is frozen after Cutting Lot save.';
  end if;

  select count(*) into existing_count
  from public.rr_cb_units
  where parent_unit_id=parent.id;

  if mode='SINGLE' then
    select * into first_child
    from public.rr_cb_units
    where parent_unit_id=parent.id
    order by batch_index,id
    limit 1;

    if first_child.id is not null then
      update public.rr_cb_units
      set garment_category_id=first_child.garment_category_id,
          sleeve_type=first_child.sleeve_type,
          sleeve_finish=first_child.sleeve_finish,
          border_pounchi=first_child.border_pounchi,
          size_family=first_child.size_family,
          size_set=first_child.size_set,
          material_decision=first_child.material_decision,
          planning_share_pct=100,
          updated_at=now()
      where id=parent.id;

      perform public.rr_cb_copy_combo_v1(first_child.id,parent.id);
    else
      update public.rr_cb_units
      set planning_share_pct=100,updated_at=now()
      where id=parent.id;
    end if;

    update public.rr_cb_purchase_rolls
    set division_id=parent.id
    where division_id in(select id from public.rr_cb_units where parent_unit_id=parent.id);

    delete from public.rr_cb_material_allocations
    where division_id in(select id from public.rr_cb_units where parent_unit_id=parent.id);

    delete from public.rr_cb_material_usage_v1
    where division_id in(select id from public.rr_cb_units where parent_unit_id=parent.id);

    delete from public.rr_cb_art_assignments
    where cb_id in(select id from public.rr_cb_units where parent_unit_id=parent.id);

    delete from public.rr_cb_units where parent_unit_id=parent.id;

    update public.rr_cb_units
    set combo_mode='single',
        is_final=true,
        is_cutting_enabled=true,
        subdivided_at=null,
        planning_share_pct=100,
        updated_at=now()
    where id=parent.id;

    return jsonb_build_object(
      'ok',true,
      'mode','SINGLE',
      'parent_unit_id',parent.id,
      'root_set_no',parent.division_index,
      'children','[]'::jsonb
    );
  end if;

  if jsonb_typeof(p_share_percents)='array'
     and jsonb_array_length(p_share_percents)=cnt
  then
    for i in 0..cnt-1 loop
      pct:=coalesce((p_share_percents->>i)::numeric,0);
      if pct<=0 then raise exception 'Every Multi Lot share must be greater than zero.'; end if;
      pct_total:=pct_total+pct;
    end loop;
    if abs(pct_total-100)>0.01 then
      raise exception 'Multi Lot shares must total 100 percent.';
    end if;
  else
    p_share_percents:=null;
  end if;

  if existing_count>cnt then
    for child in
      select *
      from public.rr_cb_units
      where parent_unit_id=parent.id
        and coalesce(batch_index,999)>cnt
      order by batch_index desc
    loop
      update public.rr_cb_purchase_rolls set division_id=parent.id where division_id=child.id;
      delete from public.rr_cb_material_allocations where division_id=child.id;
      delete from public.rr_cb_material_usage_v1 where division_id=child.id;
      delete from public.rr_cb_art_assignments where cb_id=child.id;
      delete from public.rr_cb_units where id=child.id;
    end loop;
  end if;

  select coalesce(max(division_index),0)
  into max_di
  from public.rr_cb_units
  where purchase_id=parent.purchase_id;

  for i in 1..cnt loop
    pct:=case
      when p_share_percents is not null then (p_share_percents->>(i-1))::numeric
      else round(100.0/cnt,6)
    end;

    if i=cnt and p_share_percents is null then
      pct:=100-(round(100.0/cnt,6)*(cnt-1));
    end if;

    if i=cnt then
      wt:=round(coalesce(parent.divided_weight,0)-used_wt,3);
      amt:=round(coalesce(parent.divided_amount,0)-used_amt,2);
      rolls:=greatest(coalesce(parent.divided_rolls,0)-used_rolls,0);
    else
      wt:=round(coalesce(parent.divided_weight,0)*(pct/100.0),3);
      amt:=round(coalesce(parent.divided_amount,0)*(pct/100.0),2);
      rolls:=round(coalesce(parent.divided_rolls,0)*(pct/100.0),3);
      used_wt:=used_wt+wt;
      used_amt:=used_amt+amt;
      used_rolls:=used_rolls+rolls;
    end if;

    select id into child_id
    from public.rr_cb_units
    where parent_unit_id=parent.id
      and batch_index=i
    limit 1;

    if child_id is null then
      max_di:=max_di+1;

      insert into public.rr_cb_units(
        purchase_id,cb_base_no,division_count,division_index,cb_code,
        divided_rolls,divided_weight,divided_amount,status,is_locked,
        sleeve_type,size_family,extra_family_cost_per_piece,estimated_pcs,actual_pcs,notes,
        parent_unit_id,batch_index,combo_mode,is_final,is_cutting_enabled,operation_status,
        sleeve_finish,garment_category_id,size_set,material_decision,border_pounchi,
        planning_share_pct,updated_at
      )
      values(
        parent.purchase_id,parent.cb_base_no,parent.division_count,max_di,parent.cb_code||chr(64+i),
        rolls,wt,amt,'available',false,
        parent.sleeve_type,parent.size_family,parent.extra_family_cost_per_piece,0,0,'Pre-cutting Multi Lot profile',
        parent.id,i,'single',true,true,'ACTIVE',
        parent.sleeve_finish,parent.garment_category_id,parent.size_set,parent.material_decision,parent.border_pounchi,
        pct,now()
      )
      returning id into child_id;

      perform public.rr_cb_copy_combo_v1(parent.id,child_id);
    else
      update public.rr_cb_units
      set divided_rolls=rolls,
          divided_weight=wt,
          divided_amount=amt,
          planning_share_pct=pct,
          updated_at=now()
      where id=child_id;
    end if;

    child_ids:=array_append(child_ids,child_id);
  end loop;

  update public.rr_cb_units
  set combo_mode='multi',
      is_final=false,
      is_cutting_enabled=false,
      planning_share_pct=100,
      subdivided_at=coalesce(subdivided_at,now()),
      updated_at=now()
  where id=parent.id;

  return jsonb_build_object(
    'ok',true,
    'mode','MULTI',
    'parent_unit_id',parent.id,
    'root_set_no',parent.division_index,
    'child_count',cnt,
    'child_unit_ids',to_jsonb(child_ids)
  );
end $function$;

CREATE OR REPLACE FUNCTION public.rr_cb_art_material_plan_set_v1(p_cb_id uuid, p_state text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
 st text:=upper(trim(coalesce(p_state,'')));
 r record;
begin
 perform public.rr_cb_department_assert_authority_v600();

 if st not in('PENDING','DUE','SINGLE','MULTI') then
   raise exception 'Art & Material Decision must be PENDING, DUE, SINGLE or MULTI.';
 end if;

 if not exists(select 1 from public.rr_fabric_purchases where id=p_cb_id) then
   raise exception 'CB not found.';
 end if;

 if st='SINGLE' then
   for r in
     select id from public.rr_cb_units
     where purchase_id=p_cb_id and parent_unit_id is null
     order by division_index
   loop
     perform public.rr_cb_set_lot_plan_v1(r.id,'SINGLE',2,null);
   end loop;
 end if;

 update public.rr_fabric_purchases
 set art_material_plan_state=st,updated_at=now()
 where id=p_cb_id;

 return jsonb_build_object('ok',true,'cb_id',p_cb_id,'state',st);
end $function$;

CREATE OR REPLACE FUNCTION public.rr_cb_plan_context_v1(p_cb_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
with roots as (
  select p.*
  from public.rr_cb_units p
  where p.purchase_id=p_cb_id
    and p.parent_unit_id is null
),
set_rows as (
  select jsonb_build_object(
    'set_no',p.division_index,
    'parent_unit_id',p.id,
    'mode',case when exists(select 1 from public.rr_cb_units c where c.parent_unit_id=p.id) then 'MULTI' else 'SINGLE' end,
    'structure_locked',
      public.rr_cb_unit_has_final_cutting_v1(p.id)
      or exists(
        select 1 from public.rr_cb_units c
        where c.parent_unit_id=p.id
          and public.rr_cb_unit_has_final_cutting_v1(c.id)
      ),
    'children',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'unit_id',c.id,
          'division_index',c.division_index,
          'batch_index',c.batch_index,
          'label','S'||p.division_index::text||'-'||chr(64+c.batch_index),
          'share_pct',coalesce(c.planning_share_pct,round(100.0/nullif((select count(*) from public.rr_cb_units cc where cc.parent_unit_id=p.id),0),2)),
          'locked',public.rr_cb_unit_has_final_cutting_v1(c.id)
        )
        order by c.batch_index
      )
      from public.rr_cb_units c
      where c.parent_unit_id=p.id
    ),'[]'::jsonb)
  ) row_json
  from roots p
)
select jsonb_build_object(
  'ok',true,
  'state',coalesce((select art_material_plan_state from public.rr_fabric_purchases where id=p_cb_id),'PENDING'),
  'sets',coalesce(
    (select jsonb_agg(row_json order by (row_json->>'set_no')::int) from set_rows),
    '[]'::jsonb
  )
)
$function$;

CREATE OR REPLACE FUNCTION public.rr_cb_set_art_category_allowed_v1(p_cb_unit_id uuid, p_category_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
with x as (
  select coalesce(p.division_index,u.division_index) root_set_no
  from public.rr_cb_units u
  left join public.rr_cb_units p on p.id=u.parent_unit_id
  where u.id=p_cb_unit_id
)
select case
  when x.root_set_no=1 then lower(c.category_code)='self-collar'
  when x.root_set_no in(2,3) then lower(c.category_code) in('crew-neck','drop-shoulder')
  when x.root_set_no=4 then lower(c.category_code)='flat-polo'
  else true
end
from x
join public.rr_art_categories c on c.id=p_category_id
$function$;

CREATE OR REPLACE FUNCTION public.rr_cb_set_requirement_sync_v6(p_cb_id uuid, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r jsonb;
  u public.rr_cb_units%rowtype;
  a public.rr_cb_art_assignments%rowtype;
  am record;
  di int;
  n int:=0;
  st text;
  sf text;
  sz text;
  bp text;
  cat uuid;
  art uuid;
  unit_id uuid;
  arr text[];
  unit_finish text;
  cat_code text;
begin
  perform public.rr_cb_department_assert_authority_v600();

  for r in select value from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
    di:=nullif(r->>'set_no','')::int;
    unit_id:=nullif(r->>'cb_unit_id','')::uuid;
    st:=coalesce(nullif(upper(r->>'sleeve_type'),''),'HALF');
    sf:=public.rr_cb_normalize_sleeve_finish_v1(r->>'sleeve_finish');
    sz:=replace(coalesce(nullif(upper(r->>'size_family'),''),'L,XL,XXL'),' ','');
    bp:=case when upper(coalesce(r->>'border_pounchi','WITHOUT_BORDER_POUNCHI'))='WITH_BORDER_POUNCHI'
             then 'WITH_BORDER_POUNCHI' else 'WITHOUT_BORDER_POUNCHI' end;
    cat:=nullif(r->>'art_category_id','')::uuid;
    art:=nullif(r->>'art_id','')::uuid;

    if sz not in('L,XL,XXL','2XL,3XL,4XL','3XL,4XL,5XL','M,L,XL,XXL','M,L,XL','L,XL','L,XXL','FREE SIZE') then
      raise exception 'Choose Size from the approved Size list.';
    end if;

    if unit_id is not null then
      select * into u
      from public.rr_cb_units
      where id=unit_id and purchase_id=p_cb_id
      for update;
    else
      select * into u
      from public.rr_cb_units
      where purchase_id=p_cb_id
        and parent_unit_id is null
        and division_index=di
        and coalesce(is_final,true)
      order by created_at
      limit 1
      for update;
    end if;

    if u.id is null then raise exception 'Active Set profile not found.'; end if;
    if public.rr_cb_unit_has_final_cutting_v1(u.id) then
      raise exception '% is frozen after Cutting Lot save.',public.rr_cb_profile_label_v1(u.id);
    end if;

    if art is not null then
      select id,art_category_id into am
      from public.rr_art_master
      where id=art;
      if am.id is null or am.art_category_id is null then
        raise exception 'Selected Art Category required.';
      end if;
      cat:=am.art_category_id;
    end if;

    if cat is not null and not coalesce(public.rr_cb_set_art_category_allowed_v1(u.id,cat),false) then
      raise exception '%: selected Category is not allowed for this Set.',public.rr_cb_profile_label_v1(u.id);
    end if;

    if art is not null then
      insert into public.rr_cb_art_assignments(cb_id,art_id)
      values(u.id,art)
      on conflict(cb_id) do update
      set art_id=excluded.art_id,updated_at=now();
    else
      select * into a from public.rr_cb_art_assignments where cb_id=u.id;
      if a.id is not null then
        select id,art_category_id into am from public.rr_art_master where id=a.art_id;
        if cat is null or am.art_category_id is distinct from cat then
          delete from public.rr_cb_art_assignments where id=a.id;
        else
          art:=a.art_id;
        end if;
      end if;
    end if;

    select lower(category_code) into cat_code
    from public.rr_art_categories
    where id=cat;

    arr:=case when sz='FREE SIZE' then array['FREE SIZE']::text[] else string_to_array(sz,',') end;
    unit_finish:=case sf when 'CUFF' then 'WITH_CUFF' when 'RIB' then 'RIB' else 'WITHOUT_CUFF' end;

    insert into public.rr_cb_set_requirement_v1(
      cb_unit_id,art_id,art_category_id,sleeve_type,size_family,sleeve_finish,border_pounchi,updated_at
    )
    values(u.id,art,cat,st,sz,sf,bp,now())
    on conflict(cb_unit_id) do update set
      art_id=excluded.art_id,
      art_category_id=excluded.art_category_id,
      sleeve_type=excluded.sleeve_type,
      size_family=excluded.size_family,
      sleeve_finish=excluded.sleeve_finish,
      border_pounchi=excluded.border_pounchi,
      updated_at=now();

    update public.rr_cb_units
    set garment_category_id=cat,
        sleeve_type=st,
        sleeve_finish=unit_finish,
        border_pounchi=bp,
        size_family=sz,
        size_set=arr,
        material_decision=case
          when cat_code='self-collar' then 'NOT_APPLICABLE'
          when material_decision='NOT_APPLICABLE' then 'DUE'
          else material_decision
        end,
        updated_at=now()
    where id=u.id;

    n:=n+1;
  end loop;

  return jsonb_build_object('ok',true,'synced',n);
end $function$;

CREATE OR REPLACE FUNCTION public.rr_cb_material_mapping_sync_v6(p_cb_id uuid, p_materials jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  m jsonb;
  e uuid;
  u record;
  wanted int[];
  allowed uuid[];
  n int:=0;
  dup record;
  set_cat uuid;
  set_code text;
begin
  perform public.rr_cb_department_assert_authority_v600();
  if p_cb_id is null then raise exception 'CB required.'; end if;

  select category_id,count(*) into dup
  from (
    select nullif(x.value->>'category_id','')::uuid category_id
    from jsonb_array_elements(coalesce(p_materials,'[]'::jsonb)) x
  ) z
  where category_id is not null
  group by category_id
  having count(*)>1
  limit 1;
  if dup.category_id is not null then
    raise exception 'This Material is already added in another Material card.';
  end if;

  for m in select value from jsonb_array_elements(coalesce(p_materials,'[]'::jsonb)) loop
    e:=nullif(m->>'id','')::uuid;
    if e is null then
      select id into e
      from public.rr_cb_purchase_entries
      where cb_id=p_cb_id and client_key=nullif(m->>'client_key','')::uuid
      limit 1;
    end if;
    if e is null then continue; end if;

    wanted:=coalesce(array(
      select jsonb_array_elements_text(coalesce(m->'selected_sets','[]'::jsonb))::int
    ),'{}');
    allowed:=coalesce(array(
      select jsonb_array_elements_text(coalesce(m->'allowed_art_category_ids','[]'::jsonb))::uuid
    ),'{}');

    update public.rr_cb_purchase_entries
    set allowed_art_category_ids=allowed,allocation_scope='selected'
    where id=e and cb_id=p_cb_id;

    delete from public.rr_cb_material_allocations where purchase_entry_id=e;
    delete from public.rr_cb_material_usage_v1 where purchase_entry_id=e;

    for u in
      select cu.id,
             coalesce(parent.division_index,cu.division_index) root_set_no,
             coalesce(sr.art_category_id,cu.garment_category_id) effective_category_id
      from public.rr_cb_units cu
      left join public.rr_cb_units parent on parent.id=cu.parent_unit_id
      left join public.rr_cb_set_requirement_v1 sr on sr.cb_unit_id=cu.id
      where cu.purchase_id=p_cb_id
        and coalesce(cu.is_final,true)
        and coalesce(parent.division_index,cu.division_index)=any(wanted)
      order by coalesce(parent.division_index,cu.division_index),coalesce(cu.batch_index,0),cu.division_index
    loop
      set_cat:=u.effective_category_id;
      select lower(category_code) into set_code
      from public.rr_art_categories
      where id=set_cat;

      if set_code='self-collar' then
        continue;
      end if;

      if cardinality(allowed)>0 and set_cat is not null and not(set_cat=any(allowed)) then
        raise exception 'S% active profile Category is outside this Material allowed categories.',u.root_set_no;
      end if;

      insert into public.rr_cb_material_allocations(
        purchase_entry_id,division_id,material_category_id,allowed_art_category_ids
      )
      select e,u.id,p.material_category_id,allowed
      from public.rr_cb_purchase_entries p
      where p.id=e;

      n:=n+1;
    end loop;
  end loop;

  return jsonb_build_object(
    'ok',true,
    'allocation_count',n,
    'root_set_aware',true,
    'multi_child_aware',true
  );
end $function$;

CREATE OR REPLACE FUNCTION public.rr_cb_profile_yield_v1(p_cb_unit_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  u public.rr_cb_units%rowtype;
  root public.rr_cb_units%rowtype;
  am public.rr_art_master%rowtype;
  req public.rr_cb_set_requirement_v1%rowtype;
  c record;
  y jsonb;
  exact_weight numeric;
  base_weight numeric;
  profile_weight numeric;
  root_total_weight numeric;
  profile_ratio numeric:=1;
  pcs int:=0;
  sample_count int:=0;
  confidence text:='LOW';
  rows jsonb:='[]'::jsonb;
begin
  select * into u from public.rr_cb_units where id=p_cb_unit_id;
  if u.id is null then return jsonb_build_object('available',false,'reason','PROFILE_NOT_FOUND'); end if;

  if u.parent_unit_id is not null then
    select * into root from public.rr_cb_units where id=u.parent_unit_id;
  else
    root:=u;
  end if;

  select * into req from public.rr_cb_set_requirement_v1 where cb_unit_id=u.id;

  select a.* into am
  from public.rr_cb_art_assignments ca
  join public.rr_art_master a on a.id=ca.art_id
  where ca.cb_id=u.id
  order by ca.updated_at desc nulls last
  limit 1;

  if am.id is null then
    return jsonb_build_object(
      'available',false,'reason','ART_DUE',
      'cb_unit_id',u.id,'profile_label',public.rr_cb_profile_label_v1(u.id)
    );
  end if;

  if u.parent_unit_id is not null then
    profile_ratio:=coalesce(u.planning_share_pct,0)/100.0;
    if profile_ratio<=0 and coalesce(root.divided_weight,0)>0 then
      profile_ratio:=greatest(0,coalesce(u.divided_weight,0)/root.divided_weight);
    end if;
    if profile_ratio<=0 then
      profile_ratio:=1.0/nullif((select count(*) from public.rr_cb_units cc where cc.parent_unit_id=root.id),0);
    end if;
  else
    profile_ratio:=1;
  end if;

  select coalesce(sum(r.divided_weight),0)
  into root_total_weight
  from public.rr_cb_units r
  where r.purchase_id=u.purchase_id and r.parent_unit_id is null;

  for c in
    select id,col_no,colour_name,image_url,gsm
    from public.rr_cb_colours
    where cb_id=u.purchase_id
    order by col_no
  loop
    select coalesce(sum(r.quantity),0)
    into exact_weight
    from public.rr_cb_purchase_rolls r
    where r.cb_colour_id=c.id and r.division_id=root.id;

    if exact_weight>0 then
      base_weight:=exact_weight;
    else
      select coalesce(sum(r.quantity),0)
      into base_weight
      from public.rr_cb_purchase_rolls r
      where r.cb_colour_id=c.id and r.division_id is null;

      if base_weight>0 and root_total_weight>0 then
        base_weight:=base_weight*(coalesce(root.divided_weight,0)/root_total_weight);
      end if;
    end if;

    profile_weight:=round(coalesce(base_weight,0)*profile_ratio,3);
    if profile_weight<=0 then continue; end if;

    y:=public.rr_cutting_yield_estimate_v1(am.art_no,c.gsm,profile_weight);

    if coalesce((y->>'available')::boolean,false) then
      pcs:=pcs+coalesce((y->>'estimated_pcs')::int,0);
      sample_count:=sample_count+coalesce((y->>'sample_count')::int,0);
      if y->>'confidence'='HIGH' then confidence:='HIGH';
      elsif y->>'confidence'='MEDIUM' and confidence<>'HIGH' then confidence:='MEDIUM';
      end if;
    end if;

    rows:=rows||jsonb_build_array(jsonb_build_object(
      'cb_unit_id',u.id,
      'root_set_no',root.division_index,
      'profile_label',public.rr_cb_profile_label_v1(u.id),
      'planning_share_pct',round(profile_ratio*100,2),
      'art_no',am.art_no,
      'size_mix',coalesce(req.size_family,u.size_family),
      'sleeve_type',coalesce(req.sleeve_type,u.sleeve_type,'HALF'),
      'sleeve_finish',coalesce(req.sleeve_finish,u.sleeve_finish,'CUFF'),
      'border_pounchi',coalesce(req.border_pounchi,u.border_pounchi,'WITHOUT_BORDER_POUNCHI'),
      'colour_no',c.col_no,
      'colour_name',c.colour_name,
      'colour_image_url',c.image_url,
      'gsm',c.gsm,
      'fabric_weight_kg',profile_weight,
      'estimated_pcs',coalesce((y->>'estimated_pcs')::int,0),
      'yield_scope',y->>'scope',
      'confidence',y->>'confidence',
      'sample_count',coalesce((y->>'sample_count')::int,0)
    ));
  end loop;

  return jsonb_build_object(
    'available',pcs>0,
    'cb_unit_id',u.id,
    'root_set_no',root.division_index,
    'profile_label',public.rr_cb_profile_label_v1(u.id),
    'planning_share_pct',round(profile_ratio*100,2),
    'art_id',am.id,
    'art_no',am.art_no,
    'size_mix',coalesce(req.size_family,u.size_family),
    'sleeve_type',coalesce(req.sleeve_type,u.sleeve_type,'HALF'),
    'border_pounchi',coalesce(req.border_pounchi,u.border_pounchi,'WITHOUT_BORDER_POUNCHI'),
    'estimated_pcs',pcs,
    'sample_count',sample_count,
    'confidence',confidence,
    'rows',rows
  );
end $function$;

CREATE OR REPLACE FUNCTION public.rr_cb_material_estimate_v3(p_cb_id uuid, p_material_category_id uuid, p_set_numbers integer[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  u record;
  am record;
  cat record;
  py jsonb;
  row jsonb;
  v_pcs int:=0;
  v_qty numeric:=0;
  v_samples int:=0;
  v_conf text:='LOW';
  v_rows jsonb:='[]'::jsonb;
  v_gpp numeric;
  v_rule text;
  garment_key text;
begin
  select * into cat
  from public.rr_material_categories
  where id=p_material_category_id;

  for u in
    select cu.id,
           coalesce(parent.division_index,cu.division_index) root_set_no
    from public.rr_cb_units cu
    left join public.rr_cb_units parent on parent.id=cu.parent_unit_id
    where cu.purchase_id=p_cb_id
      and coalesce(cu.is_final,true)
      and coalesce(parent.division_index,cu.division_index)=any(coalesce(p_set_numbers,'{}'::int[]))
    order by coalesce(parent.division_index,cu.division_index),coalesce(cu.batch_index,0),cu.division_index
  loop
    select a.id,a.art_no,a.art_category_id,ac.category_code
    into am
    from public.rr_cb_art_assignments ca
    join public.rr_art_master a on a.id=ca.art_id
    left join public.rr_art_categories ac on ac.id=a.art_category_id
    where ca.cb_id=u.id
    limit 1;

    if am.id is null then continue; end if;

    garment_key:=case
      when lower(coalesce(am.category_code,''))='flat-polo' then 'FLAT COLLAR'
      when lower(coalesce(am.category_code,'')) in('crew-neck','drop-shoulder') then 'ROUND NECK'
      else upper(coalesce(am.category_code,''))
    end;

    v_gpp:=null;
    v_rule:=null;

    select grams_per_piece,rule_code
    into v_gpp,v_rule
    from public.rr_material_consumption_rule_v1 r
    where r.is_active
      and lower(replace(r.material_category_code,'&',''))=lower(replace(cat.category_code,'&',''))
      and upper(trim(r.garment_category))=upper(trim(garment_key))
    limit 1;

    if coalesce(v_gpp,0)<=0 then
      continue;
    end if;

    py:=public.rr_cb_profile_yield_v1(u.id);
    if not coalesce((py->>'available')::boolean,false) then continue; end if;

    v_pcs:=v_pcs+coalesce((py->>'estimated_pcs')::int,0);
    v_samples:=v_samples+coalesce((py->>'sample_count')::int,0);

    if py->>'confidence'='HIGH' then v_conf:='HIGH';
    elsif py->>'confidence'='MEDIUM' and v_conf<>'HIGH' then v_conf:='MEDIUM';
    end if;

    for row in
      select value from jsonb_array_elements(coalesce(py->'rows','[]'::jsonb))
    loop
      v_qty:=v_qty+((coalesce((row->>'estimated_pcs')::int,0)::numeric)*v_gpp/1000);

      v_rows:=v_rows||jsonb_build_array(
        row||jsonb_build_object(
          'set_no',u.root_set_no,
          'approx_material_kg',round(((coalesce((row->>'estimated_pcs')::int,0)::numeric)*v_gpp/1000),3),
          'consumption_grams_per_piece',v_gpp,
          'consumption_rule',v_rule
        )
      );
    end loop;
  end loop;

  return jsonb_build_object(
    'available',v_pcs>0,
    'material_estimate_available',v_pcs>0,
    'estimated_pcs',v_pcs,
    'estimated_material_qty',case when v_qty>0 then round(v_qty,3) else null end,
    'consumption_grams_per_piece',null,
    'consumption_rule','PROFILE_RULES',
    'sample_count',v_samples,
    'confidence',v_conf,
    'rows',v_rows,
    'multi_child_aware',true
  );
end $function$;

CREATE OR REPLACE FUNCTION public.rr_cb_auto_supplier_v1(p_cb_id uuid, p_requirement_type text, p_source_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_type text:=upper(trim(coalesce(p_requirement_type,'')));
  v_source_type text;
  v_ledger_id uuid;
  v_supplier_name text;
  v_mobile text;
  v_material_master_id uuid;
  v_vendor text;
begin
  v_source_type:=case v_type
    when 'STICKER' then 'STICKER_MASTER_V803'
    when 'METAL_ID' then 'METAL_ID_MASTER_V803'
    else 'MATERIAL_CATEGORY'
  end;

  select m.supplier_ledger_id,l.ledger_name,l.mobile
  into v_ledger_id,v_supplier_name,v_mobile
  from public.rr_material_source_supplier_map_v805_31 m
  left join public.rr_ledgers_v805 l on l.id=m.supplier_ledger_id
  where upper(m.source_type)=v_source_type
    and m.source_id=p_source_id::text
  order by m.updated_at desc
  limit 1;

  if v_ledger_id is null and v_type='MATERIAL' then
    select mc.material_master_id
    into v_material_master_id
    from public.rr_material_categories mc
    where mc.id=p_source_id;

    if v_material_master_id is not null then
      select mm.preferred_supplier_ledger_id,l.ledger_name,l.mobile
      into v_ledger_id,v_supplier_name,v_mobile
      from public.rr_material_master_v805 mm
      left join public.rr_ledgers_v805 l on l.id=mm.preferred_supplier_ledger_id
      where mm.id=v_material_master_id;
    end if;

    if v_supplier_name is null then
      select e.vendor_name
      into v_vendor
      from public.rr_cb_purchase_entries e
      where e.material_category_id=p_source_id
        and nullif(trim(coalesce(e.vendor_name,'')),'') is not null
      order by case when e.cb_id=p_cb_id then 0 else 1 end,e.updated_at desc
      limit 1;

      if v_vendor is not null then
        select s.supplier_name,s.mobile,map.supplier_ledger_id
        into v_supplier_name,v_mobile,v_ledger_id
        from public.rr_suppliers s
        left join public.rr_supplier_accounts_map_v9763 map
          on map.supplier_id=s.id and map.is_active
        where lower(trim(s.supplier_name))=lower(trim(v_vendor))
        order by s.created_at desc
        limit 1;

        v_supplier_name:=coalesce(v_supplier_name,v_vendor);
      end if;
    end if;
  end if;

  return jsonb_build_object(
    'supplier_ledger_id',v_ledger_id,
    'supplier_name',v_supplier_name,
    'supplier_mobile',v_mobile
  );
end $function$;

CREATE OR REPLACE FUNCTION public.rr_cb_upsert_derived_requirement_v1(p_cb_id uuid, p_cb_unit_id uuid, p_root_set_no integer, p_profile_label text, p_requirement_type text, p_source_id uuid, p_item_no text, p_item_name text, p_unit text, p_fulfilment_method text, p_basis text, p_basis_pcs numeric, p_qty_per_piece numeric, p_required_qty numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
begin
  select * into ex
  from public.rr_cb_derived_requirement_v1
  where cb_unit_id=p_cb_unit_id
    and requirement_type=upper(p_requirement_type)
    and source_id=p_source_id
  for update;

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

    update public.rr_cb_derived_requirement_v1
    set root_set_no=p_root_set_no,
        profile_label=p_profile_label,
        item_no=p_item_no,
        item_name=p_item_name,
        unit=upper(coalesce(p_unit,'PCS')),
        fulfilment_method=upper(coalesce(p_fulfilment_method,'PURCHASE')),
        basis=upper(p_basis),
        basis_pcs=coalesce(p_basis_pcs,0),
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
      item_no,item_name,unit,fulfilment_method,basis,basis_pcs,qty_per_piece,required_qty,
      revision_no,status,supplier_ledger_id,supplier_name,supplier_mobile,active
    ) values(
      p_cb_id,p_cb_unit_id,p_root_set_no,p_profile_label,upper(p_requirement_type),p_source_id,
      p_item_no,p_item_name,upper(coalesce(p_unit,'PCS')),upper(coalesce(p_fulfilment_method,'PURCHASE')),
      upper(p_basis),coalesce(p_basis_pcs,0),coalesce(p_qty_per_piece,1),coalesce(p_required_qty,0),
      1,'READY',sid,sname,smobile,true
    ) returning id into out_id;
  end if;

  return out_id;
end $function$;

CREATE OR REPLACE FUNCTION public.rr_cb_refresh_derived_requirements_core_v1(p_cb_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  item_no text;
  item_name text;
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

    select coalesce(sum(qty),0)
    into basis_pcs
    from (
      select coalesce(nullif(actual_pcs,0),planned_pcs,0)::numeric qty
      from public.rr_cutting_lots_v3
      where cb_unit_id=u.id
      union all
      select coalesce(nullif(actual_pcs,0),planned_pcs,0)::numeric qty
      from public.rr_production_lots
      where cb_unit_id=u.id
    ) q;

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

  -- Keep only currently derived automatic Collar/Cuff and Rib purchase rows active.
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
end $function$;

CREATE OR REPLACE FUNCTION public.rr_cb_refresh_derived_requirements_v1(p_cb_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.rr_cb_department_assert_authority_v600();
  return public.rr_cb_refresh_derived_requirements_core_v1(p_cb_id);
end $function$;

CREATE OR REPLACE FUNCTION public.rr_cb_requirement_context_v1(p_cb_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

CREATE OR REPLACE FUNCTION public.rr_cb_requirement_whatsapp_send_v1(p_cb_id uuid, p_requirement_type text, p_source_id uuid, p_supplier_ledger_id uuid DEFAULT NULL::uuid, p_supplier_name text DEFAULT NULL::text, p_supplier_mobile text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    max(r.item_no),
    max(r.item_name),
    max(r.unit),
    max(r.fulfilment_method),
    max(r.revision_no),
    sum(r.required_qty),
    case when bool_or(r.basis='CUTTING_ACTUAL') then 'CUTTING_ACTUAL' else 'YIELD' end,
    min(r.supplier_ledger_id::text)::uuid,
    max(r.supplier_name),
    max(r.supplier_mobile)
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
      else 'REDZED PURCHASE ORDER / REQUIREMENT'
    end;
  elsif coalesce(v_last_sent_revision,0)<v_revision then
    v_template_kind:='REVISED';
    v_header:=case when v_fulfil='MAKING'
      then 'REVISED MAKING REQUIREMENT'
      else 'REVISED PURCHASE ORDER / REQUIREMENT'
    end;
  else
    v_template_kind:='RESEND';
    v_header:=case when v_fulfil='MAKING'
      then 'REMINDER · REQUIREMENT STILL PENDING · RESENDING MAKING REQUIREMENT'
      else 'REMINDER · REQUIREMENT STILL PENDING · RESENDING PURCHASE ORDER'
    end;
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
    v_lines:=v_lines||E'
• '||x.profile_label||' · '||
      trim(to_char(x.required_qty,'FM999999990.###'))||' '||v_unit||
      ' · '||case when x.basis='CUTTING_ACTUAL' then 'Actual Cutting ' else 'Yield ' end||
      trim(to_char(x.basis_pcs,'FM999999990.###'))||' pcs';
  end loop;

  v_message:=v_header||
    E'
CB: '||v_cb_no||
    E'
Item: '||coalesce(v_item_no||' · ','')||v_item_name||
    E'
Mode: '||coalesce(v_fulfil,'PURCHASE')||
    E'
Basis: '||case when v_basis='CUTTING_ACTUAL' then 'CUTTING ACTUAL' else 'YIELD SHEET' end||
    E'
Total Required: '||trim(to_char(v_total_qty,'FM999999990.###'))||' '||v_unit||
    v_lines||
    E'
Revision: '||v_revision||
    case when v_template_kind='RESEND' then E'
Resend No: '||v_sequence else '' end||
    E'

Please confirm availability / making status.';

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
end $function$;

CREATE OR REPLACE FUNCTION public.rr_cb_requirement_send_v1(p_cb_id uuid, p_requirement_type text, p_source_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  return public.rr_cb_requirement_whatsapp_send_v1(
    p_cb_id,p_requirement_type,p_source_id,null,null,null
  );
end $function$;

CREATE OR REPLACE FUNCTION public.rr_cb_requirement_send_prepare_v1(p_cb_id uuid, p_requirement_type text, p_source_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d jsonb;
begin
  d:=public.rr_cb_requirement_whatsapp_send_v1(
    p_cb_id,p_requirement_type,p_source_id,null,null,null
  );
  return d||jsonb_build_object('message_text',d->>'message');
end $function$;

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
end $function$;

CREATE OR REPLACE FUNCTION public.rr_cb_select_art_v1(p_cb_unit_id uuid, p_art_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  u public.rr_cb_units%rowtype;
  a public.rr_cb_art_assignments%rowtype;
  out jsonb;
  changed boolean:=false;
begin
  perform public.rr_cb_department_assert_authority_v600();

  select * into u from public.rr_cb_units where id=p_cb_unit_id;
  if u.id is null then raise exception 'CB child not found.'; end if;

  if public.rr_cb_unit_has_final_cutting_v1(p_cb_unit_id) then
    raise exception 'CB Set Art Combo is frozen after Cutting Lot No + Pieces save.';
  end if;

  select * into a from public.rr_cb_art_assignments where cb_id=p_cb_unit_id for update;
  changed:=a.id is not null and a.art_id is distinct from p_art_id;

  if a.id is null then
    insert into public.rr_cb_art_assignments(
      cb_id,art_id,status,
      print_not_applicable,sticker_not_applicable,metal_id_not_applicable,
      print_due,sticker_due,metal_id_due,updated_at
    ) values(
      p_cb_unit_id,p_art_id,'material_check',
      false,false,false,true,true,true,now()
    ) returning * into a;
  elsif changed then
    update public.rr_cb_art_assignments
    set art_id=p_art_id,status='material_check',
        print_not_applicable=false,sticker_not_applicable=false,metal_id_not_applicable=false,
        print_due=true,sticker_due=true,metal_id_due=true,updated_at=now()
    where id=a.id
    returning * into a;

    delete from public.rr_cb_print_assignments where assignment_id=a.id;
    delete from public.rr_cb_sticker_assignments where assignment_id=a.id;
    delete from public.rr_cb_metal_id_assignments_v801 where assignment_id=a.id;
  else
    update public.rr_cb_art_assignments
    set art_id=p_art_id,updated_at=now()
    where id=a.id;
  end if;

  out:=public.rr_sync_cb_mapping_from_art_v3(p_cb_unit_id,p_art_id);

  perform public.rr_cb_refresh_derived_requirements_core_v1(u.purchase_id);

  return out||jsonb_build_object(
    'assignment_preserved',not changed,
    'combo_reset_to_due',changed,
    'locked',false
  );
end $function$;

CREATE OR REPLACE FUNCTION public.rr_pm_save_decision_bundle_v804(p_cb_unit_id uuid, p_art_id uuid, p_print_mode text DEFAULT 'NA'::text, p_print_ids uuid[] DEFAULT '{}'::uuid[], p_sticker_mode text DEFAULT 'NA'::text, p_sticker_master_ids uuid[] DEFAULT '{}'::uuid[], p_metal_id_mode text DEFAULT 'NA'::text, p_metal_id_master_ids uuid[] DEFAULT '{}'::uuid[], p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '30s'
AS $function$
declare
  v_sticker_instruction_ids uuid[]:='{}'::uuid[];
  v_metal_instruction_ids uuid[]:='{}'::uuid[];
  v_id uuid;
  v_result jsonb;
  v_mode text:=upper(trim(coalesce(p_data_mode,'TEST')));
  v_cb_id uuid;
  i integer:=0;
begin
  if not public.rr_is_owner_or_admin() then raise exception 'Owner/Admin permission required.'; end if;
  if p_cb_unit_id is null then raise exception 'CB/D required.'; end if;

  perform pg_advisory_xact_lock(hashtextextended('RR_ART_DECISION:'||p_cb_unit_id::text,611));

  if public.rr_cb_unit_has_final_cutting_v1(p_cb_unit_id) then
    raise exception 'CB Set Art Combo is frozen after Cutting Lot No + Pieces save.';
  end if;

  if v_mode not in('TEST','REAL') then raise exception 'Data Mode must be TEST or REAL.'; end if;

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

  perform public.rr_cb_reconcile_department_states_v618();

  select purchase_id into v_cb_id
  from public.rr_cb_units
  where id=p_cb_unit_id;

  if v_cb_id is not null then
    perform public.rr_cb_refresh_derived_requirements_core_v1(v_cb_id);
  end if;

  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'sticker_master_ids',coalesce(p_sticker_master_ids,'{}'::uuid[]),
    'metal_id_master_ids',coalesce(p_metal_id_master_ids,'{}'::uuid[]),
    'data_mode',v_mode,
    'combo_authority','CB_SET_PROFILE',
    'frozen_after_cutting_save',true,
    'derived_requirements_refreshed',v_cb_id is not null
  );
end $function$;

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

revoke all on function public.rr_cb_copy_combo_v1(uuid,uuid) from public,anon,authenticated;
revoke all on function public.rr_cb_auto_supplier_v1(uuid,text,uuid) from public,anon,authenticated;
revoke all on function public.rr_cb_upsert_derived_requirement_v1(uuid,uuid,integer,text,text,uuid,text,text,text,text,text,numeric,numeric,numeric) from public,anon,authenticated;
revoke all on function public.rr_cb_refresh_derived_requirements_core_v1(uuid) from public,anon,authenticated;
revoke all on function public.rr_cb_cutting_actual_requirement_refresh_trg_v1() from public,anon,authenticated;

revoke all on function public.rr_cb_root_set_no_v1(uuid) from public,anon;
revoke all on function public.rr_cb_profile_label_v1(uuid) from public,anon;
revoke all on function public.rr_cb_unit_has_final_cutting_v1(uuid) from public,anon;
revoke all on function public.rr_cb_category_defaults_get_v1() from public,anon;
revoke all on function public.rr_cb_category_defaults_set_v1(uuid,text,text,text,text) from public,anon;
revoke all on function public.rr_cb_set_lot_plan_v1(uuid,text,integer,jsonb) from public,anon;
revoke all on function public.rr_cb_art_material_plan_set_v1(uuid,text) from public,anon;
revoke all on function public.rr_cb_plan_context_v1(uuid) from public,anon;
revoke all on function public.rr_cb_set_requirement_sync_v6(uuid,jsonb) from public,anon;
revoke all on function public.rr_cb_material_mapping_sync_v6(uuid,jsonb) from public,anon;
revoke all on function public.rr_cb_profile_yield_v1(uuid) from public,anon;
revoke all on function public.rr_cb_material_estimate_v3(uuid,uuid,integer[]) from public,anon;
revoke all on function public.rr_cb_refresh_derived_requirements_v1(uuid) from public,anon;
revoke all on function public.rr_cb_requirement_context_v1(uuid) from public,anon;
revoke all on function public.rr_cb_requirement_whatsapp_send_v1(uuid,text,uuid,uuid,text,text) from public,anon;
revoke all on function public.rr_cb_requirement_send_v1(uuid,text,uuid) from public,anon;
revoke all on function public.rr_cb_requirement_send_prepare_v1(uuid,text,uuid) from public,anon;
revoke all on function public.rr_cb_requirement_supplier_set_v1(uuid,text,uuid,uuid) from public,anon;

grant execute on function public.rr_cb_root_set_no_v1(uuid) to authenticated;
grant execute on function public.rr_cb_profile_label_v1(uuid) to authenticated;
grant execute on function public.rr_cb_unit_has_final_cutting_v1(uuid) to authenticated;
grant execute on function public.rr_cb_category_defaults_get_v1() to authenticated;
grant execute on function public.rr_cb_category_defaults_set_v1(uuid,text,text,text,text) to authenticated;
grant execute on function public.rr_cb_set_lot_plan_v1(uuid,text,integer,jsonb) to authenticated;
grant execute on function public.rr_cb_art_material_plan_set_v1(uuid,text) to authenticated;
grant execute on function public.rr_cb_plan_context_v1(uuid) to authenticated;
grant execute on function public.rr_cb_set_requirement_sync_v6(uuid,jsonb) to authenticated;
grant execute on function public.rr_cb_material_mapping_sync_v6(uuid,jsonb) to authenticated;
grant execute on function public.rr_cb_profile_yield_v1(uuid) to authenticated;
grant execute on function public.rr_cb_material_estimate_v3(uuid,uuid,integer[]) to authenticated;
grant execute on function public.rr_cb_refresh_derived_requirements_v1(uuid) to authenticated;
grant execute on function public.rr_cb_requirement_context_v1(uuid) to authenticated;
grant execute on function public.rr_cb_requirement_whatsapp_send_v1(uuid,text,uuid,uuid,text,text) to authenticated;
grant execute on function public.rr_cb_requirement_send_v1(uuid,text,uuid) to authenticated;
grant execute on function public.rr_cb_requirement_send_prepare_v1(uuid,text,uuid) to authenticated;
grant execute on function public.rr_cb_requirement_supplier_set_v1(uuid,text,uuid,uuid) to authenticated;
