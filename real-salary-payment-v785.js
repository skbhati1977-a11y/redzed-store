(()=>{'use strict';window.REAL_FACTORY_SALARY_PAYMENT_VERSION='786.3.12-INLINE-TTL-MOBILE';
const $=id=>document.getElementById(id),state={client:null,preview:null,rows:[],selected:new Set(),manual:new Map(),dirty:false,useAll:true,bulkApplied:false,history:[],activeAmountId:null};
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

function setPeriod(){if(category()==='SALARIED'){$('periodStart').value=monthStart($('periodEnd').value||today());$('periodStart').readOnly=true}else $('periodStart').readOnly=false}
function updateRule(){
  const m={
    PARTIAL_RATIO:'Ratio Payment applied है. Current Payment rows ₹100 round में हैं.',
    WORKER_LEDGER_WISE:'Default manual entry: worker की Current Payment row में amount भरें.',
    FULL_PAYMENT:'Complete Payment applied है. ₹100 से कम balance outstanding रहेगा.'
  }[method()];
  const s={
    OUTSTANDING_ONLY:'केवल Previous Outstanding pay होगा.',
    CURRENT_PERIOD_ONLY:'केवल Current Period Payable pay होगा.',
    FULL_AND_FINAL:'पहले Previous Outstanding, फिर Current Period pay होगा.'
  }[scope()];
  $('ruleNote').innerHTML=`<b>${m}</b><br>${s}<br>SUBMIT PAYMENT दबाते ही payment save/post होकर dashboard पर वापस जाएगा.`;
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
function cards(){const sel=state.rows.filter(r=>state.selected.has(String(r.worker_id)));const scopeTotal=sel.reduce((a,r)=>a+Number(r.scope_payable||0),0),paid=state.rows.reduce((a,r)=>a+(state.selected.has(String(r.worker_id))?amount(r):0),0),oldPaid=state.rows.reduce((a,r)=>a+split(r).old,0),curPaid=state.rows.reduce((a,r)=>a+split(r).cur,0),newTotal=state.rows.reduce((a,r)=>a+newBal(r),0),entered=Number($('bulkAmount').value||0);$('totalFinalPayable').textContent=`₹${money(state.preview?.total_final_payable)}`;$('selectedScopePayable').textContent=`₹${money(scopeTotal)}`;$('previousOutstanding').textContent=`₹${money(state.preview?.total_previous_outstanding)}`;$('currentPayable').textContent=`₹${money(state.preview?.total_current_period_payable)}`;$('outstandingPayment').textContent=`₹${money(oldPaid)}`;$('currentPayment').textContent=`₹${money(curPaid)}`;$('newOutstanding').textContent=`₹${money(newTotal)}`;$('advanceWorkers').textContent=`${Number(state.preview?.advance_worker_count||0)} · ₹${money(state.preview?.advance_worker_amount)}`;if(method()==='FULL_PAYMENT')$('bulkAmount').value=Number(state.preview?.bulk_amount_payment||0).toFixed(2);$('workerCount').textContent=`${state.rows.length} eligible · ${state.selected.size} selected`;const readyAmount=method()==='PARTIAL_RATIO'?entered>0:method()==='WORKER_LEDGER_WISE'?paid>0:scopeTotal>0;$('submitBulkPayment').disabled=!state.preview||!state.selected.size||!readyAmount;if(method()==='PARTIAL_RATIO')$('bulkAmountStatus').textContent=!state.preview?'पहले Load Workers — No Payment दबाएँ.':entered>0?`₹${money(entered)} submit करने के लिए button दबाएँ.`:'Bulk Payment Amount लिखें.';if($('workerCountTop'))$('workerCountTop').textContent=String(state.rows.length)}
function advance(){const a=state.preview?.advance_workers||[];$('advanceList').innerHTML=a.length?a.map(r=>`<div class="advance-item"><b>${safe(r.worker_name||r.worker_id)}</b><div>Current Payable: ₹${money(r.current_period_payable)}</div><div>Advance: ₹${money(r.total_advance_balance)}</div><a class="btn" href="real-advance-worker-payment-v785.html?mode=${encodeURIComponent($('dataMode').value)}&worker=${encodeURIComponent(r.worker_id)}">Open Account</a></div>`).join(''):'<div>No advance worker with positive current salary.</div>'}
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
const livePaid=state.rows.reduce((sum,r)=>sum+(state.selected.has(String(r.worker_id))?amount(r):0),0);$('ledgerBody').innerHTML=rows.length?rows.map(r=>{const id=String(r.worker_id),checked=state.selected.has(id),a=amount(r),x=split(r);return`<tr><td><input class="worker-check" type="checkbox" data-select="${safe(id)}" ${checked?'checked':''}></td><td><b>${safe(r.worker_name||id)}</b><br><small>${safe(r.worker_code||'—')}</small></td><td>${safe(r.department_code||'—')}</td><td class="money">₹${money(r.previous_outstanding)}</td><td class="money">₹${money(r.current_period_payable)}</td><td class="money"><b>₹${money(r.final_total_payable)}</b></td><td class="money">₹${money(r.scope_payable)}</td><td class="money">${method()==='WORKER_LEDGER_WISE'?`<div class="payment-entry-wrap"><input class="amount-input" type="number" min="0" max="${Number(r.scope_payable||0)}" step="100" value="${a.toFixed(2)}" data-amount="${safe(id)}"><span class="live-ttl-cell ${String(state.activeAmountId||'')===id?'active':''}" data-live-ttl="${safe(id)}" aria-live="polite">TTL ₹${ttlMoney(livePaid)}</span></div>`:`₹${money(a)}`}</td><td class="money">₹${money(x.old)}</td><td class="money">₹${money(x.cur)}</td><td class="money">₹${money(newBal(r))}</td><td>${safe(r.current_source||'—')}</td></tr>`}).join(''):'<tr><td colspan="12">No eligible worker.</td></tr>';
const t=state.rows.reduce((z,r)=>{const x=split(r);z.old+=Number(r.previous_outstanding||0);z.cur+=Number(r.current_period_payable||0);z.final+=Number(r.final_total_payable||0);z.scope+=Number(r.scope_payable||0);z.paid+=state.selected.has(String(r.worker_id))?amount(r):0;z.op+=x.old;z.cp+=x.cur;z.nb+=newBal(r);return z},{old:0,cur:0,final:0,scope:0,paid:0,op:0,cp:0,nb:0});$('ledgerFoot').innerHTML=`<tr class="total-row"><td colspan="3">TOTAL</td><td class="money">₹${money(t.old)}</td><td class="money">₹${money(t.cur)}</td><td class="money">₹${money(t.final)}</td><td class="money">₹${money(t.scope)}</td><td id="liveTotalAmountPaid" class="money">₹${money(t.paid)}</td><td id="liveTotalOutstandingPayment" class="money">₹${money(t.op)}</td><td id="liveTotalCurrentPayment" class="money">₹${money(t.cp)}</td><td id="liveTotalNewOutstanding" class="money">₹${money(t.nb)}</td><td></td></tr>`;
$('ledgerBody').querySelectorAll('[data-select]').forEach(i=>i.onchange=()=>{i.checked?state.selected.add(i.dataset.select):state.selected.delete(i.dataset.select);if(method()==='WORKER_LEDGER_WISE')render();else{state.dirty=true;cards();say('Selection changed. Recalculate first.','info')}});
const inputs=[...$('ledgerBody').querySelectorAll('[data-amount]')];inputs.forEach((i,k)=>{
i.onfocus=()=>{state.activeAmountId=i.dataset.amount;updateLivePaymentTotals(false)};
i.oninput=()=>{const id=i.dataset.amount,r=state.rows.find(x=>String(x.worker_id)===id),max=Number(r?.scope_payable||0),n=Math.min(Math.max(Number(i.value||0),0),max);
state.activeAmountId=id;state.manual.set(id,n);const tr=i.closest('tr'),x=split(r);tr.children[8].textContent=`₹${money(x.old)}`;tr.children[9].textContent=`₹${money(x.cur)}`;tr.children[10].textContent=`₹${money(newBal(r))}`;cards();updateLivePaymentTotals(true)};
i.onblur=()=>{const value=Number(state.manual.get(i.dataset.amount)||0);if(value>0&&!isRound100(value)){state.manual.set(i.dataset.amount,0);state.activeAmountId=null;say('Current Payment ₹100 के multiple में होना चाहिए.','error');render();return}i.value=value.toFixed(2);setTimeout(()=>{if(!document.activeElement?.matches?.('[data-amount]')){state.activeAmountId=null;updateLivePaymentTotals(false)}},0)};
i.onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();const n=inputs[k+1];if(n){n.focus();n.select()}else $('submitBulkPayment').focus()}};
});cards();updateLivePaymentTotals(false)}
async function recalc({applyAmount=false}={}){const p=await rpc('rr_salary_payment_preview_v785',{p_payroll_category:category(),p_period_start:$('periodStart').value,p_period_end:$('periodEnd').value,p_data_mode:$('dataMode').value,p_payment_method:method(),p_payment_scope:scope(),p_bulk_amount:method()==='PARTIAL_RATIO'&&applyAmount?Number($('bulkAmount').value||0):0,p_worker_ids:state.useAll?null:selectedIds(),p_worker_amounts:method()==='WORKER_LEDGER_WISE'?manualPayload():[]});state.preview=p;state.rows=p.lines||[];if(state.useAll)state.selected=new Set(state.rows.map(r=>String(r.worker_id)));state.useAll=false;if(method()==='WORKER_LEDGER_WISE')state.rows.forEach(r=>{const id=String(r.worker_id);if(!state.manual.has(id))state.manual.set(id,Number(r.amount_paid||0))});else state.manual.clear();state.bulkApplied=method()==='PARTIAL_RATIO'?applyAmount:true;state.dirty=false;render();advance();return p}
async function load(){
  try{
    $('paymentMethod').value='WORKER_LEDGER_WISE';
    state.useAll=true;
    state.selected.clear();
    state.manual.clear();
    state.bulkApplied=false;
    $('bulkAmount').value='';
    updateRule();

    say('Unpaid workers load हो रहे हैं. सभी workers default selected रहेंगे…','info');
    const p=await recalc({applyAmount:false});
    say(`${p.eligible_worker_count} workers loaded. Direct Current Payment भरें या Bulk Apply करें.`,'success');
  }catch(e){
    state.preview=null;
    state.rows=[];
    state.selected.clear();
    state.manual.clear();
    state.bulkApplied=false;
    render();
    advance();
    say(err(e),'error');
  }
}
async function applyBulkPayment(){
  try{
    if(!state.preview)throw Error('पहले LOAD UNPAID WORKS दबाएँ.');
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
async function submitBulkPayment(){
  try{
    if(!state.preview)throw Error('पहले LOAD UNPAID WORKS दबाएँ.');
    if(!state.selected.size)throw Error('कम से कम एक worker select करें.');
    if(!$('voucherNo').value.trim())throw Error('Voucher / Reference required.');

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

    const r=await rpc('rr_salary_payment_post_v785',{
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
      p_voucher_no:$('voucherNo').value.trim(),
      p_remarks:$('remarks').value.trim()||null
    });

    $('submitBulkPayment').textContent='PAYMENT SAVED';
    say(`Payment posted ₹${money(r.bulk_amount_payment)} · New Outstanding ₹${money(r.total_new_outstanding)}.`,'success');

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
async function voidBatch(id){try{const reason=prompt('Void reason','Wrong payment / date / voucher')||'';if(!reason)return;const r=await rpc('rr_salary_payment_void_v785',{p_batch_id:id,p_reason:reason});say(`Voided · Reversed ₹${money(r.voided_payment)}.`,'success');state.useAll=true;await history();await load()}catch(e){say(err(e),'error')}}

function bind(){
  $('loadPreview').onclick=load;
  $('applyBulkPayment').onclick=applyBulkPayment;
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
  if($('advanceCard')&&$('advancePanel'))$('advanceCard').onclick=()=>$('advancePanel').classList.toggle('hidden');

  $('payrollCategory').onchange=async()=>{
    setPeriod();
    state.useAll=true;
    await history();
    await load();
  };

  $('dataMode').onchange=async()=>{
    state.useAll=true;
    await history();
    await load();
  };

  $('paymentScope').onchange=async()=>{
    state.useAll=true;
    await load();
  };

  $('periodStart').onchange=()=>{
    state.preview=null;
    state.rows=[];
    render();
    say('Period changed. LOAD UNPAID WORKS again.','info');
  };

  $('periodEnd').onchange=()=>{
    setPeriod();
    state.preview=null;
    state.rows=[];
    render();
    say('Period changed. LOAD UNPAID WORKS again.','info');
  };

  $('bulkApplyMethod').onchange=()=>{
    updateBulkApplyUI();
    if($('bulkApplyMethod').value==='COMPLETE_PAYMENT')$('bulkAmount').value='';
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
async function boot(){try{state.client=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;if(!state.client)throw Error('Supabase client unavailable.');if(window.RR?.requireRoles)await RR.requireRoles(['owner','admin','account','accounts','payroll','manager','hr']);else{const s=await state.client.auth.getSession();if(!s.data?.session)throw Error('Login required.')}const p=new URLSearchParams(location.search),cat=String(p.get('category')||'').toUpperCase(),mode=String(p.get('mode')||'').toUpperCase();if(['PIECE_RATE','SALARIED'].includes(cat))$('payrollCategory').value=cat;if(window.RRDataModeReadyPromise)await window.RRDataModeReadyPromise;if(window.RRDataMode){await RRDataMode.refresh();await RRDataMode.applyInitialMode('dataMode',mode);}else $('dataMode').value='TEST';$('periodEnd').value=today();$('periodStart').value=category()==='SALARIED'?monthStart():today();$('paymentDate').value=today();$('paymentMethod').value='WORKER_LEDGER_WISE';$('bulkApplyMethod').value='RATIO_PAYMENT';setPeriod();updateRule();bind();render();advance();await history();await load();$('accessBadge').textContent='ACCESS OK'}catch(e){$('accessBadge').textContent='ACCESS ERROR';say(err(e),'error')}}document.readyState==='loading'?document.addEventListener('DOMContentLoaded',boot):boot();})();