const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');

const chat=fs.readFileSync('test70-real-chat-live-v70.js','utf8');
const migration=fs.readFileSync('supabase/migrations/20260919164902_test71_real_chat_lifecycle_projection_v320.sql','utf8');
const receiptAlias=fs.readFileSync('supabase/migrations/20260919190500_test71_receipt_identity_alias_v321.sql','utf8');
const workerSubmit=fs.readFileSync('supabase/migrations/20260919193000_test71_worker_submit_close_v322.sql','utf8');
const accept=fs.readFileSync('test70-accept-work-v205.html','utf8');
const acceptGuard=fs.readFileSync('test70-universal-accept-guard-v212.js','utf8');

test('V317 mirror resolves every emitted assignment key without a second search',()=>{
  assert.match(migration,/b:=public\.rr_real_chat_work_search_v14\(/);
  assert.equal((migration.match(/rr_real_chat_work_search_v14\(/g)||[]).length,1);
  assert.match(migration,/c->>'assignment_id'/);
  assert.match(migration,/c->>'event_key'/);
  assert.match(migration,/c->>'canonical_key'/);
  assert.match(migration,/c->>'original_record_id'/);
  assert.match(migration,/assignment_key::uuid/);
  assert.match(migration,/a\.id=raw\.assignment_id/);
  assert.doesNotMatch(migration,/a\.id::text=raw\.assignment_key/);
  assert.match(migration,/'resolved_work_state',resolved/);
  assert.match(migration,/'responsibility_event_id',eid/);
});

test('assigned identity gets canonical Accept regardless of descriptive worker role',()=>{
  assert.match(chat,/workerSelf=!!actorWorker&&!!assignedWorker&&actorWorker===assignedWorker/);
  assert.doesNotMatch(chat,/workerSelf=role==='WORKER'/);
  assert.match(chat,/label:'ACCEPT & COUNT'/);
  assert.match(chat,/test70-accept-work-v205\.html\?assignment=/);
  assert.match(chat,/engine:'rr_upm_accept_physical_count_batch_v802'/);
});

test('pending staff view cannot receive worker Accept or Submit',()=>{
  assert.match(chat,/\['SUBMIT','CONFIRM_RECEIVED_PCS'\]/);
  assert.match(chat,/const accept=workerSelf\?canonicalAcceptAction/);
  assert.match(chat,/receipt==='CONFIRMED'&&!workerSelf/);
});

test('personal cards render canonical lifecycle status and preserve action objects',()=>{
  assert.match(chat,/source_status:x\.resolved_work_state\|\|x\.receipt_status/);
  assert.match(chat,/typeof action==='string'\?\{code:action,label:action\}:action/);
});

test('page boot relies on targeted projection triggers instead of full reconciliation',()=>{
  assert.doesNotMatch(chat,/Promise\.all\(\[rpc\('rr_real_chat_sync_upm_history_v71'/);
  assert.match(chat,/historySync:"TARGETED_TRIGGER_CANONICAL_LIFECYCLE"/);
});

test('Accept reuses an already-matching effective worker identity',()=>{
  assert.match(accept,/rr_upm_effective_identity_v200/);
  assert.match(accept,/effectiveWorker!==String\(worker\)/);
  assert.match(accept,/rr_test_set_on_behalf_context_v176/);
  assert.match(accept,/rr_upm_accept_physical_count_batch_v802/);
});

test('Accept guard keeps the canonical worker from the rendered card',()=>{
  assert.match(acceptGuard,/source\.searchParams\.get\('worker'\)/);
  assert.match(acceptGuard,/canonicalWorker/);
  assert.match(acceptGuard,/worker='\+encodeURIComponent\(canonicalWorker\)/);
  assert.doesNotMatch(acceptGuard,/worker='\+encodeURIComponent\(r\.worker_id\)/);
});

test('receipt fetch and confirmation compare historical IDs canonically',()=>{
  assert.match(receiptAlias,/create or replace function public\.rr_upm_my_pending_receipts_v9112/);
  assert.match(receiptAlias,/create or replace function public\.rr_upm_confirm_assignment_receipt_batch_v204/);
  assert.ok((receiptAlias.match(/rr_canonical_worker_id_v264\(r\.worker_id\)/g)||[]).length>=4);
  assert.match(receiptAlias,/'version','V321_CANONICAL_RECEIPT_IDENTITY'/);
  assert.doesNotMatch(receiptAlias,/update public\.rr_upm_assignment_receipts_v9112\s+set worker_id=/);
});

test('Printing Submit uses one proper popup and never browser prompt for Chemical KG',()=>{
  assert.match(chat,/TEAM SALARY \/ PCS/);
  assert.match(chat,/FRAME RECOVERY \/ PCS/);
  assert.match(chat,/PRINTING MATERIAL \/ PCS/);
  assert.match(chat,/CHEMICAL KG/);
  assert.match(chat,/Chemical KG required\. Zero only when actual consumption is genuinely zero\./);
  assert.doesNotMatch(chat,/prompt\('Printing Chemical KG consumed'/);
  assert.match(chat,/rr_printing_finalize_costing_v307/);
  assert.match(chat,/rr_upm_ready_submit_to_receiver_v204/);
});

test('canonical Worker Submit stops salary and projects Personal CLOSE',()=>{
  assert.match(workerSubmit,/after insert on public\.rr_upm_submit_requests_v794/);
  assert.match(workerSubmit,/rr_salaried_team_finish_if_applicable_v300/);
  assert.match(workerSubmit,/submit_request_id is not null then 'CLOSE'/);
  assert.match(workerSubmit,/'version','V322_PERSONAL_WORKER_SUBMIT_CLOSE'/);
  assert.match(workerSubmit,/काम जमा किया/);
  assert.doesNotMatch(workerSubmit,/create table/i);
});
