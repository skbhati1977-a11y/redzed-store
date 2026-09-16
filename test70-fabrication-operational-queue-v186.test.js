const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = __dirname;
const sql = fs.readFileSync(path.join(root,'supabase/migrations/20260916053000_test70_fabrication_operational_queue_v186.sql'),'utf8');
const alterSql = fs.readFileSync(path.join(root,'supabase/migrations/20260916055500_test70_fabrication_alter_group_projection_v187.sql'),'utf8');
const live = fs.readFileSync(path.join(root,'test70-real-chat-live-v70.js'),'utf8');
const html = fs.readFileSync(path.join(root,'test70-cb-purchase-real-chat-pilot.html'),'utf8');

test('Fabrication is a virtual cross-department Lineman queue',()=>{
  assert.match(sql,/rr_real_chat_work_inbox_v79/);
  assert.match(sql,/rr_real_chat_work_inbox_v78/);
  assert.match(sql,/department_code','FABRICATION'/);
  assert.match(sql,/source_department_code/);
  assert.match(sql,/visible_department_codes/);
  assert.match(sql,/WAITING_LM','ESCALATED/);
  assert.match(sql,/LM_ACCEPTED','LM_COUNTED','DISPUTED/);
  assert.match(sql,/q\.status='COMPLETED'/);
});

test('Fabrication action direction follows the existing App engines',()=>{
  assert.match(sql,/LM_ACCEPT_COUNT/);
  assert.match(sql,/rr_upm_accept_submit_v794/);
  assert.match(sql,/LM_SEND_COUNT/);
  assert.match(sql,/rr_upm_lm_count_submit_v794/);
  assert.match(sql,/worker confirmation pending/);
  assert.match(sql,/else '\[\]'::jsonb/);
});

test('custody and missing lifecycle remain mirrored',()=>{
  assert.match(sql,/rr_upm_assignment_receipts_v9112/);
  assert.match(sql,/PENDING','DISPUTED/);
  assert.match(sql,/CONFIRMED','CONFIRMED_SHORT/);
  assert.match(sql,/WORKER_CLAIM_PENDING','RECOVERY_JOURNEY/);
  assert.match(sql,/RECOVERED','CONVERTED_TO_DAMAGE/);
  assert.match(sql,/Packing Submit/);
});

test('Real Chat uses the latest canonical queue and counts virtual group cards',()=>{
  assert.match(live,/rr_real_chat_work_search_v9/);
  assert.match(live,/rr_real_chat_work_search_v2','rr_real_chat_work_search_v5','rr_real_chat_work_search_v6/);
  assert.match(live,/visible_department_codes/);
  assert.match(html,/test70-real-chat-live-v70\.js\?v=192/);
});

test('active Alter and Remake forwarding is projected group-only',()=>{
  assert.match(alterSql,/rr_real_chat_work_inbox_v80/);
  assert.match(alterSql,/rr_upm_alter_journey_v740/);
  assert.match(alterSql,/UPM_FABRICATION_ALTER/);
  assert.match(alterSql,/'group_only',true/);
  assert.match(alterSql,/'worker_id',null/);
});
