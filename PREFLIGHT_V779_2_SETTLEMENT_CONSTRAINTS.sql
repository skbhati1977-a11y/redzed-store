
-- Run after V779.1 verification.
-- Read-only check required before settlement/ledger posting is added.

select
  t.relname as table_name,
  c.conname as constraint_name,
  c.contype as constraint_type,
  pg_get_constraintdef(c.oid) as definition
from pg_constraint c
join pg_class t on t.oid=c.conrelid
join pg_namespace n on n.oid=t.relnamespace
where n.nspname='public'
  and t.relname in(
    'rr_worker_settlements_v777_2',
    'rr_worker_advances_v777_2',
    'rr_worker_claims_v777_2'
  )
order by t.relname,c.contype,c.conname;
