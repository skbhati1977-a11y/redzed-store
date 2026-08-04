select
  to_regprocedure('public.rr_upm_alter_receiver_context_v770(text)') as receiver_context_rpc,
  to_regprocedure('public.rr_upm_alter_stage_v740(text,text,text,jsonb,jsonb,boolean,uuid,text)') as alter_wrapper,
  to_regprocedure('public.rr_upm_alter_stage_v740_core(text,text,text,jsonb,jsonb,boolean,uuid,text)') as preserved_core;

-- Run while logged in through the application session if testing through RPC:
-- select public.rr_upm_alter_receiver_context_v770(null);
