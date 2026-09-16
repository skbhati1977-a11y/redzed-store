const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');

const sql=fs.readFileSync('supabase/migrations/20260916072000_test70_fabrication_identity_rate_authority_v189.sql','utf8');
const statusOnly=fs.readFileSync('supabase/migrations/20260916074500_test70_fabrication_group_status_only_v190.sql','utf8');
const live=fs.readFileSync('test70-real-chat-live-v70.js','utf8');

test('Fabrication identities are truthful',()=>{
  assert.match(sql,/TRUTHFUL_PRINT_WORKER_V189/);
  assert.match(sql,/TRUTHFUL_METAL_ID_WORKER_V189/);
  assert.match(sql,/FABRICATION_MANAGER_CUT_TO_DESPATCH_V189/);
  assert.match(sql,/membership_side='WORKER'/);
  assert.match(sql,/membership_side='STAFF'/);
});

test('Nasim uses audited canonical multi-department Actual Rate engine',()=>{
  assert.match(sql,/rr_upm_bulk_set_department_rates_v189/);
  assert.match(sql,/rr_upm_set_department_rate_v760/);
  assert.match(sql,/SALARIED_WEIGHTED_COST_AUTO/);
  assert.match(sql,/full_name,''\)\)\)='nasim'/);
  assert.match(live,/SET ACTUAL COSTS/);
  assert.match(live,/rr_upm_bulk_set_department_rates_v189/);
});

test('Fabrication cards retain virtual group but display source work',()=>{
  assert.match(sql,/rr_real_chat_work_inbox_v81/);
  assert.match(sql,/operational_group_name/);
  assert.match(sql,/source_department_code/);
  assert.match(live,/rr_real_chat_work_search_v9/);
  assert.match(statusOnly,/'actions',case when coalesce/);
  assert.match(statusOnly,/Action source worker chat में होगा/);
});
