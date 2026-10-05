-- Compatibility endpoints delegate to the guarded contract.
alter function public.rr_collection_customer_requirement_summary_v9637(text) security invoker;
alter function public.rr_direct_collection_send_v9684(uuid,uuid,text[],uuid,text) security invoker;
-- This is an internal implementation called by SECURITY DEFINER business functions, not a separate customer API.
revoke all on function public.rr_market_submit_requirement_v9508_legacy_v67(text,text,text,text,jsonb,uuid) from public,anon,authenticated;
