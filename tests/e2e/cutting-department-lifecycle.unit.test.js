const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const sql = fs.readFileSync(
  'supabase/migrations/20260922103000_test71_cutting_department_lifecycle_v615.sql',
  'utf8'
);
const availabilitySql = fs.readFileSync(
  'supabase/migrations/20260922114500_test71_cutting_projection_availability_v616.sql',
  'utf8'
);
const timeoutSql = fs.readFileSync(
  'supabase/migrations/20260922121000_test71_cutting_proof_timeout_v617.sql',
  'utf8'
);
const cutting = fs.readFileSync('real-cutting-master-pm.V719.3.js', 'utf8');
const chat = fs.readFileSync('test70-real-chat-live-v70.js', 'utf8');
const art = fs.readFileSync('real-art-decide-master-v9231.js', 'utf8');

test('one backend classifier owns Art Due, Material Hold, Ready and Released state', () => {
  assert.match(sql, /function public\.rr_cutting_child_lifecycle_v615\(p_cb_unit_id uuid\)/i);
  assert.match(sql, /when jsonb_array_length\(v_lots\)>0 then 'RELEASED'/i);
  assert.match(sql, /when not v_decisions_complete then 'ART_DUE'/i);
  assert.match(sql, /when v_due_count>0 then 'CUTTING_HOLD'/i);
  assert.match(sql, /else 'READY_FOR_CUTTING'/i);
  assert.match(sql, /when v_state='READY_FOR_CUTTING' then 'WORKING'/i);
});

test('backend release and multi-art paths are authority, DUE and retry guarded', () => {
  assert.match(sql, /function public\.rr_cutting_assert_authority_v615/i);
  assert.match(sql, /'OWNER','SUPER_ADMIN','ADMIN','CUTTING_MASTER'/i);
  assert.match(sql, /Material Due — confirm material before Cutting/i);
  assert.match(sql, /RR_CUTTING_RELEASE:/i);
  assert.match(sql, /RR_CUTTING_MULTI_ART:/i);
  assert.match(sql, /'duplicate_blocked',true/i);
  assert.match(sql, /status=case when r\.status='DECIDED' then 'CONSUMED' else 'CANCELLED' end/i);
});

test('Real Chat uses canonical Cutting state for released lots and OPEN for ready children', () => {
  assert.match(chat, /if\(event==='READY_FOR_CUTTING'\)return status==='OPEN'/);
  assert.match(chat, /c\.canonical_state\|\|c\.chat_status/);
  assert.match(chat, /status!=='OPEN'.*READY_FOR_CUTTING/);
});

test('reconciliation archives every non-ready Cutting projection, including unavailable children', () => {
  assert.match(availabilitySql, /not exists\(select 1 from pg_temp\.rr_cb_child_truth_v615 c[\s\S]*c\.child_state='READY_FOR_CUTTING'/i);
  assert.match(availabilitySql, /archive_reason='CHILD_NOT_READY_V616'/i);
  assert.match(availabilitySql, /select public\.rr_real_chat_reconcile_cb_children_v105\(\)/i);
});

test('Cutting App derives Material Hold and opens exact Art child identity', () => {
  assert.match(cutting, /function materialDueCount\(cbId\)/);
  assert.match(cutting, /rr_cutting_lifecycle_batch_v632/);
  assert.match(cutting, /data-art-decision=/);
  assert.match(cutting, /cb_unit_id=\$\{encodeURIComponent\(unitId\)\}/);
  assert.match(cutting, /Material Due — confirm material before Cutting/);
  const exactLookup = cutting.indexOf('if (requestedDivisionId) {\n    const exactDivision');
  const productionLookup = cutting.indexOf('let productionQuery = client');
  assert.ok(exactLookup >= 0 && exactLookup < productionLookup, 'deep links must resolve the exact child before the full gallery view');
});

test('Art deep link resolves the exact requested child before rendering', () => {
  assert.match(art, /eq\("cb_unit_id",requestedId\)\.maybeSingle\(\)/);
  assert.match(art, /Requested Art Decision child is not available/);
  assert.match(art, /openDecision\(requested\)/);
});

test('rollback-only lifecycle proof covers every transition and leaves zero residue', () => {
  assert.match(sql, /function public\.rr_test_cutting_department_lifecycle_v615/i);
  assert.match(sql, /TEST71_CUTTING_LIFECYCLE_ROLLBACK/);
  assert.match(sql, /'due_release_blocked',v_due_release_blocked/i);
  assert.match(sql, /'release_retry_blocked',v_retry_blocked/i);
  assert.match(sql, /'fixture_residue',v_residue/i);
  assert.match(timeoutSql, /alter function public\.rr_test_cutting_department_lifecycle_v615\(\)[\s\S]*statement_timeout='45s'/i);
  assert.match(timeoutSql, /alter function public\.rr_test_released_dcard_regression_v502\(\)[\s\S]*statement_timeout='30s'/i);
});
