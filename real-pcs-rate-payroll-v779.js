(()=>{
'use strict';
window.REAL_FACTORY_PCS_SALARY_VERSION='786.3.0-SIMPLE-UNPAID';

const $=id=>document.getElementById(id);
const state={client:null,preview:null,rows:[]};

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

function firstDayOfMonth(dateText){
  return `${dateText.slice(0,7)}-01`;
}

async function rpc(name,payload={}){
  const result=await state.client.rpc(name,payload);
  if(result.error)throw result.error;
  return result.data;
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

function render(){
  const preview=state.preview||{};
  const rows=state.rows;

  $('workers').textContent=Number(preview.all_worker_count||rows.length||0);
  $('departments').textContent=new Set(rows.map(r=>r.department_code).filter(Boolean)).size;
  $('workRows').textContent=Number(preview.unpaid_work_row_count||0);
  $('payablePcs').textContent=qty(preview.total_period_payable_pcs||0);
  $('newSalary').textContent=money(preview.total_period_work_salary||0);
  $('totalPayable').textContent=money(preview.all_worker_total_payable||0);
  $('rowCount').textContent=`${rows.length} workers`;

  $('workerBody').innerHTML=rows.length
    ?rows.map(row=>{
      const workerId=encodeURIComponent(row.worker_id);
      const params=new URLSearchParams({
        category:'PIECE_RATE',
        mode:$('dataMode').value,
        from:$('fromDate').value,
        to:$('toDate').value,
        worker:workerId
      });
      return `<tr>
        <td><b>${safe(row.worker_name||'Unnamed')}</b></td>
        <td>${safe(row.worker_code||'—')}</td>
        <td>${safe(row.department_code||'—')}</td>
        <td class="money">₹${money(row.previous_outstanding)}</td>
        <td class="money">${qty(row.period_payable_pcs)}</td>
        <td class="money">₹${money(row.period_work_salary)}</td>
        <td class="money">₹${money(row.total_payable)}</td>
        <td><a class="btn success" href="real-salary-payment-v785.html?${params.toString()}">PAY</a></td>
      </tr>`;
    }).join('')
    :'<tr><td colspan="8">Selected period में कोई unpaid PCS work नहीं मिला.</td></tr>';
}

async function load(){
  try{
    const from=$('fromDate').value;
    const to=$('toDate').value;
    if(!from||!to)throw new Error('Period From और Period To required हैं.');
    if(to<from)throw new Error('Period To, Period From से पहले नहीं हो सकता.');

    say('All departments का unpaid submitted PCS work load हो रहा है…');

    const preview=await rpc('rr_pcs_payment_preview_v784',{
      p_from_date:from,
      p_to_date:to,
      p_data_mode:$('dataMode').value,
      p_payment_type:'FULL_PAYMENT',
      p_bulk_amount:0,
      p_worker_ids:null,
      p_worker_amounts:[]
    });

    state.preview=preview||{};
    state.rows=Array.isArray(preview?.workers)?preview.workers:
      Array.isArray(preview?.lines)?preview.lines:[];

    render();
    updatePaymentLink();

    say(
      `${state.rows.length} workers · ${qty(preview.total_period_payable_pcs||0)} payable PCS · ₹${money(preview.total_period_work_salary||0)} new unpaid work salary.`,
      'success'
    );
  }catch(error){
    state.preview=null;
    state.rows=[];
    render();
    say(err(error),'error');
  }
}

async function setInitialMode(){
  const requested=String(new URLSearchParams(location.search).get('mode')||'').toUpperCase();
  if(window.RRDataModeReadyPromise)await window.RRDataModeReadyPromise;
  if(window.RRDataMode){
    await RRDataMode.applyInitialMode('dataMode',requested);
  }else{
    $('dataMode').value='TEST';
  }
}

function bind(){
  $('loadWork').onclick=load;
  ['dataMode','fromDate','toDate'].forEach(id=>{
    $(id).addEventListener('change',updatePaymentLink);
  });
}

async function boot(){
  try{
    state.client=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
    if(!state.client)throw new Error('Supabase client unavailable.');
    if(window.RR?.requireOwner)await RR.requireOwner();

    await setInitialMode();

    const today=indiaToday();
    const params=new URLSearchParams(location.search);
    $('toDate').value=params.get('to')||today;
    $('fromDate').value=params.get('from')||firstDayOfMonth(today);

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
