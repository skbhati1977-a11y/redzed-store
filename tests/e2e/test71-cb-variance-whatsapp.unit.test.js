const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('fs');
const path=require('path');

const root=path.resolve(__dirname,'../..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');

test('CB reconciliation is rendered after Colours/Rolls and before Yield',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const colour=cb.indexOf('id="colourList"');
  const recon=cb.indexOf('id="reconciliationCard"');
  const yieldCard=cb.indexOf('id="derivedRequirementCard"');
  assert.ok(colour>=0,'Colour section missing');
  assert.ok(recon>colour,'Reconciliation must be after Colours/Rolls');
  assert.ok(yieldCard>recon,'Reconciliation must be before Yield');
  const regularStart=cb.indexOf("if(m.type==='regular')return");
  const regularEnd=cb.indexOf("const due=m.state==='DUE'",regularStart);
  assert.ok(!cb.slice(regularStart,regularEnd).includes('reconciliationPanel()'),'Regular Cloth card must not embed reconciliation');
  assert.ok(cb.includes("function renderReconciliation()"));
  assert.ok(cb.includes("renderReconciliation();\n updateSummary();"));
});

test('CB variance WhatsApp uses one atomic backend RPC before navigation',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const fnStart=cb.indexOf('async function reportReconciliationVariance()');
  const fnEnd=cb.indexOf('function reconciliationPanel()',fnStart);
  const block=cb.slice(fnStart,fnEnd);
  assert.ok(block.includes("rr_cb_variance_whatsapp_prepare_v2"));
  assert.ok(!block.includes("rr_report_send_superadmin_prepare_v1"));
  assert.ok(!block.includes("rr_report_send_superadmin_confirm_v1"));
  assert.ok(block.includes("https://api.whatsapp.com/send?phone="));
  assert.ok(block.includes('location.assign(waUrl)'));
  assert.ok(block.indexOf("rr_cb_variance_whatsapp_prepare_v2") < block.indexOf('location.assign(waUrl)'));
  assert.ok(!cb.includes("window.open('about:blank'"));
});

test('CB variance atomic RPC creates report, prepares delivery, marks SENT and returns phone/message',()=>{
  const sql=read('supabase/migrations/20261003183000_test71_cb_variance_whatsapp_atomic_v2.sql');
  for(const token of [
    'rr_cb_variance_whatsapp_prepare_v2',
    'rr_cb_variance_report_v1',
    "rr_report_send_superadmin_prepare_v1('CB_VARIANCE'",
    'rr_report_send_superadmin_confirm_v1',
    "'recipient_phone'",
    "'message'",
    'grant execute on function public.rr_cb_variance_whatsapp_prepare_v2'
  ]) assert.ok(sql.includes(token),token);
  assert.ok(sql.includes('revoke all on function public.rr_cb_variance_whatsapp_prepare_v2'));
});

test('CB Debit Note decision and variance report remain separate actions',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  assert.ok(cb.includes("mount.querySelector('.makeDebitNote')?.addEventListener('click',()=>{if(confirm('Create supplier Debit Note for the physical weight shortage?'))decideReconciliation('DEBIT_NOTE')}"));
  assert.ok(cb.includes("mount.querySelector('.reportVariance')?.addEventListener('click',reportReconciliationVariance)"));
});

test('CB variance WhatsApp template retains CB and physical reconciliation values',()=>{
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
});
