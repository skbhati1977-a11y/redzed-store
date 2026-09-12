-- V9786: preserve legacy salary IDs and expose them through the unique current worker identity.
begin;
create table if not exists public.rr_salary_worker_alias_v9786(
  legacy_worker_id uuid primary key,
  canonical_worker_id uuid not null references public.rr_worker_accounts_map_v9785(worker_id) on delete restrict,
  match_method text not null default 'EXACT_NAME_DEPARTMENT',
  mapped_at timestamptz not null default now()
);
alter table public.rr_salary_worker_alias_v9786 enable row level security;
revoke all on table public.rr_salary_worker_alias_v9786 from public,anon,authenticated;

insert into public.rr_salary_worker_alias_v9786(legacy_worker_id,canonical_worker_id)
select distinct s.worker_id,m.worker_id
from public.rr_worker_salary_ledger_v781 s
join public.rr_worker_accounts_map_v9785 m
  on lower(trim(m.worker_name))=lower(trim(s.worker_name))
 and regexp_replace(lower(coalesce(m.department_code,'')),'[^a-z0-9]','','g')
   =regexp_replace(lower(coalesce(s.department_code,'')),'[^a-z0-9]','','g')
where (select count(*) from public.rr_worker_accounts_map_v9785 z
  where lower(trim(z.worker_name))=lower(trim(s.worker_name))
  and regexp_replace(lower(coalesce(z.department_code,'')),'[^a-z0-9]','','g')
    =regexp_replace(lower(coalesce(s.department_code,'')),'[^a-z0-9]','','g'))=1
on conflict(legacy_worker_id) do update
set canonical_worker_id=excluded.canonical_worker_id,match_method='EXACT_NAME_DEPARTMENT',mapped_at=now();

create or replace view public.rr_worker_salary_ledger_accounts_v9786
with (security_invoker=true) as
select s.id,s.data_mode,coalesce(a.canonical_worker_id,s.worker_id) worker_id,
  s.worker_name,s.worker_code,s.department_code,s.payroll_category,s.source_module,s.source_run_id,
  s.source_line_id,s.period_month,s.entry_date,s.entry_type,s.amount,s.balance_effect,s.due_entry_id,
  s.related_entry_id,s.payment_mode,s.reference_no,s.remarks,s.status,s.created_by,s.created_by_name,
  s.created_at,s.voided_by,s.voided_by_name,s.voided_at,s.void_reason,s.source_key,s.bulk_batch_id,
  s.bulk_line_id,s.earning_window_start,s.earning_window_end
from public.rr_worker_salary_ledger_v781 s
left join public.rr_salary_worker_alias_v9786 a on a.legacy_worker_id=s.worker_id;
revoke all on public.rr_worker_salary_ledger_accounts_v9786 from public,anon,authenticated;
grant select on public.rr_worker_salary_ledger_accounts_v9786 to service_role;

do $$
declare v_sql text;
begin
  select pg_get_functiondef('public.rr_accounts_ledger_summary_v9785(text,text,date,date,text)'::regprocedure) into v_sql;
  v_sql:=replace(v_sql,'public.rr_worker_salary_ledger_v781 s','public.rr_worker_salary_ledger_accounts_v9786 s');
  if position('rr_worker_salary_ledger_accounts_v9786' in v_sql)=0 then raise exception 'Salary summary alias injection failed.'; end if;
  execute v_sql;

  select pg_get_functiondef('public.rr_accounts_ledger_statement_v9785(uuid,date,date,text)'::regprocedure) into v_sql;
  v_sql:=replace(v_sql,'public.rr_worker_salary_ledger_v781 s','public.rr_worker_salary_ledger_accounts_v9786 s');
  if position('rr_worker_salary_ledger_accounts_v9786' in v_sql)=0 then raise exception 'Salary statement alias injection failed.'; end if;
  execute v_sql;
end $$;
commit;
