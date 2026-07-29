-- REDZED ERP — Universal Production Final Consolidated Patch V4
-- Run AFTER:
--   1) REDZED_ALTER_REMAKE_DAMAGE_V1.sql
--   2) REDZED_UPM_SUBMIT_V2.sql
-- This patch includes Owner/Admin access, clean Production Submit, safe reversal,
-- and Alter Repair / Remake Completion responsibility workflow.

begin;
create extension if not exists pgcrypto;

-- ============================================================================
-- 1. LOCKED USER CONTEXT + OWNER/ADMIN OVERRIDE
-- ============================================================================
create or replace function public.rr_up_normalize_role_v3(p_role text)
returns text language sql immutable as $$
  select case upper(replace(coalesce(trim(p_role),''),' ','_'))
    when 'SUPER_ADMIN' then 'OWNER'
    when 'OWNER_ADMIN' then 'OWNER'
    when 'DEPT_HEAD' then 'DEPARTMENT_HEAD'
    when 'HEAD' then 'DEPARTMENT_HEAD'
    when 'LINE_MANAGER' then 'LINE_MAN'
    when 'MASTER' then 'CUTTING_MASTER'
    else upper(replace(coalesce(trim(p_role),'WORKER'),' ','_'))
  end;
$$;

create or replace function public.rr_up_current_role_v1()
returns text
language sql stable security definer set search_path=public
as $$
  select public.rr_up_normalize_role_v3(coalesce(
    (select user_category from public.rr_user_assignments_v2 where user_id=auth.uid() and is_active limit 1),
    auth.jwt()->'app_metadata'->>'role',
    auth.jwt()->'user_metadata'->>'role',
    'WORKER'
  ));
$$;

create or replace function public.rr_up_is_owner_admin_v1()
returns boolean language sql stable security definer set search_path=public
as $$ select public.rr_up_current_role_v1() in ('OWNER','ADMIN'); $$;

create or replace function public.rr_up_is_department_head_v1()
returns boolean language sql stable security definer set search_path=public
as $$ select public.rr_up_current_role_v1() in ('DEPARTMENT_HEAD','OWNER','ADMIN'); $$;

create or replace function public.rr_up_is_cutting_master_v1()
returns boolean language sql stable security definer set search_path=public
as $$ select public.rr_up_current_role_v1() in ('CUTTING_MASTER','OWNER','ADMIN'); $$;

create or replace function public.rr_up_user_context_v2()
returns jsonb
language sql stable security definer set search_path=public
as $$
  select coalesce(
    (
      select jsonb_build_object(
        'user_id',u.user_id,
        'display_name',u.display_name,
        'user_category',public.rr_up_normalize_role_v3(u.user_category),
        'department_code',u.department_code,
        'department_name',u.department_name,
        'line_man_id',u.line_man_id,
        'line_man_name',u.line_man_name,
        'cutting_master_id',u.cutting_master_id,
        'cutting_master_name',u.cutting_master_name,
        'is_active',u.is_active
      )
      from public.rr_user_assignments_v2 u
      where u.user_id=auth.uid() and u.is_active
      limit 1
    ),
    jsonb_build_object(
      'user_id',auth.uid(),
      'display_name',coalesce(auth.jwt()->'user_metadata'->>'name',auth.jwt()->>'email','User'),
      'user_category',public.rr_up_normalize_role_v3(coalesce(
        auth.jwt()->'app_metadata'->>'role',auth.jwt()->'user_metadata'->>'role','WORKER')),
      'department_code',coalesce(auth.jwt()->'app_metadata'->>'department_code',auth.jwt()->'user_metadata'->>'department_code'),
      'department_name',coalesce(auth.jwt()->'app_metadata'->>'department_name',auth.jwt()->'user_metadata'->>'department_name'),
      'is_active',true
    )
  );
$$;

create or replace function public.rr_up_category_v2()
returns text language sql stable security definer set search_path=public
as $$ select public.rr_up_normalize_role_v3(public.rr_up_user_context_v2()->>'user_category'); $$;

create or replace function public.rr_up_is_department_head_v2(p_department_code text default null)
returns boolean language sql stable security definer set search_path=public
as $$
  select public.rr_up_category_v2() in ('OWNER','ADMIN')
    or (public.rr_up_category_v2()='DEPARTMENT_HEAD'
      and (p_department_code is null or upper(coalesce(public.rr_up_user_context_v2()->>'department_code',''))=upper(p_department_code)));
$$;

-- ============================================================================
-- 2. ALTER REPAIR RESPONSIBILITY WORKFLOW
-- Worker need not have login. Line Man records both Entered By and Work Done By.
-- ============================================================================
create table if not exists public.rr_up_alter_repair_v3 (
  id uuid primary key default gen_random_uuid(),
  alter_id uuid not null references public.rr_up_alters(id) on delete restrict,
  alter_line_id uuid not null references public.rr_up_alter_lines(id) on delete restrict,
  attempt_no integer not null default 1,
  assigned_qty integer not null check (assigned_qty > 0),
  repair_worker_id uuid,
  repair_worker_name text not null,
  responsible_line_man_id uuid not null default auth.uid(),
  responsible_line_man_name text,
  assigned_by uuid not null default auth.uid(),
  assigned_by_name text,
  assigned_at timestamptz not null default now(),
  submitted_qty integer not null default 0 check (submitted_qty >= 0),
  submitted_by uuid,
  submitted_by_name text,
  submitted_at timestamptz,
  verified_qty integer not null default 0 check (verified_qty >= 0),
  verification_status text not null default 'ASSIGNED' check (verification_status in
    ('ASSIGNED','REPAIR_SUBMITTED','ACCEPTED','RETURNED_FOR_REPAIR','CLOSED_AS_DAMAGE','CANCELLED')),
  verified_by uuid,
  verified_by_name text,
  verified_at timestamptz,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists rr_up_alter_repair_v3_lookup on public.rr_up_alter_repair_v3(alter_id,alter_line_id,created_at);

create table if not exists public.rr_up_remake_completion_v3 (
  id uuid primary key default gen_random_uuid(),
  alter_id uuid not null references public.rr_up_alters(id) on delete restrict,
  alter_line_id uuid not null references public.rr_up_alter_lines(id) on delete restrict,
  completed_qty integer not null check (completed_qty > 0),
  completed_by uuid not null default auth.uid(),
  completed_by_name text,
  completed_at timestamptz not null default now(),
  evidence_path text,
  note text
);
create index if not exists rr_up_remake_completion_v3_lookup on public.rr_up_remake_completion_v3(alter_id,alter_line_id);

alter table public.rr_up_alter_repair_v3 enable row level security;
alter table public.rr_up_remake_completion_v3 enable row level security;
drop policy if exists rr_up_alter_repair_read_v3 on public.rr_up_alter_repair_v3;
create policy rr_up_alter_repair_read_v3 on public.rr_up_alter_repair_v3 for select to authenticated using (true);
drop policy if exists rr_up_remake_completion_read_v3 on public.rr_up_remake_completion_v3;
create policy rr_up_remake_completion_read_v3 on public.rr_up_remake_completion_v3 for select to authenticated using (true);

grant select on public.rr_up_alter_repair_v3,public.rr_up_remake_completion_v3 to authenticated;

create or replace function public.rr_up_assign_alter_repair_v3(
  p_alter_line_id uuid,
  p_qty integer,
  p_repair_worker_id uuid,
  p_repair_worker_name text,
  p_note text default null
) returns public.rr_up_alter_repair_v3
language plpgsql security definer set search_path=public
as $$
declare v_role text; v_ctx jsonb; v_line record; v_used integer; v_attempt integer; v_row public.rr_up_alter_repair_v3;
begin
  v_ctx:=public.rr_up_user_context_v2(); v_role:=public.rr_up_category_v2();
  if v_role not in ('LINE_MAN','DEPARTMENT_HEAD','OWNER','ADMIN') then raise exception 'Only Line Man, Department Head or Owner/Admin can assign Alter repair.'; end if;
  if p_qty is null or p_qty<=0 or nullif(trim(p_repair_worker_name),'') is null then raise exception 'Worker name and valid quantity are required.'; end if;
  select l.*,b.pending_qty,a.id alter_id into v_line
  from public.rr_up_alter_lines l join public.rr_up_alters a on a.id=l.alter_id
  join public.rr_up_alter_line_balance_v1 b on b.alter_line_id=l.id
  where l.id=p_alter_line_id;
  if not found then raise exception 'Alter line not found.'; end if;
  select coalesce(sum(assigned_qty-verified_qty),0) into v_used from public.rr_up_alter_repair_v3
   where alter_line_id=p_alter_line_id and verification_status in ('ASSIGNED','REPAIR_SUBMITTED','RETURNED_FOR_REPAIR');
  if p_qty > greatest(v_line.pending_qty-v_used,0) then raise exception 'Assigned quantity exceeds available Alter balance.'; end if;
  select coalesce(max(attempt_no),0)+1 into v_attempt from public.rr_up_alter_repair_v3 where alter_line_id=p_alter_line_id;
  insert into public.rr_up_alter_repair_v3(alter_id,alter_line_id,attempt_no,assigned_qty,repair_worker_id,repair_worker_name,
    responsible_line_man_id,responsible_line_man_name,assigned_by_name,note)
  values(v_line.alter_id,p_alter_line_id,v_attempt,p_qty,p_repair_worker_id,trim(p_repair_worker_name),auth.uid(),
    coalesce(v_ctx->>'display_name','Line Man'),coalesce(v_ctx->>'display_name','User'),nullif(trim(p_note),'')) returning * into v_row;
  return v_row;
end; $$;

create or replace function public.rr_up_submit_alter_repair_v3(p_repair_id uuid,p_submitted_qty integer,p_note text default null)
returns public.rr_up_alter_repair_v3
language plpgsql security definer set search_path=public
as $$
declare v_role text; v_ctx jsonb; v_row public.rr_up_alter_repair_v3;
begin
  v_ctx:=public.rr_up_user_context_v2(); v_role:=public.rr_up_category_v2();
  select * into v_row from public.rr_up_alter_repair_v3 where id=p_repair_id for update;
  if not found then raise exception 'Repair assignment not found.'; end if;
  if v_role not in ('LINE_MAN','DEPARTMENT_HEAD','OWNER','ADMIN') then raise exception 'Only responsible Line Man or authority can submit repaired Alter.'; end if;
  if v_role='LINE_MAN' and v_row.responsible_line_man_id<>auth.uid() then raise exception 'Only the responsible Line Man can submit this repair.'; end if;
  if v_row.verification_status not in ('ASSIGNED','RETURNED_FOR_REPAIR') then raise exception 'Repair is not available for submission.'; end if;
  if p_submitted_qty<=0 or p_submitted_qty>v_row.assigned_qty then raise exception 'Submitted quantity exceeds assigned quantity.'; end if;
  update public.rr_up_alter_repair_v3 set submitted_qty=p_submitted_qty,submitted_by=auth.uid(),
    submitted_by_name=coalesce(v_ctx->>'display_name','Line Man'),submitted_at=now(),verification_status='REPAIR_SUBMITTED',
    note=coalesce(nullif(trim(p_note),''),note),updated_at=now() where id=p_repair_id returning * into v_row;
  return v_row;
end; $$;

create or replace function public.rr_up_verify_alter_repair_v3(p_repair_id uuid,p_action text,p_verified_qty integer,p_note text default null)
returns public.rr_up_alter_repair_v3
language plpgsql security definer set search_path=public
as $$
declare v_action text:=upper(trim(p_action)); v_ctx jsonb; v_row public.rr_up_alter_repair_v3;
begin
  if not public.rr_up_is_department_head_v1() then raise exception 'Only Department Head or Owner/Admin can verify Alter repair.'; end if;
  if v_action not in ('ACCEPT','RETURN','DAMAGE') then raise exception 'Action must be ACCEPT, RETURN or DAMAGE.'; end if;
  v_ctx:=public.rr_up_user_context_v2();
  select * into v_row from public.rr_up_alter_repair_v3 where id=p_repair_id for update;
  if not found or v_row.verification_status<>'REPAIR_SUBMITTED' then raise exception 'Repair is not waiting for verification.'; end if;
  if p_verified_qty<=0 or p_verified_qty>v_row.submitted_qty then raise exception 'Verified quantity exceeds submitted repair quantity.'; end if;
  update public.rr_up_alter_repair_v3 set verified_qty=p_verified_qty,
    verification_status=case v_action when 'ACCEPT' then 'ACCEPTED' when 'RETURN' then 'RETURNED_FOR_REPAIR' else 'CLOSED_AS_DAMAGE' end,
    verified_by=auth.uid(),verified_by_name=coalesce(v_ctx->>'display_name','Department Head'),verified_at=now(),
    note=coalesce(nullif(trim(p_note),''),note),updated_at=now() where id=p_repair_id returning * into v_row;
  return v_row;
end; $$;

create or replace function public.rr_up_complete_remake_v3(p_alter_line_id uuid,p_qty integer,p_evidence_path text default null,p_note text default null)
returns public.rr_up_remake_completion_v3
language plpgsql security definer set search_path=public
as $$
declare v_line record; v_issued integer; v_done integer; v_ctx jsonb; v_row public.rr_up_remake_completion_v3;
begin
  if not public.rr_up_is_cutting_master_v1() then raise exception 'Only Cutting Master or Owner/Admin can complete Remake.'; end if;
  select l.alter_id into v_line from public.rr_up_alter_lines l where l.id=p_alter_line_id;
  if not found then raise exception 'Alter line not found.'; end if;
  select coalesce(sum(rl.qty),0) into v_issued from public.rr_up_remake_lines rl where rl.alter_line_id=p_alter_line_id;
  select coalesce(sum(completed_qty),0) into v_done from public.rr_up_remake_completion_v3 where alter_line_id=p_alter_line_id;
  if p_qty<=0 or p_qty>v_issued-v_done then raise exception 'Completed Remake exceeds issued pending Remake.'; end if;
  v_ctx:=public.rr_up_user_context_v2();
  insert into public.rr_up_remake_completion_v3(alter_id,alter_line_id,completed_qty,completed_by_name,evidence_path,note)
  values(v_line.alter_id,p_alter_line_id,p_qty,coalesce(v_ctx->>'display_name','Cutting Master'),p_evidence_path,nullif(trim(p_note),'')) returning * into v_row;
  return v_row;
end; $$;

grant execute on function public.rr_up_assign_alter_repair_v3(uuid,integer,uuid,text,text) to authenticated;
grant execute on function public.rr_up_submit_alter_repair_v3(uuid,integer,text) to authenticated;
grant execute on function public.rr_up_verify_alter_repair_v3(uuid,text,integer,text) to authenticated;
grant execute on function public.rr_up_complete_remake_v3(uuid,integer,text,text) to authenticated;

-- Consolidated line status view used by UI and Production Submit calculation.
create or replace view public.rr_up_alter_line_flow_v3 as
select l.id alter_line_id,l.alter_id,l.colour_name,l.size_code,l.alter_qty,
  coalesce(ri.remake_issued_qty,0)::integer remake_issued_qty,
  coalesce(rc.remake_completed_qty,0)::integer remake_completed_qty,
  coalesce(d.damage_qty,0)::integer damage_qty,
  coalesce(rp.repair_assigned_qty,0)::integer repair_assigned_qty,
  coalesce(rp.repair_submitted_qty,0)::integer repair_submitted_qty,
  coalesce(rp.repair_accepted_qty,0)::integer repair_accepted_qty,
  coalesce(rp.repair_returned_qty,0)::integer re_repair_pending_qty,
  greatest(l.alter_qty-coalesce(rc.remake_completed_qty,0)-coalesce(d.damage_qty,0)-coalesce(rp.repair_accepted_qty,0),0)::integer unresolved_alter_qty
from public.rr_up_alter_lines l
left join (select alter_line_id,sum(qty) remake_issued_qty from public.rr_up_remake_lines group by alter_line_id) ri on ri.alter_line_id=l.id
left join (select alter_line_id,sum(completed_qty) remake_completed_qty from public.rr_up_remake_completion_v3 group by alter_line_id) rc on rc.alter_line_id=l.id
left join (select dl.alter_line_id,sum(dl.qty) damage_qty from public.rr_up_damage_lines dl group by dl.alter_line_id) d on d.alter_line_id=l.id
left join (select alter_line_id,
  sum(assigned_qty) filter(where verification_status in ('ASSIGNED','REPAIR_SUBMITTED','RETURNED_FOR_REPAIR','ACCEPTED')) repair_assigned_qty,
  sum(submitted_qty) filter(where verification_status in ('REPAIR_SUBMITTED','ACCEPTED','RETURNED_FOR_REPAIR','CLOSED_AS_DAMAGE')) repair_submitted_qty,
  sum(verified_qty) filter(where verification_status='ACCEPTED') repair_accepted_qty,
  sum(greatest(submitted_qty-verified_qty,0)) filter(where verification_status='RETURNED_FOR_REPAIR') repair_returned_qty
  from public.rr_up_alter_repair_v3 group by alter_line_id) rp on rp.alter_line_id=l.id;

grant select on public.rr_up_alter_line_flow_v3 to authenticated;

-- ============================================================================
-- 3. SUBMIT REVERSAL AUDIT
-- ============================================================================
alter table public.rr_upm_submit_ledger_v2 add column if not exists submit_status text not null default 'ACTIVE';
alter table public.rr_upm_submit_ledger_v2 add column if not exists reversed_at timestamptz;
alter table public.rr_upm_submit_ledger_v2 add column if not exists reversed_by uuid;
alter table public.rr_upm_submit_ledger_v2 add column if not exists reversed_by_name text;
alter table public.rr_upm_submit_ledger_v2 add column if not exists reverse_reason text;

do $$ begin
  if not exists(select 1 from pg_constraint where conname='rr_upm_submit_status_v3_chk') then
    alter table public.rr_upm_submit_ledger_v2 add constraint rr_upm_submit_status_v3_chk check(submit_status in ('ACTIVE','REVERSED'));
  end if;
end $$;

create table if not exists public.rr_upm_submit_reversal_log_v3(
  id uuid primary key default gen_random_uuid(),
  submit_id uuid not null references public.rr_upm_submit_ledger_v2(id) on delete restrict,
  reason text not null,
  reversed_by uuid not null default auth.uid(),
  reversed_by_name text,
  created_at timestamptz not null default now()
);
alter table public.rr_upm_submit_reversal_log_v3 enable row level security;
drop policy if exists rr_upm_reversal_read_v3 on public.rr_upm_submit_reversal_log_v3;
create policy rr_upm_reversal_read_v3 on public.rr_upm_submit_reversal_log_v3 for select to authenticated using(true);
grant select on public.rr_upm_submit_reversal_log_v3 to authenticated;

-- Rebuild summary: issued remake does NOT release quantity; only accepted repair or completed remake does.
drop function if exists public.rr_upm_submit_summary_v2(text,text,text,text);
create function public.rr_upm_submit_summary_v2(
  p_canonical_lot_id text,p_department_code text,p_colour_code text,p_size_code text default 'ALL'
) returns table(
  lot_no text,art_no text,item_name text,cutting_qty numeric,
  alter_qty numeric,repair_assigned_qty numeric,repair_submitted_qty numeric,repair_accepted_qty numeric,re_repair_pending_qty numeric,
  remake_qty numeric,remake_completed_qty numeric,damage_qty numeric,pending_alter_qty numeric,
  already_submitted_qty numeric,submit_ready_qty numeric,actual_rate numeric,rate_filled_by text,image_required boolean
)
language sql stable security definer set search_path=public as $$
with lot as (
 select b.lot_no,b.art_no,b.item_name,public.rr_upm_colour_cut_qty_v2(p_canonical_lot_id,p_colour_code) cutting_qty
 from public.rr_upm_lot_board_v1 b where b.canonical_lot_id=p_canonical_lot_id
), alt as (
 select coalesce(sum(f.alter_qty),0)::numeric alter_qty,
  coalesce(sum(f.repair_assigned_qty),0)::numeric repair_assigned_qty,
  coalesce(sum(f.repair_submitted_qty),0)::numeric repair_submitted_qty,
  coalesce(sum(f.repair_accepted_qty),0)::numeric repair_accepted_qty,
  coalesce(sum(f.re_repair_pending_qty),0)::numeric re_repair_pending_qty,
  coalesce(sum(f.remake_issued_qty),0)::numeric remake_qty,
  coalesce(sum(f.remake_completed_qty),0)::numeric remake_completed_qty,
  coalesce(sum(f.damage_qty),0)::numeric damage_qty,
  coalesce(sum(f.unresolved_alter_qty),0)::numeric pending_qty
 from public.rr_up_alter_line_flow_v3 f join public.rr_up_alters a on a.id=f.alter_id
 where a.lot_no=(select lot_no from lot)
   and upper(f.colour_name)=upper(p_colour_code)
   and (upper(f.size_code)=upper(coalesce(p_size_code,'ALL')) or upper(coalesce(p_size_code,'ALL'))='ALL')
), sent as (
 select coalesce(sum(submitted_qty),0)::numeric qty from public.rr_upm_submit_ledger_v2
 where canonical_lot_id=p_canonical_lot_id and department_code=p_department_code and submit_status='ACTIVE'
 and upper(colour_code)=upper(p_colour_code) and upper(size_code)=upper(coalesce(p_size_code,'ALL'))
), rate as (
 select actual_rate,coalesce(updated_by_name,filled_by_name) filled_by from public.rr_upm_department_rates_v2
 where canonical_lot_id=p_canonical_lot_id and department_code=p_department_code
)
select lot.lot_no,lot.art_no,lot.item_name,lot.cutting_qty,
 alt.alter_qty,alt.repair_assigned_qty,alt.repair_submitted_qty,alt.repair_accepted_qty,alt.re_repair_pending_qty,
 alt.remake_qty,alt.remake_completed_qty,alt.damage_qty,alt.pending_qty,sent.qty,
 greatest(lot.cutting_qty-alt.pending_qty-alt.damage_qty-sent.qty,0)::numeric,
 rate.actual_rate,rate.filled_by,(upper(p_department_code) like '%PRINT%' or upper(p_department_code) like '%STITCH%')
from lot cross join alt cross join sent left join rate on true;
$$;
grant execute on function public.rr_upm_submit_summary_v2(text,text,text,text) to authenticated;

create or replace function public.rr_upm_reverse_submit_v3(p_submit_id uuid,p_reason text)
returns public.rr_upm_submit_ledger_v2
language plpgsql security definer set search_path=public as $$
declare v public.rr_upm_submit_ledger_v2; v_ctx jsonb; v_name text; v_later integer;
begin
  select * into v from public.rr_upm_submit_ledger_v2 where id=p_submit_id for update;
  if not found then raise exception 'Submission not found.'; end if;
  if v.submit_status<>'ACTIVE' then raise exception 'Submission is already reversed.'; end if;
  if not public.rr_up_is_department_head_v2(v.department_code) then raise exception 'Only assigned Department Head or Owner/Admin can reverse this submission.'; end if;
  if nullif(trim(p_reason),'') is null then raise exception 'Reverse reason is mandatory.'; end if;
  select count(*) into v_later from public.rr_upm_submit_ledger_v2 x where x.canonical_lot_id=v.canonical_lot_id
    and upper(x.colour_code)=upper(v.colour_code) and upper(x.size_code)=upper(v.size_code)
    and x.created_at>v.created_at and x.submit_status='ACTIVE' and x.department_code<>v.department_code;
  if v_later>0 then raise exception 'A later department has already submitted this quantity. Reverse the downstream entry first.'; end if;

  -- Existing UPM supports ADJUSTMENT. Negative quantity restores the previous department balance.
  begin
    perform public.rr_upm_post_entry_v1(v.canonical_lot_id,v.department_code,v.colour_code,v.size_code,'ADJUSTMENT',-v.submitted_qty,v.actual_rate,'REVERSAL: '||trim(p_reason));
  exception when others then
    raise exception 'Reversal was not posted; base UPM rejected negative ADJUSTMENT: %',sqlerrm;
  end;

  v_ctx:=public.rr_up_user_context_v2(); v_name:=coalesce(v_ctx->>'display_name','Authority');
  update public.rr_upm_submit_ledger_v2 set submit_status='REVERSED',reversed_at=now(),reversed_by=auth.uid(),
    reversed_by_name=v_name,reverse_reason=trim(p_reason) where id=p_submit_id returning * into v;
  insert into public.rr_upm_submit_reversal_log_v3(submit_id,reason,reversed_by_name) values(p_submit_id,trim(p_reason),v_name);
  return v;
end; $$;
grant execute on function public.rr_upm_reverse_submit_v3(uuid,text) to authenticated;

commit;

-- ============================================================================
-- V4 FINAL ALTER REGISTRATION FORM RULES
-- Worker / Department Head / Line Man may register an Alter.
-- Colour is selected from the Lot colour list in the UI; Size and Qty are manual.
-- One mandatory live fault image is captured in the Alter form. Repair submission
-- does not require another image. Original Alter evidence remains immutable.
-- ============================================================================
begin;

create or replace function public.rr_up_register_alter_v1(
  p_lot_no text,
  p_department_id uuid,
  p_department_name text,
  p_worker_id uuid,
  p_worker_name text,
  p_line_man_id uuid,
  p_line_man_name text,
  p_cutting_master_id uuid,
  p_cutting_master_name text,
  p_lines jsonb,
  p_note text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_alter public.rr_up_alters%rowtype;
  v_role text := public.rr_up_current_role_v1();
  v_row jsonb;
  v_colour text;
  v_size text;
  v_qty integer;
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  if v_role not in ('WORKER','LINE_MAN','DEPARTMENT_HEAD','OWNER','ADMIN') then
    raise exception 'Only Worker, Line Man, Department Head or Owner/Admin can register Alter.';
  end if;
  if v_role='WORKER' and p_worker_id <> auth.uid() then
    raise exception 'Worker can register Alter only against himself.';
  end if;
  if nullif(trim(p_lot_no),'') is null then raise exception 'Lot No is required.'; end if;
  if nullif(trim(p_department_name),'') is null then raise exception 'Department is required.'; end if;
  if p_worker_id is null or nullif(trim(p_worker_name),'') is null then raise exception 'Responsible worker is required.'; end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines)=0 then
    raise exception 'At least one Colour, Size and Qty line is required.';
  end if;

  -- Validate every line before creating the immutable Alter header.
  for v_row in select value from jsonb_array_elements(p_lines)
  loop
    v_colour := nullif(trim(v_row->>'colour_name'),'');
    v_size := nullif(upper(trim(v_row->>'size_code')),'');
    v_qty := coalesce((v_row->>'qty')::integer,0);
    if v_colour is null then raise exception 'Colour is mandatory.'; end if;
    if v_size is null then raise exception 'Size is mandatory.'; end if;
    if v_qty <= 0 then raise exception 'Every Alter Qty must be greater than zero.'; end if;
  end loop;

  insert into public.rr_up_alters(
    lot_no,department_id,department_name,worker_id,worker_name,
    line_man_id,line_man_name,cutting_master_id,cutting_master_name,note
  ) values (
    trim(p_lot_no),p_department_id,trim(p_department_name),p_worker_id,trim(p_worker_name),
    p_line_man_id,nullif(trim(p_line_man_name),''),p_cutting_master_id,
    nullif(trim(p_cutting_master_name),''),nullif(trim(p_note),'')
  ) returning * into v_alter;

  for v_row in select value from jsonb_array_elements(p_lines)
  loop
    insert into public.rr_up_alter_lines(alter_id,colour_id,colour_name,size_code,alter_qty)
    values(
      v_alter.id,
      nullif(v_row->>'colour_id','')::uuid,
      trim(v_row->>'colour_name'),
      upper(trim(v_row->>'size_code')),
      (v_row->>'qty')::integer
    );
  end loop;

  insert into public.rr_up_alter_status_log(alter_id,new_status,note)
  values(v_alter.id,'OPEN','Alter registered with mandatory fault evidence from UI');

  return to_jsonb(v_alter);
end;
$$;

grant execute on function public.rr_up_register_alter_v1(
  text,uuid,text,uuid,text,uuid,text,uuid,text,jsonb,text
) to authenticated;

commit;

-- ============================================================================
-- V5 CUT COLOUR-SIZE MAPPING + ALTER QUANTITY HARD LIMIT
-- Size is never free text. Only sizes actually cut in the selected Lot + Colour
-- are accepted. Total registered Alter cannot exceed mapped cut quantity.
-- ============================================================================
begin;

-- Owner/Admin JWT role must never be downgraded by a worker assignment row.
create or replace function public.rr_up_current_role_v1()
returns text
language sql stable security definer set search_path=public
as $$
  with jwt_role as (
    select public.rr_up_normalize_role_v3(coalesce(
      auth.jwt()->'app_metadata'->>'role',
      auth.jwt()->'user_metadata'->>'role',
      ''
    )) as role
  )
  select case
    when (select role from jwt_role) in ('OWNER','ADMIN') then (select role from jwt_role)
    else public.rr_up_normalize_role_v3(coalesce(
      (select user_category from public.rr_user_assignments_v2 where user_id=auth.uid() and is_active limit 1),
      nullif((select role from jwt_role),''),
      'WORKER'
    ))
  end;
$$;

create table if not exists public.rr_upm_lot_cut_size_map_v5 (
  id uuid primary key default gen_random_uuid(),
  canonical_lot_id text,
  lot_no text not null,
  colour_code text not null,
  colour_name text not null,
  size_code text not null,
  cut_qty integer not null check (cut_qty >= 0),
  source text not null default 'CUTTING',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  unique(lot_no,colour_code,size_code)
);
create index if not exists rr_upm_lot_cut_size_map_v5_lookup
  on public.rr_upm_lot_cut_size_map_v5(upper(lot_no),upper(colour_code),upper(size_code))
  where is_active;

alter table public.rr_upm_lot_cut_size_map_v5 enable row level security;
drop policy if exists rr_upm_lot_cut_size_map_v5_read on public.rr_upm_lot_cut_size_map_v5;
create policy rr_upm_lot_cut_size_map_v5_read on public.rr_upm_lot_cut_size_map_v5
for select to authenticated using (is_active);
grant select on public.rr_upm_lot_cut_size_map_v5 to authenticated;

create or replace function public.rr_upm_save_cut_size_map_v5(
  p_canonical_lot_id text,
  p_lot_no text,
  p_rows jsonb
) returns integer
language plpgsql security definer set search_path=public
as $$
declare v_role text:=public.rr_up_current_role_v1(); v jsonb; v_count integer:=0;
begin
  if v_role not in ('CUTTING_MASTER','DEPARTMENT_HEAD','OWNER','ADMIN') then
    raise exception 'Only Cutting Master, Department Head or Owner/Admin can save cutting size mapping.';
  end if;
  if nullif(trim(p_lot_no),'') is null then raise exception 'Lot No is required.'; end if;
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0 then
    raise exception 'At least one cut Colour-Size row is required.';
  end if;
  for v in select value from jsonb_array_elements(p_rows) loop
    if nullif(trim(v->>'colour_code'),'') is null or nullif(trim(v->>'size_code'),'') is null then
      raise exception 'Colour and Size are mandatory in cutting mapping.';
    end if;
    if coalesce((v->>'cut_qty')::integer,-1)<0 then raise exception 'Cut Qty cannot be negative.'; end if;
    insert into public.rr_upm_lot_cut_size_map_v5(
      canonical_lot_id,lot_no,colour_code,colour_name,size_code,cut_qty,updated_at
    ) values(
      nullif(trim(p_canonical_lot_id),''),trim(p_lot_no),upper(trim(v->>'colour_code')),
      coalesce(nullif(trim(v->>'colour_name'),''),upper(trim(v->>'colour_code'))),
      upper(trim(v->>'size_code')),(v->>'cut_qty')::integer,now()
    )
    on conflict(lot_no,colour_code,size_code) do update set
      canonical_lot_id=excluded.canonical_lot_id,
      colour_name=excluded.colour_name,
      cut_qty=excluded.cut_qty,
      is_active=true,
      updated_at=now();
    v_count:=v_count+1;
  end loop;
  return v_count;
end; $$;
grant execute on function public.rr_upm_save_cut_size_map_v5(text,text,jsonb) to authenticated;

create or replace function public.rr_up_get_lot_cut_sizes_v5(p_lot_no text)
returns table(
  colour_code text,
  colour_name text,
  size_code text,
  cut_qty integer,
  registered_alter_qty bigint,
  available_alter_qty bigint
)
language sql stable security definer set search_path=public
as $$
  select m.colour_code,m.colour_name,m.size_code,m.cut_qty,
    coalesce(a.registered_alter_qty,0) registered_alter_qty,
    greatest(m.cut_qty-coalesce(a.registered_alter_qty,0),0) available_alter_qty
  from public.rr_upm_lot_cut_size_map_v5 m
  left join lateral (
    select sum(l.alter_qty)::bigint registered_alter_qty
    from public.rr_up_alter_lines l
    join public.rr_up_alters h on h.id=l.alter_id
    where upper(h.lot_no)=upper(m.lot_no)
      and upper(l.colour_name) in (upper(m.colour_name),upper(m.colour_code))
      and upper(l.size_code)=upper(m.size_code)
      and upper(coalesce(h.status,'OPEN'))<>'CANCELLED'
  ) a on true
  where upper(m.lot_no)=upper(trim(p_lot_no)) and m.is_active
  order by m.colour_name,m.size_code;
$$;
grant execute on function public.rr_up_get_lot_cut_sizes_v5(text) to authenticated;

create or replace function public.rr_up_register_alter_v1(
  p_lot_no text,
  p_department_id uuid,
  p_department_name text,
  p_worker_id uuid,
  p_worker_name text,
  p_line_man_id uuid,
  p_line_man_name text,
  p_cutting_master_id uuid,
  p_cutting_master_name text,
  p_lines jsonb,
  p_note text default null
) returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  v_alter public.rr_up_alters%rowtype;
  v_role text:=public.rr_up_current_role_v1();
  v_row jsonb; v_colour text; v_size text; v_qty integer;
  v_map record; v_existing bigint; v_batch integer;
begin
  if auth.uid() is null then raise exception 'Login required.'; end if;
  if v_role not in ('WORKER','LINE_MAN','DEPARTMENT_HEAD','OWNER','ADMIN') then
    raise exception 'Only Worker, Line Man, Department Head or Owner/Admin can register Alter.';
  end if;
  if v_role='WORKER' and p_worker_id<>auth.uid() then raise exception 'Worker can register Alter only against himself.'; end if;
  if nullif(trim(p_lot_no),'') is null then raise exception 'Lot No is required.'; end if;
  if nullif(trim(p_department_name),'') is null then raise exception 'Department is required.'; end if;
  if p_worker_id is null or nullif(trim(p_worker_name),'') is null then raise exception 'Responsible worker is required.'; end if;
  if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'At least one Colour, Size and Qty line is required.'; end if;

  -- Validate grouped quantities so duplicate UI rows cannot bypass the cut limit.
  for v_row in
    select jsonb_build_object(
      'colour_name',trim(e.value->>'colour_name'),
      'size_code',upper(trim(e.value->>'size_code')),
      'qty',sum((e.value->>'qty')::integer)
    )
    from jsonb_array_elements(p_lines) as e(value)
    group by upper(trim(e.value->>'colour_name')),upper(trim(e.value->>'size_code')),trim(e.value->>'colour_name')
  loop
    v_colour:=nullif(trim(v_row->>'colour_name'),'');
    v_size:=nullif(upper(trim(v_row->>'size_code')),'');
    v_qty:=coalesce((v_row->>'qty')::integer,0);
    if v_colour is null or v_size is null or v_qty<=0 then raise exception 'Valid mapped Colour, Size and Qty are mandatory.'; end if;

    select * into v_map from public.rr_upm_lot_cut_size_map_v5 m
    where upper(m.lot_no)=upper(trim(p_lot_no))
      and upper(v_colour) in (upper(m.colour_name),upper(m.colour_code))
      and upper(m.size_code)=v_size and m.is_active
    limit 1 for update;
    if not found then raise exception 'Size % is not cut/mapped for Colour % in Lot %.',v_size,v_colour,p_lot_no; end if;

    select coalesce(sum(l.alter_qty),0) into v_existing
    from public.rr_up_alter_lines l join public.rr_up_alters h on h.id=l.alter_id
    where upper(h.lot_no)=upper(trim(p_lot_no))
      and upper(l.colour_name) in (upper(v_map.colour_name),upper(v_map.colour_code))
      and upper(l.size_code)=upper(v_map.size_code)
      and upper(coalesce(h.status,'OPEN'))<>'CANCELLED';
    if v_existing+v_qty>v_map.cut_qty then
      raise exception 'Alter Qty exceeds Cut Qty for % / %. Cut: %, Already Alter: %, Maximum New: %.',
        v_map.colour_name,v_map.size_code,v_map.cut_qty,v_existing,greatest(v_map.cut_qty-v_existing,0);
    end if;
  end loop;

  insert into public.rr_up_alters(lot_no,department_id,department_name,worker_id,worker_name,line_man_id,line_man_name,cutting_master_id,cutting_master_name,note)
  values(trim(p_lot_no),p_department_id,trim(p_department_name),p_worker_id,trim(p_worker_name),p_line_man_id,nullif(trim(p_line_man_name),''),p_cutting_master_id,nullif(trim(p_cutting_master_name),''),nullif(trim(p_note),''))
  returning * into v_alter;

  for v_row in select value from jsonb_array_elements(p_lines) loop
    insert into public.rr_up_alter_lines(alter_id,colour_id,colour_name,size_code,alter_qty)
    values(v_alter.id,nullif(v_row->>'colour_id','')::uuid,trim(v_row->>'colour_name'),upper(trim(v_row->>'size_code')),(v_row->>'qty')::integer);
  end loop;
  insert into public.rr_up_alter_status_log(alter_id,new_status,note)
  values(v_alter.id,'OPEN','Alter registered against locked Lot + Cut Colour + Cut Size mapping');
  return to_jsonb(v_alter);
end; $$;

grant execute on function public.rr_up_register_alter_v1(text,uuid,text,uuid,text,uuid,text,uuid,text,jsonb,text) to authenticated;

commit;
