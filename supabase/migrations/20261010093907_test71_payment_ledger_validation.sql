BEGIN;
CREATE OR REPLACE FUNCTION public.rr_accounts_post_payment_v805(p_against_ledger_id uuid, p_cash_bank_ledger_id uuid, p_amount numeric, p_ref_no text DEFAULT NULL::text, p_narration text DEFAULT NULL::text, p_data_mode text DEFAULT 'TEST'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.rr_acct_can_view_v805() then raise exception 'Accounts permission required.' using errcode='42501'; end if;
  if p_against_ledger_id is null or p_against_ledger_id=p_cash_bank_ledger_id then raise exception 'Payment party and Cash/Bank must be different active ledgers.'; end if;
  if not exists(select 1 from public.rr_ledgers_v805 where id=p_cash_bank_ledger_id and is_active and upper(ledger_kind) in('CASH','BANK')) then raise exception 'Active Cash/Bank payment source required.'; end if;
  if not exists(select 1 from public.rr_ledgers_v805 where id=p_against_ledger_id and is_active and upper(ledger_kind) not in('CASH','BANK')) then raise exception 'Active party or expense ledger required.'; end if;

  return public.rr_accounts_post_v805(
    'PAYMENT',
    p_amount,
    jsonb_build_array(
      jsonb_build_object(
        'ledger_id', p_against_ledger_id,
        'dr', p_amount,
        'cr', 0,
        'narration', 'Payment / Expense'
      ),
      jsonb_build_object(
        'ledger_id', p_cash_bank_ledger_id,
        'dr', 0,
        'cr', p_amount,
        'narration', 'Paid From Cash / Bank'
      )
    ),
    'ACCOUNTS_TEMPLATE',
    gen_random_uuid()::text,
    p_against_ledger_id,
    p_ref_no,
    current_date,
    p_narration,
    p_data_mode
  );
end $function$
;
CREATE OR REPLACE FUNCTION public.rr_worker_salary_can_pay_v781() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO public AS $f$
 SELECT auth.uid() IS NOT NULL AND EXISTS(SELECT 1 FROM public.rr_user_profiles p WHERE p.auth_user_id=auth.uid() AND coalesce(p.is_active,false) AND upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE')
 AND lower(coalesce(public.rr_upm_effective_identity_v200()->>'resolved_role',public.rr_upm_effective_identity_v200()->>'role_code','')) IN ('owner','super_admin','admin','account','accounts','payroll');
$f$;
REVOKE EXECUTE ON FUNCTION public.rr_worker_salary_can_pay_v781() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_worker_salary_can_pay_v781() TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_worker_salary_can_reverse_v781() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO public AS $f$
 SELECT auth.uid() IS NOT NULL AND EXISTS(SELECT 1 FROM public.rr_user_profiles p WHERE p.auth_user_id=auth.uid() AND coalesce(p.is_active,false) AND upper(coalesce(p.access_status,'ACTIVE'))='ACTIVE')
 AND lower(coalesce(public.rr_upm_effective_identity_v200()->>'resolved_role',public.rr_upm_effective_identity_v200()->>'role_code','')) IN ('owner','super_admin','admin','account','accounts');
$f$;
REVOKE EXECUTE ON FUNCTION public.rr_worker_salary_can_reverse_v781() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_worker_salary_can_reverse_v781() TO authenticated;
COMMIT;

