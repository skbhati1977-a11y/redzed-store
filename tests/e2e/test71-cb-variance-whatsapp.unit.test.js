const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('fs');
const path=require('path');

const root=path.resolve(__dirname,'../..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');

test('CB Short Excess report reserves WhatsApp window before async work',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const fnStart=cb.indexOf('async function reportReconciliationVariance()');
  const fnEnd=cb.indexOf('function reconciliationPanel()',fnStart);
  const block=cb.slice(fnStart,fnEnd);
  const reserve=block.indexOf('const waWindow=reserveWhatsappWindow()');
  const firstAwait=block.indexOf('await flushFieldAutosave()');
  assert.ok(reserve>=0,'WhatsApp window must be reserved');
  assert.ok(firstAwait>reserve,'window must be reserved before first await');
  assert.ok(block.includes("await sendReportToSuperAdmin('CB_VARIANCE',reportId,waWindow)"));
  assert.ok(!block.includes('SEND TO SUPER ADMIN on WhatsApp?'));
});

test('CB variance WhatsApp flow has same-tab fallback and return-state restore',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  assert.ok(cb.includes("sessionStorage.setItem('RR_CB_WHATSAPP_RETURN_V1'"));
  assert.ok(cb.includes("preparedWindow.location.replace(waUrl)"));
  assert.ok(cb.includes("location.assign(waUrl)"));
  assert.ok(cb.includes("rr_report_send_superadmin_confirm_v1"));
  assert.ok(cb.includes("restoreCbAfterWhatsApp"));
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
