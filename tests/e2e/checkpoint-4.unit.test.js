const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const migration = fs.readFileSync('supabase/migrations/20260920195527_test71_checkpoint4_salary_costing_printing_rate.sql', 'utf8');
const retirement = fs.readFileSync('supabase/migrations/20260920201408_test71_checkpoint4_direct_cost_retirement.sql', 'utf8');
const chat = fs.readFileSync('test70-real-chat-live-v70.js', 'utf8');
const appGuard = fs.readFileSync('real-sticker-metal-print-guard-v9160.js', 'utf8');

test('cost privacy uses canonical effective Act As identity', () => {
  assert.match(migration, /rr_upm_effective_identity_v200\(\)/);
  assert.match(migration, /'OWNER','SUPER_ADMIN'/);
  assert.match(migration, /PRIVATE_COST_OMITTED/);
  assert.match(migration, /revoke all on function public\.rr_costing_salary_pool_v294[\s\S]*authenticated/);
  assert.match(migration, /revoke all on table public\.rr_upm_department_labor_cost_v9160[\s\S]*authenticated/);
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
  assert.match(migration, /Only eligible Manager\/Admin\/Owner can fill Actual Rate/);
  assert.doesNotMatch(migration, /v_request\.requested_by=auth\.uid/);
  assert.match(chat, /function installRateFocusGuard/);
  assert.match(chat, /Fill rate first/);
  assert.match(chat, /scrollIntoView\(\{behavior:'smooth',block:'center'\}\)/);
  assert.match(chat, /departments=\[\.\.\.new Set\(pending\.map/);
});

