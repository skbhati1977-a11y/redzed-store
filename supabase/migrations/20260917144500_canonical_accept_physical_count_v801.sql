-- TEST70 canonical Accept & Count path for App + Real Chat.
-- One backend transaction: physical Good count -> custody Missing hold -> responsibility acceptance.
-- Existing Alter flow is untouched. Missing remains recoverable until DESPATCH_FINALIZED.

create or replace function public.rr_upm_accept_physical_count_v801(
  p_event_id uuid,
  p_worker_id text,
  p_counted_good_qty numeric,
  p_reason text default null,
  p_payroll_category text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  e public.rr_upm_responsibility_events_v800%rowtype;
  a public.rr_upm_work_assignments_v8%rowtype;
  v_expected numeric;
  v_counted numeric := coalesce(p_counted_good_qty,0);
  v_missing jsonb := '{}'::jsonb;
  v_accept jsonb;
  v_owner_id text;
  v_owner_name text;
  v_owner_type text;
begin
  select * into e from public.rr_upm_responsibility_events_v800 where id=p_event_id for update;
  if not found then raise exception 'Responsibility event not found.'; end if;
  if e.event_type <> 'ASSIGN_HANDOVER' then raise exception 'Accept & Count is only valid for assignment handover.'; end if;
  if coalesce(e.receiver_worker_id,'') <> coalesce(p_worker_id,'') then raise exception 'Only mapped receiver can Accept & Count.'; end if;
  if e.status not in ('OFFERED','GIVER_CONFIRMED') then raise exception 'Event already closed with status %',e.status; end if;
  if e.assignment_id like 'ASSIGN-BATCH-%' then raise exception 'Bulk handover must be accepted assignment-wise with physical count.'; end if;

  select * into a from public.rr_upm_work_assignments_v8 where id=e.assignment_id::uuid for update;
  if not found then raise exception 'Mapped assignment not found.'; end if;

  v_expected := coalesce(nullif(a.inbound_qty,0),a.assigned_qty,e.qty,0);
  if v_counted < 0 or v_counted > v_expected then
    raise exception 'Counted Good Qty must be between 0 and expected Good Qty %.',v_expected;
  end if;

  v_owner_id := coalesce(e.giver_worker_id,a.assigned_by::text);
  v_owner_name := coalesce(e.giver_name,a.assigned_by_name,'Assigning Staff');
  v_owner_type := case when a.assigner_worker_id is not null then 'WORKER' else 'STAFF' end;

  if v_counted < v_expected then
    v_missing := public.rr_upm_register_custody_missing_v185(
      a.id,v_expected,v_counted,v_owner_id,v_owner_name,v_owner_type,'ASSIGN_RECEIPT'
    );
  end if;

  v_accept := public.rr_upm_responsibility_respond_v800(
    p_event_id,p_worker_id,'ACCEPT',p_reason,p_payroll_category
  );

  update public.rr_upm_responsibility_events_v800
     set payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object(
       'expected_good_qty',v_expected,'counted_good_qty',v_counted,
       'missing_qty',greatest(v_expected-v_counted,0),
       'count_source','PHYSICAL_ACCEPT_COUNT','missing_hold_until','DESPATCH_FINALIZED'
     ),updated_at=now()
   where id=p_event_id;

  return v_accept||jsonb_build_object(
    'assignment_id',a.id,'lot_no',a.lot_no,'department_code',a.department_code,
    'colour_code',a.colour_code,'expected_good_qty',v_expected,
    'counted_good_qty',v_counted,'missing_qty',greatest(v_expected-v_counted,0),
    'missing',v_missing,'canonical_path','ACCEPT_PHYSICAL_COUNT_V801'
  );
end $$;

revoke all on function public.rr_upm_accept_physical_count_v801(uuid,text,numeric,text,text) from public,anon;
grant execute on function public.rr_upm_accept_physical_count_v801(uuid,text,numeric,text,text) to authenticated;
comment on function public.rr_upm_accept_physical_count_v801(uuid,text,numeric,text,text) is
'Canonical App + Real Chat Accept & Count transaction: physical good count, custody missing registration, then responsibility acceptance. Missing remains held until DESPATCH_FINALIZED.';
