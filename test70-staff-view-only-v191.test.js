const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const sql = fs.readFileSync('supabase/migrations/20260916080000_test70_staff_view_only_action_scope_v191.sql','utf8');
const live = fs.readFileSync('test70-real-chat-live-v70.js','utf8');

test('STAFF visibility cannot grant workflow actions', () => {
  assert.match(sql,/STAFF membership is view-only/);
  assert.match(sql,/'actions','\[\]'::jsonb,'requires_action',false/);
  assert.match(sql,/staff_view_only/);
});

test('actual worker and home-department leaders retain their own actions', () => {
  assert.match(sql,/visible_worker_ids/);
  assert.match(sql,/v_role in \('MANAGER','DEPARTMENT_HEAD','CUTTING_MASTER'\)/);
  assert.match(sql,/v_home=public\.rr_upm_core_department_v9077/);
});

test('Nasim has explicit Fabrication Manager actions, independent from STAFF', () => {
  assert.match(sql,/v_role='MANAGER' and v_home='FABRICATION'/);
  assert.match(sql,/full_name,''\)\)\)='nasim'/);
  assert.match(live,/rr_upm_bulk_set_department_rates_v189/);
});

test('live page consumes the authorization-scoped V9 search', () => {
  assert.match(live,/rr_real_chat_work_search_v10/);
});

test('Act As exposes only the selected Lineman actions in group and personal chat', () => {
  assert.match(live,/function actAsActionCard/);
  assert.match(live,/visible\.includes\(selectedId\)/);
  assert.match(live,/actions:\[\],requires_action:false,act_as_view_only:true/);
  assert.match(live,/\.map\(x=>actAsActionCard\(x,selectedId,role,allowed,selectedName\)\)/);
});
