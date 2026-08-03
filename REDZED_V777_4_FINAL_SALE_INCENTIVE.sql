
-- ============================================================
-- REDZED V777.4 FINAL — LEADERSHIP COMPENSATION + SALE INCENTIVE
-- Use this instead of the earlier V777.4 package.
-- Dependencies: V776.1 + V777.2 + V777.3 bridge
-- ============================================================

begin;

alter table public.rr_worker_leadership_profile_v776
  add column if not exists sale_incentive_basis text not null default 'NONE';

alter table public.rr_worker_leadership_profile_v776
  add column if not exists sale_incentive_rate numeric(12,4) not null default 0;

do $$
declare
  v_constraint text;
begin
  select c.conname
  into v_constraint
  from pg_constraint c
  join pg_class t on t.oid=c.conrelid
  join pg_namespace n on n.oid=t.relnamespace
  where n.nspname='public'
    and t.relname='rr_worker_leadership_profile_v776'
    and c.contype='c'
    and pg_get_constraintdef(c.oid) ilike '%compensation_mode%'
  limit 1;

  if v_constraint is not null then
    execute format(
      'alter table public.rr_worker_leadership_profile_v776 drop constraint %I',
      v_constraint
    );
  end if;
end $$;

alter table public.rr_worker_leadership_profile_v776
drop constraint if exists rr_worker_leadership_compensation_mode_v777_4_final_chk;

alter table public.rr_worker_leadership_profile_v776
add constraint rr_worker_leadership_compensation_mode_v777_4_final_chk
check(compensation_mode in(
  'SALARY_ONLY',
  'SALARY_PLUS_FLAT',
  'SALARY_PLUS_SALE_PCS',
  'SALARY_PLUS_FLAT_SALE_PCS',
  'PCS_ONLY',
  'PCS_PLUS_FLAT',
  'PCS_PLUS_RATE',
  'PCS_PLUS_FLAT_RATE',
  'HYBRID'
));

alter table public.rr_worker_leadership_profile_v776
drop constraint if exists rr_worker_leadership_sale_basis_v777_4_final_chk;

alter table public.rr_worker_leadership_profile_v776
add constraint rr_worker_leadership_sale_basis_v777_4_final_chk
check(sale_incentive_basis in(
  'NONE',
  'SOLD_PCS',
  'DISPATCH_PCS',
  'INVOICE_PCS'
));

alter table public.rr_worker_leadership_profile_v776
drop constraint if exists rr_worker_leadership_sale_rate_v777_4_final_chk;

alter table public.rr_worker_leadership_profile_v776
add constraint rr_worker_leadership_sale_rate_v777_4_final_chk
check(sale_incentive_rate>=0);

create or replace function public.rr_set_worker_leadership_v777_4_final(
  p_worker_id uuid,
  p_leadership_role text,
  p_managed_departments jsonb,
  p_base_payroll_category text,
  p_compensation_mode text,
  p_monthly_flat_incentive numeric default 0,
  p_rate_enhancement_type text default 'NONE',
  p_rate_enhancement_value numeric default 0,
  p_sale_incentive_basis text default 'NONE',
  p_sale_incentive_rate numeric default 0,
  p_effective_from date default current_date,
  p_effective_to date default null,
  p_status text default 'ACTIVE',
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_actor public.rr_user_profiles%rowtype;
  v_worker record;
  v_role text:=upper(trim(coalesce(p_leadership_role,'NONE')));
  v_payroll text:=upper(trim(coalesce(p_base_payroll_category,'PIECE_RATE')));
  v_comp text:=upper(trim(coalesce(p_compensation_mode,'PCS_ONLY')));
  v_rate_type text:=upper(trim(coalesce(p_rate_enhancement_type,'NONE')));
  v_sale_basis text:=upper(trim(coalesce(p_sale_incentive_basis,'NONE')));
  v_status text:=upper(trim(coalesce(p_status,'ACTIVE')));
  v_depts text[];
  v_dept text;
  v_old jsonb;
  v_new jsonb;
begin
  select *
  into v_actor
  from public.rr_user_profiles
  where auth_user_id=auth.uid()
    and coalesce(is_active,false)
    and upper(coalesce(access_status,'ACTIVE'))='ACTIVE'
  limit 1;

  if not found then raise exception 'Active ERP profile required.'; end if;

  if lower(coalesce(v_actor.role_code,'')) not in('owner','admin') then
    raise exception 'Leadership configuration permission denied.';
  end if;

  select worker_id,worker_name
  into v_worker
  from public.rr_worker_directory_unified_v1
  where worker_id=p_worker_id
  limit 1;

  if not found then raise exception 'Worker nahi mila.'; end if;

  if v_role not in('NONE','DEPARTMENT_HEAD','PRODUCTION_MANAGER') then
    raise exception 'Leadership Role invalid hai.';
  end if;

  if v_payroll not in('SALARIED','PIECE_RATE') then
    raise exception 'Base Payroll Category SALARIED ya PIECE_RATE honi chahiye.';
  end if;

  if v_status not in('ACTIVE','INACTIVE') then
    raise exception 'Status invalid hai.';
  end if;

  if v_rate_type not in('NONE','FLAT_PER_PCS','PERCENT') then
    raise exception 'Rate Enhancement Type invalid hai.';
  end if;

  if v_sale_basis not in('NONE','SOLD_PCS','DISPATCH_PCS','INVOICE_PCS') then
    raise exception 'Sale Incentive Basis invalid hai.';
  end if;

  if coalesce(p_monthly_flat_incentive,0)<0
     or coalesce(p_rate_enhancement_value,0)<0
     or coalesce(p_sale_incentive_rate,0)<0
  then
    raise exception 'Negative incentive/enhancement allowed nahi hai.';
  end if;

  if p_effective_to is not null and p_effective_to<p_effective_from then
    raise exception 'Effective To, Effective From se pehle nahi ho sakta.';
  end if;

  select coalesce(array_agg(distinct lower(trim(x.value))),array[]::text[])
  into v_depts
  from jsonb_array_elements_text(coalesce(p_managed_departments,'[]'::jsonb)) x
  where nullif(trim(x.value),'') is not null;

  if v_role<>'NONE' and cardinality(v_depts)=0 then
    raise exception 'Leadership Role ke liye Managed Department required hai.';
  end if;

  if v_role='NONE' and cardinality(v_depts)>0 then
    raise exception 'Leadership NONE ho to Managed Departments blank hon.';
  end if;

  if v_payroll='SALARIED'
     and v_comp not in(
       'SALARY_ONLY',
       'SALARY_PLUS_FLAT',
       'SALARY_PLUS_SALE_PCS',
       'SALARY_PLUS_FLAT_SALE_PCS'
     )
  then
    raise exception 'SALARIED Worker ke liye valid Salary compensation mode select karein.';
  end if;

  if v_payroll='PIECE_RATE'
     and v_comp not in(
       'PCS_ONLY',
       'PCS_PLUS_FLAT',
       'PCS_PLUS_RATE',
       'PCS_PLUS_FLAT_RATE'
     )
  then
    raise exception 'PIECE_RATE Worker ke liye valid PCS compensation mode select karein.';
  end if;

  if v_comp in(
       'SALARY_PLUS_FLAT',
       'SALARY_PLUS_FLAT_SALE_PCS',
       'PCS_PLUS_FLAT',
       'PCS_PLUS_FLAT_RATE'
     )
     and coalesce(p_monthly_flat_incentive,0)=0
  then
    raise exception 'Selected mode me Monthly Flat Incentive required hai.';
  end if;

  if v_comp not in(
       'SALARY_PLUS_FLAT',
       'SALARY_PLUS_FLAT_SALE_PCS',
       'PCS_PLUS_FLAT',
       'PCS_PLUS_FLAT_RATE'
     )
     and coalesce(p_monthly_flat_incentive,0)<>0
  then
    raise exception 'Selected mode me Monthly Flat Incentive zero rakhein.';
  end if;

  if v_comp in('PCS_PLUS_RATE','PCS_PLUS_FLAT_RATE')
     and (
       v_rate_type='NONE'
       or coalesce(p_rate_enhancement_value,0)=0
     )
  then
    raise exception 'Selected PCS mode me Rate Enhancement required hai.';
  end if;

  if v_comp not in('PCS_PLUS_RATE','PCS_PLUS_FLAT_RATE')
     and (
       v_rate_type<>'NONE'
       or coalesce(p_rate_enhancement_value,0)<>0
     )
  then
    raise exception 'Selected mode me Rate Enhancement NONE/zero rakhein.';
  end if;

  if v_comp in('SALARY_PLUS_SALE_PCS','SALARY_PLUS_FLAT_SALE_PCS')
     and (
       v_sale_basis='NONE'
       or coalesce(p_sale_incentive_rate,0)=0
     )
  then
    raise exception 'Selected Salary mode me Sale PCS Basis aur Rate required hain.';
  end if;

  if v_comp not in('SALARY_PLUS_SALE_PCS','SALARY_PLUS_FLAT_SALE_PCS')
     and (
       v_sale_basis<>'NONE'
       or coalesce(p_sale_incentive_rate,0)<>0
     )
  then
    raise exception 'Selected mode me Sale Incentive NONE/zero rakhein.';
  end if;

  select jsonb_build_object(
    'profile',to_jsonb(p),
    'departments',coalesce((
      select jsonb_agg(d.department_code order by d.department_code)
      from public.rr_worker_leadership_departments_v776 d
      where d.worker_id=p_worker_id and d.is_active
    ),'[]'::jsonb)
  )
  into v_old
  from public.rr_worker_leadership_profile_v776 p
  where p.worker_id=p_worker_id;

  insert into public.rr_worker_leadership_profile_v776(
    worker_id,leadership_role,base_payroll_category,compensation_mode,
    monthly_flat_incentive,rate_enhancement_type,rate_enhancement_value,
    sale_incentive_basis,sale_incentive_rate,
    effective_from,effective_to,status,
    configured_at,configured_by,reason,updated_at
  )
  values(
    p_worker_id,v_role,v_payroll,v_comp,
    coalesce(p_monthly_flat_incentive,0),
    v_rate_type,coalesce(p_rate_enhancement_value,0),
    v_sale_basis,coalesce(p_sale_incentive_rate,0),
    p_effective_from,p_effective_to,v_status,
    now(),auth.uid(),p_reason,now()
  )
  on conflict(worker_id) do update set
    leadership_role=excluded.leadership_role,
    base_payroll_category=excluded.base_payroll_category,
    compensation_mode=excluded.compensation_mode,
    monthly_flat_incentive=excluded.monthly_flat_incentive,
    rate_enhancement_type=excluded.rate_enhancement_type,
    rate_enhancement_value=excluded.rate_enhancement_value,
    sale_incentive_basis=excluded.sale_incentive_basis,
    sale_incentive_rate=excluded.sale_incentive_rate,
    effective_from=excluded.effective_from,
    effective_to=excluded.effective_to,
    status=excluded.status,
    configured_at=now(),
    configured_by=auth.uid(),
    reason=excluded.reason,
    updated_at=now();

  delete from public.rr_worker_leadership_departments_v776
  where worker_id=p_worker_id;

  foreach v_dept in array v_depts loop
    insert into public.rr_worker_leadership_departments_v776(
      worker_id,department_code,is_active,assigned_at,assigned_by,reason
    )
    values(p_worker_id,v_dept,true,now(),auth.uid(),p_reason);
  end loop;

  select jsonb_build_object(
    'profile',to_jsonb(p),
    'departments',coalesce((
      select jsonb_agg(d.department_code order by d.department_code)
      from public.rr_worker_leadership_departments_v776 d
      where d.worker_id=p_worker_id and d.is_active
    ),'[]'::jsonb)
  )
  into v_new
  from public.rr_worker_leadership_profile_v776 p
  where p.worker_id=p_worker_id;

  insert into public.rr_worker_leadership_events_v776(
    worker_id,event_type,old_snapshot,new_snapshot,
    actor_auth_user_id,actor_name,reason
  )
  values(
    p_worker_id,'LEADERSHIP_PROFILE_SET_V777_4_FINAL',
    v_old,v_new,auth.uid(),v_actor.full_name,p_reason
  );

  return jsonb_build_object(
    'ok',true,
    'version','V777_4_FINAL_SALE_INCENTIVE',
    'worker_id',p_worker_id,
    'worker_name',v_worker.worker_name,
    'leadership_role',v_role,
    'base_payroll_category',v_payroll,
    'compensation_mode',v_comp,
    'monthly_flat_incentive',coalesce(p_monthly_flat_incentive,0),
    'rate_enhancement_type',v_rate_type,
    'rate_enhancement_value',coalesce(p_rate_enhancement_value,0),
    'sale_incentive_basis',v_sale_basis,
    'sale_incentive_rate',coalesce(p_sale_incentive_rate,0),
    'ledger_posting_included',false
  );
end $$;

grant execute on function public.rr_set_worker_leadership_v777_4_final(
  uuid,text,jsonb,text,text,numeric,text,numeric,text,numeric,date,date,text,text
) to authenticated;

create or replace view public.rr_worker_leadership_board_v777_4 as
select
  w.worker_id,w.worker_code,w.worker_name,
  w.department_code as primary_job_department,
  w.role_code as worker_role_code,
  w.is_active as worker_is_active,
  w.access_status as worker_access_status,
  coalesce(p.leadership_role,'NONE') as leadership_role,
  coalesce(p.base_payroll_category,'PIECE_RATE') as base_payroll_category,
  coalesce(p.compensation_mode,'PCS_ONLY') as compensation_mode,
  coalesce(p.monthly_flat_incentive,0) as monthly_flat_incentive,
  coalesce(p.rate_enhancement_type,'NONE') as rate_enhancement_type,
  coalesce(p.rate_enhancement_value,0) as rate_enhancement_value,
  coalesce(p.sale_incentive_basis,'NONE') as sale_incentive_basis,
  coalesce(p.sale_incentive_rate,0) as sale_incentive_rate,
  p.effective_from,p.effective_to,
  coalesce(p.status,'ACTIVE') as leadership_status,
  coalesce((
    select jsonb_agg(d.department_code order by d.department_code)
    from public.rr_worker_leadership_departments_v776 d
    where d.worker_id=w.worker_id and d.is_active
  ),'[]'::jsonb) as managed_departments,
  p.updated_at
from public.rr_worker_directory_unified_v1 w
left join public.rr_worker_leadership_profile_v776 p
  on p.worker_id=w.worker_id;

grant select on public.rr_worker_leadership_board_v777_4 to authenticated;

commit;

select jsonb_build_object(
  'ok',true,
  'version','V777_4_FINAL_SALE_INCENTIVE',
  'salaried_modes',jsonb_build_array(
    'SALARY_ONLY',
    'SALARY_PLUS_FLAT',
    'SALARY_PLUS_SALE_PCS',
    'SALARY_PLUS_FLAT_SALE_PCS'
  ),
  'piece_rate_modes',jsonb_build_array(
    'PCS_ONLY',
    'PCS_PLUS_FLAT',
    'PCS_PLUS_RATE',
    'PCS_PLUS_FLAT_RATE'
  ),
  'sale_bases',jsonb_build_array(
    'SOLD_PCS','DISPATCH_PCS','INVOICE_PCS'
  ),
  'new_hybrid_allowed',false,
  'ledger_posting_included',false
) as rr_upm_v777_4_final_result;
