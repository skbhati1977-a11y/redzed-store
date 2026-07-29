-- REDZED ERP — Universal Production Submit V2
-- Additive migration. Run after REDZED_ALTER_REMAKE_DAMAGE_V1.sql.
-- Purpose:
-- 1) Locked user category + department assignment
-- 2) Department Head controls actual rate
-- 3) No manual production quantity / reject / remake entry in Production Submit
-- 4) Submit quantity is server-calculated from Cutting Qty and Alter/Remake/Damage
-- 5) Printer and Stitching require live work evidence
-- 6) Approved quantity is posted through existing rr_upm_post_entry_v1 as GOOD

begin;
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- LOCKED USER ASSIGNMENT MASTER
-- Owner/Admin should maintain this table from User Master UI.
-- ---------------------------------------------------------------------------
create table if not exists public.rr_user_assignments_v2 (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  user_category text not null check (user_category in (
    'OWNER','ADMIN','WORKER','DEPARTMENT_HEAD','CUTTING_MASTER','LINE_MAN','MANAGER'
  )),
  department_code text,
  department_name text,
  line_man_id uuid references auth.users(id),
  line_man_name text,
  cutting_master_id uuid references auth.users(id),
  cutting_master_name text,
  is_active boolean not null default true,
  locked_at timestamptz not null default now(),
  locked_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  constraint rr_user_assignment_department_required check (
    user_category in ('OWNER','ADMIN','CUTTING_MASTER','MANAGER')
    or nullif(trim(department_code),'') is not null
  )
);

create index if not exists rr_user_assignments_v2_category_idx
  on public.rr_user_assignments_v2(user_category, department_code)
  where is_active;

alter table public.rr_user_assignments_v2 enable row level security;

drop policy if exists rr_user_assignment_self_read_v2 on public.rr_user_assignments_v2;
create policy rr_user_assignment_self_read_v2
on public.rr_user_assignments_v2 for select
to authenticated
using (user_id = auth.uid() or public.rr_up_is_owner_admin_v1());

drop policy if exists rr_user_assignment_admin_write_v2 on public.rr_user_assignments_v2;
create policy rr_user_assignment_admin_write_v2
on public.rr_user_assignments_v2 for all
to authenticated
using (public.rr_up_is_owner_admin_v1())
with check (public.rr_up_is_owner_admin_v1());

create or replace function public.rr_up_user_context_v2()
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select coalesce(
    (
      select jsonb_build_object(
        'user_id', u.user_id,
        'display_name', u.display_name,
        'user_category', u.user_category,
        'department_code', u.department_code,
        'department_name', u.department_name,
        'line_man_id', u.line_man_id,
        'line_man_name', u.line_man_name,
        'cutting_master_id', u.cutting_master_id,
        'cutting_master_name', u.cutting_master_name,
        'is_active', u.is_active
      )
      from public.rr_user_assignments_v2 u
      where u.user_id=auth.uid() and u.is_active
    ),
    jsonb_build_object(
      'user_id', auth.uid(),
      'display_name', coalesce(auth.jwt()->'user_metadata'->>'name', auth.jwt()->>'email'),
      'user_category', upper(coalesce(
        auth.jwt()->'app_metadata'->>'role',
        auth.jwt()->'user_metadata'->>'role',
        'WORKER'
      )),
      'department_code', coalesce(
        auth.jwt()->'app_metadata'->>'department_code',
        auth.jwt()->'user_metadata'->>'department_code'
      ),
      'department_name', coalesce(
        auth.jwt()->'app_metadata'->>'department_name',
        auth.jwt()->'user_metadata'->>'department_name'
      ),
      'is_active', true
    )
  );
$$;

grant execute on function public.rr_up_user_context_v2() to authenticated;

create or replace function public.rr_up_category_v2()
returns text
language sql stable security definer set search_path=public
as $$ select upper(coalesce(public.rr_up_user_context_v2()->>'user_category','WORKER')); $$;

create or replace function public.rr_up_is_department_head_v2(p_department_code text default null)
returns boolean
language sql stable security definer set search_path=public
as $$
  select
    public.rr_up_category_v2() in ('OWNER','ADMIN')
    or (
      public.rr_up_category_v2()='DEPARTMENT_HEAD'
      and (p_department_code is null or upper(coalesce(public.rr_up_user_context_v2()->>'department_code',''))=upper(p_department_code))
    );
$$;

-- ---------------------------------------------------------------------------
-- ACTUAL RATE — ONE RATE PER LOT + DEPARTMENT, CONTROLLED BY DEPARTMENT HEAD
-- ---------------------------------------------------------------------------
create table if not exists public.rr_upm_department_rates_v2 (
  id uuid primary key default gen_random_uuid(),
  canonical_lot_id text not null,
  lot_no text not null,
  department_code text not null,
  actual_rate numeric(14,4) not null check (actual_rate >= 0),
  currency_code text not null default 'INR',
  filled_by uuid not null default auth.uid(),
  filled_by_name text,
  filled_at timestamptz not null default now(),
  updated_by uuid,
  updated_by_name text,
  updated_at timestamptz not null default now(),
  unique(canonical_lot_id, department_code)
);

create table if not exists public.rr_upm_department_rate_log_v2 (
  id bigint generated always as identity primary key,
  rate_id uuid not null references public.rr_upm_department_rates_v2(id) on delete restrict,
  old_rate numeric(14,4),
  new_rate numeric(14,4) not null,
  changed_by uuid not null default auth.uid(),
  changed_by_name text,
  created_at timestamptz not null default now()
);

alter table public.rr_upm_department_rates_v2 enable row level security;
alter table public.rr_upm_department_rate_log_v2 enable row level security;

drop policy if exists rr_upm_rates_read_v2 on public.rr_upm_department_rates_v2;
create policy rr_upm_rates_read_v2 on public.rr_upm_department_rates_v2
for select to authenticated using (true);

drop policy if exists rr_upm_rate_log_read_v2 on public.rr_upm_department_rate_log_v2;
create policy rr_upm_rate_log_read_v2 on public.rr_upm_department_rate_log_v2
for select to authenticated using (true);

create or replace function public.rr_upm_set_department_rate_v2(
  p_canonical_lot_id text,
  p_department_code text,
  p_actual_rate numeric
) returns public.rr_upm_department_rates_v2
language plpgsql security definer set search_path=public
as $$
declare
  v_lot_no text;
  v_name text;
  v_old numeric;
  v_row public.rr_upm_department_rates_v2;
begin
  if not public.rr_up_is_department_head_v2(p_department_code) then
    raise exception 'Only the assigned Department Head or Owner/Admin can set this rate.';
  end if;
  if p_actual_rate is null or p_actual_rate < 0 then
    raise exception 'Actual rate must be zero or greater.';
  end if;

  select lot_no into v_lot_no
  from public.rr_upm_lot_board_v1
  where canonical_lot_id=p_canonical_lot_id;
  if v_lot_no is null then raise exception 'Production lot not found.'; end if;

  v_name := coalesce(public.rr_up_user_context_v2()->>'display_name', auth.uid()::text);
  select actual_rate into v_old from public.rr_upm_department_rates_v2
   where canonical_lot_id=p_canonical_lot_id and department_code=p_department_code;

  insert into public.rr_upm_department_rates_v2(
    canonical_lot_id,lot_no,department_code,actual_rate,filled_by,filled_by_name,
    updated_by,updated_by_name,updated_at
  ) values (
    p_canonical_lot_id,v_lot_no,p_department_code,p_actual_rate,auth.uid(),v_name,
    auth.uid(),v_name,now()
  )
  on conflict(canonical_lot_id,department_code) do update set
    actual_rate=excluded.actual_rate,
    updated_by=auth.uid(),updated_by_name=v_name,updated_at=now()
  returning * into v_row;

  insert into public.rr_upm_department_rate_log_v2(rate_id,old_rate,new_rate,changed_by_name)
  values(v_row.id,v_old,p_actual_rate,v_name);
  return v_row;
end;
$$;

grant execute on function public.rr_upm_set_department_rate_v2(text,text,numeric) to authenticated;

-- ---------------------------------------------------------------------------
-- WORK EVIDENCE AND SUBMIT LEDGER
-- ---------------------------------------------------------------------------
create table if not exists public.rr_upm_work_media_v2 (
  id uuid primary key default gen_random_uuid(),
  submit_id uuid,
  canonical_lot_id text not null,
  lot_no text not null,
  department_code text not null,
  colour_code text not null,
  size_code text not null default 'ALL',
  storage_bucket text not null default 'redzed-production-work',
  storage_path text not null unique,
  mime_type text,
  captured_live boolean not null default true,
  uploaded_by uuid not null default auth.uid(),
  uploaded_by_name text,
  created_at timestamptz not null default now()
);

create table if not exists public.rr_upm_submit_ledger_v2 (
  id uuid primary key default gen_random_uuid(),
  canonical_lot_id text not null,
  lot_no text not null,
  department_code text not null,
  colour_code text not null,
  size_code text not null default 'ALL',
  cutting_qty numeric(14,3) not null,
  alter_qty numeric(14,3) not null default 0,
  remake_qty numeric(14,3) not null default 0,
  damage_qty numeric(14,3) not null default 0,
  pending_alter_qty numeric(14,3) not null default 0,
  already_submitted_qty numeric(14,3) not null default 0,
  submitted_qty numeric(14,3) not null check (submitted_qty > 0),
  actual_rate numeric(14,4) not null,
  remarks text,
  submitted_by uuid not null default auth.uid(),
  submitted_by_name text,
  submitted_by_category text not null,
  created_at timestamptz not null default now()
);

create index if not exists rr_upm_submit_ledger_lookup_v2
on public.rr_upm_submit_ledger_v2(canonical_lot_id,department_code,colour_code,size_code,created_at);

alter table public.rr_upm_work_media_v2 enable row level security;
alter table public.rr_upm_submit_ledger_v2 enable row level security;

drop policy if exists rr_upm_work_media_read_v2 on public.rr_upm_work_media_v2;
create policy rr_upm_work_media_read_v2 on public.rr_upm_work_media_v2
for select to authenticated using (true);

drop policy if exists rr_upm_submit_ledger_read_v2 on public.rr_upm_submit_ledger_v2;
create policy rr_upm_submit_ledger_read_v2 on public.rr_upm_submit_ledger_v2
for select to authenticated using (true);

-- Private storage bucket. Upload/select are limited to authenticated users;
-- final transaction validation still checks live capture and department rules.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('redzed-production-work','redzed-production-work',false,10485760,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false;

drop policy if exists rr_work_storage_insert_v2 on storage.objects;
create policy rr_work_storage_insert_v2 on storage.objects
for insert to authenticated
with check (bucket_id='redzed-production-work' and auth.uid() is not null);

drop policy if exists rr_work_storage_select_v2 on storage.objects;
create policy rr_work_storage_select_v2 on storage.objects
for select to authenticated
using (bucket_id='redzed-production-work' and auth.uid() is not null);

-- ---------------------------------------------------------------------------
-- SERVER CALCULATION HELPERS
-- ---------------------------------------------------------------------------
create or replace function public.rr_upm_colour_cut_qty_v2(
  p_canonical_lot_id text,
  p_colour_code text
) returns numeric
language plpgsql stable security definer set search_path=public
as $$
declare
  v_total numeric:=0;
  v_colours jsonb;
  v_qty numeric;
begin
  select coalesce(total_qty,0), to_jsonb(b)->'colours'
  into v_total,v_colours
  from public.rr_upm_lot_board_v1 b
  where canonical_lot_id=p_canonical_lot_id;

  if jsonb_typeof(v_colours)='array' then
    select coalesce((x->>'qty')::numeric,(x->>'cut_qty')::numeric)
      into v_qty
    from jsonb_array_elements(v_colours) x
    where upper(coalesce(x->>'colour_code',x->>'colour_name',''))=upper(coalesce(p_colour_code,''))
    limit 1;
  end if;
  return coalesce(v_qty,v_total,0);
end;
$$;

create or replace function public.rr_upm_submit_summary_v2(
  p_canonical_lot_id text,
  p_department_code text,
  p_colour_code text,
  p_size_code text default 'ALL'
) returns table(
  lot_no text,
  art_no text,
  item_name text,
  cutting_qty numeric,
  alter_qty numeric,
  remake_qty numeric,
  damage_qty numeric,
  pending_alter_qty numeric,
  already_submitted_qty numeric,
  submit_ready_qty numeric,
  actual_rate numeric,
  rate_filled_by text,
  image_required boolean
)
language sql stable security definer set search_path=public
as $$
with lot as (
  select b.lot_no,b.art_no,b.item_name,
         public.rr_upm_colour_cut_qty_v2(p_canonical_lot_id,p_colour_code) cutting_qty
  from public.rr_upm_lot_board_v1 b
  where b.canonical_lot_id=p_canonical_lot_id
), alt as (
  select
    coalesce(sum(c.alter_qty),0)::numeric alter_qty,
    coalesce(sum(c.remake_qty),0)::numeric remake_qty,
    coalesce(sum(c.damage_qty),0)::numeric damage_qty,
    coalesce(sum(c.pending_qty),0)::numeric pending_qty
  from public.rr_up_alter_card_v1 c
  where c.lot_no=(select lot_no from lot)
    and exists (
      select 1 from public.rr_up_alter_lines al
      where al.alter_id=c.id
        and upper(al.colour_name)=upper(p_colour_code)
        and (upper(al.size_code)=upper(coalesce(p_size_code,'ALL')) or upper(coalesce(p_size_code,'ALL'))='ALL')
    )
), sent as (
  select coalesce(sum(submitted_qty),0)::numeric qty
  from public.rr_upm_submit_ledger_v2
  where canonical_lot_id=p_canonical_lot_id
    and department_code=p_department_code
    and upper(colour_code)=upper(p_colour_code)
    and upper(size_code)=upper(coalesce(p_size_code,'ALL'))
), rate as (
  select actual_rate,coalesce(updated_by_name,filled_by_name) filled_by
  from public.rr_upm_department_rates_v2
  where canonical_lot_id=p_canonical_lot_id and department_code=p_department_code
)
select lot.lot_no,lot.art_no,lot.item_name,lot.cutting_qty,
       alt.alter_qty,alt.remake_qty,alt.damage_qty,alt.pending_qty,
       sent.qty,
       greatest(lot.cutting_qty-alt.pending_qty-alt.damage_qty-sent.qty,0)::numeric submit_ready_qty,
       rate.actual_rate,rate.filled_by,
       (upper(p_department_code) like '%PRINT%' or upper(p_department_code) like '%STITCH%') image_required
from lot cross join alt cross join sent left join rate on true;
$$;

grant execute on function public.rr_upm_submit_summary_v2(text,text,text,text) to authenticated;

-- ---------------------------------------------------------------------------
-- FINAL SUBMIT RPC
-- No quantity parameter: the server calculates it immediately before posting.
-- ---------------------------------------------------------------------------
create or replace function public.rr_upm_submit_ready_v2(
  p_canonical_lot_id text,
  p_department_code text,
  p_colour_code text,
  p_size_code text default 'ALL',
  p_remarks text default null,
  p_evidence_paths text[] default '{}'
) returns uuid
language plpgsql security definer set search_path=public
as $$
declare
  v record;
  v_context jsonb;
  v_category text;
  v_user_dept text;
  v_submit_id uuid:=gen_random_uuid();
  v_path text;
  v_name text;
begin
  v_context:=public.rr_up_user_context_v2();
  v_category:=upper(coalesce(v_context->>'user_category','WORKER'));
  v_user_dept:=upper(coalesce(v_context->>'department_code',''));
  v_name:=coalesce(v_context->>'display_name',auth.uid()::text);

  if v_category not in ('OWNER','ADMIN','WORKER','DEPARTMENT_HEAD','LINE_MAN','MANAGER') then
    raise exception 'This user category cannot submit production work.';
  end if;
  if v_category not in ('OWNER','ADMIN','MANAGER') and v_user_dept<>upper(p_department_code) then
    raise exception 'Your locked department does not match this production department.';
  end if;

  select * into v from public.rr_upm_submit_summary_v2(
    p_canonical_lot_id,p_department_code,p_colour_code,coalesce(p_size_code,'ALL')
  );
  if v.lot_no is null then raise exception 'Lot/colour production summary not found.'; end if;
  if v.actual_rate is null then raise exception 'Actual Rate pending from Department Head.'; end if;
  if v.submit_ready_qty<=0 then raise exception 'No quantity is ready to submit.'; end if;
  if v.image_required and coalesce(array_length(p_evidence_paths,1),0)<1 then
    raise exception 'Live work image is mandatory for Printing/Stitching.';
  end if;

  -- Existing UPM posting function advances the quantity to the next department.
  perform public.rr_upm_post_entry_v1(
    p_canonical_lot_id => p_canonical_lot_id,
    p_department_code => p_department_code,
    p_colour_code => p_colour_code,
    p_size_code => coalesce(p_size_code,'ALL'),
    p_entry_type => 'GOOD',
    p_qty => v.submit_ready_qty,
    p_rate => v.actual_rate,
    p_remarks => p_remarks
  );

  insert into public.rr_upm_submit_ledger_v2(
    id,canonical_lot_id,lot_no,department_code,colour_code,size_code,
    cutting_qty,alter_qty,remake_qty,damage_qty,pending_alter_qty,
    already_submitted_qty,submitted_qty,actual_rate,remarks,
    submitted_by_name,submitted_by_category
  ) values (
    v_submit_id,p_canonical_lot_id,v.lot_no,p_department_code,p_colour_code,coalesce(p_size_code,'ALL'),
    v.cutting_qty,v.alter_qty,v.remake_qty,v.damage_qty,v.pending_alter_qty,
    v.already_submitted_qty,v.submit_ready_qty,v.actual_rate,p_remarks,
    v_name,v_category
  );

  foreach v_path in array coalesce(p_evidence_paths,'{}') loop
    insert into public.rr_upm_work_media_v2(
      submit_id,canonical_lot_id,lot_no,department_code,colour_code,size_code,
      storage_path,captured_live,uploaded_by_name
    ) values (
      v_submit_id,p_canonical_lot_id,v.lot_no,p_department_code,p_colour_code,coalesce(p_size_code,'ALL'),
      v_path,true,v_name
    );
  end loop;

  return v_submit_id;
end;
$$;

grant execute on function public.rr_upm_submit_ready_v2(text,text,text,text,text,text[]) to authenticated;

commit;

-- IMPORTANT AFTER RUNNING:
-- Populate rr_user_assignments_v2 for every production user.
-- Example (replace UUIDs/codes):
-- insert into public.rr_user_assignments_v2
-- (user_id,display_name,user_category,department_code,department_name,line_man_id,line_man_name,cutting_master_id,cutting_master_name)
-- values
-- ('USER-UUID','Mohan','WORKER','PRINT','Printer','LINE-MAN-UUID','Rakesh','MASTER-UUID','Ramesh');
