const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const migration = fs.readFileSync(
  'supabase/migrations/20260920223000_test71_checkpoint5_purchase_fabrication_identity_v330.sql',
  'utf8'
);
const receiverProjection = fs.readFileSync(
  'supabase/migrations/20260920224500_test71_checkpoint5_selected_receiver_projection_v331.sql',
  'utf8'
);
const projectionLockdown = fs.readFileSync(
  'supabase/migrations/20260920230000_test71_checkpoint5_projection_core_lockdown_v332.sql',
  'utf8'
);
const chat = fs.readFileSync('test70-real-chat-live-v70.js', 'utf8');

test('Purchase personal lane reuses canonical bridge history', () => {
  assert.match(migration, /rr_real_chat_conversation_history_v83/);
  assert.match(migration, /rr_upm_effective_identity_v200\(\)/);
  assert.match(chat, /chatRowsV330=chatRows/);
  assert.match(chat, /purchasePersonal=kind==='person'/);
  assert.match(chat, /toUpperCase\(\)!=='PURCHASE'/);
  assert.doesNotMatch(migration, /create table[^;]*purchase_personal/i);
});

test('Fabrication receipt and worker assignment have distinct canonical states', () => {
  assert.match(migration, /UPM_FABRICATION_RECEIPT/);
  assert.match(migration, /Worker receipt confirmed · Fabrication handover closed/);
  assert.match(migration, /WAITING FOR '\|\|upper\(coalesce/);
  assert.match(migration, /V330_IDEMPOTENT_RECEIVER_ACCEPT/);
  assert.match(migration, /duplicate_blocked',true,'audit_inserted',false/);
  assert.match(receiverProjection, /rr_upm_current_worker_id_v9112\(\)/);
  assert.match(receiverProjection, /coalesce\(c->>'worker_id',''\)<>coalesce\(v_worker::text,''\)/);
  assert.match(receiverProjection, /'actions','\[\]'::jsonb/);
  assert.match(projectionLockdown, /from public,anon,authenticated/);
  assert.match(projectionLockdown, /to service_role/);
});

test('Recovery retry uses canonical journey identity and does not delete audit rows', () => {
  assert.match(migration, /MISSING_RECOVERY_HANDOVER/);
  assert.match(migration, /Existing recovery handover reused/);
  assert.match(migration, /upper\(coalesce\(x\.status,''\)\)<>'SUPERSEDED'/);
  assert.match(migration, /audit_event_count/);
  assert.doesNotMatch(migration, /delete from public\.rr_upm_missing_recovery_events_v215/i);
  assert.doesNotMatch(migration, /delete from public\.rr_upm_responsibility_events_v800/i);
});

test('Recovery card exposes separate business identities and quantity journey', () => {
  for (const field of [
    'performer_name', 'assigner_name', 'receiver_name', 'responsible_name',
    'source_expected_qty', 'accepted_qty', 'difference_qty',
    'confirmed_short_qty', 'recovery_pending_qty', 'current_downstream_good_qty'
  ]) assert.match(migration, new RegExp(field));
  assert.match(chat, /function identityAudit\(c\)/);
  assert.match(chat, /\['Responsible',c\.responsible_name\]/);
});

test('Checkpoint 5 fixtures are labelled, idempotent and rollback-only where mutating', () => {
  assert.match(migration, /TEST71 CHECKPOINT 5 — SAFE TO DELETE/);
  assert.match(migration, /on conflict\(canonical_key\) do update/);
  assert.match(migration, /TEST71_CP5_ROLLBACK/);
  assert.match(migration, /'rolled_back',not v_persisted/);
  assert.match(migration, /where canonical_key=v_key and data_mode='TEST'/);
});
