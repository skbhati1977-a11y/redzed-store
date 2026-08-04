-- Read-only verification for V769
select
  to_regclass('public.rr_upm_worker_claim_warning_v769') as warning_table,
  to_regprocedure(
    'public.rr_upm_worker_claim_warning_gate_v769(text,text,text,text,text,text,numeric,boolean,jsonb)'
  ) as warning_gate_rpc;

select
  canonical_lot_id,
  department_code,
  colour_code,
  size_code,
  worker_id,
  reason_code,
  warning_no,
  qty,
  warning_at,
  conversion_authorized
from public.rr_upm_worker_claim_warning_v769
order by warning_at desc
limit 50;
