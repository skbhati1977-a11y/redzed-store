(()=>{
'use strict';

window.REAL_FACTORY_KAAM_PAYMENT_CHECK_VERSION='786.3.2';

const $=id=>document.getElementById(id);
const state={client:null,rows:[],paymentRows:[],paymentByWork:new Map(),paymentByWorker:new Map()};

const safe=value=>String(value??'').replace(
  /[&<>"']/g,
  char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[char])
);

const money=value=>Number(value||0).toLocaleString(
  'en-IN',
  {minimumFractionDigits:2,maximumFractionDigits:2}
);

const qty=value=>Number(value||0).toLocaleString(
  'en-IN',
  {maximumFractionDigits:3}
);

const err=error=>[
  error?.message,error?.details,error?.hint,error?.code
].filter(Boolean).join(' — ')||'Unknown error';

function indiaToday(){
  return new Date().toLocaleDateString(
    'en-CA',
    {timeZone:'Asia/Kolkata'}
  );
}

function addDays(dateText,days){
  const d=new Date(`${dateText}T00:00:00+05:30`);
  d.setDate(d.getDate()+days);
  return d.toLocaleDateString(
    'en-CA',
    {timeZone:'Asia/Kolkata'}
  );
}

function say(text,type=''){
  $('message').textContent=text||'';
  $('message').className=`message ${type}`.trim();
}

async function rpc(name,payload={}){
  const result=await state.client.rpc(name,payload);
  if(result.error)throw result.error;
  return result.data||[];
}

function statusClass(status){
  if(status==='ADDED_TO_SALARY_WORKER_CLEAR')return 'ok';
  if(status==='ADDED_TO_SALARY_WORKER_OUTSTANDING')return 'warn';
  if(status==='NOT_ADDED_TO_SALARY')return 'info';
  return 'bad';
}

function statusLabel(status){
  return {
    ADDED_TO_SALARY_WORKER_CLEAR:'ADDED · CLEAR',
    ADDED_TO_SALARY_WORKER_OUTSTANDING:'ADDED · OUTSTANDING',
    NOT_ADDED_TO_SALARY:'NOT ADDED',
    NO_ACTIVE_PAYROLL_PROFILE:'NO PROFILE',
    NOT_PIECE_RATE:'NOT PCS WORKER',
    ASSIGNMENT_NOT_FOUND:'ASSIGNMENT MISSING',
    MISSING_SIZE_CAP:'SIZE CAP MISSING',
    CAP_ALREADY_USED:'CAP ALREADY USED',
    MISSING_ACTUAL_RATE:'RATE MISSING'
  }[status]||status;
}

function unique(values){
  return [...new Set(values.filter(Boolean))];
}

function isPcsEligible(row){
  return String(row.profile_status||'').toUpperCase()==='PIECE_RATE'
    && ![
      'NO_ACTIVE_PAYROLL_PROFILE','NOT_PIECE_RATE',
      'ASSIGNMENT_NOT_FOUND','MISSING_SIZE_CAP',
      'CAP_ALREADY_USED','MISSING_ACTUAL_RATE'
    ].includes(String(row.audit_status||'').toUpperCase());
}


function paymentStatusLabel(row){
  const status=String(row?.worker_batch_payment_status||'').toUpperCase();
  return {
    NOT_IN_SALARY_LEDGER:'NOT ADDED',
    PAYMENT_PENDING:'PAYMENT PENDING',
    PARTIAL_PAYMENT_POSTED:'PARTIAL PAID',
    FULL_PAYMENT_POSTED:'FULL PAID'
  }[status]||status.replaceAll('_',' ')||'—';
}

function buildPaymentMaps(){
  state.paymentByWork=new Map();
  state.paymentByWorker=new Map();

  for(const row of state.paymentRows){
    const workKey=String(row.work_key||'');
    if(workKey){
      const existing=state.paymentByWork.get(workKey);
      if(!existing || String(row.payment_date||'')>String(existing.payment_date||'')){
        state.paymentByWork.set(workKey,row);
      }
    }

    const workerKey=String(row.worker_id||row.worker_name||'UNKNOWN');
    if(!state.paymentByWorker.has(workerKey)){
      state.paymentByWorker.set(workerKey,{
        paid:0,
        lastDate:null,
        lastVoucher:'—',
        seenLines:new Set()
      });
    }

    const item=state.paymentByWorker.get(workerKey);
    const lineKey=String(row.batch_line_id||`${row.batch_id||''}|${row.worker_id||''}|${row.payment_date||''}`);
    if(row.batch_line_id && !item.seenLines.has(lineKey)){
      item.seenLines.add(lineKey);
      item.paid+=Number(row.worker_amount_paid||0);
    }

    if(row.payment_date && (!item.lastDate || String(row.payment_date)>String(item.lastDate))){
      item.lastDate=row.payment_date;
      item.lastVoucher=row.voucher_no||'—';
    }
  }
}

function workerSummary(){
  const map=new Map();

  for(const row of state.rows){
    const key=String(row.worker_id||row.worker_name||'UNKNOWN');

    if(!map.has(key)){
      map.set(key,{
        worker_id:row.worker_id,
        worker_name:row.worker_name||'Unknown',
        worker_code:row.worker_code||'—',
        category:row.payroll_category||'—',
        departments:new Set(),
        lots:new Set(),
        submitted:0,
        payable:0,
        eligiblePcs:0,
        eligibleSalary:0,
        productionCost:0,
        notAdded:0,
        outstanding:Number(row.worker_outstanding||0),
        paid:0,
        lastPaymentDate:null,
        lastVoucher:'—',
        attention:0
      });
    }

    const item=map.get(key);
    item.departments.add(row.department_code||'—');
    item.lots.add(row.lot_no||row.canonical_lot_id||'—');
    item.submitted+=Number(row.submitted_qty||0);
    item.payable+=Number(row.payable_qty||0);
    item.productionCost+=Number(row.work_salary||0);
    if(isPcsEligible(row)){
      item.eligiblePcs+=Number(row.payable_qty||0);
      item.eligibleSalary+=Number(row.work_salary||0);
    }
    item.outstanding=Math.max(
      item.outstanding,
      Number(row.worker_outstanding||0)
    );

    if(row.audit_status==='NOT_ADDED_TO_SALARY'&&isPcsEligible(row)){
      item.notAdded+=Number(row.work_salary||0);
    }

    if(row.needs_attention)item.attention+=1;
  }

  for(const [key,item] of map.entries()){
    const payment=state.paymentByWorker.get(key);
    if(payment){
      item.paid=Number(payment.paid||0);
      item.lastPaymentDate=payment.lastDate||null;
      item.lastVoucher=payment.lastVoucher||'—';
    }
  }

  return [...map.values()].sort(
    (a,b)=>b.outstanding-a.outstanding||
      a.worker_name.localeCompare(b.worker_name)
  );
}

function renderStats(){
  const rows=state.rows;
  const workers=workerSummary();

  const submitted=rows.reduce(
    (sum,row)=>sum+Number(row.submitted_qty||0),0
  );
  const payable=rows.reduce(
    (sum,row)=>sum+Number(row.payable_qty||0),0
  );
  const productionCost=rows.reduce(
    (sum,row)=>sum+Number(row.work_salary||0),0
  );
  const eligiblePcs=rows.reduce(
    (sum,row)=>sum+(isPcsEligible(row)?Number(row.payable_qty||0):0),0
  );
  const eligibleSalary=rows.reduce(
    (sum,row)=>sum+(isPcsEligible(row)?Number(row.work_salary||0):0),0
  );
  const notAdded=rows.reduce(
    (sum,row)=>sum+
      (row.audit_status==='NOT_ADDED_TO_SALARY'&&isPcsEligible(row)
        ?Number(row.work_salary||0):0),
    0
  );
  const outstanding=workers.reduce(
    (sum,row)=>sum+Number(row.outstanding||0),0
  );
  const excluded=rows.filter(row=>[
    'NO_ACTIVE_PAYROLL_PROFILE','NOT_PIECE_RATE',
    'ASSIGNMENT_NOT_FOUND','MISSING_SIZE_CAP',
    'CAP_ALREADY_USED','MISSING_ACTUAL_RATE'
  ].includes(row.audit_status)).length;

  const values=[
    ['Workers',workers.length],
    ['Work Rows',rows.length],
    ['Submitted PCS',qty(submitted)],
    ['Cap-Adjusted PCS',qty(payable)],
    ['PCS Eligible PCS',qty(eligiblePcs)],
    ['PCS Salary Eligible ₹',money(eligibleSalary)],
    ['Production Cost ₹',money(productionCost)],
    ['Not Added ₹',money(notAdded)],
    ['Worker Outstanding ₹',money(outstanding)],
    ['Excluded / Review',excluded]
  ];

  $('stats').innerHTML=values.map(([label,value])=>`
    <div class="stat">
      <small>${safe(label)}</small>
      <strong>${safe(value)}</strong>
    </div>
  `).join('');
}

function renderWorkers(){
  const rows=workerSummary();

  $('workerCount').textContent=`${rows.length} workers`;

  $('workerBody').innerHTML=rows.length
    ?rows.map(row=>`
      <tr>
        <td><b>${safe(row.worker_name)}</b><br><small>${safe(row.worker_code)}</small></td>
        <td>${safe(row.category)}</td>
        <td>${safe([...row.departments].join(', '))}</td>
        <td>${safe(row.lots.size)}</td>
        <td>${qty(row.submitted)}</td>
        <td>${qty(row.payable)}</td>
        <td>${qty(row.eligiblePcs)}</td>
        <td class="money">₹${money(row.eligibleSalary)}</td>
        <td class="money">₹${money(row.productionCost)}</td>
        <td class="money"><b>₹${money(row.paid)}</b></td>
        <td>${safe(row.lastPaymentDate||'—')}</td>
        <td>${safe(row.lastVoucher||'—')}</td>
        <td class="money">₹${money(row.notAdded)}</td>
        <td class="money"><b>₹${money(row.outstanding)}</b></td>
        <td>${safe(row.attention)}</td>
      </tr>
    `).join('')
    :'<tr><td colspan="15">No workers found.</td></tr>';
}

function salaryAdded(row){
  if(row.accrual_source==='PCS_WINDOW_LEDGER'){
    const range=row.accrual_window_start
      ?`${row.accrual_window_start} → ${row.accrual_window_end}`
      :'PCS Window';
    return `YES · ${range}`;
  }

  if(row.accrual_source==='LEGACY_MONTHLY_PCS_RUN'){
    return `YES · ${row.accrual_reference||'Monthly PCS Run'}`;
  }

  return 'NO';
}

function renderDetails(){
  $('rowCount').textContent=`${state.rows.length} rows`;

  $('detailBody').innerHTML=state.rows.length
    ?state.rows.map(row=>{
      const payment=state.paymentByWork.get(String(row.work_key||''))||null;
      return `
      <tr>
        <td>${safe(row.work_date)}</td>
        <td><b>${safe(row.worker_name||'Unknown')}</b><br><small>${safe(row.worker_code||'—')}</small></td>
        <td>${safe(row.payroll_category||'—')}</td>
        <td><b>${safe(row.lot_no||row.canonical_lot_id||'—')}</b></td>
        <td>${safe(row.department_code||'—')}</td>
        <td>${safe(row.colour_name||row.colour_code||'—')}</td>
        <td>${safe(row.size_code||'—')}</td>
        <td>${qty(row.submitted_qty)}</td>
        <td>${qty(row.payable_qty)}</td>
        <td>${isPcsEligible(row)?qty(row.payable_qty):'0'}</td>
        <td>${Number(row.actual_rate||0)>0?`₹${money(row.actual_rate)}`:'—'}</td>
        <td class="money">₹${money(row.work_salary)}</td>
        <td class="money">₹${money(isPcsEligible(row)?row.work_salary:0)}</td>
        <td>${safe(isPcsEligible(row)?salaryAdded(row):'EXCLUDED')}</td>
        <td>${safe(payment?.payment_date||'—')}</td>
        <td>${safe(payment?.voucher_no||'—')}</td>
        <td class="money">${payment?.worker_amount_paid!=null?`₹${money(payment.worker_amount_paid)}`:'—'}</td>
        <td>${safe(paymentStatusLabel(payment))}</td>
        <td class="money">₹${money(row.worker_outstanding)}</td>
        <td><span class="status ${statusClass(row.audit_status)}">${safe(statusLabel(row.audit_status))}</span></td>
        <td title="${safe(row.audit_reason)}">${safe(row.audit_reason)}</td>
      </tr>
    `}).join('')
    :'<tr><td colspan="21">No work found for this filter.</td></tr>';
}

function render(){
  renderStats();
  renderWorkers();
  renderDetails();
}

async function loadAudit(){
  try{
    say('Loading work, salary, payment amount और payment date…','info');

    const [rows,paymentRows]=await Promise.all([
      rpc(
        'rr_pcs_work_audit_v783',
        {
          p_from_date:$('fromDate').value,
          p_to_date:$('toDate').value,
          p_data_mode:$('dataMode').value,
          p_status_filter:$('statusFilter').value,
          p_search:$('searchText').value.trim()||null
        }
      ),
      rpc(
        'rr_pcs_work_payment_audit_v786_3_1',
        {
          p_from_date:$('fromDate').value,
          p_to_date:$('toDate').value,
          p_data_mode:$('dataMode').value,
          p_show:'ALL',
          p_search:$('searchText').value.trim()||null
        }
      )
    ]);

    state.rows=rows;
    state.paymentRows=paymentRows;
    buildPaymentMaps();
    render();

    say(
      `${rows.length} work rows loaded with payment amount, voucher and payment date.`,
      'success'
    );
  }catch(error){
    state.rows=[];
    state.paymentRows=[];
    buildPaymentMaps();
    render();
    say(err(error),'error');
  }
}

function bind(){
  $('loadAudit').onclick=loadAudit;
  $('statusFilter').onchange=loadAudit;
  $('dataMode').onchange=loadAudit;

  $('searchText').addEventListener('keydown',event=>{
    if(event.key==='Enter')loadAudit();
  });
}

async function boot(){
  try{
    state.client=
      window.supabaseClient||
      window.supabaseDb||
      window.redzedSupabase||
      window.sb;

    if(!state.client){
      throw new Error('Supabase client unavailable. Check config.js.');
    }

    if(window.RR?.requireRoles){
      await RR.requireRoles([
        'owner','admin','account','accounts',
        'payroll','manager','hr',
        'department_head','production'
      ]);
    }else{
      const session=await state.client.auth.getSession();
      if(!session.data?.session)throw new Error('Login required.');
    }

    const today=indiaToday();
    $('toDate').value=addDays(today,-1);
    $('fromDate').value=addDays(today,-30);

    bind();
    await loadAudit();

    $('accessBadge').textContent='ACCESS OK';
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
