-- V9785: map every existing worker/staff identity to one permanent Salary & Wages payable ledger.
begin;

create table if not exists public.rr_worker_accounts_map_v9785(
  worker_id uuid primary key,
  salary_ledger_id uuid not null unique references public.rr_ledgers_v805(id) on delete restrict,
  worker_code text, worker_name text not null, department_code text,
  payroll_category text not null default 'PIECE_RATE', worker_source text,
  linked_auth_user_id uuid, mobile text, is_active boolean not null default true,
  mapped_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.rr_worker_accounts_map_v9785 enable row level security;
revoke all on table public.rr_worker_accounts_map_v9785 from public,anon,authenticated;
create index if not exists rr_worker_accounts_department_v9785
  on public.rr_worker_accounts_map_v9785(department_code,lower(worker_name)) where is_active;

create or replace function public.rr_accounts_worker_salary_sync_v9785(p_worker_id uuid default null)
returns integer language plpgsql security definer set search_path=public as $$
declare v_category uuid;v_count integer;
begin
  if auth.uid() is not null and not public.rr_acct_can_view_v805() then raise exception 'Accounts permission required.'; end if;
  select c.id into v_category from public.rr_account_categories_v805 c
  where c.category_code='SALARY_PAYABLE' and c.is_active limit 1;
  if v_category is null then raise exception 'Salary & Wages Payable account head is missing.'; end if;

  insert into public.rr_ledgers_v805(
    ledger_code,ledger_name,normalized_name,category_id,ledger_kind,linked_entity_type,
    linked_entity_id,mobile,opening_balance,opening_side,is_active,created_by
  )
  select 'SAL-'||upper(substr(md5(w.worker_id::text),1,12)),
    trim(w.worker_name)||' ['||coalesce(nullif(trim(w.worker_code),''),upper(substr(w.worker_id::text,1,8)))||']',
    public.rr_name_normalize_v805(trim(w.worker_name)||' ['||coalesce(nullif(trim(w.worker_code),''),upper(substr(w.worker_id::text,1,8)))||']'),
    v_category,'WORKER','WORKER',w.worker_id::text,d.mobile,0,'CR',
    coalesce(w.is_active,false) and upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE',auth.uid()
  from public.rr_worker_directory_unified_v1 w
  left join public.rr_worker_directory_v1 d on d.id=w.worker_id and w.source<>'ROLE_DIRECTORY'
  where p_worker_id is null or w.worker_id=p_worker_id
  on conflict(ledger_code) do update set ledger_name=excluded.ledger_name,
    normalized_name=excluded.normalized_name,category_id=excluded.category_id,ledger_kind='WORKER',
    linked_entity_type='WORKER',linked_entity_id=excluded.linked_entity_id,
    mobile=coalesce(excluded.mobile,public.rr_ledgers_v805.mobile),is_active=excluded.is_active,updated_at=now();

  insert into public.rr_worker_accounts_map_v9785(
    worker_id,salary_ledger_id,worker_code,worker_name,department_code,payroll_category,
    worker_source,linked_auth_user_id,mobile,is_active,updated_at
  )
  select w.worker_id,l.id,w.worker_code,w.worker_name,w.department_code,
    case when upper(coalesce(p.worker_category,'')) in('SALARIED','MONTHLY','STAFF') then 'SALARIED' else 'PIECE_RATE' end,
    w.source,w.linked_auth_user_id,d.mobile,
    coalesce(w.is_active,false) and upper(coalesce(w.access_status,'ACTIVE'))='ACTIVE',now()
  from public.rr_worker_directory_unified_v1 w
  join public.rr_ledgers_v805 l on l.ledger_code='SAL-'||upper(substr(md5(w.worker_id::text),1,12))
  left join public.rr_worker_directory_v1 d on d.id=w.worker_id and w.source<>'ROLE_DIRECTORY'
  left join lateral(select b.worker_category from public.rr_worker_payroll_board_v777_3 b
    where b.worker_id=w.worker_id order by b.configured_at desc limit 1) p on true
  where p_worker_id is null or w.worker_id=p_worker_id
  on conflict(worker_id) do update set salary_ledger_id=excluded.salary_ledger_id,
    worker_code=excluded.worker_code,worker_name=excluded.worker_name,department_code=excluded.department_code,
    payroll_category=excluded.payroll_category,worker_source=excluded.worker_source,
    linked_auth_user_id=excluded.linked_auth_user_id,
    mobile=coalesce(excluded.mobile,public.rr_worker_accounts_map_v9785.mobile),
    is_active=excluded.is_active,updated_at=now();
  get diagnostics v_count=row_count; return v_count;
end $$;
revoke all on function public.rr_accounts_worker_salary_sync_v9785(uuid) from public,anon;
grant execute on function public.rr_accounts_worker_salary_sync_v9785(uuid) to authenticated,service_role;
select public.rr_accounts_worker_salary_sync_v9785(null);

create or replace function public.rr_accounts_ledger_summary_v9785(
  p_scope text default 'ALL',p_search text default '',p_from_date date default date_trunc('month',current_date)::date,
  p_to_date date default current_date,p_data_mode text default 'TEST'
) returns table(ledger_id uuid,ledger_name text,opening_balance numeric,total_debit numeric,total_credit numeric,
  closing_balance numeric,total_pieces numeric,department_code text,payroll_category text,party_kind text)
language plpgsql security definer set search_path=public as $$
begin
  if not public.rr_acct_can_view_v805() then raise exception 'Accounts permission required.'; end if;
  if upper(coalesce(p_scope,'ALL'))='SALARY' then
    return query with movement as(
      select m.worker_id,m.salary_ledger_id,
        coalesce(sum(case when s.entry_date<p_from_date then -s.balance_effect else 0 end),0) opening,
        coalesce(sum(case when s.entry_date between p_from_date and p_to_date and s.balance_effect<0 then -s.balance_effect else 0 end),0) dr,
        coalesce(sum(case when s.entry_date between p_from_date and p_to_date and s.balance_effect>0 then s.balance_effect else 0 end),0) cr
      from public.rr_worker_accounts_map_v9785 m
      left join public.rr_worker_salary_ledger_v781 s on s.worker_id=m.worker_id
        and s.data_mode=upper(coalesce(p_data_mode,'TEST')) and upper(coalesce(s.status,'POSTED'))='POSTED'
      where m.is_active and (coalesce(trim(p_search),'')='' or m.worker_name ilike '%'||trim(p_search)||'%'
        or coalesce(m.worker_code,'') ilike '%'||trim(p_search)||'%' or coalesce(m.department_code,'') ilike '%'||trim(p_search)||'%')
      group by m.worker_id,m.salary_ledger_id
    )
    select m.salary_ledger_id,m.worker_name,round(x.opening,2),round(x.dr,2),round(x.cr,2),
      round(x.opening+x.dr-x.cr,2),0::numeric,m.department_code,m.payroll_category,'WORKER'
    from movement x join public.rr_worker_accounts_map_v9785 m on m.worker_id=x.worker_id
    order by coalesce(m.department_code,''),lower(m.worker_name);
    return;
  end if;
  return query select s.ledger_id,s.ledger_name,s.opening_balance,s.total_debit,s.total_credit,
    s.closing_balance,s.total_pieces,null::text,null::text,l.ledger_kind
  from public.rr_accounts_ledger_summary_v9775(p_scope,p_search,p_from_date,p_to_date,p_data_mode) s
  join public.rr_ledgers_v805 l on l.id=s.ledger_id;
end $$;

create or replace function public.rr_accounts_ledger_statement_v9785(
  p_ledger_id uuid,p_from_date date,p_to_date date,p_data_mode text default 'TEST'
) returns table(entry_date date,particulars text,voucher_no text,voucher_type text,debit numeric,credit numeric,
  running_balance numeric,piece_qty numeric,pi_id uuid,pi_no text,cpi_no text,requirement_id uuid)
language plpgsql security definer set search_path=public as $$
declare v_worker uuid;v_open numeric;
begin
  if not public.rr_acct_can_view_v805() then raise exception 'Accounts permission required.'; end if;
  select m.worker_id into v_worker from public.rr_worker_accounts_map_v9785 m where m.salary_ledger_id=p_ledger_id and m.is_active;
  if v_worker is null then
    return query select * from public.rr_accounts_ledger_statement_v9777(p_ledger_id,p_from_date,p_to_date,p_data_mode);
    return;
  end if;
  select coalesce(sum(-s.balance_effect),0) into v_open from public.rr_worker_salary_ledger_v781 s
  where s.worker_id=v_worker and s.data_mode=upper(coalesce(p_data_mode,'TEST'))
    and upper(coalesce(s.status,'POSTED'))='POSTED' and s.entry_date<p_from_date;
  return query select s.entry_date,
    case when upper(s.entry_type) like '%PAY%' then 'Payment' when upper(s.entry_type) like '%ADVANCE%' then 'Advance'
      when upper(s.entry_type) like '%DEDUCT%' or upper(s.entry_type) like '%RECOVER%' then 'Deduction'
      when upper(s.payroll_category)='SALARIED' then 'Salary' else 'Wages' end,
    coalesce(nullif(trim(s.reference_no),''),nullif(trim(s.source_key),''),'SAL-'||upper(substr(s.id::text,1,8))),
    case when upper(s.payroll_category)='SALARIED' then 'Salary' else 'Wages' end,
    round(case when s.balance_effect<0 then -s.balance_effect else 0 end,2),
    round(case when s.balance_effect>0 then s.balance_effect else 0 end,2),
    round(v_open+sum(-s.balance_effect) over(order by s.entry_date,s.created_at,s.id rows unbounded preceding),2),
    0::numeric,null::uuid,null::text,null::text,null::uuid
  from public.rr_worker_salary_ledger_v781 s
  where s.worker_id=v_worker and s.data_mode=upper(coalesce(p_data_mode,'TEST'))
    and upper(coalesce(s.status,'POSTED'))='POSTED' and s.entry_date between p_from_date and p_to_date
  order by s.entry_date,s.created_at,s.id;
end $$;
revoke all on function public.rr_accounts_ledger_summary_v9785(text,text,date,date,text),
  public.rr_accounts_ledger_statement_v9785(uuid,date,date,text) from public,anon;
grant execute on function public.rr_accounts_ledger_summary_v9785(text,text,date,date,text),
  public.rr_accounts_ledger_statement_v9785(uuid,date,date,text) to authenticated,service_role;
commit;
