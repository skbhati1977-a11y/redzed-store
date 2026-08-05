(()=>{'use strict';
const CATEGORY='SALARIED',RETURN_URL='real-monthly-salary-dashboard-v786.html',LOAD_MESSAGE='Selected salary month और last outstanding load हो रहा है…';

const $=id=>document.getElementById(id);
const state={client:null,preview:null,rows:[],selected:new Set(),manual:new Map(),timer:null};
const safe=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));
const money=v=>Number(v||0).toLocaleString('en-IN',{minimumFractionDigits:2,maximumFractionDigits:2});
const err=e=>[e?.message,e?.details,e?.hint,e?.code].filter(Boolean).join(' — ')||'Unknown error';
const today=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Kolkata',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
function say(t,k=''){$('message').textContent=t||'';$('message').className=`message ${k}`.trim()}
async function rpc(n,p={}){const r=await state.client.rpc(n,p);if(r.error)throw r.error;return r.data}
function choice(){return $('paymentChoice').value}
function method(){return $('paymentMethod').value}
function applyChoice(){
  if(choice()==='SELECTED_PARTIAL'){$('paymentMethod').value='WORKER_LEDGER_WISE';$('bulkAmount').readOnly=true}
  else if(choice()==='RATIO_PAYMENT'){$('paymentMethod').value='PARTIAL_RATIO';$('bulkAmount').readOnly=false}
  else{$('paymentMethod').value='FULL_PAYMENT';$('bulkAmount').readOnly=true}
}
function selectedIds(){return [...state.selected]}
function manualPayload(){return state.rows.map(r=>({worker_id:r.worker_id,amount_paid:Number(state.manual.get(String(r.worker_id))||0)}))}
function pay(r){return method()==='WORKER_LEDGER_WISE'?(state.selected.has(String(r.worker_id))?Number(state.manual.get(String(r.worker_id))||0):0):(state.selected.has(String(r.worker_id))?Number(r.amount_paid||0):0)}
function balance(r){return Math.max(Number(r.final_total_payable||0)-pay(r),0)}
function totals(){
  return state.rows.reduce((s,r)=>{s.old+=Number(r.previous_outstanding||0);s.work+=Number(r.current_period_payable||0);s.total+=Number(r.final_total_payable||0);s.pay+=pay(r);s.balance+=balance(r);return s},{old:0,work:0,total:0,pay:0,balance:0})
}
function render(){
  if(!state.rows.length){$('ledgerBody').innerHTML='<tr><td colspan="8">No payable workers found.</td></tr>';$('ledgerFoot').innerHTML='';$('submitPayment').disabled=true;return}
  $('ledgerBody').innerHTML=state.rows.map(r=>{
    const id=String(r.worker_id),checked=state.selected.has(id),p=pay(r);
    const cell=method()==='WORKER_LEDGER_WISE'
      ?`<input class="amount-input" type="text" inputmode="decimal" value="${p?p.toFixed(2):''}" placeholder="0" data-amount="${safe(id)}">`
      :`₹${money(p)}`;
    return `<tr><td><input class="worker-check" type="checkbox" data-select="${safe(id)}" ${checked?'checked':''}></td><td><b>${safe(r.worker_name||id)}</b><br><small>${safe(r.worker_code||'—')}</small></td><td>${safe(r.department_code||'—')}</td><td class="money">₹${money(r.previous_outstanding)}</td><td class="money">₹${money(r.current_period_payable)}</td><td class="money"><b>₹${money(r.final_total_payable)}</b></td><td class="money">${cell}</td><td class="money">₹${money(balance(r))}</td></tr>`
  }).join('');
  $('ledgerBody').querySelectorAll('[data-select]').forEach(i=>i.onchange=()=>{i.checked?state.selected.add(i.dataset.select):state.selected.delete(i.dataset.select);method()==='WORKER_LEDGER_WISE'?render():schedule()});
  const inputs=[...$('ledgerBody').querySelectorAll('[data-amount]')];
  inputs.forEach((i,index)=>{i.oninput=()=>{const id=i.dataset.amount,r=state.rows.find(x=>String(x.worker_id)===id),max=Number(r?.final_total_payable||0);let raw=String(i.value||'').replace(/,/g,'').replace(/[^0-9.]/g,''),a=raw.split('.');raw=a.length>1?`${a.shift()}.${a.join('').slice(0,2)}`:a[0];if(i.value!==raw)i.value=raw;state.manual.set(id,Math.min(Math.max(Number(raw||0),0),max));i.closest('tr').children[7].textContent=`₹${money(balance(r))}`;updateTotals()};i.onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();const n=inputs[index+1];n?(n.focus(),n.select()):$('submitPayment').focus()}}});
  updateTotals()
}
function updateTotals(){
  const t=totals();
  if(method()==='WORKER_LEDGER_WISE')$('bulkAmount').value=t.pay?t.pay.toFixed(2):'';
  if(method()==='FULL_PAYMENT')$('bulkAmount').value=t.total.toFixed(2);
  $('ledgerFoot').innerHTML=`<tr class="total-row"><td colspan="3">TOTAL</td><td class="money">₹${money(t.old)}</td><td class="money">₹${money(t.work)}</td><td class="money">₹${money(t.total)}</td><td class="money">₹${money(t.pay)}</td><td class="money">₹${money(t.balance)}</td></tr>`;
  $('submitPayment').disabled=!(state.preview&&state.selected.size&&t.pay>0)
}
async function preview(apply=false){
  const r=await rpc('rr_salary_payment_preview_v785',{
    p_payroll_category:CATEGORY,p_period_start:getStart(),p_period_end:getEnd(),p_data_mode:$('dataMode').value,
    p_payment_method:method(),p_payment_scope:'FULL_AND_FINAL',
    p_bulk_amount:method()==='PARTIAL_RATIO'&&apply?Number($('bulkAmount').value||0):0,
    p_worker_ids:state.selected.size?selectedIds():null,p_worker_amounts:method()==='WORKER_LEDGER_WISE'?manualPayload():[]
  });
  state.preview=r;state.rows=r.lines||[];
  if(!state.selected.size)state.selected=new Set(state.rows.map(x=>String(x.worker_id)));
  if(method()==='WORKER_LEDGER_WISE')state.rows.forEach(x=>{const id=String(x.worker_id);if(!state.manual.has(id))state.manual.set(id,0)});else state.manual.clear();
  render();return r
}
function schedule(){clearTimeout(state.timer);state.timer=setTimeout(async()=>{try{if(state.preview)await preview(method()==='PARTIAL_RATIO'&&Number($('bulkAmount').value||0)>0)}catch(e){say(err(e),'error')}},300)}
async function load(){
  try{
    applyChoice();validatePeriod();state.preview=null;state.rows=[];state.selected.clear();state.manual.clear();
    say(LOAD_MESSAGE,'info');const r=await preview(method()==='PARTIAL_RATIO'&&Number($('bulkAmount').value||0)>0);
    say(`${r.eligible_worker_count} workers loaded.`,'success')
  }catch(e){state.preview=null;state.rows=[];state.selected.clear();state.manual.clear();render();say(err(e),'error')}
}
async function submit(){
  try{
    if(!state.preview)throw Error('पहले load करें.');
    if(!$('paymentDate').value)throw Error('Payment Date required.');
    if(!$('voucherNo').value.trim())throw Error('Voucher / Reference required.');
    if(!state.selected.size)throw Error('कम से कम एक worker select करें.');
    validatePaymentWindow();
    applyChoice();
    if(method()==='PARTIAL_RATIO'){if(!(Number($('bulkAmount').value||0)>0))throw Error('Bulk Payment Amount required.');await preview(true)}
    if(method()==='FULL_PAYMENT'){state.selected=new Set(state.rows.map(x=>String(x.worker_id)));await preview(false)}
    if(!(totals().pay>0))throw Error('Current Payment amount required.');
    $('submitPayment').disabled=true;say('Payment save और post हो रहा है…','info');
    const r=await rpc('rr_salary_payment_post_v785',{
      p_payroll_category:CATEGORY,p_period_start:getStart(),p_period_end:getEnd(),p_data_mode:$('dataMode').value,
      p_payment_method:method(),p_payment_scope:'FULL_AND_FINAL',
      p_bulk_amount:method()==='PARTIAL_RATIO'?Number($('bulkAmount').value||0):0,
      p_worker_ids:selectedIds(),p_worker_amounts:method()==='WORKER_LEDGER_WISE'?manualPayload():[],
      p_payment_date:$('paymentDate').value,p_payment_mode:'CASH',p_voucher_no:$('voucherNo').value.trim(),p_remarks:null
    });
    say(`Payment posted ₹${money(r.bulk_amount_payment)} · Outstanding ₹${money(r.total_new_outstanding)}.`,'success');
    setTimeout(()=>location.href=RETURN_URL,800)
  }catch(e){$('submitPayment').disabled=false;say(err(e),'error')}
}
function bind(){
  $('loadPreview').onclick=load;$('submitPayment').onclick=submit;
  $('paymentChoice').onchange=async()=>{applyChoice();if(state.preview)await preview(method()==='PARTIAL_RATIO'&&Number($('bulkAmount').value||0)>0)};
  $('bulkAmount').oninput=()=>{let raw=String($('bulkAmount').value||'').replace(/,/g,'').replace(/[^0-9.]/g,''),a=raw.split('.');raw=a.length>1?`${a.shift()}.${a.join('').slice(0,2)}`:a[0];if($('bulkAmount').value!==raw)$('bulkAmount').value=raw;if(method()==='PARTIAL_RATIO')schedule()};
}
async function boot(){
  try{
    state.client=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;if(!state.client)throw Error('Supabase client unavailable.');
    if(window.RR?.requireRoles)await RR.requireRoles(['owner','admin','account','accounts','payroll','manager','hr']);
    if(window.RRDataModeReadyPromise)await window.RRDataModeReadyPromise;
    if(window.RRDataMode){await RRDataMode.refresh();await RRDataMode.applyInitialMode('dataMode','')}else $('dataMode').value='TEST';
    initPeriod();$('paymentDate').value=today();applyChoice();bind();render();$('accessBadge').textContent='ACCESS OK'
  }catch(e){$('accessBadge').textContent='ACCESS ERROR';say(err(e),'error')}
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot);else boot();

function lastCalendarDay(y,m){return new Date(Number(y),Number(m),0).getDate()}
function getMonthParts(){const [y,m]=$('salaryMonth').value.split('-').map(Number);return {y,m}}
function getStart(){const {y,m}=getMonthParts();return `${y}-${String(m).padStart(2,'0')}-01`}
function getEnd(){const {y,m}=getMonthParts();const day=Math.min(30,lastCalendarDay(y,m));return `${y}-${String(m).padStart(2,'0')}-${String(day).padStart(2,'0')}`}
function updateLabel(){if(!$('salaryMonth').value)return;$('periodLabel').value=`${getStart()} to ${getEnd()} · 30-day salary basis`}
function validatePeriod(){if(!$('salaryMonth').value)throw Error('Salary Month required.')}
function validatePaymentWindow(){
  const p=$('paymentDate').value,choice=choice(),{y,m}=getMonthParts(),d=new Date(`${p}T00:00:00`),day=d.getDate();
  const salaryMonthKey=`${y}-${String(m).padStart(2,'0')}`;
  const payMonthKey=`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}`;
  const next=new Date(y,m,1),nextKey=`${next.getFullYear()}-${String(next.getMonth()+1).padStart(2,'0')}`;
  if(choice!=='COMPLETE_PAYMENT'){
    if(payMonthKey!==salaryMonthKey||day!==20)throw Error('Monthly Part Payment केवल salary month की 20 तारीख को allowed है.');
  }else{
    if(payMonthKey!==nextKey||day<2||day>7)throw Error('Monthly Final Payment अगली month की 2 से 7 तारीख के बीच allowed है.');
  }
}
function initPeriod(){const t=today();$('salaryMonth').value=t.slice(0,7);updateLabel();$('salaryMonth').onchange=()=>{updateLabel();state.preview=null;state.rows=[];state.selected.clear();state.manual.clear();render();say('Salary month changed. Load again.','info')};$('ruleNote').textContent='Monthly salary: 30-day basis · Part Payment on 20th · Final Payment next month 2–7.'}
})();