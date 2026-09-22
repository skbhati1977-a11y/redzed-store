const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '../..');
const chat = fs.readFileSync(path.join(root, 'test70-real-chat-live-v70.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'test70-cb-purchase-real-chat-pilot.html'), 'utf8');
const migration = fs.readFileSync(
  path.join(root, 'supabase/migrations/20260921153108_test71_mc1_real_chat_canonical_v504.sql'),
  'utf8'
);
const lifecycle = fs.readFileSync(
  path.join(root, 'supabase/migrations/20260922080811_test71_mc1_e2e_lifecycle_v613.sql'),
  'utf8'
);
const browser = fs.readFileSync(path.join(root, 'tests/e2e/mc1-real-chat.spec.js'), 'utf8');

// This static gate runs before the live MC1 browser scenario in TEST71 CI.

test('MC1 Real Chat uses business views rather than worker lifecycle', () => {
  assert.match(chat, /OPEN:'Purchase \/ Stock IN'/);
  assert.match(chat, /WORKING:'Lot Consumption'/);
  assert.match(chat, /CLOSE:'Closing Stock'/);
  assert.match(chat, /rr_mc1_real_chat_queue_v504/);
  assert.match(chat, /if\(x\[1\]\.length===1&&x\[1\]\[0\]==='MATCHING_PURCHASE'\)return openMc1Chat/);
});

test('purchase draft is non-posting until explicit canonical confirm', () => {
  const draftIndex = chat.indexOf('data-mc-save-draft');
  const confirmIndex = chat.indexOf("rr_confirm_mc_purchase_v504");
  assert.ok(draftIndex > -1 && confirmIndex > draftIndex);
  assert.match(chat, /Save Draft से stock\/accounting post नहीं होगा/);
  assert.match(migration, /perform public\.rr_product_require_admin_v1\(\)/);
  assert.match(migration, /pg_advisory_xact_lock/);
  assert.match(migration, /rr_mc1_purchases_idempotency_key_uq/);
});

test('V3 purchase contract targets current canonical MC1 schema', () => {
  const v3 = migration.slice(
    migration.indexOf('create or replace function public.rr_post_mc_fabric_purchase_v3'),
    migration.indexOf('create or replace function public.rr_confirm_mc_purchase_v504')
  );
  assert.match(v3, /where mc_no='MC1'/);
  assert.match(v3, /insert into public\.rr_mc1_ledger/);
  assert.match(v3, /supplier_ledger_id/);
  assert.doesNotMatch(v3, /account_code/);
  assert.doesNotMatch(v3, /insert into public\.rr_matching_stock_ledger/);
});

test('canonical consumption mirrors its frozen amount into Lot costing once', () => {
  assert.match(migration, /rr_mc1_sync_lot_cost_v504/);
  assert.match(migration, /if v_match\.status='POSTED' then/);
  assert.match(migration, /'duplicate_blocked',true/);
  assert.match(migration, /matching_amount=m\.total_cost/);
  assert.match(migration, /'LOT_CONSUMPTION_OUT'/);
});

test('MC1 status navigation ignores stale async projections', () => {
  assert.match(chat, /mc1LoadSeq:0/);
  assert.match(chat, /const seq=\+\+S\.mc1LoadSeq,status=S\.status/);
  assert.match(chat, /seq!==S\.mc1LoadSeq\|\|status!==S\.status/);
  assert.match(chat, /p_status:status/);
});

test('MC1 E2E uses a canonical rollback proof and creates no retry residue', () => {
  assert.match(lifecycle, /TEST71 E2E Super Admin session required/);
  assert.match(lifecycle, /pg_advisory_xact_lock/);
  assert.match(lifecycle, /rr_confirm_mc_purchase_v504/);
  assert.match(lifecycle, /rr_reserve_lot_matching_v2/);
  assert.match(lifecycle, /rr_confirm_lot_matching_v2/);
  assert.match(lifecycle, /rr_upm_final_costing_v308/);
  assert.match(lifecycle, /rr_mc1_real_chat_queue_v504/);
  assert.match(lifecycle, /TEST71_MC1_E2E_ROLLBACK/);
  assert.match(lifecycle, /'fixture_residue',v_residue/);
  assert.doesNotMatch(lifecycle, /MC1-E2E-179|E2E-FRESH-0[123]|2f9001de/);
  assert.match(browser, /rr_test_mc1_e2e_invariants_v613/);
  assert.doesNotMatch(browser, /Date\.now\(\)/);
  assert.doesNotMatch(browser, /\[data-mc-confirm\][^\n]*\.click/);
  assert.doesNotMatch(browser, /LOT 2622|p_lot_no: '2622'|2f9001de/);
  assert.doesNotMatch(browser, /rpc\(page, 'rr_confirm_lot_matching_v2'/);
  assert.match(browser, /const workingBefore = await rpc/);
  assert.match(browser, /String\(x\.lot_no\) === String\(consumption\.lot_no\)/);
});

test('deployed Real Chat loads the MC1 integration asset version', () => {
  assert.match(html, /test70-real-chat-live-v70\.js\?v=622/);
});
