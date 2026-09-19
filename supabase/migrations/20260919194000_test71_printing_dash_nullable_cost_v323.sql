-- TEST71 V323: preserve DASH semantics for unavailable weighted Printing costs.
-- Quantity remains factual; unavailable rates and totals must stay NULL, never 0.
begin;

alter table public.rr_upm_costing_inputs_v9300
  alter column weighted_rate drop not null,
  alter column total_cost drop not null;

comment on column public.rr_upm_costing_inputs_v9300.weighted_rate is
'NULL means the mapped purchase-rate source is unavailable; zero means a sourced rate is genuinely zero.';

comment on column public.rr_upm_costing_inputs_v9300.total_cost is
'NULL means costing cannot yet be calculated from its source; zero means a sourced applicable cost is genuinely zero.';

commit;
