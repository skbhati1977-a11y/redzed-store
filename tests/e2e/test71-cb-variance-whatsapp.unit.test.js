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
});

test('CB variance builds a real PNG file attachment for native share',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const fnStart=cb.indexOf('async function reportReconciliationVariance()');
  const fnEnd=cb.indexOf('function reconciliationPanel()',fnStart);
  const block=cb.slice(fnStart,fnEnd);
  assert.ok(cb.includes("function varianceReportPngFile("));
  assert.ok(cb.includes("new File([bytes],'CB-'"));
  assert.ok(cb.includes("{type:'image/png'}"));
  assert.ok(block.includes("navigator.canShare({files:[shareFile]})"));
  assert.ok(block.includes("navigator.share({title:"));
  assert.ok(block.includes("files:[shareFile]"));
});

test('CB native file share starts before any awaited backend work so mobile user activation is retained',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const fnStart=cb.indexOf('async function reportReconciliationVariance()');
  const fnEnd=cb.indexOf('function reconciliationPanel()',fnStart);
  const block=cb.slice(fnStart,fnEnd);
  const shareAt=block.indexOf("nativeShare=navigator.share(");
  const backendAt=block.indexOf("const backendPromise=");
  const firstAwait=block.indexOf("await ");
  assert.ok(shareAt>=0,'native share must start');
  assert.ok(backendAt>shareAt,'backend promise must start after native share invocation');
  assert.ok(firstAwait>shareAt,'no await may precede native share invocation');
});

test('CB variance still records the report atomically in backend while file share is open',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const fnStart=cb.indexOf('async function reportReconciliationVariance()');
  const fnEnd=cb.indexOf('function reconciliationPanel()',fnStart);
  const block=cb.slice(fnStart,fnEnd);
  assert.ok(block.includes("rr_cb_variance_whatsapp_prepare_v2"));
  assert.ok(block.includes("const backendPromise="));
  assert.ok(!block.includes("window.open('about:blank'"));
});

test('CB fallback downloads PNG and opens direct WhatsApp text only when native file share is unavailable',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  const fnStart=cb.indexOf('async function reportReconciliationVariance()');
  const fnEnd=cb.indexOf('function reconciliationPanel()',fnStart);
  const block=cb.slice(fnStart,fnEnd);
  assert.ok(cb.includes('function downloadVarianceFile(file)'));
  assert.ok(block.includes('downloadVarianceFile(shareFile)'));
  assert.ok(block.includes("https://api.whatsapp.com/send?phone="));
});

test('CB variance atomic RPC creates report, prepares delivery, marks SENT and returns phone/message',()=>{
  const sql=read('supabase/migrations/20261003183000_test71_cb_variance_whatsapp_atomic_v2.sql');
  for(const token of [
    'rr_cb_variance_whatsapp_prepare_v2',
    'rr_cb_variance_report_v1',
    "rr_report_send_superadmin_prepare_v1('CB_VARIANCE'",
    'rr_report_send_superadmin_confirm_v1',
    "'recipient_phone'",
    "'message'"
  ]) assert.ok(sql.includes(token),token);
});

test('CB Debit Note decision and variance report remain separate actions',()=>{
  const cb=read('real-cb-new-v9130-fix2.html');
  assert.ok(cb.includes("mount.querySelector('.makeDebitNote')?.addEventListener('click',()=>{if(confirm('Create supplier Debit Note for the physical weight shortage?'))decideReconciliation('DEBIT_NOTE')}"));
  assert.ok(cb.includes("mount.querySelector('.reportVariance')?.addEventListener('click',reportReconciliationVariance)"));
});
