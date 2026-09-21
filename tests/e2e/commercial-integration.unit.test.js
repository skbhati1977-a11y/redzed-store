const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const sql = fs.readFileSync('supabase/migrations/20260921085732_test71_commercial_real_chat_canonical_v500.sql', 'utf8');
const chat = fs.readFileSync('test70-real-chat-live-v70.js', 'utf8');
const pi = fs.readFileSync('real-pi-specimen-v9514.js', 'utf8');
const rci = fs.readFileSync('real-rci-v9740.js', 'utf8');

test('commercial bridge projects existing canonical engines', () => {
  for (const name of ['rr_sales_real_chat_queue_v500', 'rr_costing_real_chat_queue_v500', 'rr_accounts_real_chat_home_v500']) {
    assert.match(sql, new RegExp(`function public\\.${name}`));
    assert.match(chat, new RegExp(name));
  }
  assert.match(sql, /from public\.rr_fg_pi_v787/);
  assert.match(sql, /from public\.rr_market_requirements_v9420/);
  assert.match(sql, /from public\.rr_upm_work_assignments_v8/);
  assert.doesNotMatch(sql, /create table[^;]+(?:pi|ci|rci|market_requirement|upm_department_rates)_v500/i);
});

test('accounts FIFO extends canonical vouchers without replacing them', () => {
  assert.match(sql, /references public\.rr_account_transactions_v805/);
  assert.match(sql, /after insert on public\.rr_account_transactions_v805/);
  assert.match(sql, /bill_date,created_at,id for update/);
  assert.match(sql, /CUSTOMER_CREDIT/);
  assert.match(sql, /SUPPLIER_ADVANCE/);
  assert.match(sql, /PART_PAID/);
  assert.match(sql, /aging_90_plus/);
  assert.match(sql, /revoke all on public\.rr_account_bills_v500 from anon,authenticated/);
});

test('sales PI reopen and RCI use canonical RPCs', () => {
  assert.match(pi, /rr_sales_pi_detail_v500/);
  assert.match(pi, /p_pi_id: savedPiId/);
  assert.match(rci, /rr_rci_context_v9740/);
  assert.match(rci, /rr_rci_save_draft_v9740/);
  assert.match(rci, /rr_rci_post_linked_final_v9741/);
  assert.doesNotMatch(rci, /\.from\(/);
});

test('costing projection carries context and excludes private cost payload', () => {
  for (const token of ['art_no', 'thumbnail', 'pcs', 'missing_departments', 'departments', 'worker', 'accept_time', 'submit_time']) {
    assert.ok(sql.includes(token), token);
  }
  assert.match(sql, /'private_cost_included',false/);
  assert.doesNotMatch(chat.match(/async function openCommercialChat[\s\S]+?async function openChat/)?.[0] || '', /owner_margin|base_cost_per_pc|team_salary|material_breakdown/);
});
