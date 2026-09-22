const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const sql = fs.readFileSync(
  'supabase/migrations/20260921091751_test71_released_dcard_close_regression_v502.sql',
  'utf8'
);
const cutting = fs.readFileSync('real-cutting-master-pm.V719.3.js', 'utf8');
const chat = fs.readFileSync('test70-real-chat-live-v70.js', 'utf8');

test('released D-card gallery state comes from canonical single and multi Lot truth', () => {
  assert.match(sql, /create or replace view public\.rr_product_gallery_production_v719/i);
  assert.match(sql, /from public\.rr_cutting_lots_v3/i);
  assert.match(sql, /from public\.rr_production_lots/i);
  assert.match(sql, /then 'released'/i);
  assert.match(sql, /coalesce\(t\.lot_no,g\.lot_no\)/i);
});

test('database serializes release modes and rollback proof covers retry and residue', () => {
  assert.match(sql, /for update/i);
  assert.match(sql, /rr_000_cutting_release_cross_mode_v502/g);
  assert.match(sql, /already released across MULTI LOT mode/i);
  assert.match(sql, /already released across SINGLE LOT mode/i);
  assert.match(sql, /function public\.rr_test_released_dcard_regression_v502/i);
  assert.match(sql, /__TEST71_V502_ROLLBACK__/);
  assert.match(sql, /'fixture_residue',v_residue/);
});

test('deep-linked Cutting action renders one exact history card and never reopens release', () => {
  assert.match(cutting, /const requestedDivisionId/);
  assert.match(cutting, /productionQuery\.eq\("division_id", requestedDivisionId\)/);
  assert.match(cutting, /galleryQuery\.eq\("division_id", requestedDivisionId\)/);
  assert.match(cutting, /divisionQuery\.eq\("id", requestedDivisionId\)/);
  assert.match(cutting, /purchaseQuery\.in\("id", purchaseIds\)/);
  assert.match(cutting, /!requestedDivisionId \|\|/);
  assert.match(cutting, /requestedState === "ready"/);
  assert.match(cutting, /\["released", "completed"\]\.includes\(requestedState\)/);
  assert.match(cutting, /केवल history उपलब्ध है/);
});

test('Cutting release is terminal history in both database and Real Chat client', () => {
  assert.match(sql, /source_event_type='CUTTING_RELEASE_SUCCEEDED'/);
  assert.match(sql, /'canonical_state','CLOSE'/);
  assert.match(sql, /'next_actions','\[\]'::jsonb/);
  assert.match(chat, /if\(released\)return\['CLOSE'\]/);
  assert.match(chat, /function cuttingReleasedActions\(\)\{return\[\]\}/);
  assert.match(chat, /x\.includes\('CUTTING'\).*return'CLOSE'/);
});
