const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const migration = fs.readFileSync(
  'supabase/migrations/20260921175214_test71_canonical_material_unit_master_v606.sql',
  'utf8'
);
const cbSelection = fs.readFileSync(
  'supabase/migrations/20260922070000_test71_cb_material_unit_selection_v610.sql',
  'utf8'
);
const html = fs.readFileSync('real-material-master-v805.html', 'utf8');
const app = fs.readFileSync('real-material-master-v805.js', 'utf8');
const cb = fs.readFileSync('real-cb-new-v9130-fix2.html', 'utf8');
const chat = fs.readFileSync('test70-real-chat-live-v70.js', 'utf8');

test('one backend Unit Master is authoritative', () => {
  assert.match(migration, /create table if not exists public\.rr_unit_master_v606/);
  assert.match(migration, /rr_unit_master_list_v606/);
  assert.match(migration, /rr_unit_master_create_v606/);
  assert.match(migration, /rr_unit_require_code_v606/);
  assert.doesNotMatch(migration, /create table[^;]*(material_engine|unit_engine)/i);
  assert.match(app, /rr_unit_master_list_v606/);
  assert.match(app, /FALLBACK_UNITS/);
});

test('new Material Unit fields are dropdown-only and support New Unit', () => {
  for (const id of ['newPurchaseUnit', 'newStockUnit', 'newConsumptionUnit']) {
    assert.match(html, new RegExp(`<select id="${id}"`));
    assert.doesNotMatch(html, new RegExp(`<input id="${id}"`));
  }
  assert.match(app, /\+ NEW UNIT/);
  assert.match(html, /id="unitModal"/);
  assert.match(html, /id="newUnitName"/);
  assert.match(html, /id="newUnitCode"/);
});

test('duplicates, authority and retries are protected in backend', () => {
  assert.match(migration, /pg_advisory_xact_lock/);
  assert.match(migration, /similarity\(u\.normalized_name,norm\)>=0\.78/);
  assert.match(migration, /piece','pieces/);
  assert.match(migration, /meter','meters','metre','metres/);
  assert.match(migration, /OWNER','SUPER_ADMIN/);
  assert.match(migration, /exception when unique_violation/);
});

test('Material purchase Unit is selectable in CB and remains the Real Chat Unit', () => {
  assert.match(migration, /material_master_id uuid references public\.rr_material_master_v805/);
  assert.match(migration, /rr_sync_material_category_unit_v606/);
  assert.match(migration, /new\.purchase_unit/);
  assert.match(migration, /rr_cb_department_save_v600/);
  assert.match(cb, /class="unitSelect"/);
  assert.match(cb, /id="cbMaterialModal"/);
  assert.match(cb, /id="cbUnitModal"/);
  assert.match(cb, /rr_material_create_v805_31/);
  assert.match(cb, /rr_unit_master_create_v606/);
  assert.match(cbSelection, /nullif\(entry_row->>'unit',''\),nullif\(cat\.unit,''\),'PCS'/);
  assert.match(cbSelection, /RR_MATERIAL:/);
  assert.match(chat, /safe\(m\.unit\|\|'UNIT DUE'\)/);
});
