const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const sql=fs.readFileSync('supabase/migrations/20260916110000_test70_worker_accept_working_close_v199.sql','utf8');
const chat=fs.readFileSync('test70-real-chat-live-v70.js','utf8');
const app=fs.readFileSync('real-upm-department-view-v789.js','utf8');
const accept=fs.readFileSync('real-upm-submit-confirm-v796.js','utf8');

test('universal worker lifecycle uses OPEN accept, WORKING submit and worker CLOSE',()=>{
  assert.match(sql,/rr_real_chat_work_search_v12/);
  assert.match(sql,/v_status='OPEN'/);
  assert.match(sql,/v_status='WORKING'/);
  assert.match(sql,/v_status='CLOSE'/);
  assert.match(sql,/rr_upm_assignment_receipts_v9112/);
  assert.match(sql,/rr_upm_submit_requests_v794/);
});

test('pending receipt cannot leak into worker WORKING lane',()=>{
  assert.match(sql,/v_receipt_pending or v_submitted/);
  assert.match(sql,/PENDING','DISPUTED/);
  assert.match(sql,/READY_TO_ASSIGN/);
});

test('worker cannot assign in app, chat or guarded assignment RPC',()=>{
  assert.match(sql,/ACT AS % is view\/work scoped/);
  assert.match(chat,/canAssignWorkV200/);
  assert.match(chat,/ASSIGN_WORKER/);
  assert.match(app,/rr_superadmin_preview_actor_role/);
  assert.match(app,/assignTab\.hidden=!canAssign/);
});

test('accept and submit actions return to the correct Real Chat lane',()=>{
  assert.match(accept,/ACCEPT WORK · CONFIRM PCS/);
  assert.match(accept,/action:"CONFIRM_RECEIVED_PCS"/);
  assert.match(chat,/action==='CONFIRM_RECEIVED_PCS'\?'WORKING'/);
  assert.match(chat,/action==='SUBMIT'\?'CLOSE'/);
  assert.match(app,/realChatActionComplete.*action:'SUBMIT'/);
});
