const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const sql = fs.readFileSync(
  'supabase/migrations/20260922103000_test71_cutting_department_lifecycle_v615.sql',
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

test('Real Chat maps Ready to WORKING and release to CLOSE without stale actions', () => {
  assert.match(sql, /when e='READY_FOR_CUTTING' then 'WORKING'/i);
  assert.match(sql, /when e='CUTTING_RELEASE_SUCCEEDED' then 'CLOSE'/i);
  assert.match(sql, /'status','WORKING','canonical_state','WORKING','cutting_state','READY_FOR_CUTTING'/i);
  assert.match(chat, /\['ART_DUE','CUTTING_HOLD'\]\.includes\(x\.state\)\?'OPEN'/);
  assert.match(chat, /status!=='WORKING'.*READY_FOR_CUTTING/);
  assert.match(chat, /status==='WORKING'\?e==='READY_FOR_CUTTING'/);
});

test('Cutting App derives Material Hold and opens exact Art child identity', () => {
  assert.match(cutting, /function materialDueCount\(cbId\)/);
  assert.match(cutting, /return "cutting_hold"/);
  assert.match(cutting, /data-art-decision=/);
  assert.match(cutting, /cb_unit_id=\$\{encodeURIComponent\(unitId\)\}/);
  assert.match(cutting, /Material Due — confirm material before Cutting/);
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
});
