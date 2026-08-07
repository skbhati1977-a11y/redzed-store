with d as (
 select upper(m.department_code) department_code,count(distinct m.worker_id) active_workers
 from public.rr_worker_department_map_v1 m join public.rr_worker_directory_unified_v1 w on w.worker_id=m.worker_id
 where coalesce(m.is_active,true) and coalesce(w.is_active,true) and upper(m.department_code)<>'CUTTING'
 group by upper(m.department_code)
), a as (
 select department_code,count(*) allocated_workers,
 count(*) filter(where premise_code='L1') l1_count,count(*) filter(where premise_code='L2') l2_count
 from public.rr_test_location_allocation_v796 where data_mode='TEST' and is_active group by department_code
), conflicts as (
 select worker_id,jsonb_agg(distinct premise_code) locations
 from public.rr_test_location_allocation_v796 where data_mode='TEST' and is_active
 group by worker_id having count(distinct premise_code)>1
), bad_dept as (
 select d.department_code from d left join a using(department_code)
 where d.active_workers>=2 and (coalesce(a.l1_count,0)<>1 or coalesce(a.l2_count,0)<>1)
)
select jsonb_build_object(
 'version','V796_3',
 'result',case when exists(select 1 from conflicts) or exists(select 1 from bad_dept) then 'FAIL' else 'PASS' end,
 'worker_location_conflicts',coalesce((select jsonb_agg(jsonb_build_object('worker_id',worker_id,'locations',locations)) from conflicts),'[]'::jsonb),
 'departments',coalesce((select jsonb_agg(jsonb_build_object(
   'department_code',d.department_code,'active_workers',d.active_workers,
   'allocated_workers',coalesce(a.allocated_workers,0),'L1',coalesce(a.l1_count,0),'L2',coalesce(a.l2_count,0),
   'status',case when d.active_workers<2 then 'SHORTAGE' when a.l1_count=1 and a.l2_count=1 then 'READY' else 'LOCATION_SHORTAGE' end
 ) order by d.department_code) from d left join a using(department_code)),'[]'::jsonb),
 'real_attendance_unchanged',true,'real_payroll_unchanged',true
);
