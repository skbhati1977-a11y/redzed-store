(()=>{'use strict';
const CATEGORY='PIECE_RATE',RETURN_URL='real-pcs-salary-dashboard-v786.html',LOAD_MESSAGE='Current period submitted work और last outstanding load हो रहा है…';

const $=id=>document.getElementById(id);
const state={client:null,preview:null,rows:[],selected:new Set(),manual:new Map(),timer:null};
const safe=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));
const money=v=>Number(v||0).toLocaleString('en-IN',{minimumFractionDigits:2,maximumFractionDigits:2});
const err=e=>[e?.message,e?.details,e?.hint,e?.code].filter(Boolean).join(' — ')||'Unknown error';
const today=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Kolkata',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
function autoVoucher(){
  const now=new Date();
  const stamp=new Intl.DateTimeFormat('en-GB',{
    timeZone:'Asia/Kolkata',
    year:'numeric',month:'2-digit',day:'2-digit',
    hour:'2-digit',minute:'2-digit',second:'2-digit',
    hour12:false
  }).formatToParts(now).reduce((o,p)=>(o[p.type]=p.value,o),{});
  const prefix=CATEGORY==='PIECE_RATE'?'PCS':'MTH';
  const random=Math.random().toString(36).slice(2,6).toUpperCase();
  return `${prefix}-${stamp.year}${stamp.month}${stamp.day}-${stamp.hour}${stamp.minute}${stamp.second}-${random}`;
}
function say(t,k=''){
  const text=t||'';
  const className=`message ${k}`.trim();
  if($('message')){$('message').textContent=text;$('message').className=className}
  if($('submitStatus')){$('submitStatus').textContent=text;$('submitStatus').className=className}
}
async function rpc(n,p={}){const r=await state.client.rpc(n,p);if(r.error)throw r.error;return r.data}
function choice(){return $('paymentChoice').value}
function method(){return $('paymentMethod').value}
function applyChoice(){
  if(choice()==='SELECTED_PARTIAL'){$('paymentMethod').value='WORKER_LEDGER_WISE';$('bulkAmount').readOnly=true}
  else if(choice()==='RATIO_PAYMENT'){$('paymentMethod').value='WORKER_LEDGER_WISE';$('bulkAmount').readOnly=false}
  else{$('paymentMethod').value='FULL_PAYMENT';$('bulkAmount').readOnly=true}
}
function selectedIds(){return [...state.selected]}
function manualPayload(){return state.rows.map(r=>({worker_id:r.worker_id,amount_paid:Number(state.manual.get(String(r.worker_id))||0)}))}
function isManualPayment(){return choice()==='SELECTED_PARTIAL'||choice()==='RATIO_PAYMENT'}
function allocateRatioRound100(){
  const bulk=Number($('bulkAmount').value||0);
  if(!(bulk>0))throw Error('Bulk Payment Amount required.');
  if(bulk%100!==0)throw Error('Ratio Division Payment amount ₹100 के multiple में होना चाहिए.');

  const rows=state.rows.filter(r=>state.selected.has(String(r.worker_id)));
  if(!rows.length)throw Error('कम से कम एक worker select करें.');

  const targetUnits=Math.round(bulk/100);
  const capacities=rows.map(r=>Math.floor((Number(r.final_total_payable||0)+1e-9)/100));
  const totalCapacity=capacities.reduce((a,b)=>a+b,0);

  if(targetUnits>totalCapacity){
    throw Error(`₹100 round rule में maximum payable ₹${money(totalCapacity*100)} है.`);
  }

  const weights=rows.map(r=>Math.max(Number(r.final_total_payable||0),0));
  const totalWeight=weights.reduce((a,b)=>a+b,0);
  if(!(totalWeight>0))throw Error('Selected workers का payable 0 है.');

  const ideal=weights.map(w=>targetUnits*w/totalWeight);
  const units=ideal.map((v,i)=>Math.min(Math.floor(v),capacities[i]));

  let used=units.reduce((a,b)=>a+b,0);
  let remaining=targetUnits-used;

  while(remaining>0){
    const candidates=rows.map((r,i)=>({
      i,
      room:capacities[i]-units[i],
      score:ideal[i]-units[i],
      payable:weights[i],
      id:String(r.worker_id)
    })).filter(x=>x.room>0)
      .sort((a,b)=>b.score-a.score||b.payable-a.payable||a.id.localeCompare(b.id));

    if(!candidates.length)throw Error('₹100 ratio allocation पूरा नहीं हो सका.');

    let moved=false;
    for(const candidate of candidates){
      if(remaining<=0)break;
      units[candidate.i]+=1;
      remaining-=1;
      moved=true;
    }
    if(!moved)throw Error('₹100 ratio allocation रुक गया.');
  }

  state.manual.clear();
  rows.forEach((r,i)=>state.manual.set(String(r.worker_id),units[i]*100));
}
function pay(r){return isManualPayment()?(state.selected.has(String(r.worker_id))?Number(state.manual.get(String(r.worker_id))||0):0):(state.selected.has(String(r.worker_id))?Number(r.amount_paid||0):0)}
function balance(r){return Math.max(Number(r.final_total_payable||0)-pay(r),0)}
function totals(){
  return state.rows.reduce((s,r)=>{s.old+=Number(r.previous_outstanding||0);s.work+=Number(r.current_period_payable||0);s.total+=Number(r.final_total_payable||0);s.pay+=pay(r);s.balance+=balance(r);return s},{old:0,work:0,total:0,pay:0,balance:0})
}
function render(){
  if(!state.rows.length){$('ledgerBody').innerHTML='<tr><td colspan="8">No payable workers found.</td></tr>';$('ledgerFoot').innerHTML='';$('submitPayment').disabled=true;return}
  $('ledgerBody').innerHTML=state.rows.map(r=>{
    const id=String(r.worker_id),checked=state.selected.has(id),p=pay(r);
    const cell=choice()==='SELECTED_PARTIAL'
      ?`<input class="amount-input" type="text" inputmode="decimal" value="${p?p.toFixed(2):''}" placeholder="0" data-amount="${safe(id)}">`
      :`₹${money(p)}`;
    return `<tr><td><input class="worker-check" type="checkbox" data-select="${safe(id)}" ${checked?'checked':''}></td><td><b>${safe(r.worker_name||id)}</b><br><small>${safe(r.worker_code||'—')}</small></td><td>${safe(r.department_code||'—')}</td><td class="money">₹${money(r.previous_outstanding)}</td><td class="money">₹${money(r.current_period_payable)}</td><td class="money"><b>₹${money(r.final_total_payable)}</b></td><td class="money">${cell}</td><td class="money">₹${money(balance(r))}</td></tr>`
  }).join('');
  $('ledgerBody').querySelectorAll('[data-select]').forEach(i=>i.onchange=()=>{i.checked?state.selected.add(i.dataset.select):state.selected.delete(i.dataset.select);if(choice()==='RATIO_PAYMENT')schedule();else if(choice()==='SELECTED_PARTIAL')render();else schedule()});
  const inputs=[...$('ledgerBody').querySelectorAll('[data-amount]')];
  inputs.forEach((i,index)=>{i.oninput=()=>{const id=i.dataset.amount,r=state.rows.find(x=>String(x.worker_id)===id),max=Number(r?.final_total_payable||0);let raw=String(i.value||'').replace(/,/g,'').replace(/[^0-9.]/g,''),a=raw.split('.');raw=a.length>1?`${a.shift()}.${a.join('').slice(0,2)}`:a[0];if(i.value!==raw)i.value=raw;let value=Math.min(Math.max(Number(raw||0),0),max);if(value>0&&value%100!==0){state.manual.set(id,0);say('Selected Workers Partial Payment में हर worker amount ₹100 के multiple में होना चाहिए.','error');}else{state.manual.set(id,value);}i.closest('tr').children[7].textContent=`₹${money(balance(r))}`;updateTotals()};i.onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();const n=inputs[index+1];n?(n.focus(),n.select()):$('submitPayment').focus()}}});
  updateTotals()
}
function updateTotals(){
  const t=totals();
  if($('totalPayableTop'))$('totalPayableTop').value=`₹${money(t.total)}`;
  if(choice()==='SELECTED_PARTIAL')$('bulkAmount').value=t.pay?t.pay.toFixed(2):'';
  if(method()==='FULL_PAYMENT')$('bulkAmount').value=t.total.toFixed(2);
  $('ledgerFoot').innerHTML=`<tr class="total-row"><td colspan="3">TOTAL</td><td class="money">₹${money(t.old)}</td><td class="money">₹${money(t.work)}</td><td class="money">₹${money(t.total)}</td><td class="money">₹${money(t.pay)}</td><td class="money">₹${money(t.balance)}</td></tr>`;
  $('submitPayment').disabled=!(state.preview&&state.selected.size&&t.pay>0)
}
async function preview(apply=false){
  const r=await rpc('rr_salary_payment_preview_v785',{
    p_payroll_category:CATEGORY,p_period_start:getStart(),p_period_end:getEnd(),p_data_mode:$('dataMode').value,
    p_payment_method:method(),p_payment_scope:'FULL_AND_FINAL',
    p_bulk_amount:0,
    p_worker_ids:state.selected.size?selectedIds():null,p_worker_amounts:isManualPayment()?manualPayload():[]
  });
  state.preview=r;state.rows=r.lines||[];
  if(!state.selected.size)state.selected=new Set(state.rows.map(x=>String(x.worker_id)));
  if(isManualPayment())state.rows.forEach(x=>{const id=String(x.worker_id);if(!state.manual.has(id))state.manual.set(id,0)});else state.manual.clear();
  if(choice()==='RATIO_PAYMENT'&&Number($('bulkAmount').value||0)>0)allocateRatioRound100();
  render();return r
}
function schedule(){clearTimeout(state.timer);state.timer=setTimeout(async()=>{try{if(!state.preview)return;if(choice()==='RATIO_PAYMENT'){allocateRatioRound100();render();say('Ratio Current Payment ₹100 round में distribute हो गया.','success')}else{await preview(false)}}catch(e){say(err(e),'error')}},250)}
async function load(){
  try{
    applyChoice();validatePeriod();state.preview=null;state.rows=[];state.selected.clear();state.manual.clear();
    say(LOAD_MESSAGE,'info');const r=await preview(false);
    say(`${r.eligible_worker_count} workers loaded.`,'success')
  }catch(e){state.preview=null;state.rows=[];state.selected.clear();state.manual.clear();render();say(err(e),'error')}
}
async function submit(){
  const button=$('submitPayment');
  const originalText=button.textContent;
  try{
    button.disabled=true;
    button.textContent='PROCESSING…';
    say('Submit Payment click received. Validation हो रही है…','info');

    if(!state.preview)throw Error('पहले current work load करें.');
    if(!$('paymentDate').value)$('paymentDate').value=today();
    if(!$('voucherNo').value.trim())$('voucherNo').value=autoVoucher();
    if(!state.selected.size)throw Error('कम से कम एक worker select करें.');
    validatePaymentWindow();
    applyChoice();
    if(choice()==='RATIO_PAYMENT'){allocateRatioRound100();render()}
    if(method()==='FULL_PAYMENT'){state.selected=new Set(state.rows.map(x=>String(x.worker_id)));await preview(false)}
    if(!(totals().pay>0))throw Error('Current Payment amount required.');if(choice()==='SELECTED_PARTIAL'){const invalid=state.rows.some(r=>{const p=pay(r);return p>0&&p%100!==0});if(invalid)throw Error('Selected Workers Partial Payment में सभी payment ₹100 के multiple में होने चाहिए.');}
    button.disabled=true;button.textContent='POSTING…';say('Voucher save और payment post हो रहा है…','info');
    const r=await rpc('rr_salary_payment_post_v785',{
      p_payroll_category:CATEGORY,p_period_start:getStart(),p_period_end:getEnd(),p_data_mode:$('dataMode').value,
      p_payment_method:method(),p_payment_scope:'FULL_AND_FINAL',
      p_bulk_amount:0,
      p_worker_ids:selectedIds(),p_worker_amounts:isManualPayment()?manualPayload():[],
      p_payment_date:$('paymentDate').value,p_payment_mode:'CASH',p_voucher_no:$('voucherNo').value.trim(),
      p_remarks:choice()==='RATIO_PAYMENT'?'RATIO_PAYMENT_ROUND_100':null
    });
    button.textContent='PAYMENT POSTED';say(`Payment posted ₹${money(r.bulk_amount_payment)} · Outstanding ₹${money(r.total_new_outstanding)}.`,'success');
    setTimeout(()=>location.href=RETURN_URL,1400)
  }catch(e){
    button.disabled=false;
    button.textContent=originalText;
    const message=err(e);
    say(message,'error');
    if(/Voucher/i.test(message)){$('voucherNo').focus()}
    else if(/Payment Date/i.test(message)){$('paymentDate').focus()}
    else if(/Bulk Payment Amount|Current Payment/i.test(message)){$('bulkAmount').focus()}
    if($('submitStatus'))$('submitStatus').scrollIntoView({behavior:'smooth',block:'center'});
  }
}
function bind(){
  $('loadPreview').onclick=load;$('submitPayment').onclick=submit;
  $('paymentChoice').onchange=async()=>{applyChoice();state.manual.clear();if(state.preview)await preview(false)};
  $('bulkAmount').oninput=()=>{let raw=String($('bulkAmount').value||'').replace(/,/g,'').replace(/[^0-9.]/g,''),a=raw.split('.');raw=a.length>1?`${a.shift()}.${a.join('').slice(0,2)}`:a[0];if($('bulkAmount').value!==raw)$('bulkAmount').value=raw;if(choice()==='RATIO_PAYMENT'){const v=Number($('bulkAmount').value||0);if(v>0&&v%100!==0){say('Ratio Payment amount ₹100 के multiple में भरें.','error');}else{schedule();}}};
}
async function boot(){
  try{
    state.client=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;if(!state.client)throw Error('Supabase client unavailable.');
    if(window.RR?.requireRoles)await RR.requireRoles(['owner','admin','account','accounts','payroll','manager','hr']);
    if(window.RRDataModeReadyPromise)await window.RRDataModeReadyPromise;
    if(window.RRDataMode){await RRDataMode.refresh();await RRDataMode.applyInitialMode('dataMode','')}else $('dataMode').value='TEST';
    initPeriod();$('paymentDate').value=today();if(!$('voucherNo').value.trim())$('voucherNo').value=autoVoucher();applyChoice();bind();render();$('accessBadge').textContent='ACCESS OK'
  }catch(e){$('accessBadge').textContent='ACCESS ERROR';say(err(e),'error')}
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot);else boot();

function getStart(){return $('periodStart').value}
function getEnd(){return $('periodEnd').value}
function validatePeriod(){if(!getStart()||!getEnd())throw Error('Period From और Period To required हैं.');if(getEnd()<getStart())throw Error('Period To invalid.')}
function validatePaymentWindow(){}
function initPeriod(){const t=today();$('periodEnd').value=t;$('periodStart').value=`${t.slice(0,7)}-01`;['periodStart','periodEnd'].forEach(id=>$(id).onchange=()=>{state.preview=null;state.rows=[];state.selected.clear();state.manual.clear();render();say('Period changed. Load again.','info')})}
})();