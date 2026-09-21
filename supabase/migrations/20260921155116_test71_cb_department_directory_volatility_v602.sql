-- TEST71 CB Department V602: preserve the volatility contract of the canonical
-- Real Chat directory. V85 may perform its existing session/identity touch, so
-- a STABLE wrapper would incorrectly force that call into a read-only context.

alter function public.rr_real_chat_directory_v600() volatile;

comment on function public.rr_real_chat_directory_v600() is
  'CB-labelled wrapper over the canonical V85 directory; VOLATILE because V85 retains its existing session/identity mutation contract.';
