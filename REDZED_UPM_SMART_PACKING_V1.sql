-- REDZED SMART PACKING V1
-- Additive only. Existing Cutting / UPM Submit / Alter / Repair / Damage / Remake / Reversal logic is untouched.

create extension if not exists pgcrypto;

create table if not exists public.rr_pack_plans (
  id uuid primary key default gen_random_uuid(),
  lot_no text not null,
  department_code text not null default 'PACKING',
  carton_capacity integer not null default 18 check (carton_capacity = 18),
  total_qty integer not null check (total_qty >= 0),
  colour_count integer not null check (colour_count > 0),
  size_count integer not null check (size_count > 0),
  fresh_box_count integer not null default 0,
  assortment_box_count integer not null default 0,
  mix_box_count integer not null default 0,
  total_box_count integer not null default 0,
  status text not null default 'DRAFT' check (status in ('DRAFT','SUBMITTED','CANCELLED')),
  source_matrix jsonb not null,
  algorithm_version text not null default 'SIZE_FIRST_18_V1',
  generated_by uuid default auth.uid(),
  generated_at timestamptz not null default now(),
  submitted_by uuid,
  submitted_at timestamptz,
  unique (lot_no, status) deferrable initially immediate
);

create table if not exists public.rr_pack_plan_boxes (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.rr_pack_plans(id) on delete cascade,
  box_from integer not null,
  box_to integer not null,
  pack_mark text not null check (pack_mark in ('F','ASST','MIX')),
  box_count integer not null check (box_count > 0),
  pcs_per_box integer not null check (pcs_per_box > 0),
  size_composition jsonb not null,
  box_total_qty integer not null check (box_total_qty > 0),
  display_order integer not null,
  created_at timestamptz not null default now(),
  unique(plan_id, display_order)
);

create table if not exists public.rr_pack_plan_box_cells (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.rr_pack_plans(id) on delete cascade,
  box_no integer not null,
  pack_mark text not null check (pack_mark in ('F','ASST','MIX')),
  colour_code text not null,
  size_code text not null,
  qty integer not null check (qty > 0),
  created_at timestamptz not null default now(),
  unique(plan_id, box_no, colour_code, size_code)
);

create index if not exists rr_pack_plans_lot_idx on public.rr_pack_plans(lot_no, generated_at desc);
create index if not exists rr_pack_cells_plan_box_idx on public.rr_pack_plan_box_cells(plan_id, box_no);

alter table public.rr_pack_plans enable row level security;
alter table public.rr_pack_plan_boxes enable row level security;
alter table public.rr_pack_plan_box_cells enable row level security;

-- Uses your existing authenticated user/role model. Tighten these policies to your final role table when ready.
drop policy if exists rr_pack_plans_read on public.rr_pack_plans;
create policy rr_pack_plans_read on public.rr_pack_plans for select to authenticated using (true);
drop policy if exists rr_pack_plans_write on public.rr_pack_plans;
create policy rr_pack_plans_write on public.rr_pack_plans for all to authenticated using (true) with check (true);
drop policy if exists rr_pack_boxes_read on public.rr_pack_plan_boxes;
create policy rr_pack_boxes_read on public.rr_pack_plan_boxes for select to authenticated using (true);
drop policy if exists rr_pack_boxes_write on public.rr_pack_plan_boxes;
create policy rr_pack_boxes_write on public.rr_pack_plan_boxes for all to authenticated using (true) with check (true);
drop policy if exists rr_pack_cells_read on public.rr_pack_plan_box_cells;
create policy rr_pack_cells_read on public.rr_pack_plan_box_cells for select to authenticated using (true);
drop policy if exists rr_pack_cells_write on public.rr_pack_plan_box_cells;
create policy rr_pack_cells_write on public.rr_pack_plan_box_cells for all to authenticated using (true) with check (true);

-- Optional adapter. It dynamically reads common UPM actual tables if present.
create or replace function public.rr_get_packable_matrix_v1(p_lot_no text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_sql text;
begin
  if to_regclass('public.rr_lot_process_actuals') is not null then
    v_sql := $q$
      select coalesce(jsonb_agg(jsonb_build_object(
        'colour_code', coalesce(colour_name, colour_id::text, 'UNKNOWN'),
        'size_code', coalesce(size_code, 'ALL'),
        'qty', greatest(0, floor(coalesce(out_pcs, in_pcs, 0)))::int
      ) order by coalesce(colour_name, colour_id::text), coalesce(size_code,'ALL')), '[]'::jsonb)
      from public.rr_lot_process_actuals
      where lot_no = $1 and upper(process_code) in ('PRESS','PACKING') and coalesce(out_pcs,in_pcs,0) > 0
    $q$;
    execute v_sql into v_result using p_lot_no;
  elsif to_regclass('public.rr_production_entries') is not null then
    v_sql := $q$
      select coalesce(jsonb_agg(jsonb_build_object(
        'colour_code', coalesce(colour_name, colour_code, 'UNKNOWN'),
        'size_code', coalesce(size_code, size_name, 'ALL'),
        'qty', greatest(0, floor(quantity))::int
      ) order by coalesce(colour_name, colour_code), coalesce(size_code,size_name,'ALL')), '[]'::jsonb)
      from public.rr_production_entries
      where lot_no = $1 and upper(department_code) = 'PRESS' and upper(entry_type) = 'GOOD' and quantity > 0
    $q$;
    execute v_sql into v_result using p_lot_no;
  else
    v_result := '[]'::jsonb;
  end if;
  return coalesce(v_result, '[]'::jsonb);
end;
$$;

grant execute on function public.rr_get_packable_matrix_v1(text) to authenticated;

create or replace function public.rr_generate_smart_pack_plan_v1(
  p_lot_no text,
  p_matrix jsonb,
  p_carton_capacity integer default 18
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan uuid;
  v_total int;
  v_colours text[];
  v_sizes text[];
  v_colour_count int;
  v_size_count int;
  v_fresh int;
  v_full int;
  v_rem int;
  v_standard_before_mix int;
  v_asst int;
  v_mix int;
  v_box int := 1;
  v_i int;
  v_s text;
  v_c text;
  v_need int;
  v_pick text;
  v_qty int;
  v_comp jsonb;
  v_mix_qty int;
begin
  if p_carton_capacity <> 18 then raise exception 'Packing rule locked: carton capacity must be 18 PCS'; end if;
  if p_matrix is null or jsonb_typeof(p_matrix) <> 'array' or jsonb_array_length(p_matrix)=0 then raise exception 'Colour-size matrix is required'; end if;

  create temporary table tmp_pack_remaining(colour_code text, size_code text, qty int, primary key(colour_code,size_code)) on commit drop;
  insert into tmp_pack_remaining
  select trim(x->>'colour_code'), trim(x->>'size_code'), sum(greatest(0,(x->>'qty')::int))
  from jsonb_array_elements(p_matrix) x
  where coalesce(trim(x->>'colour_code'),'')<>'' and coalesce(trim(x->>'size_code'),'')<>''
  group by 1,2;

  select array_agg(distinct colour_code order by colour_code), array_agg(distinct size_code order by size_code), sum(qty)
  into v_colours, v_sizes, v_total from tmp_pack_remaining;
  v_colour_count := cardinality(v_colours); v_size_count := cardinality(v_sizes);
  if v_colour_count < 1 or v_size_count < 1 then raise exception 'Invalid colour-size matrix'; end if;
  if v_colour_count * v_size_count <> (select count(*) from tmp_pack_remaining) then raise exception 'Every colour must contain every size cell, including zero qty'; end if;
  if p_carton_capacity % v_size_count <> 0 then raise exception '18 PCS cannot be divided equally across % sizes', v_size_count; end if;

  select min(qty) into v_fresh from tmp_pack_remaining;
  v_full := v_total / 18; v_rem := v_total % 18;
  if v_rem > 0 and v_rem <= 9 and v_full > 0 then
    v_standard_before_mix := v_full - 1; v_mix := 1;
  else
    v_standard_before_mix := v_full; v_mix := case when v_rem>0 then 1 else 0 end;
  end if;
  v_fresh := least(v_fresh, v_standard_before_mix);
  v_asst := greatest(0, v_standard_before_mix - v_fresh);

  delete from rr_pack_plans where lot_no=p_lot_no and status='DRAFT';
  insert into rr_pack_plans(lot_no,total_qty,colour_count,size_count,fresh_box_count,assortment_box_count,mix_box_count,total_box_count,source_matrix)
  values(p_lot_no,v_total,v_colour_count,v_size_count,v_fresh,v_asst,v_mix,v_standard_before_mix+v_mix,p_matrix) returning id into v_plan;

  -- Fresh boxes: one of every colour-size cell. This requires 6 colours x 3 sizes for the locked 18 PCS fresh pattern.
  if v_fresh > 0 then
    if v_colour_count * v_size_count <> 18 then raise exception 'Fresh rule requires Colours × Sizes = 18'; end if;
    for v_i in 1..v_fresh loop
      foreach v_c in array v_colours loop foreach v_s in array v_sizes loop
        insert into rr_pack_plan_box_cells(plan_id,box_no,pack_mark,colour_code,size_code,qty) values(v_plan,v_box,'F',v_c,v_s,1);
        update tmp_pack_remaining set qty=qty-1 where colour_code=v_c and size_code=v_s;
      end loop; end loop;
      v_box := v_box+1;
    end loop;
    v_comp := (select jsonb_object_agg(size_code, comp) from (
      select size_code, string_agg(colour_code, ', ' order by colour_code) comp from tmp_pack_remaining cross join unnest(v_sizes) size_code where false group by size_code
    )z);
    -- Summary row uses a fixed compact composition built from original colours.
    v_comp := (select jsonb_object_agg(s, array_to_string(v_colours, ', ')) from unnest(v_sizes) s);
    insert into rr_pack_plan_boxes(plan_id,box_from,box_to,pack_mark,box_count,pcs_per_box,size_composition,box_total_qty,display_order)
    values(v_plan,1,v_fresh,'F',v_fresh,18,v_comp,v_fresh*18,1);
  end if;

  -- Assortment boxes: SIZE-FIRST. Every box has equal target pieces per size; maximise distinct colours, then duplicate highest balance.
  for v_i in 1..v_asst loop
    foreach v_s in array v_sizes loop
      v_need := 18 / v_size_count;
      -- First pass: maximum distinct colours, 1 PCS each.
      while v_need > 0 loop
        select r.colour_code into v_pick
        from tmp_pack_remaining r
        where r.size_code=v_s and r.qty>0
          and not exists(select 1 from rr_pack_plan_box_cells c where c.plan_id=v_plan and c.box_no=v_box and c.size_code=v_s and c.colour_code=r.colour_code)
        order by r.qty desc, r.colour_code
        limit 1;
        exit when v_pick is null;
        insert into rr_pack_plan_box_cells(plan_id,box_no,pack_mark,colour_code,size_code,qty) values(v_plan,v_box,'ASST',v_pick,v_s,1);
        update tmp_pack_remaining set qty=qty-1 where colour_code=v_pick and size_code=v_s;
        v_need:=v_need-1; v_pick:=null;
      end loop;
      -- Second pass: duplicates from highest remaining colour.
      while v_need > 0 loop
        select colour_code into v_pick from tmp_pack_remaining where size_code=v_s and qty>0 order by qty desc, colour_code limit 1;
        if v_pick is null then raise exception 'Unable to fill box % size % to 18 PCS',v_box,v_s; end if;
        insert into rr_pack_plan_box_cells(plan_id,box_no,pack_mark,colour_code,size_code,qty)
        values(v_plan,v_box,'ASST',v_pick,v_s,1)
        on conflict(plan_id,box_no,colour_code,size_code) do update set qty=rr_pack_plan_box_cells.qty+1;
        update tmp_pack_remaining set qty=qty-1 where colour_code=v_pick and size_code=v_s;
        v_need:=v_need-1;
      end loop;
    end loop;
    v_comp := (select jsonb_object_agg(size_code, composition) from (
      select size_code,string_agg(case when qty=1 then colour_code else colour_code||'×'||qty end, ', ' order by colour_code) composition
      from rr_pack_plan_box_cells where plan_id=v_plan and box_no=v_box group by size_code
    )x);
    insert into rr_pack_plan_boxes(plan_id,box_from,box_to,pack_mark,box_count,pcs_per_box,size_composition,box_total_qty,display_order)
    values(v_plan,v_box,v_box,'ASST',1,18,v_comp,18,v_box-v_fresh+1);
    v_box:=v_box+1;
  end loop;

  -- MIX: consume every remaining piece. For <=9 remainder this is the last standard 18 plus remainder, e.g. 26 PCS.
  if v_mix=1 then
    if v_rem>0 and v_rem<=9 then v_mix_qty:=18+v_rem; else v_mix_qty:=v_rem; end if;
    foreach v_s in array v_sizes loop
      foreach v_c in array v_colours loop
        select qty into v_qty from tmp_pack_remaining where colour_code=v_c and size_code=v_s;
        if v_qty>0 then
          insert into rr_pack_plan_box_cells(plan_id,box_no,pack_mark,colour_code,size_code,qty) values(v_plan,v_box,'MIX',v_c,v_s,v_qty);
          update tmp_pack_remaining set qty=0 where colour_code=v_c and size_code=v_s;
        end if;
      end loop;
    end loop;
    v_comp := (select jsonb_object_agg(size_code, composition) from (
      select size_code,string_agg(case when qty=1 then colour_code else colour_code||'×'||qty end, ', ' order by colour_code) composition
      from rr_pack_plan_box_cells where plan_id=v_plan and box_no=v_box group by size_code
    )x);
    insert into rr_pack_plan_boxes(plan_id,box_from,box_to,pack_mark,box_count,pcs_per_box,size_composition,box_total_qty,display_order)
    values(v_plan,v_box,v_box,'MIX',1,v_mix_qty,v_comp,v_mix_qty,100000);
  end if;

  if exists(select 1 from tmp_pack_remaining where qty<>0) then raise exception 'Algorithm validation failed: unpacked balance remains'; end if;
  if (select coalesce(sum(qty),0) from rr_pack_plan_box_cells where plan_id=v_plan)<>v_total then raise exception 'Algorithm validation failed: packed total mismatch'; end if;
  return v_plan;
end;
$$;

grant execute on function public.rr_generate_smart_pack_plan_v1(text,jsonb,integer) to authenticated;

create or replace function public.rr_submit_smart_pack_plan_v1(p_plan_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_plan rr_pack_plans%rowtype; v_cells int; begin
  select * into v_plan from rr_pack_plans where id=p_plan_id for update;
  if not found then raise exception 'Packing plan not found'; end if;
  if v_plan.status<>'DRAFT' then raise exception 'Packing plan already submitted/cancelled'; end if;
  select coalesce(sum(qty),0) into v_cells from rr_pack_plan_box_cells where plan_id=p_plan_id;
  if v_cells<>v_plan.total_qty then raise exception 'Submit blocked: packed quantity mismatch'; end if;
  update rr_pack_plans set status='SUBMITTED',submitted_by=auth.uid(),submitted_at=now() where id=p_plan_id;
  return jsonb_build_object('plan_id',p_plan_id,'lot_no',v_plan.lot_no,'total_qty',v_plan.total_qty,'total_boxes',v_plan.total_box_count,'status','SUBMITTED');
end $$;
grant execute on function public.rr_submit_smart_pack_plan_v1(uuid) to authenticated;

create or replace view public.rr_pack_plan_worker_v as
select p.id plan_id,p.lot_no,p.status,p.total_qty,p.fresh_box_count,p.assortment_box_count,p.mix_box_count,p.total_box_count,
 b.box_from,b.box_to,b.pack_mark,b.box_count,b.pcs_per_box,b.size_composition,b.box_total_qty,b.display_order
from rr_pack_plans p join rr_pack_plan_boxes b on b.plan_id=p.id;
grant select on public.rr_pack_plan_worker_v to authenticated;
