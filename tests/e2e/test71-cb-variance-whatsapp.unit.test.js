const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('fs');
const path=require('path');

const root=path.resolve(__dirname,'../..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');

test('CB Short Excess report avoids mobile about:blank dead-end',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const fnStart=cb.indexOf('async function reportReconciliationVariance()');
  const fnEnd=cb.indexOf('function reconciliationPanel()',fnStart);
  const block=cb.slice(fnStart,fnEnd);
  assert.ok(block.includes('await flushFieldAutosave()'));
  assert.ok(block.includes("await sendReportToSuperAdmin('CB_VARIANCE',reportId)"));
  assert.ok(!cb.includes("window.open('about:blank'"));
  assert.ok(!cb.includes('reserveWhatsappWindow()'));
  assert.ok(!block.includes('preparedWindow'));
});

test('CB variance WhatsApp uses same-tab handoff and restores CB return state',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const fnStart=cb.indexOf('async function sendReportToSuperAdmin(');
  const fnEnd=cb.indexOf('async function reportReconciliationVariance()',fnStart);
  const block=cb.slice(fnStart,fnEnd);
  const confirmAt=block.indexOf("rr_report_send_superadmin_confirm_v1");
  const assignAt=block.indexOf('location.assign(waUrl)');
  assert.ok(cb.includes("sessionStorage.setItem('RR_CB_WHATSAPP_RETURN_V1'"));
  assert.ok(confirmAt>=0,'SENT status confirmation must run');
  assert.ok(assignAt>confirmAt,'same-tab WhatsApp handoff must happen after SENT status save attempt');
  assert.ok(!block.includes('window.open('));
  assert.ok(cb.includes('restoreCbAfterWhatsApp'));
});

test('CB Debit Note decision and variance report remain separate actions',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  assert.ok(cb.includes("node.querySelector('.makeDebitNote')?.addEventListener('click',()=>{if(confirm('Create supplier Debit Note for the physical weight shortage?'))decideReconciliation('DEBIT_NOTE')}"));
  assert.ok(cb.includes("node.querySelector('.reportVariance')?.addEventListener('click',reportReconciliationVariance)"));
});

test('CB variance WhatsApp template contains CB and physical reconciliation values',()=>{
  const sql=read('supabase/migrations/20261003174200_test71_cb_variance_whatsapp_delivery.sql');
  for(const token of [
    "REDZED · CB ",
    "CB No.: ",
    "Party Bill Qty: ",
    "Physical Roll / Stock-In Qty: ",
    "Difference: ",
    "Action: Please review and forward this report to the Supplier.",
    "Physical Received Qty: "
  ]) assert.ok(sql.includes(token),token);
  assert.ok(sql.includes("rr_cb_variance_report_v1"));
  assert.ok(sql.includes("rr_cb_purchase_rolls"));
  assert.ok(sql.includes("variance_qty"));
});
