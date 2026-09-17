create or replace function public.rr_upm_accept_physical_count_batch_v802(
  p_receipt_batch_id uuid,
  p_rows jsonb,
  p_note text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_result jsonb; v_row jsonb; v_assignment uuid; v_event uuid;
  v_worker uuid:=public.rr_upm_current_worker_id_v9112();
begin
  if v_worker is null then raise exception 'Effective worker identity is required.'; end if;
  v_result:=public.rr_upm_confirm_assignment_receipt_batch_v204(p_receipt_batch_id,p_rows,p_note);
  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_assignment:=nullif(v_row->>'assignment_id','')::uuid;
    select e.id into v_event from public.rr_upm_responsibility_events_v800 e
     where e.assignment_id=v_assignment::text and upper(e.event_type)='ASSIGN_HANDOVER'
       and nullif(e.receiver_worker_id,'')::uuid=v_worker
       and upper(e.status) in ('OFFERED','GIVER_CONFIRMED')
     order by e.created_at desc limit 1;
    if v_event is not null then
      perform public.rr_upm_responsibility_respond_v800(v_event,v_worker::text,'ACCEPT',p_note,null);
    end if;
  end loop;
  return v_result||jsonb_build_object('canonical_path','ACCEPT_PHYSICAL_COUNT_BATCH_V802');
end $$;
revoke all on function public.rr_upm_accept_physical_count_batch_v802(uuid,jsonb,text) from public,anon;
grant execute on function public.rr_upm_accept_physical_count_batch_v802(uuid,jsonb,text) to authenticated;
comment on function public.rr_upm_accept_physical_count_batch_v802(uuid,jsonb,text) is 'Canonical App + Real Chat Accept & Count batch path. Reuses V204 physical count/missing/custody engine and mirrors acceptance into responsibility events in the same transaction.';
