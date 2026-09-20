-- TEST71 Checkpoint 5 V332
-- The V331 wrapper is the only client-facing Fabrication projection.  The
-- renamed V330 core must not be callable directly by an authenticated client,
-- otherwise a non-selected participant could bypass the read-only projection.
begin;

revoke all on function public.rr_real_chat_work_search_v317_core_v330(text,text,text,integer)
from public,anon,authenticated;
grant execute on function public.rr_real_chat_work_search_v317_core_v330(text,text,text,integer)
to service_role;

comment on function public.rr_real_chat_work_search_v317_core_v330(text,text,text,integer) is
'TEST71 V332: internal canonical state core; client access is restricted to the V331 authorization wrapper.';

commit;
