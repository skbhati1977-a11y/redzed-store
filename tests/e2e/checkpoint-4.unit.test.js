const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const migration = fs.readFileSync('supabase/migrations/20260920195527_test71_checkpoint4_salary_costing_printing_rate.sql', 'utf8');
const retirement = fs.readFileSync('supabase/migrations/20260920201408_test71_checkpoint4_direct_cost_retirement.sql', 'utf8');
const recovery = fs.readFileSync('supabase/migrations/20260921030000_test71_checkpoint4_super_admin_privacy_v401.sql', 'utf8');
const legacyLockdown = fs.readFileSync('supabase/migrations/20260921072000_test71_checkpoint4_legacy_cost_api_lockdown_v402.sql', 'utf8');
const safeLegacyViews = fs.readFileSync('supabase/migrations/20260921073500_test71_checkpoint4_safe_legacy_identity_views_v403.sql', 'utf8');
const chat = fs.readFileSync('test70-real-chat-live-v70.js', 'utf8');
const appGuard = fs.readFileSync('real-sticker-metal-print-guard-v9160.js', 'utf8');
const artMaster = fs.readFileSync('real-art-master.js', 'utf8');

test('cost privacy uses canonical effective Act As identity', () => {
  assert.match(migration, /rr_upm_effective_identity_v200\(\)/);
  assert.match(recovery, /v_private:=v_role='SUPER_ADMIN'/);
  assert.match(recovery, /v_rate_editor:=v_role in \('OWNER','SUPER_ADMIN','ADMIN','MANAGER'\)/);
  assert.match(migration, /PRIVATE_COST_OMITTED/);
  assert.match(recovery, /PRIVATE_COST_OMITTED/);
  assert.match(migration, /revoke all on function public\.rr_costing_salary_pool_v294[\s\S]*authenticated/);
  assert.match(migration, /revoke all on table public\.rr_upm_department_labor_cost_v9160[\s\S]*authenticated/);
  assert.match(recovery, /revoke all on table public\.rr_upm_department_rates_v2[\s\S]*authenticated/);
  assert.match(recovery, /revoke all on table public\.rr_upm_lot_costing_v760[\s\S]*authenticated/);
});

test('legacy manufacturing cost APIs cannot bypass the canonical privacy boundary', () => {
  assert.match(legacyLockdown, /rr_private_cost_scope_v402/);
  assert.match(legacyLockdown, /public\.rr_costing_user_scope_v760\(null\)/);
  assert.match(legacyLockdown, /alter table public\.rr_art_master rename to rr_art_master_core_v402/);
  const safeArtView = legacyLockdown.match(/create view public\.rr_art_master[\s\S]*?from public\.rr_art_master_core_v402 a;/)?.[0] || '';
  assert.ok(safeArtView);
  assert.doesNotMatch(safeArtView, /default_margin/);
  for (const endpoint of [
    'rr_art_cost_summary', 'rr_art_process_cost_summary', 'rr_cb_material_cost_summary',
    'rr_live_lot_status', 'rr_lot_process_actuals', 'rr_mc1_lot_cost_v1',
    'rr_report_costing_lot_summary_v852', 'rr_material_running_cost_v805_1'
  ]) assert.match(legacyLockdown, new RegExp(endpoint));
  assert.doesNotMatch(artMaster, /rr_art_process_cost_summary|rr_art_process_costs|rr_art_category_costs|rr_get_art_category_costs|rr_save_art_process_costs/);
  assert.match(artMaster, /const ART_SAFE_COLUMNS=/);
  assert.doesNotMatch(artMaster.match(/const ART_SAFE_COLUMNS=.*$/m)?.[0] || '', /default_margin/);
  assert.match(safeLegacyViews, /revoke all on table public\.rr_art_master_core_v402[\s\S]*authenticated/);
  assert.match(safeLegacyViews, /create view public\.rr_lots[\s\S]*security_invoker=true/);
  const lotView = safeLegacyViews.match(/create view public\.rr_lots[\s\S]*?from public\.rr_lots_core_v403 l;/)?.[0] || '';
  assert.ok(lotView);
  assert.doesNotMatch(lotView, /margin_percent|making_cost_snapshot|material_cost_snapshot|factory_cost_snapshot|hidden_fabric_adjustment/);
  const dashboardView = safeLegacyViews.match(/create view public\.rr_live_lot_status[\s\S]*?left join public\.rr_cb_units cb on cb\.id=l\.cb_id;/)?.[0] || '';
  assert.ok(dashboardView);
  assert.doesNotMatch(dashboardView, /margin_percent|making_cost_snapshot|material_cost_snapshot|factory_cost_snapshot/);
});

test('salary allocation is Accept to Submit and mutually exclusive', () => {
  assert.match(migration, /rr_upm_assignment_receipts_v9112[\s\S]*confirmed_at/);
  assert.match(migration, /coalesce\(a\.completed_at,now\(\)\)-r\.confirmed_at/);
  assert.match(migration, /worker_category='SALARIED'/);
  assert.match(migration, /worker_category<>'SALARIED'/);
  assert.match(migration, /department_lapse_lot/);
  assert.match(migration, /fabrication_staff_lot/);
  assert.match(migration, /CUTTING_TO_PACKING_ONLY/);
});

test('Printing keeps one V307/V204 path with multi-design mapping', () => {
  assert.match(migration, /regexp_split_to_table[\s\S]*print_no/);
  assert.match(migration, /on conflict\(canonical_lot_id,print_no\)/);
  assert.match(migration, /rr_print_apply_frame_recovery_v302/);
  assert.match(migration, /V204 HANDOVER/);
  assert.match(appGuard, /if\(m\.querySelector\('#rfSubmitLM'\)\)\{m\.dataset\.rr9160Atomic='1';return\}/);
  assert.match(retirement, /RETIRED TEST71 CP4/);
});

test('rate editor is backend restricted and UI focus is enforced', () => {
  assert.match(recovery, /Only eligible Manager\/Admin\/Owner\/Super Admin can fill Actual Rate/);
  assert.match(recovery, /V401_CANONICAL_RATE_IDEMPOTENT/);
  assert.match(recovery, /duplicate_blocked/);
  assert.match(recovery, /drop trigger if exists rr_upm_lot_department_rate_after_insert_v7726/);
  assert.doesNotMatch(migration, /v_request\.requested_by=auth\.uid/);
  assert.match(chat, /function installRateFocusGuard/);
  assert.match(chat, /Fill rate first/);
  assert.match(chat, /scrollIntoView\(\{behavior:'smooth',block:'center'\}\)/);
  assert.match(chat, /departments=\[\.\.\.new Set\(pending\.map/);
});
