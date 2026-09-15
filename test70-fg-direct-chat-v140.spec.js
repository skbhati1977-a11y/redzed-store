const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = __dirname;
const js = fs.readFileSync(path.join(root, 'test70-fg-direct-chat-v140.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'test70-cb-purchase-real-chat-pilot.html'), 'utf8');
const appJs = fs.readFileSync(path.join(root, 'real-upm-department-view-v789.js'), 'utf8');
const appHtml = fs.readFileSync(path.join(root, 'real-department-lite-v9127.html'), 'utf8');
const identityMigration = fs.readFileSync(
  path.join(root, 'supabase/migrations/20260915161000_test70_upm_dangling_worker_identity_v162.sql'),
  'utf8'
);
const migration = fs.readFileSync(
  path.join(root, 'supabase/migrations/20260915124500_test70_fg_direct_chat_action_contract_v140.sql'),
  'utf8'
);

test('Packing and Despatch use existing authoritative engines in Real Chat', () => {
  for (const rpc of [
    'rr_fg_assign_packing_v788',
    'rr_fg_accept_packing_v788',
    'rr_fg_generate_assigned_pack_v788',
    'rr_pack_save_media_v9332',
    'rr_pack_request_rate_v9340',
    'rr_pack_rate_approve_v9340',
    'rr_fg_submit_assigned_pack_v788',
    'rr_fg_create_despatch_lot_v9361',
    'rr_fg_receive_accept_v9361'
  ]) {
    assert.match(js, new RegExp(rpc));
    assert.match(migration, new RegExp(rpc));
  }
  assert.match(html, /test70-fg-direct-chat-v140\.js\?v=170/);
  assert.match(js, /CONTINUE PACKING/);
  assert.match(js, /rr_upm_submit_with_actual_cost_gate_v9300/);
  assert.match(js, /rr_upm_set_department_rate_v760/);
  assert.match(js, /rr_upm_dynamic_submit_history_v741/);
  assert.match(js, /FINALIZE PACKING/);
  assert.match(js, /Final Sale Rate \/ PCS — Admin/);
  assert.match(js, /finalRateAdmin/);
  assert.match(js, /Gallery\/Camera से exactly 3 photos चुनें/);
  assert.doesNotMatch(js, /capture="environment"/);
  assert.match(js, /Composition/);
  assert.match(js, /\.eq\('department_code','PRESS'\)\.gt\('good_qty',0\)/);
  assert.doesNotMatch(js, /data-kind="upm-assign"/);
  assert.match(js, /data-kind="challan"/);
  assert.match(html, /rrfg-boot/);
  assert.match(js, /classList\.remove\('rrfg-boot'\)/);
  assert.match(js, /new MutationObserver/);
  assert.match(js, /cachedCanonicalHtml/);
  assert.match(js, /querySelectorAll\('\.closed-row'\)/);
});

test('legacy Packing assignments reconcile only to one active canonical worker', () => {
  assert.match(identityMigration, /having count\(\*\)=1/);
  assert.match(identityMigration, /rr_upm_work_assignments_v8/);
  assert.match(identityMigration, /rr_upm_dynamic_submit_history_v741/);
  assert.match(identityMigration, /not exists/);
});

test('App and Real Chat share the guarded Packing completion contract', () => {
  assert.match(appHtml, /real-upm-department-view-v789\.js\?v=9313/);
  assert.match(appJs, /COMPLETE PACKING STAGE/);
  assert.match(appJs, /COMPLETE STAGE · SAVE & HANDOVER/);
  assert.match(appJs, /rr_upm_submit_with_actual_cost_gate_v9300/);
  assert.match(appJs, /rr_upm_set_department_rate_v760/);
  assert.match(appJs, /ACTUAL PACKING RATE \/ PCS/);
  assert.match(appJs, /rr_upm_dynamic_submit_history_v741/);
  assert.match(appJs, /\.eq\('department_code','PRESS'\)\.gt\('good_qty',0\)/);
  assert.match(appJs, /PACKING STAGE COMPLETED · FG HANDOVER READY/);
});

test('photo-first and difference-hold gates stay explicit', () => {
  assert.match(js, /Gallery\/Camera से exactly 3 photos चुनें/);
  assert.match(js, /photos\.length===3/);
  assert.match(js, /Rate \$\{approved\?'APPROVED'/);
  assert.match(js, /Difference Hold/);
  assert.match(migration, /PACKING_FINAL_PHOTOS[\s\S]+PACKING_RATE_REQUEST/);
  assert.match(migration, /DESPATCH_CREATE[\s\S]+STORE_RECEIVE/);
});

test('Packing lifecycle owns one canonical regular card per source state', () => {
  assert.match(js, /packingState/);
  assert.match(js, /SUBMITTED','COMPLETED','CLOSED','CANCELLED/);
  assert.match(js, /function cleanLegacy\(root,status,canonicalLots\)[\s\S]*?\.work-card[\s\S]*?x\.remove\(\)/);
  assert.match(js, /activeLane\(\)!=='READY_TO_SUBMIT'/);
  assert.match(js, /function legacyLot/);
  assert.match(js, /function isPackingMilestone/);
  assert.match(js, /legacyRegularCount/);
  assert.match(js, /:scope > \.empty/);
  assert.match(js, /PERSONAL CHAT/);
  assert.match(js, /SUBMITTED WORK/);
  assert.doesNotMatch(js, /NO CURRENT SOURCE ACTION/);
});

test('cost visibility and Super Admin action identity follow the universal contract', () => {
  assert.match(js, /fullCostingViewer=.*OWNER.*SUPER_ADMIN/);
  assert.match(js, /costingViewer=.*OWNER.*SUPER_ADMIN.*ADMIN.*SALES/);
  assert.match(js, /if\(!fullCostingViewer\(\)\)/);
  assert.match(js, /adminView=\['OWNER','ADMIN'\]/);
  assert.match(js, /FINAL RATE REVIEW · SUPER ADMIN/);
  assert.match(js, /Owner Margin \/ PCS/);
  assert.match(js, /SUPER ADMIN VIEW/);
  assert.match(js, /Signed in:/);
  assert.match(js, /Viewing:/);
  assert.match(js, /Action audit:/);
  assert.match(html, /test70-fg-direct-chat-v140\.js\?v=170/);
});
