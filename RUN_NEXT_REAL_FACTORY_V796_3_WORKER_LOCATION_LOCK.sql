-- REAL FACTORY V796.3
-- Run after V796.2. TEST-only worker-level L1/L2 consistency repair.
begin;

create table if not exists public.rr_test_worker_location_v796 (
  worker_id uuid primary key,
  worker_name text,
  premise_id uuid not null,
  premise_code text not null check (premise_code in ('L1','L2')),
  data_mode text not null default 'TEST' check (data_mode='TEST'),
  is_active boolean not null default true,
  allocated_at timestamptz not null default now()
);

do $$
declare
  v_l1 uuid;
  v_l2 uuid;
  v_changed integer;
  v_pass integer:=0;
  v_row record;
begin
  select premise_id into v_l1 from public.rr_attendance_premises_v778_1
   where upper(premise_code)='L1' and upper(data_mode)='TEST' and is_active
   order by created_at nulls last,premise_id limit 1;
  select premise_id into v_l2 from public.rr_attendance_premises_v778_1
   where upper(premise_code)='L2' and upper(data_mode)='TEST' and is_active
   order by created_at nulls last,premise_id limit 1;
  if v_l1 is null or v_l2 is null then raise exception 'Canonical TEST premises L1 and L2 are required.'; end if;

  create temporary table tmp_worker_loc on commit drop as
  with workers as (
    select distinct w.worker_id,w.worker_name
    from public.rr_worker_department_map_v1 m
    join public.rr_worker_directory_unified_v1 w on w.worker_id=m.worker_id
    where coalesce(m.is_active,true) and coalesce(w.is_active,true)
      and upper(m.department_code)<>'CUTTING'
  )
  select worker_id,worker_name,
         case when row_number() over(order by coalesce(worker_name,''),worker_id)%2=1 then 'L1' else 'L2' end::text premise_code
  from workers;

  -- Deterministic repair: flip the least-shared worker in a department that has
  -- two or more workers but only one colour. Stop safely if no further change.
  loop
    exit when v_pass>=100;
    v_pass:=v_pass+1;
    v_changed:=0;
    for v_row in
      with membership as (
        select upper(m.department_code) department_code,t.worker_id,t.premise_code,
               count(*) over(partition by t.worker_id) shared_count
        from public.rr_worker_department_map_v1 m join tmp_worker_loc t on t.worker_id=m.worker_id
        where coalesce(m.is_active,true) and upper(m.department_code)<>'CUTTING'
      ), bad as (
        select department_code,min(premise_code) only_code
        from membership group by department_code
        having count(distinct worker_id)>=2 and count(distinct premise_code)=1
      )
      select distinct on (b.department_code) b.department_code,m.worker_id,b.only_code
      from bad b join membership m using(department_code)
      order by b.department_code,m.shared_count,m.worker_id
    loop
      update tmp_worker_loc set premise_code=case when v_row.only_code='L1' then 'L2' else 'L1' end
       where worker_id=v_row.worker_id and premise_code=v_row.only_code;
      if found then v_changed:=v_changed+1; end if;
    end loop;
    exit when v_changed=0;
  end loop;

  insert into public.rr_test_worker_location_v796(worker_id,worker_name,premise_id,premise_code,data_mode,is_active,allocated_at)
  select worker_id,worker_name,case when premise_code='L1' then v_l1 else v_l2 end,premise_code,'TEST',true,now()
  from tmp_worker_loc
  on conflict(worker_id) do update set worker_name=excluded.worker_name,premise_id=excluded.premise_id,
    premise_code=excluded.premise_code,data_mode='TEST',is_active=true,allocated_at=now();

  update public.rr_test_location_allocation_v796 set is_active=false where data_mode='TEST';
  insert into public.rr_test_location_allocation_v796
    (department_code,worker_id,worker_name,premise_id,premise_code,allocation_rank,data_mode,is_active,allocated_at)
  with eligible as (
    select upper(m.department_code) department_code,t.worker_id,t.worker_name,t.premise_id,t.premise_code,
      row_number() over(partition by upper(m.department_code),t.premise_code order by coalesce(t.worker_name,''),t.worker_id) pick_rank
    from public.rr_worker_department_map_v1 m join public.rr_test_worker_location_v796 t on t.worker_id=m.worker_id and t.is_active
    where coalesce(m.is_active,true) and upper(m.department_code)<>'CUTTING'
  ), picked as (
    select *,case premise_code when 'L1' then 1 else 2 end allocation_rank from eligible where pick_rank=1
  )
  select department_code,worker_id,worker_name,premise_id,premise_code,allocation_rank,'TEST',true,now() from picked
  on conflict(department_code,worker_id,data_mode) do update set worker_name=excluded.worker_name,
    premise_id=excluded.premise_id,premise_code=excluded.premise_code,allocation_rank=excluded.allocation_rank,is_active=true,allocated_at=now();

  -- One active TEST attendance premise per worker, matching the canonical lock.
  update public.rr_worker_attendance_premises_v778_1 wp set is_active=false,
    effective_to=case when effective_from<current_date then current_date-1 else effective_from end,
    reason='Replaced by REAL FACTORY V796.3 worker location lock'
  where wp.is_active and wp.premise_id in(v_l1,v_l2)
    and exists(select 1 from public.rr_test_worker_location_v796 t where t.worker_id=wp.worker_id and t.is_active);

  insert into public.rr_worker_attendance_premises_v778_1
    (worker_id,premise_id,is_primary,is_active,effective_from,assigned_at,assigned_by,reason)
  select worker_id,premise_id,true,true,current_date,now(),auth.uid(),'V796.3 TEST canonical worker location'
  from public.rr_test_worker_location_v796 where is_active
  on conflict(worker_id,premise_id,effective_from) do update set is_primary=true,is_active=true,effective_to=null,
    assigned_at=now(),assigned_by=auth.uid(),reason=excluded.reason;
end $$;

commit;

select jsonb_build_object('ok',true,'version','V796_3','next','Run VERIFY_REAL_FACTORY_V796_3.sql');
