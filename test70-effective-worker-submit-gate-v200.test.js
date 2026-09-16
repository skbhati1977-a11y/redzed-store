const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');

const migration=fs.readFileSync('supabase/migrations/20260916132600_test70_effective_worker_submit_gate_v200.sql','utf8');
const transitionMigration=fs.readFileSync('supabase/migrations/20260916141000_test70_worker_transition_idempotency_v201.sql','utf8');
const receiptMigration=fs.readFileSync('supabase/migrations/20260916001000_test70_custody_missing_owner_mirror_v185.sql','utf8');
const app=fs.readFileSync('real-upm-department-view-v789.js','utf8');
const actualCostGate=fs.readFileSync('real-upm-actual-cost-gate-v9300.js','utf8');
const chat=fs.readFileSync('test70-real-chat-live-v70.js','utf8');
const appHtml=fs.readFileSync('real-department-lite-v9127.html','utf8');
const chatHtml=fs.readFileSync('test70-cb-purchase-real-chat-pilot.html','utf8');

const canonicalRoles=['OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN'];

test('receipt and confirmation RPCs resolve the effective Act-As worker',()=>{
  assert.match(migration,/rr_upm_effective_identity_v200/);
  assert.match(migration,/rr_test_on_behalf_context_v176/);
  assert.match(migration,/create or replace function public\.rr_upm_current_worker_id_v9112/);
  assert.match(migration,/rr_upm_effective_identity_v200\(\)->>'worker_id'/);
  assert.match(receiptMigration,/rr_upm_my_pending_receipts_v9112[\s\S]*rr_upm_current_worker_id_v9112/);
  assert.match(receiptMigration,/rr_upm_confirm_assignment_receipt_v9112[\s\S]*rr_upm_current_worker_id_v9112/);
  assert.match(app,/rr_upm_effective_identity_v200/);
});

test('PENDING or DISPUTED receipt is blocked in both queue and submit mutation',()=>{
  assert.match(migration,/V200_RECEIPT_GATED_SUBMIT_QUEUE/);
  assert.match(migration,/upper\(receipt\.status\) in \('PENDING','DISPUTED'\)/);
  assert.match(migration,/ACCEPT WORK and confirm received PCS before READY TO SUBMIT/);
  assert.match(migration,/create or replace function public\.rr_upm_ready_submit_v794/);
});

test('Line Man handoff remains the submit engine for worker lifecycle sheets',()=>{
  assert.match(app,/rr_upm_ready_submit_to_lm_v184/);
  assert.match(actualCostGate,/if\(m\.querySelector\('#rfSubmitLM'\)\)\{m\.dataset\.rr9300='1';return\}/);
  assert.match(appHtml,/real-upm-actual-cost-gate-v9300\.js\?v=201/);
});

test('accept records WORKING and submitted assignments cannot be queued twice',()=>{
  assert.match(transitionMigration,/set status='IN_PROGRESS'/);
  assert.match(transitionMigration,/'work_status','WORKING'/);
  assert.match(transitionMigration,/V201_IDEMPOTENT_SUBMIT_QUEUE/);
  assert.match(transitionMigration,/active_submit_blocked_count/);
  assert.match(transitionMigration,/This Colour is already submitted to Line Man/);
  assert.match(transitionMigration,/pg_advisory_xact_lock/);
});

test('App, Chat and backend use the same assignment authority allowlist',()=>{
  const appRoles=app.match(/const allowed=new Set\(\[([^\]]+)\]\)/)?.[1].match(/'[^']+'/g)?.map(x=>x.slice(1,-1));
  const chatRoles=chat.match(/const ASSIGN_ROLES_V200=new Set\(\[([^\]]+)\]\)/)?.[1].match(/'[^']+'/g)?.map(x=>x.slice(1,-1));
  assert.deepEqual(appRoles,canonicalRoles);
  assert.deepEqual(chatRoles,canonicalRoles);
  assert.match(migration,/\('OWNER','SUPER_ADMIN','ADMIN','MANAGER','LINE_MANAGER','LINE_MAN'\)/);
  assert.doesNotMatch(app,/const allowed=new Set\([^\n]*CUTTING_MASTER/);
  assert.doesNotMatch(chat,/ASSIGN_ROLES_V200[^\n]*(CUTTING_MASTER|DEPARTMENT_HEAD)/);
});

test('V200 assets are cache-busted for the live TEST70 flow',()=>{
  assert.match(appHtml,/real-upm-department-view-v789\.js\?v=200/);
  assert.match(appHtml,/real-upm-submit-confirm-v796\.js\?v=200/);
  assert.match(chatHtml,/test70-real-chat-live-v70\.js\?v=202/);
});
