(()=>{
'use strict';
window.REAL_FACTORY_PCS_SALARY_VERSION='786.3.1-UNPAID-PAID-AUDIT';

const $=id=>document.getElementById(id);
const state={client:null,rows:[]};

const safe=value=>String(value??'').replace(/[&<>"']/g,c=>({
  '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'
})[c]);

const money=value=>Number(value||0).toLocaleString('en-IN',{
  minimumFractionDigits:2,maximumFractionDigits:2
});
const qty=value=>Number(value||0).toLocaleString('en-IN',{
  maximumFractionDigits:3
});
const err=error=>[
  error?.message,error?.details,error?.hint,error?.code
].filter(Boolean).join(' — ')||'Unknown error';

function say(text,type=''){
  $('message').textContent=text||'';
  $('message').className=`message ${type}`.trim();
}
function indiaToday(){
  return new Intl.DateTimeFormat('en-CA',{
    timeZone:'Asia/Kolkata',year:'numeric',month:'2-digit',day:'2-digit'
  }).format(new Date());
}
function firstDay(dateText){return `${dateText.slice(0,7)}-01`}

async function rpc(name,payload={}){
  const result=await state.client.rpc(name,payload);
  if(result.error)throw result.error;
  return result.data;
}

function statusMeta(row){
  const s=String(row.work_status||'');
  if(s==='UNPAID_WORK')return ['UNPAID WORK','unpaid'];
  if(s==='SALARY_ADDED_PAYMENT_PENDING')return ['SALARY ADDED · PAYMENT PENDING','pending'];
  if(s==='BATCH_LINE_PARTIALLY_PAID')return ['PARTIAL PAYMENT POSTED','partial'];
  if(s==='BATCH_LINE_FULLY_SETTLED')return ['FULL PAYMENT POSTED','paid'];
  return [s.replaceAll('_',' '),''];
}

function distinctLineTotals(rows){
  const lines=new Map();
  rows.forEach(row=>{
    if(!row.batch_line_id)return;
    if(!lines.has(row.batch_line_id)){
      lines.set(row.batch_line_id,{
        paid:Number(row.worker_amount_paid||0),
        outstanding:Number(row.worker_new_outstanding||0)
      });
    }
  });
  return [...lines.values()].reduce((sum,line)=>({
    paid:sum.paid+line.paid,
    outstanding:sum.outstanding+line.outstanding
  }),{paid:0,outstanding:0});
}

function render(){
  const rows=state.rows;
  const workerIds=new Set(rows.map(r=>r.worker_id).filter(Boolean));
  const departments=new Set(rows.map(r=>r.department_code).filter(Boolean));
  const lineTotals=distinctLineTotals(rows);

  $('workers').textContent=workerIds.size;
  $('departments').textContent=departments.size;
  $('workRows').textContent=rows.length;
  $('payablePcs').textContent=qty(
    rows.reduce((sum,row)=>sum+Number(row.payable_qty||0),0)
  );
  $('workSalary').textContent=money(
    rows.reduce((sum,row)=>sum+Number(row.salary_amount||0),0)
  );
  $('paymentPosted').textContent=money(lineTotals.paid);
  $('newOutstanding').textContent=money(lineTotals.outstanding);
  $('rowCount').textContent=`${rows.length} rows`;

  const seenLines=new Set();
  $('workBody').innerHTML=rows.length
    ?rows.map(row=>{
      const [label,klass]=statusMeta(row);
      const firstLine=row.batch_line_id&&!seenLines.has(row.batch_line_id);
      if(row.batch_line_id)seenLines.add(row.batch_line_id);
      return `<tr>
        <td class="status ${klass}">${safe(label)}</td>
        <td>${safe(row.work_date||'—')}</td>
        <td><b>${safe(row.worker_name||'Unnamed')}</b></td>
        <td>${safe(row.worker_code||'—')}</td>
        <td>${safe(row.department_code||'—')}</td>
        <td>${safe(row.lot_no||row.canonical_lot_id||'—')}</td>
        <td>${safe(row.colour_name||row.colour_code||'—')}</td>
        <td>${safe(row.size_code||'—')}</td>
        <td class="money">${qty(row.submitted_qty)}</td>
        <td class="money">${qty(row.payable_qty)}</td>
        <td class="money">₹${money(row.actual_rate)}</td>
        <td class="money">₹${money(row.salary_amount)}</td>
        <td>${safe(row.payment_date||'—')}</td>
        <td>${safe(row.voucher_no||'—')}</td>
        <td class="money">${firstLine?`₹${money(row.worker_amount_paid)}`:'—'}</td>
        <td class="money">${firstLine?`₹${money(row.worker_new_outstanding)}`:'—'}</td>
        <td>${safe(row.payment_type?row.payment_type.replaceAll('_',' '):'—')}</td>
      </tr>`;
    }).join('')
    :'<tr><td colspan="17">Selected filter में कोई work नहीं मिला.</td></tr>';
}

function updatePaymentLink(){
  const params=new URLSearchParams({
    category:'PIECE_RATE',
    mode:$('dataMode').value,
    from:$('fromDate').value,
    to:$('toDate').value
  });
  $('paymentLink').href=`real-salary-payment-v785.html?${params.toString()}`;
}

async function load(){
  try{
    const from=$('fromDate').value;
    const to=$('toDate').value;
    if(!from||!to)throw new Error('Period From और Period To required हैं.');
    if(to<from)throw new Error('Period To, Period From से पहले नहीं हो सकता.');

    say('PCS work loading…');

    const rows=await rpc(
      'rr_pcs_work_payment_audit_v786_3_1',
      {
        p_from_date:from,
        p_to_date:to,
        p_data_mode:$('dataMode').value,
        p_show:$('showMode').value,
        p_search:$('search').value.trim()||null
      }
    );

    state.rows=Array.isArray(rows)?rows:[];
    render();
    updatePaymentLink();

    say(
      `${state.rows.length} work rows loaded · ${$('showMode').selectedOptions[0].text}.`,
      'success'
    );
  }catch(error){
    state.rows=[];
    render();
    say(err(error),'error');
  }
}

async function setInitialMode(){
  const requested=String(
    new URLSearchParams(location.search).get('mode')||''
  ).toUpperCase();

  if(window.RRDataModeReadyPromise){
    await window.RRDataModeReadyPromise;
  }

  if(window.RRDataMode){
    await RRDataMode.applyInitialMode('dataMode',requested);
  }else{
    $('dataMode').value='TEST';
  }
}

function bind(){
  $('loadWork').onclick=load;
  $('showMode').onchange=load;
  $('search').onkeydown=event=>{
    if(event.key==='Enter'){
      event.preventDefault();
      load();
    }
  };
  ['dataMode','fromDate','toDate'].forEach(id=>{
    $(id).addEventListener('change',updatePaymentLink);
  });
}

async function boot(){
  try{
    state.client=
      window.supabaseClient||
      window.supabaseDb||
      window.redzedSupabase||
      window.sb;

    if(!state.client)throw new Error('Supabase client unavailable.');
    if(window.RR?.requireOwner)await RR.requireOwner();

    await setInitialMode();

    const today=indiaToday();
    const params=new URLSearchParams(location.search);
    $('toDate').value=params.get('to')||today;
    $('fromDate').value=params.get('from')||firstDay(today);

    bind();
    updatePaymentLink();
    $('accessBadge').textContent='ACCESS OK · OWNER';
    await load();
  }catch(error){
    $('accessBadge').textContent='ACCESS ERROR';
    say(err(error),'error');
  }
}

if(document.readyState==='loading'){
  document.addEventListener('DOMContentLoaded',boot);
}else{
  boot();
}
})();
