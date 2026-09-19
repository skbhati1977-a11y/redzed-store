const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');

const chat=fs.readFileSync('test70-real-chat-live-v70.js','utf8');
const migration=fs.readFileSync('supabase/migrations/20260919164902_test71_real_chat_lifecycle_projection_v320.sql','utf8');

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
