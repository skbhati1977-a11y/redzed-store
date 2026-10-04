-- Remove only the unused, read-only candidate introduced during this receipt task.
-- The concurrently published V2 context and audit RPCs remain the single active flow.
-- No business rows, existing table grants, or V2 functions are changed.
drop function if exists public.rr_cb_requirement_receipt_context_test71(uuid,text,uuid);
drop function if exists test71_private.cb_requirement_receipt_context_v1(uuid,text,uuid);
drop schema if exists test71_private;
notify pgrst,'reload schema';
