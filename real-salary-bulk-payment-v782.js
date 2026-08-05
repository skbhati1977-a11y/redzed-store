(()=>{
'use strict';

window.REDZED_BULK_RATIO_PAYMENT_VERSION='782.2.0';

const $=id=>document.getElementById(id);
const state={
  client:null,
  preview:null,
  selected:new Set(),
  history:[],
  cycleStatus:null,
  selectionDirty:false
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

function monthNow(){
  return today().slice(0,7);
}

function monthStart(){
  return `${$('periodMonth').value}-01`;
}

function addDays(dateText,days){
  const date=new Date(`${dateText}T00:00:00+05:30`);
  date.setDate(date.getDate()+days);
  return date.toLocaleDateString(
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
  return result.data;
}

function cycle(){
  return $('cycleType').value;
}

function isPCS(){
  return cycle().startsWith('PCS_');
}

function selectedIds(){
  return [...state.selected];
}

function queryDefaults(){
  const params=new URLSearchParams(location.search);
  const category=String(params.get('category')||'').toUpperCase();
  const cycleParam=String(params.get('cycle')||'').toUpperCase();

  if([
    'MONTHLY_PART','MONTHLY_FINAL',
    'PCS_PART_BULK','PCS_FULL_BULK'
  ].includes(cycleParam)){
    $('cycleType').value=cycleParam;
  }else if(category==='PIECE_RATE'){
    $('cycleType').value='PCS_PART_BULK';
  }

  const mode=String(params.get('mode')||'').toUpperCase();
  if(['REAL','TEST'].includes(mode))$('dataMode').value=mode;

  const month=params.get('month');
  if(month&&/^\d{4}-\d{2}$/.test(month))$('periodMonth').value=month;
}

function setWindowDayOptions(){
  const select=$('windowDays');
  const values=cycle()==='PCS_PART_BULK'
    ?[[7,'7 DAYS — PART BULK 50%'],[15,'15 DAYS — PART BULK 50%']]
    :[[15,'15 DAYS — FULL BULK 100%'],[30,'30 DAYS — FULL BULK 100%']];

  const previous=Number(select.value||0);

  select.innerHTML=values.map(
    ([value,label])=>`<option value="${value}">${label}</option>`
  ).join('');

  if(values.some(([value])=>value===previous)){
    select.value=String(previous);
  }
}

function autoEnd(){
  if(!isPCS()||!$('windowStart').value)return;
  const days=Number($('windowDays').value||0);
  if(days>0)$('windowEnd').value=addDays($('windowStart').value,days-1);
}

async function loadCycleStatus(){
  if(!isPCS()){
    $('cycleStatus').classList.add('hidden');
    return;
  }

  try{
    const status=await rpc(
      'rr_salary_pcs_cycle_status_v782_2',
      {p_data_mode:$('dataMode').value}
    );

    state.cycleStatus=status;

    const fields=[
      ['Mode',status.data_mode],
      ['Anchor',status.anchor_locked?status.anchor_date:'Not locked'],
      ['Last Accrued End',status.last_window_end||'—'],
      ['Next Required Start',status.expected_next_start||'Owner chooses first date'],
      ['Last Payment Type',status.last_cycle_type||'—']
    ];

    $('cycleStatus').innerHTML=fields.map(([label,value])=>`
      <div><small>${safe(label)}</small><b>${safe(value)}</b></div>
    `).join('');

    $('cycleStatus').classList.remove('hidden');

    if(status.expected_next_start){
      $('windowStart').value=status.expected_next_start;
      $('windowStart').readOnly=true;
      autoEnd();
    }else{
      $('windowStart').readOnly=false;
    }
  }catch(error){
    say(err(error),'error');
  }
}

async function updateCycleUI(){
  const value=cycle();

  if(value==='MONTHLY_PART'){
    $('windowDaysWrap').classList.add('hidden');
    $('windowStart').disabled=true;
    $('windowStart').readOnly=false;
    $('windowStart').value='';
    $('windowEnd').disabled=false;
    $('windowEndLabel').textContent='Part-Payment Cut-off Date';
    $('windowStartLabel').textContent='Not Used';

    if($('periodMonth').value){
      $('windowEnd').value=`${$('periodMonth').value}-20`;
    }

    $('ruleNote').innerHTML=
      '<b>Monthly Part:</b> Previous Outstanding + MIN(50% Monthly Salary, actual earned salary up to cut-off).';
  }

  if(value==='MONTHLY_FINAL'){
    $('windowDaysWrap').classList.add('hidden');
    $('windowStart').disabled=true;
    $('windowStart').readOnly=false;
    $('windowStart').value='';
    $('windowEnd').disabled=true;
    $('windowEnd').value='';
    $('windowStartLabel').textContent='Not Used';
    $('windowEndLabel').textContent='Not Used';

    $('ruleNote').innerHTML=
      '<b>Monthly Final:</b> Approved monthly salary is added; Part Payment is deducted; remaining balance receives the final bulk ratio payment.';
  }

  if(isPCS()){
    $('windowDaysWrap').classList.remove('hidden');
    $('windowStart').disabled=false;
    $('windowEnd').disabled=false;
    $('windowEnd').readOnly=true;
    $('windowStartLabel').textContent='Completed Work Window Start';
    $('windowEndLabel').textContent='Completed Work Window End';
    setWindowDayOptions();

    $('ruleNote').innerHTML=
      value==='PCS_PART_BULK'
        ?'<b>PCS Part Bulk:</b> Choose completed 7 or 15 days. Eligible = Previous Outstanding + 50% of selected-window PCS salary. Full window salary still accrues to every worker ledger.'
        :'<b>PCS Full Bulk:</b> Choose completed 15 or 30 days. Eligible = Previous Outstanding + 100% of selected-window PCS salary. A 15-day Part followed by the next 15-day Full creates a 30-day work cycle.';

    await loadCycleStatus();
    autoEnd();
  }else{
    $('cycleStatus').classList.add('hidden');
  }

  state.preview=null;
  state.selected.clear();
  state.selectionDirty=false;
  renderPreview();
}

function headers(){
  if(cycle().startsWith('MONTHLY_')){
    return [
      'Select','Worker','Department',
      'Previous Outstanding','Monthly Salary',
      'Earned to Cut-off','Eligible Part Payment',
      'Part Payment','Balance After Part Payment',
      'Month Final Payment','New Outstanding'
    ];
  }

  return [
    'Select','Worker','Department',
    'Previous Outstanding','Window Days',
    'Window PCS','Window PCS Salary',
    'Eligible Payment','Bulk Payment',
    'New Outstanding','Payment Selected'
  ];
}

function renderHeader(){
  $('flowHeader').innerHTML=headers()
    .map(label=>`<th>${safe(label)}</th>`)
    .join('');
}

function lineWorker(line){
  return `
    <b>${safe(line.worker_name||line.worker_id)}</b>
    <br><small style="color:#aeb8c8">${safe(line.worker_code||'—')}</small>
  `;
}

function renderStats(){
  const preview=state.preview;
  if(!preview){
    $('stats').innerHTML='';
    return;
  }

  const selected=(preview.lines||[]).filter(
    line=>state.selected.has(String(line.worker_id))
  );

  const allocated=selected.reduce(
    (sum,line)=>sum+Number(line.allocated_amount||0),
    0
  );

  const outstanding=(preview.lines||[]).reduce(
    (sum,line)=>sum+Number(line.new_outstanding||0),
    0
  );

  const values=[
    ['Selected Workers',selected.length],
    ['Eligible Total ₹',money(preview.eligible_total)],
    ['Owner Amount ₹',money(preview.owner_payment_amount)],
    ['Ratio %',`${(Number(preview.allocation_ratio||0)*100).toFixed(4)}%`],
    ['Allocated ₹',money(allocated)],
    ['All Workers New Outstanding ₹',money(outstanding)],
    ['Window',preview.window_days?`${preview.window_days} Days`:'Monthly']
  ];

  $('stats').innerHTML=values.map(([label,value])=>`
    <div class="stat"><small>${safe(label)}</small><strong>${safe(value)}</strong></div>
  `).join('');
}

function renderPreview(){
  renderHeader();

  const lines=state.preview?.lines||[];

  if(!lines.length){
    $('flowBody').innerHTML=`
      <tr><td colspan="${headers().length}">
        Load preview to see worker-wise salary, eligibility and fair ₹100 allocation.
      </td></tr>
    `;
    $('postBatch').disabled=true;
    renderStats();
    return;
  }

  $('flowBody').innerHTML=lines.map(line=>{
    const checked=state.selected.has(String(line.worker_id));

    if(cycle().startsWith('MONTHLY_')){
      return `<tr>
        <td><input class="worker-check" type="checkbox" data-worker="${safe(line.worker_id)}" ${checked?'checked':''}></td>
        <td>${lineWorker(line)}</td>
        <td>${safe(line.department_code||'—')}</td>
        <td class="money">₹${money(line.previous_outstanding)}</td>
        <td class="money">₹${money(line.monthly_salary)}</td>
        <td class="money">₹${money(line.earned_to_cutoff)}</td>
        <td class="money">₹${money(line.eligible_part_payment)}</td>
        <td class="money">₹${money(line.part_payment)}</td>
        <td class="money">₹${money(line.balance_after_part_payment)}</td>
        <td class="money">₹${money(line.final_payment)}</td>
        <td class="money strong ${Number(line.new_outstanding)>0?'status-bal':'status-ok'}">₹${money(line.new_outstanding)}</td>
      </tr>`;
    }

    return `<tr>
      <td><input class="worker-check" type="checkbox" data-worker="${safe(line.worker_id)}" ${checked?'checked':''}></td>
      <td>${lineWorker(line)}</td>
      <td>${safe(line.department_code||'—')}</td>
      <td class="money">₹${money(line.previous_outstanding)}</td>
      <td>${safe(line.pcs_window_days)}</td>
      <td>${qty(line.payable_pcs)}</td>
      <td class="money">₹${money(line.pcs_window_earning)}</td>
      <td class="money">₹${money(line.eligible_part_payment)}</td>
      <td class="money">₹${money(line.allocated_amount)}</td>
      <td class="money strong ${Number(line.new_outstanding)>0?'status-bal':'status-ok'}">₹${money(line.new_outstanding)}</td>
      <td>${checked?'YES':'NO — Salary still accrued'}</td>
    </tr>`;
  }).join('');

  $('flowBody').querySelectorAll('[data-worker]').forEach(input=>{
    input.onchange=()=>{
      if(input.checked)state.selected.add(input.dataset.worker);
      else state.selected.delete(input.dataset.worker);

      state.selectionDirty=true;
      $('postBatch').disabled=true;
      say('Worker selection changed. Press Load / Recalculate Preview before posting.','info');
      renderStats();
    };
  });

  $('postBatch').disabled=
    state.selectionDirty||
    !state.selected.size||
    Number($('ownerAmount').value||0)<=0;

  renderStats();
}

async function loadPreview(){
  try{
    say('Calculating completed-window salary and fair ₹100 ratio…','info');

    const data=await rpc(
      'rr_salary_bulk_preview_v782_2',
      {
        p_cycle_type:cycle(),
        p_period_month:monthStart(),
        p_window_start:$('windowStart').value||null,
        p_window_end:$('windowEnd').value||null,
        p_data_mode:$('dataMode').value,
        p_owner_amount:Number($('ownerAmount').value||0),
        p_worker_ids:state.selected.size
          ?selectedIds()
          :null
      }
    );

    state.preview=data;

    if(!state.selected.size){
      state.selected=new Set(
        (data.lines||[])
          .filter(line=>line.payment_selected!==false)
          .map(line=>String(line.worker_id))
      );
    }

    state.selectionDirty=false;
    renderPreview();

    say(
      `${data.lines.length} workers accrued · Selected eligible ₹${money(data.eligible_total)} · Owner ₹${money(data.owner_payment_amount)} · Ratio ${(Number(data.allocation_ratio||0)*100).toFixed(4)}%.`,
      'success'
    );
  }catch(error){
    state.preview=null;
    renderPreview();
    say(err(error),'error');
  }
}

async function postBatch(){
  try{
    if(state.selectionDirty){
      throw new Error('Worker selection changed. Recalculate Preview first.');
    }

    if(!state.selected.size){
      throw new Error('Select at least one worker for payment.');
    }

    if(!$('voucherNo').value.trim()){
      throw new Error('One bulk voucher/reference required.');
    }

    if(!state.preview){
      throw new Error('Load Preview first.');
    }

    const confirmed=confirm(
      `${cycle()}\n`+
      `Work Window: ${$('windowStart').value||'Monthly'} → ${$('windowEnd').value||''}\n`+
      `Selected Workers: ${state.selected.size}\n`+
      `Owner Payment: ₹${money($('ownerAmount').value)}\n`+
      `Post one voucher ${$('voucherNo').value.trim()}?`
    );

    if(!confirmed)return;

    say('Posting salary accrual and worker-wise payment ledger…','info');

    const result=await rpc(
      'rr_salary_bulk_post_v782_2',
      {
        p_cycle_type:cycle(),
        p_period_month:monthStart(),
        p_window_start:$('windowStart').value||null,
        p_window_end:$('windowEnd').value||null,
        p_data_mode:$('dataMode').value,
        p_owner_amount:Number($('ownerAmount').value),
        p_worker_ids:selectedIds(),
        p_payment_date:$('paymentDate').value,
        p_payment_mode:$('paymentMode').value,
        p_voucher_no:$('voucherNo').value.trim(),
        p_remarks:$('remarks').value.trim()||null
      }
    );

    say(
      `Posted. Batch ${result.batch_id} · ₹${money(result.owner_payment_amount)} · Next PCS start ${result.expected_next_start||'—'} · Outstanding ₹${money(result.new_outstanding_total)}.`,
      'success'
    );

    state.preview=null;
    state.selected.clear();
    state.selectionDirty=false;
    renderPreview();

    await loadCycleStatus();
    await loadHistory();
  }catch(error){
    say(err(error),'error');
  }
}

function selectAll(){
  if(!state.preview)return;
  state.selected=new Set(
    state.preview.lines.map(line=>String(line.worker_id))
  );
  state.selectionDirty=true;
  renderPreview();
  say('All workers selected. Recalculate Preview before posting.','info');
}

function clearAll(){
  state.selected.clear();
  state.selectionDirty=true;
  renderPreview();
  say('Payment selection cleared. Completed PCS salary will still accrue when a batch is posted with selected workers.','info');
}

function historyWindow(row){
  if(!row.earning_window_start)return '—';
  const days=Math.round(
    (new Date(row.earning_window_end)-new Date(row.earning_window_start))
    /86400000
  )+1;
  return `${row.earning_window_start} → ${row.earning_window_end} (${days}D)`;
}

function renderHistory(){
  $('historyBody').innerHTML=state.history.length
    ?state.history.map(row=>`
      <tr>
        <td>${safe(row.payment_date)}</td>
        <td>${safe(row.cycle_type)}</td>
        <td>${safe(historyWindow(row))}</td>
        <td>${safe(row.voucher_no)}</td>
        <td>${safe(row.payment_mode)}</td>
        <td class="money">₹${money(row.owner_payment_amount)}</td>
        <td class="money">₹${money(row.eligible_total)}</td>
        <td>${safe(row.worker_count)}</td>
        <td>${safe(row.status)}</td>
        <td>${safe(row.created_by_name||'—')}</td>
        <td>${safe(row.remarks||'—')}</td>
        <td>${
          row.status==='POSTED'
            ?`<button class="btn danger" data-reverse="${safe(row.id)}" type="button">Reverse Payment</button>`
            :'—'
        }</td>
      </tr>
    `).join('')
    :'<tr><td colspan="12">No bulk batches.</td></tr>';

  $('historyBody').querySelectorAll('[data-reverse]').forEach(button=>{
    button.onclick=()=>reverseBatch(button.dataset.reverse);
  });
}

async function loadHistory(){
  try{
    const result=await state.client
      .from('rr_salary_bulk_batches_v782')
      .select('*')
      .eq('data_mode',$('historyMode').value)
      .order('created_at',{ascending:false})
      .limit(500);

    if(result.error)throw result.error;

    state.history=result.data||[];
    renderHistory();
    $('historyMessage').textContent=`${state.history.length} batches loaded.`;
    $('historyMessage').className='message success';
  }catch(error){
    $('historyMessage').textContent=err(error);
    $('historyMessage').className='message error';
  }
}

async function reverseBatch(batchId){
  try{
    const reason=prompt(
      'Owner reversal reason',
      'Wrong payment amount / wrong voucher'
    )||'';

    if(!reason)return;

    const result=await rpc(
      'rr_salary_bulk_reverse_v782_2',
      {
        p_batch_id:batchId,
        p_reason:reason
      }
    );

    say(
      `Payment reversed ₹${money(result.reversed_amount)}. Completed PCS salary due is preserved.`,
      'success'
    );

    await loadHistory();
  }catch(error){
    say(err(error),'error');
  }
}

function bind(){
  $('cycleType').onchange=updateCycleUI;

  $('dataMode').onchange=async()=>{
    $('historyMode').value=$('dataMode').value;
    state.preview=null;
    state.selected.clear();
    state.selectionDirty=false;
    await updateCycleUI();
    await loadHistory();
  };

  $('periodMonth').onchange=()=>{
    if(cycle()==='MONTHLY_PART'){
      $('windowEnd').value=`${$('periodMonth').value}-20`;
    }
    state.preview=null;
    renderPreview();
  };

  $('windowDays').onchange=()=>{
    autoEnd();
    state.preview=null;
    renderPreview();
  };

  $('windowStart').onchange=()=>{
    autoEnd();
    state.preview=null;
    renderPreview();
  };

  $('ownerAmount').onchange=loadPreview;
  $('loadPreview').onclick=loadPreview;
  $('selectAll').onclick=selectAll;
  $('clearAll').onclick=clearAll;
  $('postBatch').onclick=postBatch;
  $('loadHistory').onclick=loadHistory;
  $('historyMode').onchange=loadHistory;
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

    $('periodMonth').value=monthNow();
    $('paymentDate').value=today();

    queryDefaults();
    $('historyMode').value=$('dataMode').value;

    bind();
    await updateCycleUI();
    renderPreview();
    await loadHistory();

    $('accessBadge').textContent='ACCESS OK';
  }catch(error){
    console.error(error);
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
