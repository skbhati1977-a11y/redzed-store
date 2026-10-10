CREATE OR REPLACE FUNCTION public.rr_advance_payment_preview_v785(p_data_mode text, p_payroll_category_filter text DEFAULT 'ALL'::text, p_worker_ids uuid[] DEFAULT NULL::uuid[], p_worker_amounts jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_mode text:=upper(coalesce(nullif(trim(p_data_mode),''),'REAL')); v_cat text:=upper(coalesce(nullif(trim(p_payroll_category_filter),''),'ALL'));
begin
  if not public.rr_worker_salary_can_view_v781() then raise exception 'Advance payment view permission required.'; end if;
  if v_mode not in('TEST','REAL') then raise exception 'Invalid Data Mode.';end if;
  if v_cat not in('ALL','PIECE_RATE','SALARIED') then raise exception 'Invalid category filter.'; end if;
  create temporary table if not exists rr_advance_preview_tmp_v785(
    worker_id uuid primary key,worker_name text,worker_code text,department_code text,payroll_category text,
    payment_selected boolean,existing_advance_balance numeric(16,2),new_advance_amount numeric(16,2),updated_advance_balance numeric(16,2)
  ) on commit drop;
  truncate rr_advance_preview_tmp_v785;
  insert into rr_advance_preview_tmp_v785(worker_id,worker_name,worker_code,department_code,payroll_category,payment_selected,existing_advance_balance,updated_advance_balance)
  select w.worker_id,w.worker_name,w.worker_code,w.department_code,w.worker_category,
    (p_worker_ids is null or w.worker_id=any(p_worker_ids)),
    coalesce(a.total_advance_balance,0),coalesce(a.total_advance_balance,0)
  from (
    select distinct on(worker_id) * from public.rr_worker_payroll_board_v777_3
    where data_mode=v_mode and payroll_profile_status='ACTIVE'
      and worker_category in('SALARIED','PIECE_RATE')
      and coalesce(effective_from,(now() at time zone 'Asia/Kolkata')::date)<=(now() at time zone 'Asia/Kolkata')::date
      and coalesce(effective_to,(now() at time zone 'Asia/Kolkata')::date)>=(now() at time zone 'Asia/Kolkata')::date
    order by worker_id,effective_from desc nulls last
  ) w left join public.rr_worker_advance_balance_v785 a
    on a.worker_id=w.worker_id and a.data_mode=v_mode
  where v_cat='ALL' or w.worker_category=v_cat;
  update rr_advance_preview_tmp_v785 t
  set new_advance_amount=round(greatest(coalesce(x.amount_paid,0),0),2),
      updated_advance_balance=t.existing_advance_balance+round(greatest(coalesce(x.amount_paid,0),0),2)
  from jsonb_to_recordset(coalesce(p_worker_amounts,'[]'::jsonb)) x(worker_id uuid,amount_paid numeric)
  where t.worker_id=x.worker_id and t.payment_selected;
  return jsonb_build_object(
    'ok',true,'data_mode',v_mode,'payroll_category_filter',v_cat,
    'advance_worker_count',(select count(*) from rr_advance_preview_tmp_v785),
    'selected_worker_count',(select count(*) from rr_advance_preview_tmp_v785 where payment_selected),
    'existing_advance_total',(select round(coalesce(sum(existing_advance_balance),0),2) from rr_advance_preview_tmp_v785),
    'new_advance_payment_total',(select round(coalesce(sum(new_advance_amount),0),2) from rr_advance_preview_tmp_v785 where payment_selected),
    'updated_advance_total',(select round(coalesce(sum(updated_advance_balance),0),2) from rr_advance_preview_tmp_v785),
    'lines',coalesce((select jsonb_agg(to_jsonb(t) order by t.existing_advance_balance desc,t.worker_name) from rr_advance_preview_tmp_v785 t),'[]'::jsonb)
  );
end;
$function$
;
