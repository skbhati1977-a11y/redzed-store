-- TEST70 — Missing claim canonical lifecycle
-- Canonical rule shared by App + Real Chat:
-- Missing detected -> responsibility hold -> recovery journey -> Packing Submit remains held
-- -> DESPATCH_FINALIZED -> unresolved balance becomes final worker debit.
--
-- Safe/idempotent migration. Do NOT restore any PACKING_SUBMITTED finalizer.

begin;

-- Legacy packing-stage finalization is forbidden.
revoke execute on function public.rr_upm_missing_packing_finalize_v185(text)
  from public, anon, authenticated, service_role;
drop function if exists public.rr_upm_packing_claim_trigger_v185();
drop function if exists public.rr_upm_missing_packing_finalize_v185(text);

-- Existing custody registration must continue to hold missing until despatch finalization.
-- This assertion intentionally fails installation if a future schema removes the canonical RPC.
do $$
begin
  if to_regprocedure('public.rr_upm_missing_despatch_finalize_v800(text)') is null then
    raise exception 'Canonical missing finalizer rr_upm_missing_despatch_finalize_v800(text) is required.';
  end if;
  if to_regprocedure('public.rr_upm_missing_despatch_final_claim_v800(text)') is null then
    raise exception 'Canonical missing claim alias rr_upm_missing_despatch_final_claim_v800(text) is required.';
  end if;
end$$;

comment on function public.rr_upm_missing_despatch_finalize_v800(text) is
  'CANONICAL missing finalizer. App + Real Chat use the same backend state. Unresolved missing converts to final debit only at DESPATCH_FINALIZED; Packing Submit must not finalize it.';
comment on function public.rr_upm_missing_despatch_final_claim_v800(text) is
  'Canonical DESPATCH_FINALIZED missing-claim entry point. Never call a packing-stage missing finalizer.';

commit;
