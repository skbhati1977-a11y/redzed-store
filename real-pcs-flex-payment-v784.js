(()=>{const p=new URLSearchParams(location.search);location.replace('real-salary-payment-v785.html?category=PIECE_RATE&mode='+encodeURIComponent(String(p.get('mode')||'REAL')));})();
(()=>{
'use strict';

window.REDZED_PCS_FLEX_PAYMENT_VERSION='784.1.0';

const $=id=>document.getElementById(id);

const state={
  client:null,
  preview:null,
  rows:[],
  selected:new Set(),
  manualAmounts:new Map(),
  history:[],
  selectionDirty:false,
  useAllOnNextLoad:true
};

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

function today(){
  return new Date().toLocaleDateString(
    'en-CA',
    {timeZone:'Asia/Kolkata'}
  );
}

function monthStart(){
  return `${today().slice(0,8)}01`;
}

function say(text,type=''){
  $('message').textContent=text||'';
  $('message').className=`message ${type}`.trim();
}

async function rpc(name,payload={}){
  const result=await state.client.rpc(name,payload);
  if(result.error)throw result.error;
  return result.data;
}

function paymentType(){
  return $('paymentType').value;
}

function selectedIds(){
  return [...state.selected];
}

function manualPayload(){
  return state.rows.map(row=>({
    worker_id:row.worker_id,
    amount_paid:Number(
      state.manualAmounts.get(String(row.worker_id))||0
    )
  }));
}

function selectedRows(){
  return state.rows.filter(
    row=>state.selected.has(String(row.worker_id))
  );
}

function updateRule(){
  const type=paymentType();

  if(type==='PARTIAL_RATIO'){
    $('ruleNote').innerHTML=
      '<b>Partial Payment:</b> All unpaid PCS ledgers appear. Enter one Bulk Amount Paid in the header. It is divided over selected workers by the locked ₹100 floor + highest remainder ratio.';
    $('bulkAmount').readOnly=false;
    $('bulkAmount').step='100';
  }

  if(type==='FULL_PAYMENT'){
    $('ruleNote').innerHTML=
      '<b>Full Payment:</b> Every selected worker receives exact Total Payable = Previous Outstanding + selected-period unpaid PCS work. Selected workers become ₹0 outstanding.';
    $('bulkAmount').readOnly=true;
  }

  if(type==='WORKER_WISE_BULK'){
    $('ruleNote').innerHTML=
      '<b>Worker-Wise Bulk:</b> Fill Amount Paid separately in every worker row. Press Enter to move to the next worker. New Outstanding and header totals update live.';
    $('bulkAmount').readOnly=true;
  }
}

function statusClass(value){
  if(value==='ACTIVE')return 'active';
  if(value==='INACTIVE')return 'inactive';
  return 'ledger';
}

function filteredRows(){
  const search=$('workerSearch').value.trim().toLowerCase();

  if(!search)return state.rows;

  return state.rows.filter(row=>
    [
      row.worker_name,
      row.worker_code,
      row.department_code,
      row.worker_status
    ].join(' ').toLowerCase().includes(search)
  );
}

function liveAmount(row){
  if(paymentType()==='WORKER_WISE_BULK'){
    return Number(
      state.manualAmounts.get(String(row.worker_id))||0
    );
  }

  return Number(row.amount_paid||0);
}

function liveNewOutstanding(row){
  return Math.max(
    Number(row.total_payable||0)-liveAmount(row),
    0
  );
}

function renderHeaderTotals(){
  const allTotal=state.rows.reduce(
    (sum,row)=>sum+Number(row.total_payable||0),
    0
  );

  const selected=selectedRows();

  const selectedPayable=selected.reduce(
    (sum,row)=>sum+Number(row.total_payable||0),
    0
  );

  const previous=state.rows.reduce(
    (sum,row)=>sum+Number(row.previous_outstanding||0),
    0
  );

  const period=state.rows.reduce(
    (sum,row)=>sum+Number(row.period_work_salary||0),
    0
  );

  const totalPaid=state.rows.reduce(
    (sum,row)=>sum+
      (
        state.selected.has(String(row.worker_id))
          ?liveAmount(row)
          :0
      ),
    0
  );

  const newOutstanding=state.rows.reduce(
    (sum,row)=>sum+
      (
        state.selected.has(String(row.worker_id))
          ?liveNewOutstanding(row)
          :Number(row.total_payable||0)
      ),
    0
  );

  $('totalPayable').textContent=`₹${money(allTotal)}`;
  $('selectedPayable').textContent=`₹${money(selectedPayable)}`;
  $('previousOutstanding').textContent=`₹${money(previous)}`;
  $('periodWork').textContent=`₹${money(period)}`;
  $('newOutstanding').textContent=`₹${money(newOutstanding)}`;

  if(paymentType()==='WORKER_WISE_BULK'){
    $('bulkAmount').value=totalPaid.toFixed(2);
  }else if(paymentType()==='FULL_PAYMENT'){
    $('bulkAmount').value=selectedPayable.toFixed(2);
  }

  $('workerCount').textContent=
    `${state.rows.length} unpaid ledgers · ${state.selected.size} selected`;

  $('postPayment').disabled=
    !state.preview||
    state.selectionDirty||
    state.selected.size===0||
    totalPaid<=0;
}

function renderTable(){
  const rows=filteredRows();

  $('ledgerBody').innerHTML=rows.length
    ?rows.map((row,index)=>{
      const id=String(row.worker_id);
      const checked=state.selected.has(id);
      const amount=liveAmount(row);
      const newBalance=checked
        ?liveNewOutstanding(row)
        :Number(row.total_payable||0);

      const amountCell=paymentType()==='WORKER_WISE_BULK'
        ?`<input
             class="amount-input"
             type="number"
             min="0"
             max="${Number(row.total_payable||0)}"
             step="0.01"
             value="${amount.toFixed(2)}"
             data-amount-worker="${safe(id)}"
           >`
        :`₹${money(amount)}`;

      return `<tr>
        <td>
          <input
            class="worker-check"
            type="checkbox"
            data-select-worker="${safe(id)}"
            ${checked?'checked':''}
          >
        </td>

        <td>
          <b>${safe(row.worker_name||id)}</b>
          <br>
          <small>${safe(row.worker_code||'—')}</small>
        </td>

        <td>
          <span class="status ${statusClass(row.worker_status)}">
            ${safe(row.worker_status||'LEDGER_ONLY')}
          </span>
        </td>

        <td>${safe(row.department_code||'—')}</td>

        <td class="money">₹${money(row.previous_outstanding)}</td>
        <td>${qty(row.period_payable_pcs)}</td>
        <td class="money">₹${money(row.period_work_salary)}</td>
        <td class="money"><b>₹${money(row.total_payable)}</b></td>

        <td class="money">${amountCell}</td>

        <td class="money ${newBalance<=0.005?'zero':'new-balance'}">
          ₹${money(newBalance)}
        </td>

        <td>
          <button
            class="btn"
            type="button"
            data-detail-worker="${safe(id)}"
            data-detail-name="${safe(row.worker_name||id)}"
          >View Work</button>
        </td>
      </tr>`;
    }).join('')
    :'<tr><td colspan="11">No worker matches this search.</td></tr>';

  const previous=state.rows.reduce(
    (sum,row)=>sum+Number(row.previous_outstanding||0),0
  );
  const pcs=state.rows.reduce(
    (sum,row)=>sum+Number(row.period_payable_pcs||0),0
  );
  const work=state.rows.reduce(
    (sum,row)=>sum+Number(row.period_work_salary||0),0
  );
  const payable=state.rows.reduce(
    (sum,row)=>sum+Number(row.total_payable||0),0
  );
  const paid=state.rows.reduce(
    (sum,row)=>sum+
      (
        state.selected.has(String(row.worker_id))
          ?liveAmount(row)
          :0
      ),0
  );
  const balance=state.rows.reduce(
    (sum,row)=>sum+
      (
        state.selected.has(String(row.worker_id))
          ?liveNewOutstanding(row)
          :Number(row.total_payable||0)
      ),0
  );

  $('ledgerFoot').innerHTML=`
    <tr class="table-total">
      <td colspan="4">TOTAL</td>
      <td class="money">₹${money(previous)}</td>
      <td>${qty(pcs)}</td>
      <td class="money">₹${money(work)}</td>
      <td class="money">₹${money(payable)}</td>
      <td class="money">₹${money(paid)}</td>
      <td class="money">₹${money(balance)}</td>
      <td></td>
    </tr>
  `;

  $('ledgerBody').querySelectorAll('[data-select-worker]').forEach(input=>{
    input.onchange=()=>{
      const id=input.dataset.selectWorker;

      if(input.checked)state.selected.add(id);
      else state.selected.delete(id);

      if(paymentType()==='WORKER_WISE_BULK'){
        renderHeaderTotals();
        renderTable();
      }else{
        state.selectionDirty=true;
        $('postPayment').disabled=true;
        renderHeaderTotals();
        say(
          'Worker selection changed. Press Load All Unpaid Ledgers to recalculate payment.',
          'info'
        );
      }
    };
  });

  const amountInputs=[
    ...$('ledgerBody').querySelectorAll('[data-amount-worker]')
  ];

  amountInputs.forEach((input,index)=>{
    input.oninput=()=>{
      const id=input.dataset.amountWorker;
      const row=state.rows.find(
        item=>String(item.worker_id)===id
      );

      const payable=Number(row?.total_payable||0);
      const entered=Number(input.value||0);
      const amount=Math.min(
        Math.max(
          Number.isFinite(entered)?entered:0,
          0
        ),
        payable
      );

      state.manualAmounts.set(id,amount);
      renderHeaderTotals();

      const balanceCell=input.closest('tr').children[9];
      balanceCell.textContent=`₹${money(
        Math.max(payable-amount,0)
      )}`;
    };

    input.onblur=()=>{
      const id=input.dataset.amountWorker;
      const row=state.rows.find(
        item=>String(item.worker_id)===id
      );

      const payable=Number(row?.total_payable||0);
      const amount=Math.min(
        Math.max(
          Number(state.manualAmounts.get(id)||0),
          0
        ),
        payable
      );

      state.manualAmounts.set(id,amount);
      input.value=amount.toFixed(2);
      renderHeaderTotals();
    };

    input.onkeydown=event=>{
      if(event.key!=='Enter')return;
      event.preventDefault();

      const next=amountInputs[index+1];

      if(next){
        next.focus();
        next.select();
      }else{
        $('postPayment').focus();
      }
    };
  });

  $('ledgerBody').querySelectorAll('[data-detail-worker]').forEach(button=>{
    button.onclick=()=>loadDetail(
      button.dataset.detailWorker,
      button.dataset.detailName
    );
  });

  renderHeaderTotals();
}

async function recalculatePreview(){
  const type=paymentType();

  const preview=await rpc(
    'rr_pcs_payment_preview_v784',
    {
      p_from_date:$('workFrom').value,
      p_to_date:$('workTo').value,
      p_data_mode:$('dataMode').value,
      p_payment_type:type,
      p_bulk_amount:
        type==='PARTIAL_RATIO'
          ?Number($('bulkAmount').value||0)
          :0,
      p_worker_ids:
        state.useAllOnNextLoad
          ?null
          :selectedIds(),
      p_worker_amounts:
        type==='WORKER_WISE_BULK'
          ?manualPayload()
          :[]
    }
  );

  state.preview=preview;
  state.rows=preview.lines||[];

  if(state.useAllOnNextLoad){
    state.selected=new Set(
      state.rows.map(row=>String(row.worker_id))
    );
  }

  state.useAllOnNextLoad=false;

  if(type==='WORKER_WISE_BULK'){
    for(const row of state.rows){
      const id=String(row.worker_id);

      if(!state.manualAmounts.has(id)){
        state.manualAmounts.set(
          id,
          Number(row.amount_paid||0)
        );
      }
    }
  }else{
    state.manualAmounts.clear();
  }

  state.selectionDirty=false;
  renderTable();

  return preview;
}

async function loadPreview(){
  try{
    say(
      'Loading every unpaid PCS ledger and selected-period unpaid work…',
      'info'
    );

    const preview=await recalculatePreview();

    say(
      `${preview.all_worker_count} unpaid worker ledgers loaded · Total Payable ₹${money(preview.total_payable)} · Period Work ₹${money(preview.total_period_work_salary)}.`,
      'success'
    );
  }catch(error){
    state.preview=null;
    state.rows=[];
    state.selected.clear();
    state.manualAmounts.clear();
    renderTable();
    say(err(error),'error');
  }
}

async function postPayment(){
  try{
    if(state.selectionDirty){
      throw new Error(
        'Worker selection changed. Recalculate before posting.'
      );
    }

    if(!$('voucherNo').value.trim()){
      throw new Error('Voucher / Reference required.');
    }

    if(!state.preview){
      throw new Error('Load All Unpaid Ledgers first.');
    }

    const type=paymentType();
    const totalPaid=Number($('bulkAmount').value||0);

    if(totalPaid<=0){
      throw new Error('Bulk Amount Paid must be greater than zero.');
    }

    const confirmed=confirm(
      `PCS ${type.replaceAll('_',' ')}\n`+
      `Work Period: ${$('workFrom').value} to ${$('workTo').value}\n`+
      `All Payable: ₹${money(
        state.rows.reduce(
          (sum,row)=>sum+Number(row.total_payable||0),0
        )
      )}\n`+
      `Amount Paid: ₹${money(totalPaid)}\n`+
      `Selected Workers: ${state.selected.size}\n`+
      `Voucher: ${$('voucherNo').value.trim()}\n\n`+
      `Post worker ledgers and queue APP / mobile messages?`
    );

    if(!confirmed)return;

    say('Posting work salary, payments and worker messages…','info');

    const result=await rpc(
      'rr_pcs_payment_post_v784',
      {
        p_from_date:$('workFrom').value,
        p_to_date:$('workTo').value,
        p_data_mode:$('dataMode').value,
        p_payment_type:type,
        p_bulk_amount:
          type==='PARTIAL_RATIO'
            ?Number($('bulkAmount').value||0)
            :0,
        p_worker_ids:selectedIds(),
        p_worker_amounts:
          type==='WORKER_WISE_BULK'
            ?manualPayload()
            :[],
        p_payment_date:$('paymentDate').value,
        p_payment_mode:$('paymentMode').value,
        p_voucher_no:$('voucherNo').value.trim(),
        p_remarks:$('remarks').value.trim()||null
      }
    );

    say(
      `Posted successfully · Paid ₹${money(result.total_amount_paid)} · New Outstanding ₹${money(result.total_new_outstanding)} · Worker messages queued.`,
      'success'
    );

    state.preview=null;
    state.rows=[];
    state.selected.clear();
    state.manualAmounts.clear();
    renderTable();

    await loadHistory();
    await loadPreview();
  }catch(error){
    say(err(error),'error');
  }
}

async function loadDetail(workerId,workerName){
  try{
    $('detailPanel').classList.remove('hidden');
    $('detailTitle').textContent=
      `${workerName} · Unpaid Work Detail`;

    $('detailMessage').textContent='Loading work detail…';
    $('detailMessage').className='message info';

    const rows=await rpc(
      'rr_pcs_unpaid_work_detail_v784',
      {
        p_from_date:$('workFrom').value,
        p_to_date:$('workTo').value,
        p_data_mode:$('dataMode').value,
        p_worker_id:workerId
      }
    );

    $('detailBody').innerHTML=rows.length
      ?rows.map(row=>`
        <tr>
          <td>${safe(row.work_date)}</td>
          <td><b>${safe(row.lot_no||row.canonical_lot_id||'—')}</b></td>
          <td>${safe(row.department_code||'—')}</td>
          <td>${safe(row.colour_name||row.colour_code||'—')}</td>
          <td>${safe(row.size_code||'—')}</td>
          <td>${qty(row.submitted_qty)}</td>
          <td>${qty(row.payable_qty)}</td>
          <td>₹${money(row.actual_rate)}</td>
          <td class="money">₹${money(row.salary_amount)}</td>
        </tr>
      `).join('')
      :'<tr><td colspan="9">No new unpaid work in this period. This worker is shown because an earlier ledger outstanding still exists.</td></tr>';

    $('detailMessage').textContent=
      `${rows.length} unpaid work rows in selected period.`;
    $('detailMessage').className='message success';
  }catch(error){
    $('detailMessage').textContent=err(error);
    $('detailMessage').className='message error';
  }
}

function renderHistory(){
  $('historyBody').innerHTML=state.history.length
    ?state.history.map(row=>`
      <tr>
        <td>${safe(row.payment_date)}</td>
        <td>${safe(row.work_from_date)} → ${safe(row.work_to_date)}</td>
        <td>${safe(row.payment_type)}</td>
        <td>${safe(row.voucher_no)}</td>
        <td>${safe(row.selected_worker_count)} / ${safe(row.all_worker_count)}</td>
        <td class="money">₹${money(row.total_payable)}</td>
        <td class="money">₹${money(row.total_amount_paid)}</td>
        <td class="money">₹${money(row.total_new_outstanding)}</td>
        <td>APP ${safe(row.app_notification_count||0)} · Mobile ${safe(row.mobile_message_count||0)}</td>
        <td>${safe(row.status)}</td>
        <td>${
          row.status==='POSTED'
            ?`<button class="btn danger" data-void-batch="${safe(row.id)}" type="button">Void Batch</button>`
            :'—'
        }</td>
      </tr>
    `).join('')
    :'<tr><td colspan="11">No PCS V784 payment history.</td></tr>';

  $('historyBody').querySelectorAll('[data-void-batch]').forEach(button=>{
    button.onclick=()=>voidBatch(button.dataset.voidBatch);
  });
}

async function loadHistory(){
  try{
    const result=await state.client
      .from('rr_pcs_payment_history_v784')
      .select('*')
      .eq('data_mode',$('dataMode').value)
      .order('created_at',{ascending:false})
      .limit(300);

    if(result.error)throw result.error;

    state.history=result.data||[];
    renderHistory();
  }catch(error){
    say(err(error),'error');
  }
}

async function voidBatch(batchId){
  try{
    const reason=prompt(
      'Owner void reason',
      'Wrong date / amount / voucher'
    )||'';

    if(!reason)return;

    const result=await rpc(
      'rr_pcs_payment_void_v784',
      {
        p_batch_id:batchId,
        p_reason:reason
      }
    );

    say(
      `Batch voided · Payment reversed ₹${money(result.voided_payment)} · Work restored to unpaid.`,
      'success'
    );

    await loadHistory();
    await loadPreview();
  }catch(error){
    say(err(error),'error');
  }
}

function selectAll(){
  state.selected=new Set(
    state.rows.map(row=>String(row.worker_id))
  );
  state.useAllOnNextLoad=false;

  if(paymentType()==='WORKER_WISE_BULK'){
    renderTable();
  }else{
    state.selectionDirty=true;
    renderTable();
    say('All selected. Recalculate payment before posting.','info');
  }
}

function clearAll(){
  state.selected.clear();
  state.useAllOnNextLoad=false;

  if(paymentType()==='WORKER_WISE_BULK'){
    renderTable();
  }else{
    state.selectionDirty=true;
    renderTable();
    say('Selection cleared. Recalculate payment before posting.','info');
  }
}

function bind(){
  $('paymentType').onchange=async()=>{
    updateRule();
    state.preview=null;
    state.rows=[];
    state.selected.clear();
    state.manualAmounts.clear();
    state.useAllOnNextLoad=true;
    $('bulkAmount').value='0';
    renderTable();
    await loadPreview();
  };

  $('dataMode').onchange=async()=>{
    state.preview=null;
    state.rows=[];
    state.selected.clear();
    state.manualAmounts.clear();
    state.useAllOnNextLoad=true;
    await loadHistory();
    await loadPreview();
  };

  $('loadPreview').onclick=loadPreview;
  $('postPayment').onclick=postPayment;
  $('selectAll').onclick=selectAll;
  $('clearAll').onclick=clearAll;
  $('loadHistory').onclick=loadHistory;

  const invalidatePeriod=()=>{
    state.preview=null;
    state.selectionDirty=true;
    $('postPayment').disabled=true;
    say(
      'Work period changed. Press Load All Unpaid Ledgers.',
      'info'
    );
  };

  $('workFrom').onchange=invalidatePeriod;
  $('workTo').onchange=invalidatePeriod;

  $('bulkAmount').addEventListener('input',()=>{
    if(paymentType()==='PARTIAL_RATIO'&&state.preview){
      state.selectionDirty=true;
      $('postPayment').disabled=true;
    }
  });

  $('bulkAmount').addEventListener('keydown',event=>{
    if(event.key==='Enter')loadPreview();
  });

  $('workerSearch').oninput=renderTable;

  $('closeDetail').onclick=()=>{
    $('detailPanel').classList.add('hidden');
  };
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
        'payroll','manager','hr'
      ]);
    }else{
      const session=await state.client.auth.getSession();
      if(!session.data?.session)throw new Error('Login required.');
    }

    const now=today();

    $('workFrom').value=monthStart();
    $('workTo').value=now;
    $('paymentDate').value=now;

    const params=new URLSearchParams(location.search);
    const mode=String(params.get('mode')||'').toUpperCase();

    if(['REAL','TEST'].includes(mode)){
      $('dataMode').value=mode;
    }

    updateRule();
    bind();
    renderTable();

    await loadHistory();
    await loadPreview();

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
