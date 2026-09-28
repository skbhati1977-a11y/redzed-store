-- TEST71 compensation-aware submit rate gate.
-- Salaried-team departments use canonical payroll/special-cost engines; individual/unclassified assignments require Actual Rate.
create or replace function public.rr_upm_submit_request_require_actual_rate_v402()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
declare
  a public.rr_upm_work_assignments_v8%rowtype;
  v uuid;
  d text;
  c jsonb;
  is_team boolean;
begin
  if coalesce(array_length(new.assignment_ids,1),0)=0 then
    raise exception 'Submit blocked: Active Assignment is required before receiver handover.';
  end if;
  d:=public.rr_costing_canonical_department_v760(new.department_code);
  foreach v in array new.assignment_ids loop
    select * into a from public.rr_upm_work_assignments_v8 where id=v;
    if not found then raise exception 'Submit blocked: Assignment not found.'; end if;
    if a.canonical_lot_id is distinct from new.canonical_lot_id then raise exception 'Submit blocked: Assignment Lot mismatch.'; end if;
    if public.rr_costing_canonical_department_v760(a.department_code)<>d then raise exception 'Submit blocked: Assignment Department mismatch.'; end if;
    c:=public.rr_department_compensation_choices_v667(a.department_code,'TEST');
    is_team:=coalesce(c->>'auto_mode','')='SALARIED_TEAM';
    if not is_team and coalesce(a.actual_rate,0)<=0 then
      raise exception 'Submit blocked: Assignment Actual Rate required. Lot %, Department %, Worker %, Colour %.',
        coalesce(a.lot_no,'—'),coalesce(a.department_code,'—'),coalesce(a.worker_name_snapshot,'—'),coalesce(a.colour_code,'—');
    end if;
  end loop;
  return new;
end
$function$;