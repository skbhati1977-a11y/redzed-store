-- TEST71 Checkpoint 4 follow-up: close legacy manufacturing-cost API bypasses.
-- The V760/V400/V307 boundaries remain the sole client-facing costing path.

begin;

create or replace function public.rr_private_cost_scope_v402()
returns boolean
language sql
stable
security definer
set search_path=public
as $function$
  select coalesce(
    (public.rr_costing_user_scope_v760(null)->>'can_view_private_cost')::boolean,
    false
  )
$function$;

revoke all on function public.rr_private_cost_scope_v402()
  from public,anon;
grant execute on function public.rr_private_cost_scope_v402()
  to authenticated,service_role;

-- Art identity remains manageable by the Checkpoint 3 roles, but its obsolete
-- default-margin column is omitted at the browser relation boundary. Super
-- Admin receives margin only from the canonical role-aware costing RPCs.
-- Existing foreign keys/functions stay attached to
-- the renamed base table; direct clients continue through the updatable view.
alter table public.rr_art_master rename to rr_art_master_core_v402;

create view public.rr_art_master
with (security_invoker=true)
as
select
  a.id,
  a.art_no,
  a.item_name,
  a.product_name,
  a.category,
  a.fabric_id,
  a.description,
  a.standard_sizes,
  a.default_box_qty,
  a.cuff_collar_required,
  a.matching_cloth_required,
  a.folding_patti_required,
  a.other_material_required,
  a.other_material_note,
  a.dealer_rate,
  a.mrp,
  a.is_active,
  a.created_at,
  a.updated_at,
  a.caption_text,
  a.caption_items,
  a.art_category_id,
  a.material_requirements
from public.rr_art_master_core_v402 a;

revoke all on table public.rr_art_master from public,anon;
grant select,insert,update,delete on table public.rr_art_master to authenticated;
grant all on table public.rr_art_master to service_role;

comment on view public.rr_art_master is
  'V402 updatable Art identity boundary; private default_margin is available only through canonical Super Admin costing RPCs.';

-- Legacy per-Art and per-Lot cost stores used Owner/Admin RLS. They are not a
-- second authorization engine: their direct row policies now reuse V401.
drop policy if exists rr_owner_admin_all on public.rr_art_category_costs;
drop policy if exists rr_super_admin_private_cost_v402 on public.rr_art_category_costs;
create policy rr_super_admin_private_cost_v402
on public.rr_art_category_costs for all to authenticated
using (public.rr_private_cost_scope_v402())
with check (public.rr_private_cost_scope_v402());

drop policy if exists rr_owner_admin_all on public.rr_art_costs;
drop policy if exists rr_super_admin_private_cost_v402 on public.rr_art_costs;
create policy rr_super_admin_private_cost_v402
on public.rr_art_costs for all to authenticated
using (public.rr_private_cost_scope_v402())
with check (public.rr_private_cost_scope_v402());

drop policy if exists rr_owner_admin_all on public.rr_art_process_costs;
drop policy if exists rr_super_admin_private_cost_v402 on public.rr_art_process_costs;
create policy rr_super_admin_private_cost_v402
on public.rr_art_process_costs for all to authenticated
using (public.rr_private_cost_scope_v402())
with check (public.rr_private_cost_scope_v402());

drop policy if exists rr_owner_admin_all on public.rr_lot_costs;
drop policy if exists rr_super_admin_private_cost_v402 on public.rr_lot_costs;
create policy rr_super_admin_private_cost_v402
on public.rr_lot_costs for all to authenticated
using (public.rr_private_cost_scope_v402())
with check (public.rr_private_cost_scope_v402());

drop policy if exists rr_owner_admin_all on public.rr_lots;
drop policy if exists rr_super_admin_private_cost_v402 on public.rr_lots;
create policy rr_super_admin_private_cost_v402
on public.rr_lots for all to authenticated
using (public.rr_private_cost_scope_v402())
with check (public.rr_private_cost_scope_v402());

-- These SECURITY DEFINER views predate canonical costing and bypass underlying
-- RLS. Internal functions keep owner access; no browser role may query them.
do $do$
declare
  v_name text;
begin
  foreach v_name in array array[
    'rr_art_cost_summary',
    'rr_art_process_cost_summary',
    'rr_cb_material_cost_summary',
    'rr_live_lot_status',
    'rr_lot_process_actuals',
    'rr_mc1_lot_cost_v1',
    'rr_product_lot_damage_cost_v1',
    'rr_report_costing_lot_summary_v852',
    'rr_material_running_cost_v805_1',
    'rr_material_running_cost_v805_2',
    'rr_cost_trading_cogs_v850',
    'rr_cost_trading_monthly_v850'
  ]
  loop
    if to_regclass(format('public.%I',v_name)) is not null then
      execute format(
        'revoke all on table public.%I from public, anon, authenticated',
        v_name
      );
      execute format(
        'grant select on table public.%I to service_role',
        v_name
      );
    end if;
  end loop;
end
$do$;

-- Retire direct execution of the legacy Art/standard-cost calculators. Their
-- server-side callers keep owner/service execution through normal ownership.
do $do$
declare
  v_proc record;
begin
  for v_proc in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname=any(array[
        'rr_get_art_category_costs',
        'rr_save_art_process_costs',
        'rr_calculate_lot_cost',
        'rr_calculate_rate',
        'rr_upm_art_standard_rate_v759'
      ])
  loop
    execute format(
      'revoke all on function %s from public, anon, authenticated',
      v_proc.oid::regprocedure
    );
    execute format(
      'grant execute on function %s to service_role',
      v_proc.oid::regprocedure
    );
  end loop;
end
$do$;

comment on function public.rr_private_cost_scope_v402() is
  'V402 legacy cost boundary delegates exclusively to the canonical V401 effective-role scope.';

commit;
