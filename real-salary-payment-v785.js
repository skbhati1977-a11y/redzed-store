(()=>{'use strict';window.REAL_FACTORY_SALARY_PAYMENT_VERSION='786.3.9-STRICT-METHODS-ROUND100';
const $=id=>document.getElementById(id),state={client:null,preview:null,rows:[],selected:new Set(),manual:new Map(),dirty:false,useAll:true,bulkApplied:false,history:[]};
const safe=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));
const money=v=>Number(v||0).toLocaleString('en-IN',{minimumFractionDigits:2,maximumFractionDigits:2});
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
function updateRule(){const m={PARTIAL_RATIO:'Workers load करें, Bulk Payment Amount लिखें और SUBMIT PAYMENT दबाएँ.',WORKER_LEDGER_WISE:'हर worker की Amount Paid row भरें। Blank/0 worker skip होगा। फिर SUBMIT PAYMENT दबाएँ.',FULL_PAYMENT:'Workers load करें। पूरी selected payable amount के लिए SUBMIT PAYMENT दबाएँ.'}[method()];const s={OUTSTANDING_ONLY:'केवल Previous Outstanding pay होगा.',CURRENT_PERIOD_ONLY:'केवल Current Period Payable pay होगा.',FULL_AND_FINAL:'पहले Previous Outstanding, फिर Current Period pay होगा.'}[scope()];$('ruleNote').innerHTML=`<b>${m}</b><br>${s}<br>Payment केवल SUBMIT PAYMENT दबाने के बाद confirmation पर post होगा.`;$('bulkAmount').readOnly=method()!=='PARTIAL_RATIO';$('bulkAmountStatus').classList.toggle('hidden',method()!=='PARTIAL_RATIO')}
function filtered(){const q=$('workerSearch').value.trim().toLowerCase();return q?state.rows.filter(r=>[r.worker_name,r.worker_code,r.department_code,r.current_source].join(' ').toLowerCase().includes(q)):state.rows}
function amount(r){return method()==='WORKER_LEDGER_WISE'?Number(state.manual.get(String(r.worker_id))||0):Number(r.amount_paid||0)}
function split(r){const a=state.selected.has(String(r.worker_id))?amount(r):0;if(scope()==='OUTSTANDING_ONLY')return{old:Math.min(a,Number(r.previous_outstanding||0)),cur:0};if(scope()==='CURRENT_PERIOD_ONLY')return{old:0,cur:Math.min(a,Number(r.current_period_payable||0))};const old=Math.min(a,Number(r.previous_outstanding||0));return{old,cur:Math.max(a-old,0)}}
function newBal(r){const x=split(r);return Math.max(Number(r.previous_outstanding||0)-x.old,0)+Math.max(Number(r.current_period_payable||0)-x.cur,0)}
function cards(){const sel=state.rows.filter(r=>state.selected.has(String(r.worker_id)));const scopeTotal=sel.reduce((a,r)=>a+Number(r.scope_payable||0),0),paid=state.rows.reduce((a,r)=>a+(state.selected.has(String(r.worker_id))?amount(r):0),0),oldPaid=state.rows.reduce((a,r)=>a+split(r).old,0),curPaid=state.rows.reduce((a,r)=>a+split(r).cur,0),newTotal=state.rows.reduce((a,r)=>a+newBal(r),0),entered=Number($('bulkAmount').value||0);$('totalFinalPayable').textContent=`₹${money(state.preview?.total_final_payable)}`;$('selectedScopePayable').textContent=`₹${money(scopeTotal)}`;$('previousOutstanding').textContent=`₹${money(state.preview?.total_previous_outstanding)}`;$('currentPayable').textContent=`₹${money(state.preview?.total_current_period_payable)}`;$('outstandingPayment').textContent=`₹${money(oldPaid)}`;$('currentPayment').textContent=`₹${money(curPaid)}`;$('newOutstanding').textContent=`₹${money(newTotal)}`;$('advanceWorkers').textContent=`${Number(state.preview?.advance_worker_count||0)} · ₹${money(state.preview?.advance_worker_amount)}`;if(method()==='WORKER_LEDGER_WISE')$('bulkAmount').value=paid?paid.toFixed(2):'';if(method()==='FULL_PAYMENT')$('bulkAmount').value=Number(state.preview?.bulk_amount_payment||0).toFixed(2);$('workerCount').textContent=`${state.rows.length} eligible · ${state.selected.size} selected`;const readyAmount=method()==='PARTIAL_RATIO'?entered>0:method()==='WORKER_LEDGER_WISE'?paid>0:scopeTotal>0;$('submitBulkPayment').disabled=!state.preview||!state.selected.size||!readyAmount;if(method()==='PARTIAL_RATIO')$('bulkAmountStatus').textContent=!state.preview?'पहले Load Workers — No Payment दबाएँ.':entered>0?`₹${money(entered)} submit करने के लिए button दबाएँ.`:'Bulk Payment Amount लिखें.';if($('workerCountTop'))$('workerCountTop').textContent=String(state.rows.length)}
function advance(){const a=state.preview?.advance_workers||[];$('advanceList').innerHTML=a.length?a.map(r=>`<div class="advance-item"><b>${safe(r.worker_name||r.worker_id)}</b><div>Current Payable: ₹${money(r.current_period_payable)}</div><div>Advance: ₹${money(r.total_advance_balance)}</div><a class="btn" href="real-advance-worker-payment-v785.html?mode=${encodeURIComponent($('dataMode').value)}&worker=${encodeURIComponent(r.worker_id)}">Open Account</a></div>`).join(''):'<div>No advance worker with positive current salary.</div>'}
function render(){const rows=filtered();$('ledgerBody').innerHTML=rows.length?rows.map(r=>{const id=String(r.worker_id),checked=state.selected.has(id),a=amount(r),x=split(r);return`<tr><td><input class="worker-check" type="checkbox" data-select="${safe(id)}" ${checked?'checked':''}></td><td><b>${safe(r.worker_name||id)}</b><br><small>${safe(r.worker_code||'—')}</small></td><td>${safe(r.department_code||'—')}</td><td class="money">₹${money(r.previous_outstanding)}</td><td class="money">₹${money(r.current_period_payable)}</td><td class="money"><b>₹${money(r.final_total_payable)}</b></td><td class="money">₹${money(r.scope_payable)}</td><td class="money">${method()==='WORKER_LEDGER_WISE'?`<input class="amount-input" type="number" min="0" max="${Number(r.scope_payable||0)}" step="100" value="${a.toFixed(2)}" data-amount="${safe(id)}">`:`₹${money(a)}`}</td><td class="money">₹${money(x.old)}</td><td class="money">₹${money(x.cur)}</td><td class="money">₹${money(newBal(r))}</td><td>${safe(r.current_source||'—')}</td></tr>`}).join(''):'<tr><td colspan="12">No eligible worker.</td></tr>';
const t=state.rows.reduce((z,r)=>{const x=split(r);z.old+=Number(r.previous_outstanding||0);z.cur+=Number(r.current_period_payable||0);z.final+=Number(r.final_total_payable||0);z.scope+=Number(r.scope_payable||0);z.paid+=state.selected.has(String(r.worker_id))?amount(r):0;z.op+=x.old;z.cp+=x.cur;z.nb+=newBal(r);return z},{old:0,cur:0,final:0,scope:0,paid:0,op:0,cp:0,nb:0});$('ledgerFoot').innerHTML=`<tr class="total-row"><td colspan="3">TOTAL</td><td class="money">₹${money(t.old)}</td><td class="money">₹${money(t.cur)}</td><td class="money">₹${money(t.final)}</td><td class="money">₹${money(t.scope)}</td><td class="money">₹${money(t.paid)}</td><td class="money">₹${money(t.op)}</td><td class="money">₹${money(t.cp)}</td><td class="money">₹${money(t.nb)}</td><td></td></tr>`;
$('ledgerBody').querySelectorAll('[data-select]').forEach(i=>i.onchange=()=>{i.checked?state.selected.add(i.dataset.select):state.selected.delete(i.dataset.select);if(method()==='WORKER_LEDGER_WISE')render();else{state.dirty=true;cards();say('Selection changed. Recalculate first.','info')}});
const inputs=[...$('ledgerBody').querySelectorAll('[data-amount]')];inputs.forEach((i,k)=>{i.oninput=()=>{const id=i.dataset.amount,r=state.rows.find(x=>String(x.worker_id)===id),max=Number(r?.scope_payable||0),n=Math.min(Math.max(Number(i.value||0),0),max);
if(n>0&&!isRound100(n)){state.manual.set(id,0);say('Manual payment ₹100 के multiple में भरें.','error')}else{state.manual.set(id,n)};const tr=i.closest('tr'),x=split(r);tr.children[8].textContent=`₹${money(x.old)}`;tr.children[9].textContent=`₹${money(x.cur)}`;tr.children[10].textContent=`₹${money(newBal(r))}`;cards()};i.onblur=()=>i.value=Number(state.manual.get(i.dataset.amount)||0).toFixed(2);i.onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();const n=inputs[k+1];if(n){n.focus();n.select()}else $('submitBulkPayment').focus()}}});cards()}
async function recalc({applyAmount=false}={}){const p=await rpc('rr_salary_payment_preview_v785',{p_payroll_category:category(),p_period_start:$('periodStart').value,p_period_end:$('periodEnd').value,p_data_mode:$('dataMode').value,p_payment_method:method(),p_payment_scope:scope(),p_bulk_amount:method()==='PARTIAL_RATIO'&&applyAmount?Number($('bulkAmount').value||0):0,p_worker_ids:state.useAll?null:selectedIds(),p_worker_amounts:method()==='WORKER_LEDGER_WISE'?manualPayload():[]});state.preview=p;state.rows=p.lines||[];if(state.useAll)state.selected=new Set(state.rows.map(r=>String(r.worker_id)));state.useAll=false;if(method()==='WORKER_LEDGER_WISE')state.rows.forEach(r=>{const id=String(r.worker_id);if(!state.manual.has(id))state.manual.set(id,Number(r.amount_paid||0))});else state.manual.clear();state.bulkApplied=method()==='PARTIAL_RATIO'?applyAmount:true;state.dirty=false;render();advance();return p}
async function load(){try{say('Loading workers only — no payment is being applied or posted…','info');state.bulkApplied=false;const p=await recalc({applyAmount:false});if(method()==='PARTIAL_RATIO'){$('bulkAmount').value='';state.dirty=false;cards()}say(`${p.eligible_worker_count} workers loaded. Amount भरकर SUBMIT PAYMENT दबाएँ.`,'success')}catch(e){state.preview=null;state.rows=[];state.selected.clear();state.manual.clear();state.bulkApplied=false;render();advance();say(err(e),'error')}}

async function submitBulkPayment(){try{if(!state.preview)throw Error('पहले Load Workers — No Payment दबाएँ.');if(!state.selected.size)throw Error('कम से कम एक worker select करें.');if(!$('voucherNo').value.trim())throw Error('Voucher / Reference required.');if(method()==='PARTIAL_RATIO'){
  const entered=Number($('bulkAmount').value||0);
  if(!(entered>0))throw Error('Bulk Payment Amount 0 से ज्यादा होना चाहिए.');
  if(!isRound100(entered))throw Error('Ratio Division Payment amount ₹100 के multiple में होना चाहिए.');
  say('₹100 round ratio payment calculate हो रहा है…','info');
  await recalc({applyAmount:true});
}
if(method()==='WORKER_LEDGER_WISE')validateManualRound100();
if(method()==='FULL_PAYMENT')await recalc({applyAmount:false});const paid=method()==='WORKER_LEDGER_WISE'
  ?state.rows.reduce((sum,r)=>sum+(state.selected.has(String(r.worker_id))?Number(state.manual.get(String(r.worker_id))||0):0),0)
  :method()==='FULL_PAYMENT'
    ?Number(state.preview?.bulk_amount_payment||0)
    :Number($('bulkAmount').value||0);if(!(paid>0))throw Error('Payment amount 0 से ज्यादा होना चाहिए.');const ok=confirm(`${category()}
Scope: ${scope().replaceAll('_',' ')}
Period: ${$('periodStart').value} to ${$('periodEnd').value}
Selected Workers: ${state.selected.size}
Payment Amount: ₹${money(paid)}
Voucher: ${$('voucherNo').value.trim()}

SUBMIT और POST PAYMENT करें?`);if(!ok)return;say('Payment post हो रहा है…','info');const r=await rpc('rr_salary_payment_post_v785',{p_payroll_category:category(),p_period_start:$('periodStart').value,p_period_end:$('periodEnd').value,p_data_mode:$('dataMode').value,p_payment_method:method(),p_payment_scope:scope(),p_bulk_amount:method()==='PARTIAL_RATIO'?Number($('bulkAmount').value||0):0,p_worker_ids:selectedIds(),p_worker_amounts:method()==='WORKER_LEDGER_WISE'?manualPayload():[],p_payment_date:$('paymentDate').value,p_payment_mode:$('paymentMode').value,p_voucher_no:$('voucherNo').value.trim(),p_remarks:$('remarks').value.trim()||null});say(`Payment posted ₹${money(r.bulk_amount_payment)} · New Outstanding ₹${money(r.total_new_outstanding)} · Messages queued.`,'success');state.useAll=true;state.selected.clear();state.manual.clear();state.bulkApplied=false;await history();await load()}catch(e){say(err(e),'error')}}
function renderHistory(){$('historyBody').innerHTML=state.history.length?state.history.map(r=>`<tr><td>${safe(r.payment_date)}</td><td>${safe(r.payroll_category)}</td><td>${safe(r.period_start)} → ${safe(r.period_end)}</td><td>${safe(r.payment_method)}</td><td>${safe(r.payment_scope)}</td><td>${safe(r.voucher_no)}</td><td>${safe(r.selected_worker_count)} / ${safe(r.eligible_worker_count)}</td><td class="money">₹${money(r.total_final_payable)}</td><td class="money">₹${money(r.bulk_amount_payment)}</td><td class="money">₹${money(r.total_new_outstanding)}</td><td>APP ${safe(r.app_notification_count||0)} · Mobile ${safe(r.mobile_message_count||0)}</td><td>${safe(r.status)}</td><td>${r.status==='POSTED'?`<button class="btn danger" data-void="${safe(r.id)}">Void</button>`:'—'}</td></tr>`).join(''):'<tr><td colspan="13">No history.</td></tr>';$('historyBody').querySelectorAll('[data-void]').forEach(b=>b.onclick=()=>voidBatch(b.dataset.void))}
async function history(){try{const r=await state.client.from('rr_salary_payment_history_v785').select('*').eq('data_mode',$('dataMode').value).eq('payroll_category',category()).order('created_at',{ascending:false}).limit(300);if(r.error)throw r.error;state.history=r.data||[];renderHistory()}catch(e){say(err(e),'error')}}
async function voidBatch(id){try{const reason=prompt('Void reason','Wrong payment / date / voucher')||'';if(!reason)return;const r=await rpc('rr_salary_payment_void_v785',{p_batch_id:id,p_reason:reason});say(`Voided · Reversed ₹${money(r.voided_payment)}.`,'success');state.useAll=true;await history();await load()}catch(e){say(err(e),'error')}}

async function smartChoiceAndSubmit(){
  try{
    if(!state.preview)throw Error('पहले LOAD UNPAID WORKS दबाएँ.');
    if(!$('voucherNo').value.trim())throw Error('Voucher / Reference required.');

    const currentPayable=Number(state.preview?.total_final_payable||0);
    const entered=Number($('bulkAmount').value||0);

    if(!(currentPayable>0))throw Error('Current Payable 0 है.');

    $('paymentChoiceSummary').textContent=
      `Current Payable ₹${money(currentPayable)} · Entered Payment ₹${money(entered)}`;

    // All three choices are always correctly clickable.
    $('choiceSelected').disabled=false;
    $('choiceRatio').disabled=false;
    $('choiceComplete').disabled=false;
    $('choiceSelected').style.opacity='1';
    $('choiceRatio').style.opacity='1';
    $('choiceComplete').style.opacity='1';

    $('paymentChoiceDialog').showModal();
  }catch(e){
    say(err(e),'error');
  }
}
async function postBySmartChoice(choice){
  try{
    if(choice==='selected'){
      $('paymentMethod').value='WORKER_LEDGER_WISE';
      updateRule();
      $('paymentChoiceDialog').close();

      const manualTotal=[...state.manual.values()]
        .reduce((sum,value)=>sum+Number(value||0),0);

      if(manualTotal<=0){
        state.rows.forEach(r=>{
          const id=String(r.worker_id);
          if(!state.manual.has(id))state.manual.set(id,0);
        });
        render();
        say('Selected Workers की Amount Paid row में ₹100 के multiple में amount भरें, फिर SUBMIT PAYMENT दबाकर यही पहला option चुनें.','info');
        return;
      }

      validateManualRound100();
      await submitBulkPayment();
      return;
    }

    if(choice==='ratio'){
      const entered=Number($('bulkAmount').value||0);
      if(!(entered>0))throw Error('Ratio Division के लिए Bulk Payment Amount required है.');
      if(!isRound100(entered))throw Error('Ratio Division Payment amount ₹100 के multiple में होना चाहिए.');

      $('paymentMethod').value='PARTIAL_RATIO';
      updateRule();
      if(!state.selected.size)state.selected=new Set(state.rows.map(r=>String(r.worker_id)));
      $('paymentChoiceDialog').close();
      await submitBulkPayment();
      return;
    }

    if(choice==='complete'){
      $('paymentMethod').value='FULL_PAYMENT';
      updateRule();
      state.selected=new Set(state.rows.map(r=>String(r.worker_id)));
      $('paymentChoiceDialog').close();
      await submitBulkPayment();
      return;
    }

    throw Error('Invalid Payment Method selection.');
  }catch(e){
    if($('paymentChoiceDialog').open)$('paymentChoiceDialog').close();
    say(err(e),'error');
  }
}
function bind(){$('loadPreview').onclick=load;$('submitBulkPayment').onclick=smartChoiceAndSubmit;if($('loadHistory'))$('loadHistory').onclick=history;if($('selectAll'))$('selectAll').onclick=()=>{state.selected=new Set(state.rows.map(r=>String(r.worker_id)));state.useAll=false;if(method()==='WORKER_LEDGER_WISE')render();else cards()};if($('clearAll'))$('clearAll').onclick=()=>{state.selected.clear();state.useAll=false;if(method()==='WORKER_LEDGER_WISE')render();else cards()};if($('workerSearch'))$('workerSearch').oninput=render;if($('advanceCard')&&$('advancePanel'))$('advanceCard').onclick=()=>$('advancePanel').classList.toggle('hidden');$('payrollCategory').onchange=async()=>{setPeriod();updateRule();state.useAll=true;state.selected.clear();state.manual.clear();state.bulkApplied=false;$('bulkAmount').value='';await history();await load()};$('dataMode').onchange=async()=>{state.useAll=true;state.selected.clear();state.manual.clear();state.bulkApplied=false;await history();await load()};$('paymentMethod').onchange=async()=>{updateRule();state.useAll=true;state.selected.clear();state.manual.clear();state.bulkApplied=false;$('bulkAmount').value='';await load()};$('paymentScope').onchange=async()=>{state.useAll=true;state.selected.clear();state.manual.clear();state.bulkApplied=false;await load()};$('periodStart').onchange=()=>{state.preview=null;state.rows=[];render();say('Period changed. Load Workers again.','info')};$('periodEnd').onchange=()=>{setPeriod();state.preview=null;state.rows=[];render();say('Period changed. Load Workers again.','info')};$('bulkAmount').oninput=()=>{if(method()==='PARTIAL_RATIO'||method()==='WORKER_LEDGER_WISE'){let raw=String($('bulkAmount').value||'').replace(/,/g,'').replace(/[^0-9.]/g,''),parts=raw.split('.'),clean=parts.length>1?`${parts.shift()}.${parts.join('').slice(0,2)}`:parts[0];if($('bulkAmount').value!==clean)$('bulkAmount').value=clean;cards()}};$('bulkAmount').onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();$('submitBulkPayment').click()}};$('choiceSelected').onclick=e=>{e.preventDefault();postBySmartChoice('selected')};$('choiceRatio').onclick=e=>{e.preventDefault();postBySmartChoice('ratio')};$('choiceComplete').onclick=e=>{e.preventDefault();postBySmartChoice('complete')};}
async function boot(){try{state.client=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;if(!state.client)throw Error('Supabase client unavailable.');if(window.RR?.requireRoles)await RR.requireRoles(['owner','admin','account','accounts','payroll','manager','hr']);else{const s=await state.client.auth.getSession();if(!s.data?.session)throw Error('Login required.')}const p=new URLSearchParams(location.search),cat=String(p.get('category')||'').toUpperCase(),mode=String(p.get('mode')||'').toUpperCase();if(['PIECE_RATE','SALARIED'].includes(cat))$('payrollCategory').value=cat;if(window.RRDataModeReadyPromise)await window.RRDataModeReadyPromise;if(window.RRDataMode){await RRDataMode.refresh();await RRDataMode.applyInitialMode('dataMode',mode);}else $('dataMode').value='TEST';$('periodEnd').value=today();$('periodStart').value=category()==='SALARIED'?monthStart():today();$('paymentDate').value=today();setPeriod();updateRule();bind();render();advance();await history();await load();$('accessBadge').textContent='ACCESS OK'}catch(e){$('accessBadge').textContent='ACCESS ERROR';say(err(e),'error')}}document.readyState==='loading'?document.addEventListener('DOMContentLoaded',boot):boot();})();