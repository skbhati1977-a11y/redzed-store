-- REAL FACTORY V801.2 — CUTTING MASTER BACKEND WORKER MAPPING CHECK
-- No new worker table is created.
-- Cutting Master UI must use the existing authoritative unified worker RPC.

select *
from public.rr_upm_worker_list_v8_3('CUTTING');
