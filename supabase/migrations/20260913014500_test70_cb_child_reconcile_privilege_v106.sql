-- TEST70 V106: reconciliation runs from trusted triggers/service jobs, never from the browser.
begin;
revoke all on function public.rr_real_chat_reconcile_cb_children_v105() from public,anon,authenticated;
grant execute on function public.rr_real_chat_reconcile_cb_children_v105() to service_role;
commit;
