-- REAL FACTORY SALARY VOUCHER TEXT ASCII FIX V786.3.20
-- Run once in Supabase SQL Editor. This does not change any voucher number.

begin;

create or replace function public.rr_salary_voucher_preview_v786(p_payroll_category text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare
  v_category text:=upper(trim(coalesce(p_payroll_category,'')));
  v_prefix text;
  v_last bigint:=0;
  v_next bigint;
begin
  if not public.rr_worker_salary_can_view_v781() then
    raise exception 'Salary payment view permission required.';
  end if;

  v_prefix:=case
    when v_category='PIECE_RATE' then 'PCSL'
    when v_category='SALARIED' then 'MSL'
    else null
  end;
  if v_prefix is null then
    raise exception 'Payroll Category must be PIECE_RATE or SALARIED.';
  end if;

  select greatest(
    coalesce((select s.last_number from public.rr_salary_voucher_sequence_v786 s
      where s.voucher_prefix=v_prefix),0),
    coalesce((select max(substring(upper(trim(b.voucher_no)) from length(v_prefix)+1)::bigint)
      from public.rr_salary_payment_batches_v785 b
      where upper(trim(coalesce(b.voucher_no,'')))~('^'||v_prefix||'[0-9]+$')),0)
  ) into v_last;
  v_next:=v_last+1;

  return jsonb_build_object(
    'ok',true,
    'payroll_category',v_category,
    'voucher_prefix',v_prefix,
    'next_number',v_next,
    'voucher_no',concat(v_prefix,v_next),
    'display_text',concat('NEXT - ',v_prefix,v_next),
    'final_assigned_on_submit',true
  );
end;
$$;

revoke all on function public.rr_salary_voucher_preview_v786(text) from public,anon;
grant execute on function public.rr_salary_voucher_preview_v786(text) to authenticated;

commit;

select case when
  to_regprocedure('public.rr_salary_voucher_preview_v786(text)') is not null
  and position('NEXT - ' in pg_get_functiondef(
    to_regprocedure('public.rr_salary_voucher_preview_v786(text)')
  ))>0
then 'PASS' else 'FAIL' end as salary_voucher_text_fix_v786_3_20_result;
