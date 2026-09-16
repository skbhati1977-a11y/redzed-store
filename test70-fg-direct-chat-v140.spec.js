const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = __dirname;
const js = fs.readFileSync(path.join(root, 'test70-fg-direct-chat-v140.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'test70-cb-purchase-real-chat-pilot.html'), 'utf8');
const appJs = fs.readFileSync(path.join(root, 'real-upm-department-view-v789.js'), 'utf8');
const appHtml = fs.readFileSync(path.join(root, 'real-department-lite-v9127.html'), 'utf8');
const config = fs.readFileSync(path.join(root, 'config.js'), 'utf8');
const globalViewAs = fs.readFileSync(path.join(root, 'real-superadmin-view-as-v176.js'), 'utf8');
const live = fs.readFileSync(path.join(root, 'test70-real-chat-live-v70.js'), 'utf8');
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
  assert.match(html, /test70-fg-direct-chat-v140\.js\?v=176/);
  assert.match(js, /CONTINUE PACKING/);
  assert.match(js, /rr_upm_submit_with_actual_cost_gate_v9300/);
  assert.match(js, /rr_upm_set_department_rate_v760/);
  assert.match(js, /rr_upm_dynamic_submit_history_v741/);
  assert.match(js, /FINALIZE PACKING/);
  assert.match(js, /Final Rate \/ PCS — Super Admin/);
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
  assert.match(appHtml, /real-upm-department-view-v789\.js\?v=200/);
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
  assert.match(js, /<span>Sale Rate<b>/);
  assert.match(js, /FINAL RATE REVIEW · SUPER ADMIN/);
  assert.match(js, /Owner Margin \/ PCS/);
  assert.match(js, /SUPER ADMIN VIEW/);
  assert.match(js, /Signed in:/);
  assert.match(js, /Viewing:/);
  assert.match(js, /Action audit:/);
  assert.match(html, /test70-fg-direct-chat-v140\.js\?v=176/);
  assert.match(js, /rr_superadmin_preview_role/);
  assert.match(js, /READ-ONLY ROLE PREVIEW/);
  assert.match(js, /ON BEHALF/);
  assert.match(js, /RR_VIEW_AS_ACTOR_NAME/);
  assert.match(globalViewAs, /ACT AS/);
  assert.match(globalViewAs, /Search worker/);
  assert.match(js, /body\.querySelectorAll\('button,input,select,textarea'\).*disabled=true/);
  assert.match(js, /location\.reload\(\)/);
  assert.match(globalViewAs, /rr_worker_directory_unified_v1/);
  assert.match(globalViewAs, /RR_EFFECTIVE_ROLE/);
  assert.doesNotMatch(globalViewAs, /READ-ONLY ROLE PREVIEW/);
  assert.match(globalViewAs, /rr-view-handle/);
  assert.match(globalViewAs, /touchstart/);
  assert.match(globalViewAs, /translateX\(100%\)/);
  assert.match(globalViewAs, /rr_test_set_on_behalf_context_v176/);
  assert.match(globalViewAs, /Worker name \/ code \/ department/);
  assert.match(globalViewAs, /RR_ON_BEHALF_ACTIVE/);
  assert.match(globalViewAs, /window\.supabaseDb/);
  assert.match(globalViewAs, /for\(let i=0;i<24&&!db;i\+\+\)/);
  assert.match(globalViewAs, /replace\(\/\[\^A-Z0-9\]\/g,''\)/);
  assert.match(html, /real-superadmin-view-as-v176\.js\?v=187/);
  assert.match(appHtml, /real-superadmin-view-as-v176\.js\?v=187/);
  assert.match(config, /RR_GLOBAL_ACT_AS_LOADER_V187/);
  assert.match(config, /rr_superadmin_preview_enabled/);
  assert.match(config, /real-superadmin-view-as-v176\.js\?v=187/);
  assert.match(config, /rrModeParam==="TEST"/);
  assert.match(globalViewAs, /rr_real_chat_directory_v85/);
  assert.match(globalViewAs, /toUpperCase\(\)===['"]ADMIN['"]/);
  assert.match(live, /actAsScope/);
  assert.match(live, /globalRole=\['OWNER','SUPER_ADMIN','ADMIN'\]\.includes\(role\)/);
  assert.match(live, /worker_count:workers\.length,staff_count:staff\.length/);
  assert.match(live, /RR_VIEW_AS_DEPARTMENTS/);
  assert.match(js, /ON BEHALF/);
  assert.match(js, /rateSuggester=.*SALES.*ADMIN/);
  assert.match(js, /finalRateAdmin=.*OWNER.*SUPER_ADMIN/);
  assert.match(js, /RRQ Total Impact/);
});
