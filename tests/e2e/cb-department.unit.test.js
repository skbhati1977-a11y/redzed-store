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
  assert.match(migration, /Cutting-blocking DUE Material must be confirmed first/);
  assert.match(form, /DUE Qty blank/);
  assert.match(form, /DEFINE IN MATERIAL MASTER/);
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
  assert.match(chat, /SENT TO CUTTING/);
  assert.match(artProjection, /real-art-decide-master\.html\?cb_unit_id=/);
  assert.match(artProjection, /rr_cb_art_assignments a where a\.cb_id=u\.id/);
  assert.doesNotMatch(chat, /real-art-decide-master\.html\?cb_id=/);
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
