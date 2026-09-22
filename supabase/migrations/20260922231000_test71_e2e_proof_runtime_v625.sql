-- TEST71 V625: rollback-only proof RPCs must be bounded consistently, and a
-- slow cold plan must return a database timeout instead of outliving the
-- browser checkpoint. No business writer or retained TEST row is changed.
begin;

alter function public.rr_test_cb_material_unit_v610()
  set statement_timeout='30s';

comment on function public.rr_test_cb_material_unit_v610() is
  'Rollback-only TEST71 proof: selected CB Unit wins over category default, DUE Qty remains NULL, retry is single, residue is zero; execution is bounded to 30 seconds.';

notify pgrst,'reload schema';
commit;
