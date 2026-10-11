const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const chat = fs.readFileSync('test70-real-chat-live-v70.js', 'utf8');
const migration = fs.readFileSync('supabase/migrations/20260928111500_test71_compensation_aware_submit_rate_gate_v777.sql', 'utf8');

test('receipt form prepares read-only and only Save invokes authorized atomic count',()=>{
 const fn=chat.match(/async function openReceiptCountTableV736\(button\)\{[\s\S]*?\nfunction bindMedia/)?.[0]||'';
 assert.match(fn,/rr_chat_assignment_count_context_test71/);assert.match(fn,/rr_chat_assignment_count_save_test71/);
 assert.doesNotMatch(fn,/rr_upm_claim_team_assignment_v694/);
 const authority=fs.readFileSync('sql/test71_assignment_count_delegate.sql','utf8');
 assert.match(authority,/rr_upm_team_assignment_action_allowed_v774/);assert.match(authority,/for update of r,a/);
});

test('submit Actual Rate gate is compensation-aware and remains backend enforced', () => {
  assert.match(migration, /rr_department_compensation_choices_v667/);
  assert.match(migration, /auto_mode/);
  assert.match(migration, /SALARIED_TEAM/);
  assert.match(migration, /not is_team and coalesce\(a\.actual_rate,0\)<=0/);
  assert.match(migration, /Submit blocked: Assignment Actual Rate required/);
});
