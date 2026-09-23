const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const migration = fs.readFileSync(
  'supabase/migrations/20260921153843_test71_cb_department_canonical_flow_v600.sql',
  'utf8'
);
const form = fs.readFileSync('real-cb-new-v9130-fix2.html', 'utf8');
const chat = fs.readFileSync('test70-real-chat-live-v70.js', 'utf8');
const artProjection = fs.readFileSync(
  'supabase/migrations/20260921154236_test71_cb_department_art_child_actions_v601.sql',
  'utf8'
);
const directoryVolatility = fs.readFileSync(
  'supabase/migrations/20260921155116_test71_cb_department_directory_volatility_v602.sql',
  'utf8'
);
const authorityBridge = fs.readFileSync(
  'supabase/migrations/20260921160242_test71_cb_effective_authority_bridge_v603.sql',
  'utf8'
);
const v713Authority = fs.readFileSync(
  'supabase/migrations/20260921160647_test71_cb_v713_effective_authority_v604.sql',
  'utf8'
);
const generatedAmount = fs.readFileSync(
  'supabase/migrations/20260921161124_test71_cb_generated_amount_contract_v605.sql',
  'utf8'
);
const openDraftInvariants = fs.readFileSync(
  'supabase/migrations/20260922052840_test71_cb_open_draft_invariants_v608.sql',
  'utf8'
);
const openDraftProof = fs.readFileSync(
  'supabase/migrations/20260922064000_test71_cb_open_draft_proof_v609.sql',
  'utf8'
);
const materialUnitSelection = fs.readFileSync(
  'supabase/migrations/20260922070000_test71_cb_material_unit_selection_v610.sql',
  'utf8'
);
const workingArtProjection = fs.readFileSync(
  'supabase/migrations/20260922073000_test71_cb_working_art_projection_v611.sql',
  'utf8'
);
const proofTimeout = fs.readFileSync(
  'supabase/migrations/20260922083605_test71_cb_proof_timeout_v614.sql',
  'utf8'
);
const workingCanonicalProjection = fs.readFileSync(
  'supabase/migrations/20260922220000_test71_cb_working_canonical_projection_v618.sql',
  'utf8'
);
const isolatedUiFixture = fs.readFileSync(
  'supabase/migrations/20260922222500_test71_cb_ui_fixture_colour_evidence_v623.sql',
  'utf8'
);
const artPage = fs.readFileSync('real-art-decide-master-v9231.js', 'utf8');
const artHtml = fs.readFileSync('real-art-decide-master.html', 'utf8');

test('CB Department extends the existing canonical engines', () => {
  assert.match(migration, /alter table public\.rr_fabric_purchases/);
  assert.match(migration, /alter table public\.rr_cb_purchase_entries/);
  assert.match(migration, /public\.rr_create_cb_v713/);
  assert.doesNotMatch(migration, /create table[^;]*(cb_engine|material_engine|art_engine|cutting_engine)/i);
  assert.match(migration, /technical PURCHASE code preserved/);
});

test('material unit and requirement states are backend authoritative', () => {
  assert.match(migration, /NOT REQUIRED','DUE','CONFIRMED/);
  assert.match(migration, /lower\(category_code\)='zip'/);
  assert.match(migration, /set unit='pcs'/);
  assert.match(migration, /lower\(category_code\) in\('elastic','tape'\)/);
  assert.match(migration, /set unit='roll'/);
  assert.match(workingArtProjection, /DUE Materials block Cutting, not OPEN -> WORKING Art decisions/);
  assert.match(workingArtProjection, /Cutting-blocking DUE Material must be confirmed first/);
  assert.match(form, /DUE Qty blank/);
  assert.match(form, /class="unitSelect"/);
  assert.match(form, /rr_unit_master_list_v606/);
  assert.match(materialUnitSelection, /rr_unit_require_code_v606/);
  assert.match(materialUnitSelection, /nullif\(entry_row->>'unit',''\),nullif\(cat\.unit,''\),'PCS'/);
});

test('one CB supports draft, confirm, late DUE material and rollback proof', () => {
  assert.match(migration, /rr_cb_department_save_v600/);
  assert.match(migration, /rr_test_cb_department_flow_v600/);
  assert.match(migration, /TEST71_CB_DEPARTMENT_ROLLBACK/);
  assert.match(migration, /'open_to_working'/);
  assert.match(migration, /'due_survived_confirm'/);
  assert.match(form, /DRAFT SAVE/);
  assert.match(form, /SAVE &amp; CONFIRM/);
  assert.match(form, /SAVE DUE MATERIAL/);
  assert.match(chat, /Pending Material/);
  assert.match(workingCanonicalProjection, /SENT TO CUTTING/);
  assert.match(artProjection, /real-art-decide-master\.html\?cb_unit_id=/);
  assert.match(workingArtProjection, /rr_pm_decision_status_v802 d on d\.cb_unit_id=u\.id/);
  assert.match(workingArtProjection, /not coalesce\(d\.all_decisions_complete,false\)/);
  assert.doesNotMatch(chat, /real-art-decide-master\.html\?cb_id=/);
});

test('rollback-only CB proofs have a bounded CI timeout without changing production writers', () => {
  assert.match(proofTimeout, /alter function public\.rr_test_cb_department_flow_v600\(\)/);
  assert.match(proofTimeout, /alter function public\.rr_test_cb_open_draft_invariants_v608\(\)/);
  assert.match(proofTimeout, /alter function public\.rr_test_cb_working_art_v611\(\)/);
  assert.equal((proofTimeout.match(/set statement_timeout='30s'/g) || []).length, 3);
  assert.doesNotMatch(proofTimeout, /alter function public\.rr_cb_department_save_v600/);
  assert.doesNotMatch(proofTimeout, /alter role|set lock_timeout/);
});

test('WORKING Art actions follow canonical complete status and retries serialize', () => {
  assert.match(workingArtProjection, /RR_ART_DECISION:/);
  assert.match(workingArtProjection, /pg_advisory_xact_lock/);
  assert.match(workingArtProjection, /rr_pm_save_decision_bundle_v804/);
  assert.match(workingArtProjection, /rr_test_cb_working_art_v611/);
  assert.match(workingArtProjection, /'partial_action_count'/);
  assert.match(workingArtProjection, /'complete_action_count'/);
  assert.match(workingArtProjection, /fixture_residue/);
  assert.match(workingArtProjection, /ART COMPLETE · MATERIAL DUE 1 · CUTTING HOLD/);
});

test('CB completion and Cutting readiness are separate canonical dimensions', () => {
  assert.match(workingCanonicalProjection, /rr_cb_reconcile_department_states_v618/);
  assert.match(workingCanonicalProjection, /when coalesce\(x\.art_due_count,0\)>0 then 'WORKING'/);
  assert.match(workingCanonicalProjection, /else 'CLOSE'/);
  assert.match(workingCanonicalProjection, /CB COMPLETE · CUTTING HOLD/);
  assert.match(workingCanonicalProjection, /CB COMPLETE · READY FOR CUTTING/);
  assert.match(workingCanonicalProjection, /rr_cutting_child_lifecycle_v615/);
  assert.match(workingCanonicalProjection, /lower\(coalesce\(mc\.category_code,''\)\)='regular-cloth'/);
  assert.match(workingCanonicalProjection, /INCOMPLETE LEGACY CB · READ-ONLY HISTORY/);
  assert.match(workingCanonicalProjection, /rr_test_cb_working_projection_v618/);
  assert.match(workingCanonicalProjection, /fixture_residue/);
  assert.match(chat, /CB Status/);
  assert.match(chat, /Cutting Status/);
  assert.match(chat, /function cbDepartmentContext/);
  assert.match(chat, /if\(cbDepartmentContext\(\)\)\{box\.hidden=true;return\}/);
  assert.match(chat, /focusCbCard\(cbNo,consume=false\)/);
  assert.match(chat, /<details class="closed-row"'\+identity/);
  assert.match(chat, /inner\.replace\(\/ data-cb-no=/);
  assert.match(chat, /if\(!fast&&S\.returnFocusCb\)focusCbCard\(S\.returnFocusCb,true\)/);
});

test('Art picker uses effective authority, canonical media thumbnails and No Name fallback', () => {
  assert.match(artPage, /rr_upm_effective_identity_v200/);
  assert.doesNotMatch(artPage, /rpc\("rr_current_role"\)/);
  assert.match(artPage, /\["OWNER","SUPER_ADMIN","ADMIN"\]/);
  assert.match(artPage, /itemImage\(step,row\)/);
  assert.match(artPage, /class="pick-media"/);
  assert.match(artPage, /\|\|"No Name"/);
  assert.match(artHtml, /\.pick-media img/);
  assert.match(chat, /arr\(c\.next_actions\)/);
  assert.match(workingCanonicalProjection, /real-art-decide-master\.html/);
});

test('deployed CB/Cutting UI fixtures are isolated, retry-safe and retire through canonical history', () => {
  assert.match(isolatedUiFixture, /TEST71 V623/);
  assert.match(isolatedUiFixture, /rr_test_cb_ui_fixture_v619/);
  assert.match(isolatedUiFixture, /TEST71 E2E Super Admin/);
  assert.match(isolatedUiFixture, /rr_upm_effective_identity_v200/);
  assert.match(isolatedUiFixture, /pg_advisory_xact_lock/);
  assert.match(isolatedUiFixture, /rr_cb_department_save_v600/);
  assert.match(isolatedUiFixture, /'image_url','https:\/\/example\.invalid\/test71-v623\.jpg'/);
  assert.match(isolatedUiFixture, /rr_pm_save_decision_bundle_v804/);
  assert.match(isolatedUiFixture, /rr_cb_purchase_return_v806/);
  assert.match(isolatedUiFixture, /operation_status='TEST_RETIRED'/);
  assert.match(isolatedUiFixture, /archived_at=coalesce/);
  assert.match(isolatedUiFixture, /retained_purchase_return_count/);
  assert.match(isolatedUiFixture, /set statement_timeout='30s'/);
  assert.match(isolatedUiFixture, /from public,anon,authenticated,service_role/);
  assert.doesNotMatch(isolatedUiFixture, /\bdelete\s+from\b/i);
  assert.doesNotMatch(isolatedUiFixture, /\b(TST1|TTT1-S2|1002S1|CB 1004)\b/);
});

test('authority, idempotency and audit remain server enforced', () => {
  assert.match(migration, /rr_cb_department_assert_authority_v600/);
  assert.match(migration, /OWNER','SUPER_ADMIN','ADMIN/);
  assert.match(migration, /action_id uuid not null unique/);
  assert.match(migration, /duplicate_blocked',true/);
  assert.match(migration, /actual_actor_id/);
  assert.match(migration, /effective_actor_id/);
  assert.match(migration, /previous_state/);
  assert.match(migration, /new_state/);
  assert.match(form, /if\(saving\)return/);
  assert.match(form, /params=\{p_cb_id:cbId,p_action_id:pending\.actionId/);
  assert.equal((form.match(/rr_cb_department_save_v600',params/g) || []).length, 2);
  assert.match(form, /statement timeout\|57014\|canceling statement\|failed to fetch\|network/);
});

test('CB directory preserves the canonical V85 volatility contract', () => {
  assert.match(directoryVolatility, /alter function public\.rr_real_chat_directory_v600\(\) volatile/);
  assert.match(directoryVolatility, /V85 retains its existing session\/identity mutation contract/);
});

test('reused V713 creator resolves canonical effective authority', () => {
  assert.match(authorityBridge, /rr_upm_effective_identity_v200\(\)/);
  assert.match(authorityBridge, /OWNER','SUPER_ADMIN','ADMIN/);
  assert.match(authorityBridge, /Act As authority is enforced/);
  assert.doesNotMatch(authorityBridge, /rr_current_role\(\)/);
  assert.match(v713Authority, /create or replace function public\.rr_is_owner_or_admin\(\)/);
  assert.match(v713Authority, /rr_upm_effective_identity_v200\(\)/);
  assert.match(v713Authority, /OWNER','SUPER_ADMIN','ADMIN/);
});

test('CB save respects canonical generated purchase amount', () => {
  assert.match(generatedAmount, /amount is GENERATED ALWAYS/);
  assert.match(generatedAmount, /database-generated from Qty × Rate/);
  assert.match(generatedAmount, /rr_cb_department_save_v600/);
});

test('CB OPEN preserves canonical Qty, Value and exact Roll identity', () => {
  assert.match(form, /function entryQty\(m\)\{return Number\(m\?\.qty\|\|0\)\}/);
  assert.match(form, /function hydrateRegularRolls\(/);
  assert.match(form, /ri=Number\(x\.roll_no\)-1/);
  assert.match(form, /qtySource:'manual'/);
  assert.match(form, /Purchase Qty \*/);
  assert.match(form, /return q>0&&r>0\?q\*r:0/);
  assert.match(form, /window\.__CB_DEPARTMENT_TEST__=\{draftInvariantPreview,hydrateRegularRolls,showMessage:setMessage\}/);
});

test('CB create and Draft retry are backend serialized and identity guarded', () => {
  assert.match(openDraftInvariants, /rr_fabric_purchases_active_cb_no_v608_uq/);
  assert.match(openDraftInvariants, /create unique index if not exists/);
  assert.match(openDraftInvariants, /where upper\(coalesce\(operation_status,'ACTIVE'\)\)='ACTIVE'/);
  assert.match(openDraftInvariants, /rr_guard_cb_number_identity_v608/);
  assert.match(openDraftInvariants, /pg_advisory_xact_lock\(hashtextextended\('RR_CB_NO:'/);
  assert.match(openDraftInvariants, /before insert or update of cb_no,operation_status/);
  assert.match(openDraftInvariants, /pg_advisory_xact_lock\(hashtextextended\('RR_CB_ACTION:'/);
  assert.match(openDraftInvariants, /rr_test_cb_open_draft_invariants_v608/);
  assert.match(openDraftInvariants, /'qty',120/);
  assert.match(openDraftInvariants, /'rate',365/);
  assert.match(openDraftInvariants, /'amount',43800/);
  assert.match(openDraftInvariants, /'roll_no',1,'qty',120/);
  assert.match(openDraftInvariants, /'same_action_audits'/);
  assert.match(openDraftInvariants, /fixture_residue/);
  assert.match(openDraftProof, /when raise_exception then/);
  assert.match(openDraftProof, /position\(v_cb_no in sqlerrm\)>0/);
  assert.match(openDraftProof, /lower\(sqlerrm\) like '%already exists%'/);
  assert.match(openDraftProof, /No business row, duplicate guard, or canonical save behavior is changed/);
  assert.match(form, /RR_CB_PENDING_ACTION_V608/);
  assert.match(form, /localStorage\.removeItem\(pending\.key\)/);
  assert.match(form, /materials\[0\]\.clientKey=cbClientKey/);
});

test('CB 1004 audit is read-only and mobile messages clear the sticky footer', () => {
  assert.match(openDraftInvariants, /rr_test_cb_snapshot_v608\(p_cb_no text\)/);
  assert.doesNotMatch(openDraftInvariants, /like '%1004%'/i);
  assert.match(openDraftInvariants, /language plpgsql\s+stable\s+security definer/);
  assert.doesNotMatch(
    openDraftInvariants.match(/create or replace function public\.rr_test_cb_snapshot_v608\(p_cb_no text\)[\s\S]*?\$function\$;/)?.[0] || '',
    /\b(insert|update|delete)\b/i
  );
  assert.match(form, /calc\(156px \+ env\(safe-area-inset-bottom\)\)/);
  assert.match(form, /function revealAboveFooter\(/);
  assert.match(form, /scrollIntoView\(\{behavior:'smooth',block:'center'\}\)/);
});
