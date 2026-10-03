-- TEST71: CB Art & Material planning, reversible Single/Multi profiles, category defaults and profile-aware Yield.
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

revoke all on function public.rr_cb_category_defaults_get_v1() from public,anon;
revoke all on function public.rr_cb_category_defaults_set_v1(uuid,text,text,text,text) from public,anon;
revoke all on function public.rr_cb_root_set_no_v1(uuid) from public,anon;
revoke all on function public.rr_cb_profile_label_v1(uuid) from public,anon;
revoke all on function public.rr_cb_unit_has_final_cutting_v1(uuid) from public,anon;
revoke all on function public.rr_cb_copy_combo_v1(uuid,uuid) from public,anon,authenticated;
revoke all on function public.rr_cb_set_lot_plan_v1(uuid,text,integer,jsonb) from public,anon;
revoke all on function public.rr_cb_art_material_plan_set_v1(uuid,text) from public,anon;
revoke all on function public.rr_cb_plan_context_v1(uuid) from public,anon;
revoke all on function public.rr_cb_set_requirement_sync_v6(uuid,jsonb) from public,anon;
revoke all on function public.rr_cb_material_mapping_sync_v6(uuid,jsonb) from public,anon;
revoke all on function public.rr_cb_profile_yield_v1(uuid) from public,anon;
revoke all on function public.rr_cb_material_estimate_v3(uuid,uuid,integer[]) from public,anon;

grant execute on function public.rr_cb_category_defaults_get_v1() to authenticated;
grant execute on function public.rr_cb_category_defaults_set_v1(uuid,text,text,text,text) to authenticated;
grant execute on function public.rr_cb_root_set_no_v1(uuid) to authenticated;
grant execute on function public.rr_cb_profile_label_v1(uuid) to authenticated;
grant execute on function public.rr_cb_unit_has_final_cutting_v1(uuid) to authenticated;
grant execute on function public.rr_cb_set_lot_plan_v1(uuid,text,integer,jsonb) to authenticated;
grant execute on function public.rr_cb_art_material_plan_set_v1(uuid,text) to authenticated;
grant execute on function public.rr_cb_plan_context_v1(uuid) to authenticated;
grant execute on function public.rr_cb_set_requirement_sync_v6(uuid,jsonb) to authenticated;
grant execute on function public.rr_cb_material_mapping_sync_v6(uuid,jsonb) to authenticated;
grant execute on function public.rr_cb_profile_yield_v1(uuid) to authenticated;
grant execute on function public.rr_cb_material_estimate_v3(uuid,uuid,integer[]) to authenticated;
