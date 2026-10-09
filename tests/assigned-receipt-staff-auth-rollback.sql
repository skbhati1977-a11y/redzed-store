begin;
select set_config('request.jwt.claim.sub','af915a18-3823-48df-b039-1e4c7a88479b',true),set_config('rr_chat_notifications_test71.test_run','on',true);
create temp table staff_count_checks(name text,passed boolean);
DO $$
declare a uuid;ctx jsonb;input jsonb;r jsonb;uid uuid:=auth.uid();original jsonb;n int:=0;
begin
 if public.rr_upm_current_worker_id_v9112() is not null or not public.rr_upm_fabrication_receiver_allowed_v770() then raise exception 'Regression fixture requires authenticated staff without worker mapping';end if;
 for a in select x.id from public.rr_upm_work_assignments_v8 x join public.rr_upm_assignment_receipts_v9112 z on z.assignment_id=x.id where x.status in('ASSIGNED','IN_PROGRESS') and z.status='PENDING' and not exists(select 1 from public.rr_upm_submit_requests_v794 q where x.id=any(q.assignment_ids) and q.status not in('CANCELLED','CANCELED','REJECTED','VOID')) loop
  ctx:=public.rr_chat_assignment_count_context_test71(a);if jsonb_array_length(ctx->'rows')=0 then raise exception 'Staff context empty';end if;n:=n+1;
 end loop;
 if n=0 then raise exception 'No pending receipt fixture';end if;
 insert into staff_count_checks values('authenticated staff without worker mapping opens every pending assignment',true);
 select x.id into a from public.rr_upm_work_assignments_v8 x join public.rr_upm_assignment_receipts_v9112 z on z.assignment_id=x.id where z.status='PENDING' and x.status in('ASSIGNED','IN_PROGRESS') and not exists(select 1 from public.rr_upm_submit_requests_v794 q where x.id=any(q.assignment_ids) and q.status not in('CANCELLED','CANCELED','REJECTED','VOID')) limit 1;
 ctx:=public.rr_chat_assignment_count_context_test71(a);
 select jsonb_agg(jsonb_build_object('assignment_id',x->>'assignment_id','confirmed_qty',x->'expected_qty')) into input from jsonb_array_elements(ctx->'rows')x;
 r:=public.rr_chat_assignment_count_save_test71(a,input,null);
 if exists(select 1 from jsonb_array_elements(ctx->'rows')x join public.rr_upm_assignment_receipts_v9112 z on z.assignment_id=(x->>'assignment_id')::uuid where z.status<>'CONFIRMED' or z.confirmed_by is distinct from uid) then raise exception 'Staff Save attribution failed';end if;
 insert into staff_count_checks values('authorized staff saves full count with actual performer attribution',true);
 perform set_config('request.jwt.claim.sub','',true);
 begin perform public.rr_chat_assignment_count_context_test71(a);raise exception 'Unauthenticated context allowed';exception when others then if sqlerrm='Unauthenticated context allowed' then raise;end if;end;
 insert into staff_count_checks values('unauthenticated context remains denied',true);
end $$;
select * from staff_count_checks;
rollback;
