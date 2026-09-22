-- TEST71 V617: rollback-only Cutting proofs compose several canonical writers
-- in one authenticated statement. Keep the production role timeout unchanged;
-- only the guarded TEST E2E proof functions receive a bounded allowance.
begin;

alter function public.rr_test_cutting_department_lifecycle_v615()
  set statement_timeout='45s';

alter function public.rr_test_released_dcard_regression_v502()
  set statement_timeout='30s';

commit;
