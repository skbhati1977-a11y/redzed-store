-- Final salary-cost authority wrapper. Payroll remains the payable-salary authority.
create or replace function public.rr_costing_salary_final_v403(p_canonical_lot_id text,p_data_mode text default 'TEST')
returns jsonb language sql stable security definer set search_path to 'public' as $function$
 select public.rr_costing_salary_reconciliation_v402(p_canonical_lot_id,p_data_mode)
$function$;
create or replace function public.rr_costing_salary_final_gate_v403(p_canonical_lot_id text,p_data_mode text default 'TEST')
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare s jsonb:=public.rr_costing_salary_final_v403(p_canonical_lot_id,p_data_mode);
begin return jsonb_build_object('ok',coalesce((s->>'final_actual_salary_cost')::boolean,false),'state',s->>'payroll_reconciliation_state','salary',s,'rule','FINAL ACTUAL COSTING REQUIRES MONTH-MATCHED PAYROLL; PROVISIONAL UI MAY DISPLAY BEFORE PAYROLL');end $function$;