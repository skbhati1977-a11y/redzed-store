-- TEST71 V614: the rollback-only CB proof RPCs intentionally compose several
-- canonical mutations and projections inside one atomic statement.  The live
-- authenticated role keeps its 8s production timeout; only these guarded E2E
-- proofs receive enough bounded time to finish and roll back under CI load.
begin;

alter function public.rr_test_cb_department_flow_v600()
  set statement_timeout='30s';
alter function public.rr_test_cb_open_draft_invariants_v608()
  set statement_timeout='30s';
alter function public.rr_test_cb_working_art_v611()
  set statement_timeout='30s';

commit;
