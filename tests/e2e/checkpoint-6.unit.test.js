const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const migration = fs.readFileSync('supabase/migrations/20260920231500_test71_checkpoint6_packing_final_rate_rrq_v333.sql', 'utf8');
const chat = fs.readFileSync('test70-fg-direct-chat-v140.js', 'utf8');
const appHtml = fs.readFileSync('real-finished-goods-v787.html', 'utf8');
const appJs = fs.readFileSync('real-finished-goods-v787.js', 'utf8');
const appCss = fs.readFileSync('real-finished-goods-v787.css', 'utf8');
const legacy = fs.readFileSync('real-finished-goods-v853.js', 'utf8');

test('Final Rate approval keeps one canonical RRQ writer and blocks retries', () => {
  assert.match(migration, /rr_pack_rate_approve_v9340[\s\S]*rrq_apply_packing_rate_compat_v312/);
  assert.match(migration, /v_role not in \('owner','admin','super_admin'\)/);
  assert.match(migration, /if r\.status='APPROVED'[\s\S]*duplicate_blocked',true/);
  assert.match(migration, /rr_test_checkpoint6_rate_approval_v333[\s\S]*__TEST71_CP6_ROLLBACK__/);
  assert.match(migration, /ledger_delta_during/);
});

test('RRQ internals are server-only and role projections use effective Act As identity', () => {
  assert.match(migration, /rr_upm_effective_identity_v200\(\)/);
  assert.match(migration, /PACKING_STATUS_ONLY/);
  assert.match(migration, /SALESMAN/);
  assert.match(migration, /revoke all on table public\.rr_pack_rate_approval_v9340 from public,anon,authenticated/);
  assert.match(migration, /revoke all on table public\.rrq_rate_ledger_v9300 from public,anon,authenticated/);
  assert.match(migration, /revoke all on function public\.rrq_apply_packing_rate_compat_v312[\s\S]*authenticated/);
  assert.match(migration, /rr_pack_rate_context_public_v333/);
});

test('Packing role surfaces show only the current action and first tap is pending', () => {
  assert.match(chat, /\['PACKER','PACKING','PACKING_OPERATOR'\]/);
  assert.match(chat, /FINAL RATE APPROVAL PENDING · No worker action/);
  assert.match(chat, /if\(actionBusy\)return;actionBusy=true/);
  assert.match(chat, /SUPER ADMIN APPROVE & MAP TO RRQ/);
  assert.match(chat, /rr_pack_rate_context_public_v333/);
  assert.doesNotMatch(chat, /rr_pack_rate_context_universal_v9405/);
});

test('Packing table uses exact columns and vertical mobile composition', () => {
  for (const heading of ['Box No.', 'Consignment', 'Box PCS', 'Colour / Size Composition']) {
    assert.match(appHtml, new RegExp(`<th>${heading.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}</th>`));
  }
  assert.match(appJs, /fg-pack-composition/);
  assert.match(appJs, /data-label="Colour \/ Size Composition"/);
  assert.match(appJs, /×/);
  assert.match(appCss, /\.fg-pack-composition\{display:grid/);
  assert.match(appCss, /data-label="Colour \/ Size Composition"/);
  assert.match(chat, /@media\(max-width:600px\)[\s\S]*\.rrfg-composition\{display:grid;grid-template-columns:1fr/);
});

test('Legacy Packing surface no longer reads or invokes raw RRQ internals', () => {
  assert.doesNotMatch(legacy, /from\('rrq_lot_rates_v9300'\)/);
  assert.doesNotMatch(legacy, /rpc\('rrq_apply_packing_rate_v9300'/);
  assert.match(legacy, /rpc\('rr_pack_rate_status_v9340'/);
  assert.match(legacy, /rpc\('rr_pack_rate_approve_v9340'/);
});
