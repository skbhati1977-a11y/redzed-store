/* REAL FACTORY Salary Payment V786.3.22 — simple seven-column payment table */
(()=>{'use strict';window.REAL_FACTORY_SALARY_PAYMENT_VERSION='786.3.22-SIMPLE-SEVEN-COLUMN-PAYMENT-TABLE';
const $=id=>document.getElementById(id),state={client:null,preview:null,rows:[],selected:new Set(),manual:new Map(),dirty:false,useAll:true,bulkApplied:false,history:[],activeAmountId:null,autoLoadTimer:null,loading:false,queuedLoadKey:null,contextKey:null,voucherPreviewToken:0};
const safe=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));
const money=v=>Number(v||0).toLocaleString('en-IN',{minimumFractionDigits:2,maximumFractionDigits:2});
const ttlMoney=v=>Number(v||0).toLocaleString('en-IN',{maximumFractionDigits:0});
const err=e=>[e?.message,e?.details,e?.hint,e?.code].filter(Boolean).join(' — ')||'Unknown error';
const today=()=>new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Kolkata'});const monthStart=d=>`${(d||today()).slice(0,8)}01`;
const say=(t,k='')=>{$('message').textContent=t||'';$('message').className=`message ${k}`.trim()};
async function rpc(n,p={}){const r=await state.client.rpc(n,p);if(r.error)throw r.error;return r.data}
const category=()=>$('payrollCategory').value,method=()=>$('paymentMethod').value,scope=()=>$('paymentScope').value;
const selectedIds=()=>[...state.selected];const manualPayload=()=>state.rows.map(r=>({worker_id:r.worker_id,amount_paid:Number(state.manual.get(String(r.worker_id))||0)}));
const isRound100=v=>Math.abs(Number(v||0)%100)<0.005;
function validateManualRound100(){
  const invalid=state.rows.find(r=>{
    if(!state.selected.has(String(r.worker_id)))return false;
    const value=Number(state.manual.get(String(r.worker_id))||0);
    return value>0&&!isRound100(value);
  });
  if(invalid)throw Error(`${invalid.worker_name||invalid.worker_id} का payment ₹100 के multiple में होना चाहिए.`);
}

function updateVoucherDisplay({force=false}={}){
  const input=$('voucherNo'),cat=category();
  if(!force&&input.dataset.category===cat&&input.dataset.previewReady==='true')return;
  input.dataset.category=cat;
  input.dataset.previewReady='false';
  input.value=cat==='PIECE_RATE'?'CHECKING PCSL':'CHECKING MSL';
}
async function refreshVoucherPreview(){
  const input=$('voucherNo'),cat=category(),token=++state.voucherPreviewToken;
  updateVoucherDisplay({force:true});
  try{
    const result=await rpc('rr_salary_voucher_preview_v786',{p_payroll_category:cat});
    if(token!==state.voucherPreviewToken||cat!==category())return;
    input.dataset.category=cat;
    input.dataset.previewReady='true';
    input.value=result?.voucher_no||'CHECKING';
  }catch(_){
    if(token!==state.voucherPreviewToken||cat!==category())return;
    input.dataset.previewReady='false';
    input.value=cat==='PIECE_RATE'?'PCSL AUTO':'MSL AUTO';
  }
}
function validPeriod(){
  const start=$('periodStart').value;
  const end=$('periodEnd').value;
  return /^\d{4}-\d{2}-\d{2}$/.test(start)
    && /^\d{4}-\d{2}-\d{2}$/.test(end)
    && start<=end;
}
function autoLoadKey(){
  return [
    category(),
    $('dataMode').value,
    scope(),
    $('periodStart').value,
    $('periodEnd').value
  ].join('|');
}
function setAutoLoadState(on){
  state.loading=on;
  const badge=$('autoLoadStatus');
  if(badge){
    badge.classList.toggle('loading',on);
    badge.textContent=on?'LOADING UNPAID…':'AUTO LOAD ACTIVE';
  }
  if($('applyBulkPayment'))$('applyBulkPayment').disabled=on;
  if($('applyRoundReadyAll'))$('applyRoundReadyAll').disabled=on;
  if($('submitBulkPayment')&&on)$('submitBulkPayment').disabled=true;
}
function clearPaymentEntryState(){
  state.preview=null;
  state.rows=[];
  state.selected.clear();
  state.manual.clear();
  state.bulkApplied=false;
  state.activeAmountId=null;
  state.useAll=true;
  $('bulkAmount').value='';
  $('paymentMethod').value='WORKER_LEDGER_WISE';
  updateRule();
  render();
  advance();
}
function scheduleAutoLoad({immediate=false,refreshHistory=false}={}){
  clearTimeout(state.autoLoadTimer);
  updateVoucherDisplay();

  if(!validPeriod()){
    clearPaymentEntryState();
    say('Valid From और To period select करें.','info');
    return;
  }

  const key=autoLoadKey();
  if(key!==state.contextKey){
    state.contextKey=key;
    clearPaymentEntryState();
  }

  state.autoLoadTimer=setTimeout(
    ()=>autoLoadWorkers(key,{refreshHistory}),
    immediate?0:280
  );
}
function setPeriod(){if(category()==='SALARIED'){$('periodStart').value=monthStart($('periodEnd').value||today());$('periodStart').readOnly=true}else $('periodStart').readOnly=false}
function updateRule(){
  const m={
    PARTIAL_RATIO:'Ratio Payment applied है. हर payment ₹100 के multiple में रहेगा.',
    WORKER_LEDGER_WISE:'₹100 Ready Pay use करें या worker की Current Payment row में amount भरें.',
    FULL_PAYMENT:'₹100 Ready Payment applied है. छोटा balance Carry Forward रहेगा.'
  }[method()];
  const s={
    OUTSTANDING_ONLY:'केवल Previous Outstanding pay होगा.',
    CURRENT_PERIOD_ONLY:'केवल Current Period Payable pay होगा.',
    FULL_AND_FINAL:'पहले Previous Outstanding, फिर Current Period pay होगा; यह regular settlement है.'
  }[scope()];
  $('ruleNote').innerHTML=`<b>${m}</b><br>${s}<br>Exact payable सुरक्षित रहेगा; ₹100 से छोटा remainder Carry Forward होगा. Exact Nil केवल worker exit के Full & Final settlement में करें. Voucher submit पर auto बनेगा.`;
  updateBulkApplyUI();
}
function updateBulkApplyUI(){
  const selected=$('bulkApplyMethod')?.value||'RATIO_PAYMENT';
  const complete=selected==='COMPLETE_PAYMENT';
  $('bulkAmount').readOnly=complete;
  if(complete && method()!=='FULL_PAYMENT')$('bulkAmount').value='';
  if($('bulkAmountStatus')){
    $('bulkAmountStatus').textContent=method()==='WORKER_LEDGER_WISE'
      ?'Default manual entry active: worker की Current Payment row में amount भरें.'
      :method()==='PARTIAL_RATIO'
        ?'Ratio Payment applied. SUBMIT PAYMENT दबाएँ.'
        :'Complete Payment applied. SUBMIT PAYMENT दबाएँ.';
  }
}
function filtered(){const q=$('workerSearch').value.trim().toLowerCase();return q?state.rows.filter(r=>[r.worker_name,r.worker_code,r.department_code,r.current_source].join(' ').toLowerCase().includes(q)):state.rows}
function amount(r){return method()==='WORKER_LEDGER_WISE'?Number(state.manual.get(String(r.worker_id))||0):Number(r.amount_paid||0)}
function split(r){const a=state.selected.has(String(r.worker_id))?amount(r):0;if(scope()==='OUTSTANDING_ONLY')return{old:Math.min(a,Number(r.previous_outstanding||0)),cur:0};if(scope()==='CURRENT_PERIOD_ONLY')return{old:0,cur:Math.min(a,Number(r.current_period_payable||0))};const old=Math.min(a,Number(r.previous_outstanding||0));return{old,cur:Math.max(a-old,0)}}
function newBal(r){const x=split(r);return Math.max(Number(r.previous_outstanding||0)-x.old,0)+Math.max(Number(r.current_period_payable||0)-x.cur,0)}
const grossPayable=r=>Number(r.gross_previous_outstanding||0)+Number(r.gross_current_period_payable||0);
const afterAdvanceBalance=r=>Number(r.gross_previous_outstanding||0)-Number(r.advance_opening_balance||0);
function afterAdvanceDisplay(r){
  const value=afterAdvanceBalance(r);
  if(value>0.005)return`<span class="balance-pill due">DUE ₹${money(value)}</span>`;
  if(value<-0.005)return`<span class="balance-pill adv">ADV ₹${money(Math.abs(value))}</span>`;
  return'<span class="balance-pill nil">NIL ₹0.00</span>';
}
const round100Ready=r=>'round_100_ready_payment' in r
  ?Number(r.round_100_ready_payment||0)
  :Math.floor((Number(r.scope_payable||0)+0.000001)/100)*100;
const round100Carry=r=>'round_100_carry_forward' in r
  ?Number(r.round_100_carry_forward||0)
  :Math.max(Math.round((Number(r.scope_payable||0)-round100Ready(r))*100)/100,0);
function cards(){
  const sel=state.rows.filter(r=>state.selected.has(String(r.worker_id)));
  const scopeTotal=sel.reduce((a,r)=>a+Number(r.scope_payable||0),0);
  const readyTotal=sel.reduce((a,r)=>a+round100Ready(r),0);
  const carryTotal=sel.reduce((a,r)=>a+round100Carry(r),0);
  const paid=state.rows.reduce((a,r)=>a+(state.selected.has(String(r.worker_id))?amount(r):0),0);
  const oldPaid=state.rows.reduce((a,r)=>a+split(r).old,0);
  const curPaid=state.rows.reduce((a,r)=>a+split(r).cur,0);
  const newTotal=state.rows.reduce((a,r)=>a+newBal(r),0);
  const entered=Number($('bulkAmount').value||0);
  $('totalFinalPayable').textContent=`₹${money(state.preview?.total_final_payable)}`;
  $('selectedScopePayable').textContent=`₹${money(scopeTotal)}`;
  $('previousOutstanding').textContent=`₹${money(state.preview?.total_previous_outstanding)}`;
  $('currentPayable').textContent=`₹${money(state.preview?.total_current_period_payable)}`;
  $('outstandingPayment').textContent=`₹${money(oldPaid)}`;
  $('currentPayment').textContent=`₹${money(curPaid)}`;
  $('newOutstanding').textContent=`₹${money(newTotal)}`;
  $('advanceWorkers').textContent=`${Number(state.preview?.advance_worker_count||0)} · ₹${money(state.preview?.advance_worker_amount)}`;
  if($('totalAdvanceAdjusted'))$('totalAdvanceAdjusted').textContent=`₹${money(state.preview?.total_advance_recovery)}`;
  if($('roundReadyTotal'))$('roundReadyTotal').textContent=`₹${money(readyTotal)}`;
  if($('roundCarryTotal'))$('roundCarryTotal').textContent=`₹${money(carryTotal)}`;
  if(method()==='FULL_PAYMENT')$('bulkAmount').value=Number(state.preview?.bulk_amount_payment||0).toFixed(2);
  $('workerCount').textContent=`${state.rows.length} eligible · ${state.selected.size} selected`;
  const readyAmount=method()==='PARTIAL_RATIO'?entered>0:method()==='WORKER_LEDGER_WISE'?paid>0:scopeTotal>0;
  $('submitBulkPayment').disabled=!state.preview||!state.selected.size||!readyAmount;
  if(method()==='PARTIAL_RATIO')$('bulkAmountStatus').textContent=!state.preview?'Unpaid workers auto-load हो रहे हैं.':entered>0?`₹${money(entered)} submit करने के लिए button दबाएँ.`:'Bulk Payment Amount लिखें.';
  if($('workerCountTop'))$('workerCountTop').textContent=String(state.rows.length);
}
function advance(){const a=state.preview?.advance_workers||[];$('advanceList').innerHTML=a.length?a.map(r=>`<div class="advance-item"><b>${safe(r.worker_name||r.worker_id)}</b><div>Gross Earned: ₹${money(r.final_total_payable)}</div><div>Remaining Advance: ₹${money(r.total_advance_balance)}</div><div>Regular window के लिए और: ₹${money(r.amount_needed_for_regular)}</div><a class="btn" href="real-advance-worker-payment-v785.html?mode=${encodeURIComponent($('dataMode').value)}&worker=${encodeURIComponent(r.worker_id)}">Open Account</a></div>`).join(''):'<div>No worker is waiting below the advance threshold.</div>'}
function updateLivePaymentTotals(flash=false){
  const t=state.rows.reduce((z,r)=>{
    const x=split(r);
    z.paid+=state.selected.has(String(r.worker_id))?amount(r):0;
    z.op+=x.old;
    z.cp+=x.cur;
    z.nb+=newBal(r);
    return z;
  },{paid:0,op:0,cp:0,nb:0});

  if($('liveTotalAmountPaid'))$('liveTotalAmountPaid').textContent=`₹${money(t.paid)}`;
  if($('liveTotalOutstandingPayment'))$('liveTotalOutstandingPayment').textContent=`₹${money(t.op)}`;
  if($('liveTotalCurrentPayment'))$('liveTotalCurrentPayment').textContent=`₹${money(t.cp)}`;
  if($('liveTotalNewOutstanding'))$('liveTotalNewOutstanding').textContent=`₹${money(t.nb)}`;

  document.querySelectorAll('[data-live-ttl]').forEach(cell=>{
    const active=String(cell.dataset.liveTtl)===String(state.activeAmountId||'');
    cell.classList.toggle('active',active);
    if(active){
      cell.textContent=`TTL ₹${ttlMoney(t.paid)}`;
      if(flash){
        cell.classList.remove('flash');
        void cell.offsetWidth;
        cell.classList.add('flash');
      }
    }else{
      cell.classList.remove('flash');
    }
  });
}
function render(){
const rows=filtered();
const livePaid=state.rows.reduce((sum,r)=>sum+(state.selected.has(String(r.worker_id))?amount(r):0),0);
$('ledgerBody').innerHTML=rows.length?rows.map(r=>{
  const id=String(r.worker_id),a=amount(r);
  return`<tr>
    <td><b>${safe(r.worker_name||id)}</b><br><small>${safe(r.worker_code||'—')}</small></td>
    <td class="money">₹${money(r.gross_previous_outstanding)}</td>
    <td class="money">${afterAdvanceDisplay(r)}</td>
    <td class="money">₹${money(r.gross_current_period_payable)}</td>
    <td class="money"><b>₹${money(r.final_total_payable)}</b></td>
    <td class="money">${method()==='WORKER_LEDGER_WISE'?`<div class="payment-entry-wrap"><input class="amount-input" type="number" min="0" max="${Number(r.scope_payable||0)}" step="100" value="${a.toFixed(2)}" data-amount="${safe(id)}"><span class="live-ttl-cell ${String(state.activeAmountId||'')===id?'active':''}" data-live-ttl="${safe(id)}" aria-live="polite">TTL ₹${ttlMoney(livePaid)}</span></div>`:`₹${money(a)}`}</td>
    <td class="money" data-new-balance>₹${money(newBal(r))}</td>
  </tr>`;
}).join(''):'<tr><td colspan="7">No regular-payable worker. Advance threshold list देखें.</td></tr>';
const t=state.rows.reduce((z,r)=>{
  const balance=afterAdvanceBalance(r);
  z.previous+=Number(r.gross_previous_outstanding||0);
  z.current+=Number(r.gross_current_period_payable||0);
  z.payable+=Number(r.final_total_payable||0);
  z.paid+=state.selected.has(String(r.worker_id))?amount(r):0;
  z.outstanding+=newBal(r);
  if(balance>0)z.due+=balance;else z.advance+=Math.abs(balance);
  return z;
},{previous:0,current:0,payable:0,paid:0,outstanding:0,due:0,advance:0});
$('ledgerFoot').innerHTML=`<tr class="total-row"><td>TOTAL</td><td class="money">₹${money(t.previous)}</td><td class="money"><span class="balance-pill due">DUE ₹${money(t.due)}</span> <span class="balance-pill adv">ADV ₹${money(t.advance)}</span></td><td class="money">₹${money(t.current)}</td><td class="money">₹${money(t.payable)}</td><td id="liveTotalAmountPaid" class="money">₹${money(t.paid)}</td><td id="liveTotalNewOutstanding" class="money">₹${money(t.outstanding)}</td></tr>`;
$('ledgerBody').querySelectorAll('[data-select]').forEach(i=>i.onchange=()=>{i.checked?state.selected.add(i.dataset.select):state.selected.delete(i.dataset.select);if(method()==='WORKER_LEDGER_WISE')render();else{state.dirty=true;cards();say('Selection changed. Recalculate first.','info')}});
$('ledgerBody').querySelectorAll('[data-use-round]').forEach(b=>b.onclick=()=>{
const id=b.dataset.useRound,r=state.rows.find(x=>String(x.worker_id)===id);if(!r)return;$('paymentMethod').value='WORKER_LEDGER_WISE';state.selected.add(id);state.manual.set(id,round100Ready(r));state.bulkApplied=true;state.useAll=false;updateRule();render();say(`${r.worker_name||id}: ₹${money(round100Ready(r))} Ready Pay set · ₹${money(round100Carry(r))} Carry Forward.`,'success')});
const inputs=[...$('ledgerBody').querySelectorAll('[data-amount]')];inputs.forEach((i,k)=>{
i.onfocus=()=>{state.activeAmountId=i.dataset.amount;updateLivePaymentTotals(false)};
i.oninput=()=>{const id=i.dataset.amount,r=state.rows.find(x=>String(x.worker_id)===id),max=Number(r?.scope_payable||0),n=Math.min(Math.max(Number(i.value||0),0),max);
state.activeAmountId=id;state.manual.set(id,n);const tr=i.closest('tr'),balanceCell=tr.querySelector('[data-new-balance]');if(balanceCell)balanceCell.textContent=`₹${money(newBal(r))}`;cards();updateLivePaymentTotals(true)};
i.onblur=()=>{const value=Number(state.manual.get(i.dataset.amount)||0);if(value>0&&!isRound100(value)){state.manual.set(i.dataset.amount,0);state.activeAmountId=null;say('Current Payment ₹100 के multiple में होना चाहिए.','error');render();return}i.value=value.toFixed(2);setTimeout(()=>{if(!document.activeElement?.matches?.('[data-amount]')){state.activeAmountId=null;updateLivePaymentTotals(false)}},0)};
i.onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();const n=inputs[k+1];if(n){n.focus();n.select()}else $('submitBulkPayment').focus()}};
});cards();updateLivePaymentTotals(false)}
async function recalc({applyAmount=false,expectedKey=null}={}){const p=await rpc('rr_salary_payment_preview_v786',{p_payroll_category:category(),p_period_start:$('periodStart').value,p_period_end:$('periodEnd').value,p_data_mode:$('dataMode').value,p_payment_method:method(),p_payment_scope:scope(),p_bulk_amount:method()==='PARTIAL_RATIO'&&applyAmount?Number($('bulkAmount').value||0):0,p_worker_ids:state.useAll?null:selectedIds(),p_worker_amounts:method()==='WORKER_LEDGER_WISE'?manualPayload():[]});if(expectedKey&&expectedKey!==autoLoadKey())return null;state.preview=p;state.rows=p.lines||[];if(state.useAll)state.selected=new Set(state.rows.map(r=>String(r.worker_id)));state.useAll=false;if(method()==='WORKER_LEDGER_WISE')state.rows.forEach(r=>{const id=String(r.worker_id);if(!state.manual.has(id))state.manual.set(id,Number(r.amount_paid||0))});else state.manual.clear();state.bulkApplied=method()==='PARTIAL_RATIO'?applyAmount:true;state.dirty=false;render();advance();return p}
async function autoLoadWorkers(key=autoLoadKey(),{refreshHistory=false}={}){
  if(!validPeriod()||key!==autoLoadKey())return null;

  if(state.loading){
    state.queuedLoadKey=autoLoadKey();
    return null;
  }

  state.loading=true;
  setAutoLoadState(true);

  try{
    $('paymentMethod').value='WORKER_LEDGER_WISE';
    state.useAll=true;
    state.selected.clear();
    state.manual.clear();
    state.bulkApplied=false;
    state.activeAmountId=null;
    $('bulkAmount').value='';
    updateRule();

    say('Unpaid workers automatically load हो रहे हैं…','info');

    if(refreshHistory)await history();

    const p=await recalc({
      applyAmount:false,
      expectedKey:key
    });

    if(!p)return null;

    state.selected=new Set(state.rows.map(r=>String(r.worker_id)));
    state.manual.clear();
    state.rows.forEach(r=>state.manual.set(String(r.worker_id),round100Ready(r)));
    state.useAll=false;
    state.bulkApplied=true;
    state.activeAmountId=null;
    render();

    const readyTotal=state.rows.reduce((sum,r)=>sum+round100Ready(r),0);
    const carryTotal=state.rows.reduce((sum,r)=>sum+round100Carry(r),0);

    say(
      `${p.eligible_worker_count} unpaid workers auto-loaded. `
      +`₹100 Ready Pay ₹${money(readyTotal)} auto-filled · ₹${money(carryTotal)} Carry Forward.`,
      'success'
    );
    return p;
  }catch(e){
    if(key===autoLoadKey()){
      state.preview=null;
      state.rows=[];
      state.selected.clear();
      state.manual.clear();
      state.bulkApplied=false;
      state.activeAmountId=null;
      render();
      advance();
      say(err(e),'error');
    }
    return null;
  }finally{
    state.loading=false;
    setAutoLoadState(false);
    cards();

    const queued=state.queuedLoadKey;
    state.queuedLoadKey=null;

    if(queued&&queued===autoLoadKey()){
      setTimeout(()=>autoLoadWorkers(queued),0);
    }
  }
}
async function applyBulkPayment(){
  try{
    if(!state.preview)throw Error('Unpaid workers अभी auto-load नहीं हुए.');
    if(!state.selected.size)throw Error('कम से कम एक worker select करें.');

    const bulkMode=$('bulkApplyMethod').value;

    if(bulkMode==='RATIO_PAYMENT'){
      const entered=Number($('bulkAmount').value||0);
      if(!(entered>0))throw Error('Bulk Payment Amount required है.');
      if(!isRound100(entered))throw Error('Ratio Payment amount ₹100 के multiple में होना चाहिए.');

      $('paymentMethod').value='PARTIAL_RATIO';
      updateRule();
      say('Ratio Payment apply हो रहा है…','info');
      await recalc({applyAmount:true});
      say(`Ratio Payment ₹${money(entered)} apply हो गया. अब SUBMIT PAYMENT दबाएँ.`,'success');
      return;
    }

    if(bulkMode==='COMPLETE_PAYMENT'){
      $('paymentMethod').value='FULL_PAYMENT';
      updateRule();
      say('Complete Payment apply हो रहा है…','info');
      const preview=await recalc({applyAmount:false});
      $('bulkAmount').value=Number(preview?.bulk_amount_payment||0).toFixed(2);
      say(`Complete Payment ₹${money(preview?.bulk_amount_payment)} apply हो गया. अब SUBMIT PAYMENT दबाएँ.`,'success');
      return;
    }

    throw Error('Bulk Apply Method invalid है.');
  }catch(e){
    say(err(e),'error');
  }
}
function applyRoundReadyAll(){
  try{
    if(!state.preview)throw Error('Unpaid workers अभी auto-load नहीं हुए.');
    if(!state.rows.length)throw Error('₹100 Ready Pay के लिए कोई worker नहीं है.');
    const total=state.rows.reduce((sum,r)=>sum+round100Ready(r),0);
    const carry=state.rows.reduce((sum,r)=>sum+round100Carry(r),0);
    if(!(total>0))throw Error(`अभी ₹100 Ready Pay ₹0.00 है; ₹${money(carry)} पूरा Carry Forward रहेगा.`);
    $('paymentMethod').value='WORKER_LEDGER_WISE';
    state.selected=new Set(state.rows.map(r=>String(r.worker_id)));
    state.manual.clear();
    state.rows.forEach(r=>state.manual.set(String(r.worker_id),round100Ready(r)));
    state.useAll=false;
    state.bulkApplied=true;
    state.activeAmountId=null;
    updateRule();
    render();
    say(`₹100 Ready Pay ₹${money(total)} set हो गया · ₹${money(carry)} Carry Forward रहेगा. अब SUBMIT PAYMENT दबाएँ.`,'success');
  }catch(e){say(err(e),'error')}
}
async function submitBulkPayment(){
  try{
    if(!state.preview)throw Error('Unpaid workers अभी auto-load नहीं हुए.');
    if(!state.selected.size)throw Error('कम से कम एक worker select करें.');

    if(method()==='PARTIAL_RATIO'){
      if(!state.bulkApplied)throw Error('पहले APPLY PAYMENT दबाएँ.');
      const entered=Number($('bulkAmount').value||0);
      if(!(entered>0))throw Error('Bulk Payment Amount required.');
      if(!isRound100(entered))throw Error('Ratio Payment amount ₹100 के multiple में होना चाहिए.');
    }

    if(method()==='WORKER_LEDGER_WISE')validateManualRound100();

    if(method()==='FULL_PAYMENT'&&!state.bulkApplied){
      throw Error('पहले APPLY PAYMENT दबाएँ.');
    }

    const paid=method()==='WORKER_LEDGER_WISE'
      ?state.rows.reduce((sum,r)=>sum+(state.selected.has(String(r.worker_id))?Number(state.manual.get(String(r.worker_id))||0):0),0)
      :method()==='FULL_PAYMENT'
        ?Number(state.preview?.bulk_amount_payment||0)
        :Number($('bulkAmount').value||0);

    if(!(paid>0))throw Error('Current Payment amount 0 से ज्यादा होना चाहिए.');

    $('submitBulkPayment').disabled=true;
    $('submitBulkPayment').textContent='POSTING…';
    say('Payment save/post हो रहा है…','info');

    const r=await rpc('rr_salary_payment_post_v786',{
      p_payroll_category:category(),
      p_period_start:$('periodStart').value,
      p_period_end:$('periodEnd').value,
      p_data_mode:$('dataMode').value,
      p_payment_method:method(),
      p_payment_scope:scope(),
      p_bulk_amount:method()==='PARTIAL_RATIO'?Number($('bulkAmount').value||0):0,
      p_worker_ids:selectedIds(),
      p_worker_amounts:method()==='WORKER_LEDGER_WISE'?manualPayload():[],
      p_payment_date:$('paymentDate').value,
      p_payment_mode:$('paymentMode').value,
      p_voucher_no:null,
      p_remarks:$('remarks').value.trim()||null
    });

    $('submitBulkPayment').textContent='PAYMENT SAVED';
    $('voucherNo').value=r.voucher_no||$('voucherNo').value;
    say(`Payment ${safe(r.voucher_no)} posted ₹${money(r.bulk_amount_payment)} · Advance Adjusted ₹${money(r.total_advance_recovery)} · New Outstanding ₹${money(r.total_new_outstanding)}.`,'success');

    const target=category()==='PIECE_RATE'
      ?'real-pcs-salary-dashboard-v786.html'
      :'real-monthly-salary-dashboard-v786.html';

    setTimeout(()=>{location.href=target},900);
  }catch(e){
    $('submitBulkPayment').disabled=false;
    $('submitBulkPayment').textContent='SUBMIT PAYMENT';
    say(err(e),'error');
  }
}
function renderHistory(){$('historyBody').innerHTML=state.history.length?state.history.map(r=>`<tr><td>${safe(r.payment_date)}</td><td>${safe(r.payroll_category)}</td><td>${safe(r.period_start)} → ${safe(r.period_end)}</td><td>${safe(r.payment_method)}</td><td>${safe(r.payment_scope)}</td><td>${safe(r.voucher_no)}</td><td>${safe(r.selected_worker_count)} / ${safe(r.eligible_worker_count)}</td><td class="money">₹${money(r.total_final_payable)}</td><td class="money">₹${money(r.bulk_amount_payment)}</td><td class="money">₹${money(r.total_new_outstanding)}</td><td>APP ${safe(r.app_notification_count||0)} · Mobile ${safe(r.mobile_message_count||0)}</td><td>${safe(r.status)}</td><td>${r.status==='POSTED'?`<button class="btn danger" data-void="${safe(r.id)}">Void</button>`:'—'}</td></tr>`).join(''):'<tr><td colspan="13">No history.</td></tr>';$('historyBody').querySelectorAll('[data-void]').forEach(b=>b.onclick=()=>voidBatch(b.dataset.void))}
async function history(){try{const r=await state.client.from('rr_salary_payment_history_v785').select('*').eq('data_mode',$('dataMode').value).eq('payroll_category',category()).order('created_at',{ascending:false}).limit(300);if(r.error)throw r.error;state.history=r.data||[];renderHistory()}catch(e){say(err(e),'error')}}
async function voidBatch(id){try{const reason=prompt('Void reason','Wrong payment / date / voucher')||'';if(!reason)return;const r=await rpc('rr_salary_payment_void_v786',{p_batch_id:id,p_reason:reason});say(`Voided · Payment Reversed ₹${money(r.voided_payment)} · Advance Recovery Reversed ₹${money(r.advance_recovery_reversed)}.`,'success');state.useAll=true;await history();scheduleAutoLoad({immediate:true})}catch(e){say(err(e),'error')}}

function bind(){
  $('applyBulkPayment').onclick=applyBulkPayment;
  if($('applyRoundReadyAll'))$('applyRoundReadyAll').onclick=applyRoundReadyAll;
  $('submitBulkPayment').onclick=submitBulkPayment;

  if($('loadHistory'))$('loadHistory').onclick=history;

  if($('selectAll'))$('selectAll').onclick=()=>{
    state.selected=new Set(state.rows.map(r=>String(r.worker_id)));
    state.useAll=false;
    render();
  };

  if($('clearAll'))$('clearAll').onclick=()=>{
    state.selected.clear();
    state.useAll=false;
    render();
  };

  if($('workerSearch'))$('workerSearch').oninput=render;
  if($('advanceCard')&&$('advancePanel')){
    $('advanceCard').onclick=()=>$('advancePanel').classList.toggle('hidden');
  }

  $('payrollCategory').onchange=()=>{
    setPeriod();
    refreshVoucherPreview();
    scheduleAutoLoad({refreshHistory:true});
  };

  $('dataMode').onchange=()=>{
    scheduleAutoLoad({refreshHistory:true});
  };

  $('paymentScope').onchange=()=>{
    scheduleAutoLoad();
  };

  $('periodStart').oninput=()=>{
    scheduleAutoLoad();
  };
  $('periodStart').onchange=()=>{
    scheduleAutoLoad();
  };

  $('periodEnd').oninput=()=>{
    setPeriod();
    scheduleAutoLoad();
  };
  $('periodEnd').onchange=()=>{
    setPeriod();
    scheduleAutoLoad();
  };

  $('bulkApplyMethod').onchange=()=>{
    updateBulkApplyUI();
    if($('bulkApplyMethod').value==='COMPLETE_PAYMENT'){
      $('bulkAmount').value='';
    }
  };

  $('bulkAmount').oninput=()=>{
    let raw=String($('bulkAmount').value||'')
      .replace(/,/g,'')
      .replace(/[^0-9.]/g,'');
    const parts=raw.split('.');
    const clean=parts.length>1
      ?`${parts.shift()}.${parts.join('').slice(0,2)}`
      :parts[0];
    if($('bulkAmount').value!==clean)$('bulkAmount').value=clean;
  };

  $('bulkAmount').onkeydown=e=>{
    if(e.key==='Enter'){
      e.preventDefault();
      $('applyBulkPayment').click();
    }
  };
}
async function boot(){try{state.client=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;if(!state.client)throw Error('Supabase client unavailable.');if(window.RR?.requireRoles)await RR.requireRoles(['owner','admin','account','accounts','payroll','manager','hr']);else{const s=await state.client.auth.getSession();if(!s.data?.session)throw Error('Login required.')}const p=new URLSearchParams(location.search),cat=String(p.get('category')||'').toUpperCase(),mode=String(p.get('mode')||'').toUpperCase();if(['PIECE_RATE','SALARIED'].includes(cat))$('payrollCategory').value=cat;if(window.RRDataModeReadyPromise)await window.RRDataModeReadyPromise;if(window.RRDataMode){await RRDataMode.refresh();await RRDataMode.applyInitialMode('dataMode',mode);}else $('dataMode').value='TEST';$('periodEnd').value=today();$('periodStart').value=category()==='SALARIED'?monthStart():today();$('paymentDate').value=today();$('paymentMethod').value='WORKER_LEDGER_WISE';$('bulkApplyMethod').value='RATIO_PAYMENT';setPeriod();updateVoucherDisplay({force:true});updateRule();bind();render();advance();await refreshVoucherPreview();await history();state.contextKey=autoLoadKey();await autoLoadWorkers(state.contextKey);$('accessBadge').textContent='ACCESS OK'}catch(e){$('accessBadge').textContent='ACCESS ERROR';say(err(e),'error')}}document.readyState==='loading'?document.addEventListener('DOMContentLoaded',boot):boot();})();
