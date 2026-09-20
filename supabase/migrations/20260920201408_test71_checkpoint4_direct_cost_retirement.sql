-- Retire the client-supplied direct-cost submit RPC. Current App/Real Chat use
-- the canonical rate gate and receiver handover; private labor is calculated
-- server-side by V400 and must never be read from a browser view.
revoke all on function public.rr_upm_submit_with_direct_cost_v9160(
  text,text,jsonb,text,numeric,numeric,numeric,numeric,text
) from public,anon,authenticated;

comment on function public.rr_upm_submit_with_direct_cost_v9160(
  text,text,jsonb,text,numeric,numeric,numeric,numeric,text
) is 'RETIRED TEST71 CP4: client-supplied cost path. Use canonical rate gate + V204 receiver handover.';
