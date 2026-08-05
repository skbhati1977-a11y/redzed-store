(()=>{
'use strict';
window.REDZED_PCS_RATE_PAYROLL_VERSION='779.4.2';

const state={client:null,auth:null,workers:[],run:null,lines:[],details:[],attendance:[],holidays:[],adjustments:[],mapping:[],ledgerDues:[],ledgerEntries:[],ledgerSelectedDueId:'',ledgerFocusWorkerId:'',attendanceWorkerId:'',adjustmentWorkerId:''};
const $=id=>document.getElementById(id);
const safe=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));
const err=e=>[e?.message,e?.details,e?.hint,e?.code].filter(Boolean).join(' — ')||'Unknown error';
const upper=v=>String(v||'').trim().toUpperCase();
const normCategory=v=>upper(v).replace(/[ -]+/g,'_');
const money=v=>Number(v||0).toLocaleString('en-IN',{minimumFractionDigits:2,maximumFractionDigits:2});
const qty=v=>Number(v||0).toLocaleString('en-IN',{minimumFractionDigits:0,maximumFractionDigits:3});
const monthStart=value=>`${value}-01`;
const monthRange=value=>{const [y,m]=value.split('-').map(Number);const start=new Date(Date.UTC(y,m-1,1));const end=new Date(Date.UTC(y,m,0));return [start.toISOString().slice(0,10),end.toISOString().slice(0,10)]};
const localISO=(date,time)=>date&&time?new Date(`${date}T${time}:00+05:30`).toISOString():null;
const localTime=value=>value?new Date(value).toLocaleTimeString('en-IN',{timeZone:'Asia/Kolkata',hour:'2-digit',minute:'2-digit',hour12:false}):'—';
const localDateTime=value=>value?new Date(value).toLocaleString('en-IN',{timeZone:'Asia/Kolkata',dateStyle:'medium',timeStyle:'short'}):'—';
const dayName=d=>new Date(`${d}T00:00:00+05:30`).toLocaleDateString('en-IN',{weekday:'short',timeZone:'Asia/Kolkata'});
const todayMonth=()=>new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Kolkata',year:'numeric',month:'2-digit'}).slice(0,7);
const todayDate=()=>new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Kolkata'});
function say(id,text,type=''){const el=$(id);if(!el)return;el.textContent=text||'';el.className=`message ${type}`.trim()}
async function rpc(name,payload={}){const r=await state.client.rpc(name,payload);if(r.error)throw r.error;return r.data}

class SearchSelect{
  constructor(select){
    this.select=select;
    this.wrap=document.createElement('div');
    this.wrap.className='combo';
    this.input=document.createElement('input');
    this.input.className='combo-input';
    this.input.autocomplete='off';
    this.list=document.createElement('div');
    this.list.className='combo-list hidden';
    select.parentNode.insertBefore(this.wrap,select);
    this.wrap.append(this.input,this.list,select);
    select.classList.add('hidden');
    select._searchCombo=this;
    this.input.addEventListener('focus',()=>{this.input.select();this.render(true)});
    this.input.addEventListener('click',()=>this.render(true));
    this.input.addEventListener('input',()=>this.render(false));
    this.input.addEventListener('keydown',e=>this.key(e));
    // Commit an option on pointer-down, before the input blur handler can restore the old value.
    // This fixes REAL/TEST being visible but not selectable on mouse and touch devices.
    this.list.addEventListener('pointerdown',e=>{
      const option=e.target.closest('[data-si]');
      if(!option||!this.list.contains(option))return;
      e.preventDefault();
      e.stopPropagation();
      this.pick(Number(option.dataset.si));
    });
    this.input.addEventListener('blur',()=>setTimeout(()=>{
      if(!this.wrap.contains(document.activeElement)){
        this.list.classList.add('hidden');
        this.sync();
      }
    },0));
    document.addEventListener('click',e=>{
      if(!this.wrap.contains(e.target)){
        this.list.classList.add('hidden');
        this.sync();
      }
    });
    this.sync();
  }
  options(){return [...this.select.options].map((o,i)=>({i,value:o.value,label:o.textContent.trim(),disabled:o.disabled}))}
  selectedLabel(){return this.select.selectedOptions[0]?.textContent.trim()||''}
  sync(){this.input.value=this.selectedLabel()}
  render(showAll=false){
    const raw=this.input.value.trim().toLowerCase();
    const selected=this.selectedLabel().toLowerCase();
    const q=showAll||raw===selected?'':raw;
    this.filtered=this.options().filter(o=>!o.disabled&&(!q||o.label.toLowerCase().includes(q)));
    this.index=-1;
    this.list.innerHTML=this.filtered.length
      ?this.filtered.map((o,i)=>`<div class="combo-option" data-si="${i}">${safe(o.label)}</div>`).join('')
      :'<div class="combo-option muted">No option</div>';
    this.list.classList.remove('hidden');
  }
  pick(i){
    const o=this.filtered[i];
    if(!o)return;
    this.select.value=o.value;
    this.select.selectedIndex=o.i;
    this.sync();
    this.list.classList.add('hidden');
    this.select.dispatchEvent(new Event('input',{bubbles:true}));
    this.select.dispatchEvent(new Event('change',{bubbles:true}));
  }
  key(e){
    if(this.list.classList.contains('hidden'))return;
    if(e.key==='ArrowDown'){
      e.preventDefault();
      this.index=Math.min(this.filtered.length-1,this.index+1);
    }else if(e.key==='ArrowUp'){
      e.preventDefault();
      this.index=Math.max(0,this.index-1);
    }else if(e.key==='Enter'&&this.index>=0){
      e.preventDefault();
      this.pick(this.index);
      return;
    }else if(e.key==='Escape'){
      this.list.classList.add('hidden');
      this.sync();
      return;
    }else return;
    [...this.list.querySelectorAll('[data-si]')].forEach((x,i)=>x.classList.toggle('active',i===this.index));
  }
}
function upgradeSelects(){document.querySelectorAll('select').forEach(s=>{if(!s._searchCombo)new SearchSelect(s)})}
function syncSelects(){document.querySelectorAll('select').forEach(s=>s._searchCombo?.sync())}

class SearchCombo{
  constructor(root,onSelect){this.root=root;this.onSelect=onSelect;this.rows=[];this.filtered=[];this.index=-1;this.value='';this.root.innerHTML='<div class="combo"><input class="combo-input" autocomplete="off" placeholder="Type worker name / code / department"><div class="combo-list hidden"></div></div>';this.input=this.root.querySelector('.combo-input');this.list=this.root.querySelector('.combo-list');this.input.addEventListener('input',()=>this.render());this.input.addEventListener('focus',()=>this.render());this.input.addEventListener('keydown',e=>this.key(e));document.addEventListener('click',e=>{if(!this.root.contains(e.target))this.list.classList.add('hidden')})}
  setRows(rows){this.rows=rows||[];this.render()}
  setValue(id){const row=this.rows.find(x=>String(x.worker_id)===String(id));this.value=row?.worker_id||'';this.input.value=row?`${row.worker_name} · ${row.worker_code||'—'} · ${row.department_code||'—'}`:''}
  render(){const q=this.input.value.trim().toLowerCase();this.filtered=this.rows.filter(r=>!q||JSON.stringify([r.worker_name,r.worker_code,r.department_code]).toLowerCase().includes(q)).slice(0,100);this.index=-1;this.list.innerHTML=this.filtered.length?this.filtered.map((r,i)=>`<div class="combo-option" data-i="${i}"><b>${safe(r.worker_name||'Unnamed')}</b><small>${safe(r.worker_code||'—')} · ${safe(r.department_code||'—')} · PIECE RATE</small></div>`).join(''):'<div class="combo-option muted">No matching Piece-Rate worker</div>';this.list.classList.remove('hidden');this.list.querySelectorAll('[data-i]').forEach(el=>el.onclick=()=>this.pick(Number(el.dataset.i)))}
  pick(i){const row=this.filtered[i];if(!row)return;this.value=row.worker_id;this.input.value=`${row.worker_name} · ${row.worker_code||'—'} · ${row.department_code||'—'}`;this.list.classList.add('hidden');this.onSelect?.(row)}
  key(e){if(this.list.classList.contains('hidden'))return;if(e.key==='ArrowDown'){e.preventDefault();this.index=Math.min(this.filtered.length-1,this.index+1)}else if(e.key==='ArrowUp'){e.preventDefault();this.index=Math.max(0,this.index-1)}else if(e.key==='Enter'&&this.index>=0){e.preventDefault();this.pick(this.index);return}else if(e.key==='Escape'){this.list.classList.add('hidden');return}else return;[...this.list.querySelectorAll('[data-i]')].forEach((x,i)=>x.classList.toggle('active',i===this.index))}
}
let attendanceCombo,adjustmentCombo;

async function loadWorkers(mode){
  const r=await state.client.from('rr_worker_payroll_board_v777_3').select('*').eq('data_mode',mode).order('worker_name',{ascending:true});
  if(r.error)throw r.error;
  const byId=new Map();
  for(const row of r.data||[]){if(normCategory(row.worker_category)!=='PIECE_RATE')continue;if(!byId.has(String(row.worker_id)))byId.set(String(row.worker_id),row)}
  state.workers=[...byId.values()];
  attendanceCombo.setRows(state.workers);adjustmentCombo.setRows(state.workers);
  if(state.attendanceWorkerId&&state.workers.some(w=>String(w.worker_id)===String(state.attendanceWorkerId)))attendanceCombo.setValue(state.attendanceWorkerId);
  if(state.adjustmentWorkerId&&state.workers.some(w=>String(w.worker_id)===String(state.adjustmentWorkerId)))adjustmentCombo.setValue(state.adjustmentWorkerId);
}

function paymentStatusClass(value){
  const status=upper(value);
  if(status==='PAID')return 'ledger-paid';
  if(status==='PARTIAL')return 'ledger-partial';
  return 'ledger-unpaid';
}

function renderPayroll(){
  const r=state.run;
  const lines=state.lines;

  $('payrollStats').innerHTML=[
    ['Status',r?.status||'NOT CALCULATED'],
    ['Workers',r?.worker_count||0],
    ['Payable PCS',qty(r?.total_payable_qty)],
    ['Exceptions',r?.incomplete_worker_count||0],
    ['Salary Due ₹',money(r?.ledger_due_total||r?.net_total)],
    ['Paid ₹',money(r?.ledger_paid_total)],
    ['Balance ₹',money(r?.ledger_balance_total||r?.net_total)],
    ['Ledger Status',r?.ledger_payment_status||'NOT_POSTED']
  ].map(([label,value],index)=>
    `<div class="stat ${
      (
        index===3&&Number(value)>0
      )||
      (
        index===6&&Number(r?.ledger_balance_total||0)>0
      )
        ?'alert'
        :''
    }">
      <small>${safe(label)}</small>
      <strong>${safe(value)}</strong>
    </div>`
  ).join('');

  $('payrollBody').innerHTML=lines.length
    ?lines.map(line=>{
      const balance=Number(
        line.ledger_balance_amount||
        (
          line.run_status==='CALCULATED'
            ?line.net_pay
            :0
        )||
        0
      );

      const due=Number(
        line.ledger_due_amount||
        (
          ['APPROVED','PARTIALLY_PAID','PAID'].includes(
            line.run_status
          )
            ?line.net_pay
            :0
        )||
        0
      );

      const paid=Number(line.ledger_paid_amount||0);
      const paymentStatus=line.ledger_payment_status||(
        line.run_status==='CALCULATED'
          ?'APPROVE_FIRST'
          :'NOT_POSTED'
      );

      const paymentAction=line.due_entry_id
        ?(
          balance>0.005
            ?`<button
                class="btn success ledger-payment-button"
                data-pay-due="${safe(line.due_entry_id)}"
                type="button">PAY ₹${money(balance)}</button>`
            :`<button
                class="btn ledger-payment-button"
                data-open-ledger-worker="${safe(line.worker_id)}"
                type="button">OPEN LEDGER</button>`
        )
        :(
          line.run_status==='CALCULATED'
            ?'<span class="muted">Approve first</span>'
            :'<span class="muted">Due not posted</span>'
        );

      return `<tr>
        <td>
          <b>${safe(line.worker_name||line.worker_id)}</b>
          <br>
          <small class="muted">${safe(line.worker_code||'—')}</small>
        </td>

        <td>${safe(line.department_code||'—')}</td>
        <td>${safe(line.compensation_mode||'PCS_ONLY')}</td>
        <td>${qty(line.payable_qty)}</td>
        <td class="money">${money(line.average_base_rate)}</td>
        <td class="money">${money(line.base_piece_earning)}</td>
        <td class="money">${money(line.rate_enhancement_earning)}</td>
        <td class="money">${money(line.monthly_flat_incentive)}</td>
        <td class="money">${money(line.adjustment_earning)}</td>
        <td class="money">${money(line.adjustment_deduction)}</td>
        <td class="money">${money(line.advance_deduction)}</td>
        <td class="money">${money(line.damage_reference_amount)}</td>
        <td>${qty(line.attendance_present_days)}</td>
        <td>${qty(line.attendance_absent_days)}</td>
        <td class="${Number(line.missing_rate_rows)>0?'status-MISSING_RATE':''}">
          ${line.missing_rate_rows}
        </td>
        <td class="${Number(line.missing_cap_rows)>0?'status-MISSING_SIZE_CAP':''}">
          ${line.missing_cap_rows}
        </td>
        <td class="money"><b>${money(due)}</b></td>
        <td class="money">${money(paid)}</td>
        <td class="money ledger-balance">${money(balance)}</td>
        <td class="${paymentStatusClass(paymentStatus)}">${safe(paymentStatus)}</td>
        <td>${paymentAction}</td>
        <td>
          <button
            class="btn"
            data-worker-detail="${safe(line.worker_name||'')}"
            type="button">Open PCS</button>
        </td>
      </tr>`;
    }).join('')
    :'<tr><td colspan="22" class="muted">Calculate Piece payroll to create snapshot lines.</td></tr>';

  $('payrollBody').querySelectorAll('[data-worker-detail]').forEach(
    button=>button.onclick=()=>{
      showTab('details');
      $('detailSearch').value=button.dataset.workerDetail;
      loadDetails();
    }
  );

  $('payrollBody').querySelectorAll('[data-pay-due]').forEach(
    button=>button.onclick=async()=>{
      await openPayment(
        button.dataset.payDue,
        {
          mode:$('payrollMode').value,
          month:$('payrollMonth').value
        }
      );
    }
  );

  $('payrollBody').querySelectorAll('[data-open-ledger-worker]').forEach(
    button=>button.onclick=async()=>{
      showTab('ledger');
      $('ledgerMode').value=$('payrollMode').value;
      $('ledgerMonth').value=$('payrollMonth').value;
      $('ledgerSearch').value='';
      state.ledgerFocusWorkerId=button.dataset.openLedgerWorker;
      syncSelects();
      await loadLedger();
    }
  );

  const locked=[
    'APPROVED',
    'PARTIALLY_PAID',
    'PAID'
  ].includes(r?.status);

  $('calculatePayroll').disabled=locked;
  $('approvePayroll').disabled=
    !r||
    r.status!=='CALCULATED'||
    Number(r.incomplete_worker_count)>0;
  $('reopenPayroll').disabled=!locked;
  $('markPaid').disabled=!r||![
    'APPROVED',
    'PARTIALLY_PAID',
    'PAID'
  ].includes(r.status);
}

async function loadPayroll(){
  try{
    const month=monthStart($('payrollMonth').value);
    const mode=$('payrollMode').value;

    const runResult=await state.client
      .from('rr_piece_payroll_run_board_v779')
      .select('*')
      .eq('period_month',month)
      .eq('data_mode',mode)
      .maybeSingle();

    if(runResult.error)throw runResult.error;

    state.run=runResult.data||null;

    if(state.run){
      const lineResult=await state.client
        .from('rr_piece_payroll_line_board_v779')
        .select('*')
        .eq('piece_run_id',state.run.id)
        .order('worker_name');

      if(lineResult.error)throw lineResult.error;
      state.lines=lineResult.data||[];
    }else{
      state.lines=[];
    }

    renderPayroll();

    say(
      'payrollMessage',
      state.run
        ?`Run loaded: ${state.run.status} · Ledger Due ₹${money(state.run.ledger_due_total)} · Paid ₹${money(state.run.ledger_paid_total)} · Balance ₹${money(state.run.ledger_balance_total)}`
        :'No calculated run for this month.',
      'success'
    );
  }catch(error){
    say('payrollMessage',err(error),'error');
  }
}

async function calculatePayroll(){
  try{
    say(
      'payrollMessage',
      'Reading UPM Dynamic Submit, assignment-size cap and frozen Assignment Actual Rate…',
      'info'
    );

    const id=await rpc(
      'rr_piece_payroll_calculate_v779',
      {
        p_period_month:monthStart($('payrollMonth').value),
        p_data_mode:$('payrollMode').value
      }
    );

    await loadPayroll();

    say(
      'payrollMessage',
      `Piece payroll calculated. Run ${id}`,
      'success'
    );
  }catch(error){
    say('payrollMessage',err(error),'error');
  }
}

async function approvePayroll(){
  try{
    if(!state.run){
      throw new Error('Calculate payroll first.');
    }

    const reason=prompt(
      'Approval reason',
      'UPM PCS, rates and adjustments verified'
    )||'';

    if(!reason)return;

    await rpc(
      'rr_piece_payroll_approve_v779',
      {
        p_piece_run_id:state.run.id,
        p_reason:reason
      }
    );

    await loadPayroll();
    await loadLedger();

    say(
      'payrollMessage',
      'Piece payroll approved and locked. Worker-wise Salary Due posted in Worker Ledger.',
      'success'
    );
  }catch(error){
    say('payrollMessage',err(error),'error');
  }
}

async function reopenPayroll(){
  try{
    if(!state.run){
      throw new Error('Run missing.');
    }

    const reason=prompt(
      'OWNER reopen reason',
      'Rate / UPM / adjustment correction required'
    )||'';

    if(!reason)return;

    await rpc(
      'rr_piece_payroll_reopen_v779',
      {
        p_piece_run_id:state.run.id,
        p_reason:reason
      }
    );

    await loadPayroll();
    await loadLedger();

    say(
      'payrollMessage',
      'Piece payroll reopened. If payment existed, it must have been reversed first.',
      'success'
    );
  }catch(error){
    say('payrollMessage',err(error),'error');
  }
}

async function markPaid(){
  if(!state.run)return;

  showTab('ledger');
  $('ledgerMode').value=$('payrollMode').value;
  $('ledgerMonth').value=$('payrollMonth').value;
  $('ledgerStatus').value='ALL';
  syncSelects();
  await loadLedger();

  say(
    'ledgerMessage',
    'Select a worker Salary Due and post partial/full payment with voucher/reference.',
    'info'
  );
}

function currentAccess(){
  return {
    role:upper(
      state.auth?.role_code||
      state.auth?.profile?.role_code||
      ''
    ),
    department:upper(
      state.auth?.department_code||
      state.auth?.profile?.department_code||
      ''
    )
  };
}

function canShowRateEditor(row){
  const access=currentAccess();
  return ['OWNER','ADMIN','MANAGER'].includes(access.role)||
    (
      access.role==='DEPARTMENT_HEAD'&&
      access.department===upper(row.department_code)
    );
}

function isMissingDetail(row){
  return row.mapping_status==='MISSING_ACTUAL_RATE'||
    row.mapping_status==='MISSING_RATE';
}

function detailGroupKey(row){
  return [
    String(
      row.worker_id||
      row.worker_code||
      row.worker_name||
      ''
    ),
    upper(row.lot_no),
    upper(row.department_code)
  ].join('||');
}

function buildDetailGroups(){
  const groups=new Map();

  for(const row of state.details){
    const key=detailGroupKey(row);

    if(!groups.has(key)){
      groups.set(key,{
        key,
        worker_id:row.worker_id,
        worker_name:row.worker_name,
        worker_code:row.worker_code,
        lot_no:row.lot_no,
        department_code:row.department_code,
        rows:[],
        assignments:new Map(),
        colours:new Map(),
        nextDepartments:new Set(),
        positiveRates:new Set(),
        payableRates:new Set(),
        rateSources:new Set(),
        mappingStatuses:new Map(),
        assignedCap:0,
        beforeQty:0,
        toEndQty:0,
        payableQty:0,
        baseAmount:0,
        enhancementAmount:0,
        lastSourceAt:null
      });
    }

    const group=groups.get(key);
    group.rows.push(row);

    if(row.assignment_id){
      group.assignments.set(
        String(row.assignment_id),
        row
      );
    }

    const colour=String(
      row.colour_code||
      row.colour_name||
      '—'
    );
    if(!group.colours.has(colour)){
      group.colours.set(colour,new Set());
    }
    group.colours.get(colour).add(
      String(row.size_code||'—')
    );

    if(row.to_department_code){
      group.nextDepartments.add(
        String(row.to_department_code)
      );
    }

    const rate=Number(row.base_rate||0);
    if(rate>0){
      group.positiveRates.add(
        rate.toFixed(4)
      );
    }

    const payableRate=Number(
      row.enhanced_rate||0
    );
    if(payableRate>0){
      group.payableRates.add(
        payableRate.toFixed(4)
      );
    }

    if(row.rate_source){
      group.rateSources.add(
        String(row.rate_source)
      );
    }

    const mapping=String(
      row.mapping_status||
      '—'
    );
    group.mappingStatuses.set(
      mapping,
      Number(group.mappingStatuses.get(mapping)||0)+1
    );

    group.assignedCap+=Number(
      row.assigned_cap_qty||0
    );
    group.beforeQty+=Number(
      row.submitted_before_qty||0
    );
    group.toEndQty+=Number(
      row.submitted_to_end_qty||0
    );
    group.payableQty+=Number(
      row.payable_qty||0
    );
    group.baseAmount+=Number(
      row.base_amount||0
    );
    group.enhancementAmount+=Number(
      row.enhancement_amount||0
    );

    if(
      row.last_source_at&&
      (
        !group.lastSourceAt||
        new Date(row.last_source_at)>
          new Date(group.lastSourceAt)
      )
    ){
      group.lastSourceAt=row.last_source_at;
    }
  }

  return [...groups.values()].map(group=>{
    group.rateValues=[
      ...group.positiveRates
    ].map(Number).sort((a,b)=>a-b);

    group.payableRateValues=[
      ...group.payableRates
    ].map(Number).sort((a,b)=>a-b);

    group.hasRateConflict=
      group.rateValues.length>1;

    group.groupRate=
      group.rateValues.length===1
        ?group.rateValues[0]
        :0;

    group.groupPayableRate=
      group.payableQty>0
        ?(
          (
            group.baseAmount+
            group.enhancementAmount
          )/group.payableQty
        )
        :(
          group.payableRateValues.length===1
            ?group.payableRateValues[0]
            :0
        );

    group.missingRows=
      group.rows.filter(
        isMissingDetail
      ).length;

    group.missingAssignments=
      new Set(
        group.rows
          .filter(isMissingDetail)
          .map(row=>String(
            row.assignment_id||''
          ))
          .filter(Boolean)
      ).size;

    group.missingCapRows=
      group.rows.filter(
        row=>
          row.mapping_status===
          'MISSING_SIZE_CAP'
      ).length;

    group.representativeRow=
      group.rows.find(
        isMissingDetail
      )||
      group.rows[0];

    return group;
  });
}

function filteredDetailGroups(){
  const query=$('detailSearch')
    .value
    .trim()
    .toLowerCase();

  const missingOnly=Boolean(
    $('detailMissingOnly')?.checked
  );

  return buildDetailGroups()
    .filter(group=>{
      if(
        missingOnly&&
        group.missingRows===0&&
        !group.hasRateConflict
      ){
        return false;
      }

      if(!query)return true;

      const colourSizeText=[
        ...group.colours.entries()
      ].map(([colour,sizes])=>
        `${colour} ${[
          ...sizes
        ].join(' ')}`
      );

      return JSON.stringify([
        group.worker_name,
        group.worker_code,
        group.lot_no,
        group.department_code,
        [...group.nextDepartments],
        colourSizeText,
        [...group.rateSources],
        [...group.mappingStatuses.keys()]
      ]).toLowerCase().includes(query);
    })
    .sort((a,b)=>{
      const workerCompare=String(
        a.worker_name||''
      ).localeCompare(
        String(b.worker_name||''),
        undefined,
        {sensitivity:'base'}
      );
      if(workerCompare)return workerCompare;

      const lotCompare=String(
        a.lot_no||''
      ).localeCompare(
        String(b.lot_no||''),
        undefined,
        {
          numeric:true,
          sensitivity:'base'
        }
      );
      if(lotCompare)return lotCompare;

      return String(
        a.department_code||''
      ).localeCompare(
        String(b.department_code||''),
        undefined,
        {sensitivity:'base'}
      );
    });
}

function colourSizeSummary(group){
  const entries=[
    ...group.colours.entries()
  ].sort(([a],[b])=>
    String(a).localeCompare(
      String(b),
      undefined,
      {
        numeric:true,
        sensitivity:'base'
      }
    )
  );

  const visible=entries.slice(0,10);
  const hidden=entries.length-visible.length;

  return `<div class="collab-colour-size">${
    visible.map(([colour,sizes])=>{
      const ordered=[
        ...sizes
      ].sort((a,b)=>
        String(a).localeCompare(
          String(b),
          undefined,
          {
            numeric:true,
            sensitivity:'base'
          }
        )
      );

      return `<div class="colour-line">
        <span class="colour-code">${safe(colour)}</span>
        <span class="sizes">${safe(
          ordered.join(' · ')
        )}</span>
      </div>`;
    }).join('')
  }${
    hidden>0
      ?`<div class="collab-more">+${hidden} more colour(s)</div>`
      :''
  }</div>`;
}

function groupRateDisplay(group){
  if(group.hasRateConflict){
    return `<span class="group-rate-conflict">CONFLICT · ${
      group.rateValues
        .map(rate=>`₹${money(rate)}`)
        .join(' / ')
    }</span>`;
  }

  if(group.groupRate>0){
    return `<span class="group-rate-ok">₹${money(
      group.groupRate
    )}</span>${
      group.missingAssignments>0
        ?`<span class="group-subnote group-rate-bad">${
          group.missingAssignments
        } assignment missing</span>`
        :''
    }`;
  }

  return '<span class="group-rate-bad">MISSING</span>';
}

function rateSourceDisplay(group){
  const sources=[
    ...group.rateSources
  ];

  if(!sources.length)return '—';
  if(sources.length===1){
    return safe(sources[0]);
  }

  return `<span class="group-rate-conflict">${
    safe(sources.join(' / '))
  }</span>`;
}

function mappingDisplay(group){
  return `<div class="mapping-stack">${
    [...group.mappingStatuses.entries()]
      .map(([status,count])=>{
        const cls=status==='OK'
          ?'ok'
          :(
            status.includes('MISSING')
              ?'bad'
              :'warn'
          );

        return `<span class="${cls}">
          ${safe(status)} · ${count}
        </span>`;
      }).join('')
  }</div>`;
}

function groupRateEditor(group){
  const row=group.representativeRow;

  if(!row?.assignment_id){
    return '<span class="muted">Assignment missing</span>';
  }

  if(!canShowRateEditor(row)){
    return '<span class="muted">View only</span>';
  }

  const value=
    group.groupRate>0&&
    !group.hasRateConflict
      ?group.groupRate.toFixed(4)
      :'';

  const label=
    group.groupRate>0||
    group.hasRateConflict
      ?'UPDATE GROUP + NEXT'
      :'SAVE GROUP + NEXT';

  return `<div class="rate-editor">
    <input
      data-detail-group-rate="${safe(group.key)}"
      type="number"
      min="0.0001"
      step="0.0001"
      value="${safe(value)}"
      placeholder="Group Rate"
      inputmode="decimal">
    <button
      class="btn rate-save"
      data-save-detail-group="${safe(group.key)}"
      data-assignment-id="${safe(
        row.assignment_id
      )}"
      type="button">${safe(label)}</button>
  </div>`;
}

function rawEvaluationTable(group){
  return `<div class="collab-eval-box">
    <div class="collab-eval-title">
      <div>
        <b>Evaluation Table</b>
        <span class="muted">
          · ${safe(group.lot_no)}
          · ${safe(group.department_code)}
          · ${safe(group.worker_name)}
        </span>
      </div>
      <span class="muted">
        ${group.rows.length} raw Colour/Size row(s)
      </span>
    </div>

    <table>
      <thead>
        <tr>
          <th>Colour</th>
          <th>Size</th>
          <th>Assignment ID</th>
          <th>Assigned Cap</th>
          <th>Before PCS</th>
          <th>To End PCS</th>
          <th>Payable PCS</th>
          <th>Actual Rate</th>
          <th>Rate Source</th>
          <th>Payable Rate</th>
          <th>Base ₹</th>
          <th>Enhancement ₹</th>
          <th>Mapping</th>
          <th>Last Submit</th>
        </tr>
      </thead>
      <tbody>${
        group.rows.map(row=>`<tr>
          <td>${safe(
            row.colour_name||
            row.colour_code||
            '—'
          )}</td>
          <td>${safe(row.size_code||'—')}</td>
          <td>${safe(
            row.assignment_id||
            '—'
          )}</td>
          <td>${qty(row.assigned_cap_qty)}</td>
          <td>${qty(
            row.submitted_before_qty
          )}</td>
          <td>${qty(
            row.submitted_to_end_qty
          )}</td>
          <td><b>${qty(
            row.payable_qty
          )}</b></td>
          <td class="money">${money(
            row.base_rate
          )}</td>
          <td>${safe(
            row.rate_source||
            '—'
          )}</td>
          <td class="money">${money(
            row.enhanced_rate
          )}</td>
          <td class="money">${money(
            row.base_amount
          )}</td>
          <td class="money">${money(
            row.enhancement_amount
          )}</td>
          <td class="status-${safe(
            row.mapping_status
          )}">${safe(
            row.mapping_status
          )}</td>
          <td>${safe(localDateTime(
            row.last_source_at
          ))}</td>
        </tr>`).join('')
      }</tbody>
    </table>
  </div>`;
}

function renderDetails(options={}){
  const groups=filteredDetailGroups();
  state.detailGroups=groups;

  const rawRows=groups.reduce(
    (sum,group)=>
      sum+group.rows.length,
    0
  );

  const missingAssignments=groups.reduce(
    (sum,group)=>
      sum+group.missingAssignments,
    0
  );

  const missingGroups=groups.filter(
    group=>
      group.missingAssignments>0||
      group.hasRateConflict
  ).length;

  const missingCaps=groups.reduce(
    (sum,group)=>
      sum+group.missingCapRows,
    0
  );

  $('detailStats').innerHTML=[
    ['Collaborative Groups',groups.length],
    ['Raw Evaluation Rows',rawRows],
    ['Workers',new Set(
      groups.map(group=>group.worker_id)
    ).size],
    ['Payable PCS',qty(
      groups.reduce(
        (sum,group)=>
          sum+group.payableQty,
        0
      )
    )],
    ['Base ₹',money(
      groups.reduce(
        (sum,group)=>
          sum+group.baseAmount,
        0
      )
    )],
    ['Missing / Conflict Groups',missingGroups],
    ['Missing Assignments',missingAssignments],
    ['Missing Cap Rows',missingCaps]
  ].map(([label,value],index)=>
    `<div class="stat ${
      index>=5&&Number(value)>0
        ?'alert'
        :''
    }">
      <small>${safe(label)}</small>
      <strong>${safe(value)}</strong>
    </div>`
  ).join('');

  $('detailBody').innerHTML=groups.length
    ?groups.map(group=>{
      const nextDepartments=[
        ...group.nextDepartments
      ];

      return `
        <tr
          class="collab-summary-row"
          data-detail-group-row="${safe(group.key)}">
          <td>
            <b class="collab-lot">${safe(
              group.lot_no||
              '—'
            )}</b>
          </td>
          <td class="collab-worker">
            <b>${safe(
              group.worker_name||
              group.worker_id||
              '—'
            )}</b>
            <small>${safe(
              group.worker_code||
              '—'
            )}</small>
          </td>
          <td>${safe(
            group.department_code||
            '—'
          )}</td>
          <td>${safe(
            nextDepartments.join(', ')||
            '—'
          )}</td>
          <td>${colourSizeSummary(group)}</td>
          <td>
            <b>${group.assignments.size}</b>
            <span class="group-subnote">
              ${group.rows.length} evaluation row(s)
            </span>
          </td>
          <td>${qty(group.assignedCap)}</td>
          <td>${qty(group.beforeQty)}</td>
          <td>${qty(group.toEndQty)}</td>
          <td><b>${qty(
            group.payableQty
          )}</b></td>
          <td>${groupRateDisplay(group)}</td>
          <td>${rateSourceDisplay(group)}</td>
          <td>${groupRateEditor(group)}</td>
          <td class="money">${money(
            group.groupPayableRate
          )}</td>
          <td class="money"><b>${money(
            group.baseAmount
          )}</b></td>
          <td class="money">${money(
            group.enhancementAmount
          )}</td>
          <td>${mappingDisplay(group)}</td>
          <td>${safe(localDateTime(
            group.lastSourceAt
          ))}</td>
          <td>
            <button
              class="btn detail-toggle"
              data-toggle-evaluation="${safe(group.key)}"
              type="button">VIEW EVALUATION</button>
          </td>
        </tr>

        <tr
          id="detail-eval-${safe(group.key)}"
          class="collab-eval-row hidden">
          <td colspan="19">
            ${rawEvaluationTable(group)}
          </td>
        </tr>`;
    }).join('')
    :'<tr><td colspan="19" class="muted">No collaborative Lot rows.</td></tr>';

  const body=$('detailBody');

  body.querySelectorAll(
    '[data-toggle-evaluation]'
  ).forEach(button=>{
    button.onclick=()=>{
      const key=button.dataset.toggleEvaluation;
      const row=$(`detail-eval-${key}`);

      if(!row)return;

      const opening=row.classList.contains(
        'hidden'
      );
      row.classList.toggle(
        'hidden',
        !opening
      );
      button.textContent=opening
        ?'HIDE EVALUATION'
        :'VIEW EVALUATION';
    };
  });

  body.querySelectorAll(
    '[data-save-detail-group]'
  ).forEach(button=>{
    button.onclick=()=>saveDetailGroupRate(
      button
    );
  });

  body.querySelectorAll(
    '[data-detail-group-rate]'
  ).forEach(input=>{
    input.addEventListener(
      'keydown',
      event=>{
        if(event.key!=='Enter')return;

        event.preventDefault();

        const key=
          input.dataset.detailGroupRate;

        const button=body.querySelector(
          `[data-save-detail-group="${
            CSS.escape(key)
          }"]`
        );

        if(
          button&&
          !button.disabled
        ){
          saveDetailGroupRate(button);
        }
      }
    );
  });

  let focusIndex=null;

  if(Number.isInteger(options.focusIndex)){
    focusIndex=options.focusIndex;
  }else if(options.focusFirst){
    focusIndex=0;
  }

  if(focusIndex!==null){
    requestAnimationFrame(
      ()=>focusDetailGroupRate(focusIndex)
    );
  }
}

function focusDetailGroupRate(index){
  const inputs=[
    ...$('detailBody').querySelectorAll(
      '[data-detail-group-rate]'
    )
  ];

  if(!inputs.length)return;

  const safeIndex=Math.max(
    0,
    Math.min(
      index,
      inputs.length-1
    )
  );

  const input=inputs[safeIndex];

  input.scrollIntoView({
    block:'center',
    inline:'nearest',
    behavior:'smooth'
  });
  input.focus();
  input.select();
}

async function saveDetailGroupRate(button){
  const key=button.dataset.saveDetailGroup;
  const assignmentId=
    button.dataset.assignmentId;

  const group=state.detailGroups?.find(
    item=>item.key===key
  );

  const input=$('detailBody').querySelector(
    `[data-detail-group-rate="${
      CSS.escape(key)
    }"]`
  );

  const allInputs=[
    ...$('detailBody').querySelectorAll(
      '[data-detail-group-rate]'
    )
  ];

  const currentIndex=Math.max(
    0,
    allInputs.indexOf(input)
  );

  const rate=Number(input?.value);

  if(!group){
    say(
      'detailMessage',
      'Collaborative group reload required.',
      'error'
    );
    return;
  }

  if(!assignmentId){
    say(
      'detailMessage',
      'Assignment ID missing.',
      'error'
    );
    return;
  }

  if(
    !Number.isFinite(rate)||
    rate<=0
  ){
    say(
      'detailMessage',
      'Group Actual Rate 0 se zyada honi chahiye.',
      'error'
    );
    input?.focus();
    input?.select();
    return;
  }

  const rateChanged=
    group.hasRateConflict||
    (
      group.groupRate>0&&
      Math.abs(
        group.groupRate-rate
      )>0.0000001
    );

  let reason=
    'Missing Lot+Department group Actual Rate filled from Collaborative Lot / PCS Details';

  if(rateChanged){
    reason=prompt(
      `Complete group rate correction reason · ${
        group.lot_no
      } · ${group.department_code}`,
      'Authorized complete Lot+Department Actual Rate correction'
    )||'';

    if(!reason.trim())return;
  }else if(group.groupRate>0){
    reason=
      'Existing Lot+Department rate applied to remaining missing assignments';
  }

  const nextFocusIndex=
    $('detailMissingOnly')?.checked
      ?currentIndex
      :currentIndex+1;

  try{
    button.disabled=true;
    if(input)input.disabled=true;

    say(
      'detailMessage',
      `Lot ${group.lot_no} · Department ${
        group.department_code
      } की group rate save हो रही है…`,
      'info'
    );

    const saved=await rpc(
      'rr_upm_set_assignment_actual_rate_v772',
      {
        p_assignment_id:assignmentId,
        p_actual_rate:rate,
        p_reason:reason.trim()
      }
    );

    const runId=await rpc(
      'rr_piece_payroll_calculate_v779',
      {
        p_period_month:monthStart(
          $('detailMonth').value
        ),
        p_data_mode:
          $('detailMode').value
      }
    );

    await loadDetails({
      focusIndex:nextFocusIndex
    });
    await loadPayroll();

    say(
      'detailMessage',
      `DONE · Lot ${
        saved?.lot_no||
        group.lot_no
      } · Department ${
        saved?.department_code||
        group.department_code
      } · Group Rate ₹${money(
        saved?.group_rate||
        rate
      )}. ${
        Number(
          saved?.updated_assignments||
          group.assignments.size
        )
      } assignment(s) updated; ${
        Number(
          saved?.auto_filled_assignments||
          group.missingAssignments
        )
      } missing rate(s) auto-filled. Payroll recalculated · Run ${runId}. Cursor next unresolved collaborative group पर पहुँच गया है.`,
      'success'
    );
  }catch(error){
    say(
      'detailMessage',
      err(error),
      'error'
    );

    if(input){
      input.disabled=false;
      input.focus();
      input.select();
    }
  }finally{
    button.disabled=false;
  }
}

async function loadDetails(options={}){
  try{
    const month=monthStart(
      $('detailMonth').value
    );
    const mode=$('detailMode').value;

    const runResult=await state.client
      .from(
        'rr_piece_payroll_run_board_v779'
      )
      .select('id')
      .eq('period_month',month)
      .eq('data_mode',mode)
      .maybeSingle();

    if(runResult.error){
      throw runResult.error;
    }

    if(!runResult.data){
      state.details=[];
      renderDetails(options);
      say(
        'detailMessage',
        'Calculate payroll first.',
        'info'
      );
      return;
    }

    const detailResult=await state.client
      .from(
        'rr_piece_payroll_detail_board_v779'
      )
      .select('*')
      .eq(
        'piece_run_id',
        runResult.data.id
      )
      .order('worker_name')
      .order('lot_no')
      .order('department_code')
      .order('colour_code')
      .order('size_code');

    if(detailResult.error){
      throw detailResult.error;
    }

    state.details=
      detailResult.data||[];

    renderDetails(options);

    say(
      'detailMessage',
      `${state.details.length} raw UPM Colour/Size rows loaded and collaborative Lot groups में evaluated.`,
      'success'
    );
  }catch(error){
    say(
      'detailMessage',
      err(error),
      'error'
    );
  }
}

function calendarDates(from,to){const out=[];for(let d=new Date(`${from}T00:00:00Z`),e=new Date(`${to}T00:00:00Z`);d<=e;d.setUTCDate(d.getUTCDate()+1))out.push(d.toISOString().slice(0,10));return out}
function attendanceCalendarRows(){if(!state.attendanceWorkerId||!$('attendanceMonth').value)return state.attendance;const [mf,mt]=monthRange($('attendanceMonth').value);const worker=state.workers.find(w=>String(w.worker_id)===String(state.attendanceWorkerId));const from=worker?.effective_from&&worker.effective_from>mf?worker.effective_from:mf;const to=worker?.effective_to&&worker.effective_to<mt?worker.effective_to:mt;const byDate=new Map(state.attendance.map(x=>[x.attendance_date,x]));const holidays=new Map(state.holidays.filter(h=>h.is_active!==false).map(h=>[h.holiday_date,h]));return calendarDates(from,to).map(date=>{if(byDate.has(date))return byDate.get(date);const monday=dayName(date)==='Mon';const holiday=holidays.get(date);return {id:null,attendance_date:date,status:holiday?'HOLIDAY':monday?'WEEKLY_OFF':'ABSENT',check_in_at:null,check_out_at:null,is_weekly_off:monday,is_holiday:Boolean(holiday),revision_no:0,locked_piece_run_id:null,is_virtual:true}})}
function renderAttendance(){const rows=attendanceCalendarRows();const count=s=>rows.filter(x=>x.status===s).length;$('attendanceStats').innerHTML=[['Present',count('PRESENT')],['Absent / Missing',count('ABSENT')],['Half Day',count('HALF_DAY')],['Paid Leave',count('LEAVE_PAID')],['Weekly Off',count('WEEKLY_OFF')],['Holiday',count('HOLIDAY')],['Incomplete',count('INCOMPLETE')]].map(([a,b],i)=>`<div class="stat ${i===6&&b>0?'alert':''}"><small>${a}</small><strong>${b}</strong></div>`).join('');$('attendanceBody').innerHTML=rows.length?rows.map(x=>`<tr><td>${safe(x.attendance_date)}</td><td>${safe(dayName(x.attendance_date))}</td><td class="status-${safe(x.status)}">${safe(x.status)}${x.is_virtual?' · default':''}</td><td>${safe(localTime(x.check_in_at))}</td><td>${safe(localTime(x.check_out_at))}</td><td>${x.is_weekly_off?'YES':'—'}</td><td>${x.is_holiday?'YES':'—'}</td><td>${x.revision_no||0}</td><td>${x.locked_piece_run_id?'LOCKED':'—'}</td><td>${x.locked_piece_run_id?'—':`<button class="btn" data-edit-attendance="${safe(x.attendance_date)}" type="button">Edit</button>`}</td></tr>`).join(''):'<tr><td colspan="10" class="muted">Select a Piece-Rate worker.</td></tr>';$('attendanceBody').querySelectorAll('[data-edit-attendance]').forEach(b=>b.onclick=()=>editAttendance(b.dataset.editAttendance))}
async function loadAttendance(){try{await loadWorkers($('attendanceMode').value);if(!state.attendanceWorkerId){state.attendance=[];renderAttendance();say('attendanceMessage','Search and select a Piece-Rate worker.','info');return}const [from,to]=monthRange($('attendanceMonth').value);const a=await state.client.from('rr_piece_attendance_board_v779').select('*').eq('worker_id',state.attendanceWorkerId).eq('data_mode',$('attendanceMode').value).gte('attendance_date',from).lte('attendance_date',to).order('attendance_date');if(a.error)throw a.error;state.attendance=a.data||[];try{const h=await state.client.from('rr_payroll_holidays_v778').select('*').gte('holiday_date',from).lte('holiday_date',to).order('holiday_date');state.holidays=h.error?[]:(h.data||[])}catch{state.holidays=[]}renderAttendance();say('attendanceMessage',`${state.attendance.length} saved attendance rows loaded.`,'success')}catch(e){say('attendanceMessage',err(e),'error')}}
function clearAttendanceForm(){$('attendanceDate').value=todayDate();$('attendanceStatus').value='AUTO';$('checkInTime').value='';$('checkOutTime').value='';$('attendanceSource').value='MANUAL';$('attendanceHoliday').checked=false;$('attendanceRemarks').value='';$('attendanceReason').value='';syncSelects()}
function editAttendance(date){const x=attendanceCalendarRows().find(r=>r.attendance_date===date);$('attendanceDate').value=date;$('attendanceStatus').value=x?.status||'AUTO';$('checkInTime').value=x?.check_in_at?new Date(x.check_in_at).toLocaleTimeString('en-GB',{timeZone:'Asia/Kolkata',hour:'2-digit',minute:'2-digit'}):'';$('checkOutTime').value=x?.check_out_at?new Date(x.check_out_at).toLocaleTimeString('en-GB',{timeZone:'Asia/Kolkata',hour:'2-digit',minute:'2-digit'}):'';$('attendanceSource').value=x?.source_type||'MANUAL';$('attendanceHoliday').checked=Boolean(x?.is_holiday);$('attendanceRemarks').value=x?.remarks||'';$('attendanceReason').value=x?.id?'Attendance correction':'Attendance entry';syncSelects();scrollTo({top:$('attendanceForm').offsetTop-20,behavior:'smooth'})}
async function saveAttendance(e){e.preventDefault();try{if(!state.attendanceWorkerId)throw new Error('Select a Piece-Rate worker.');const date=$('attendanceDate').value,status=$('attendanceStatus').value;await rpc('rr_piece_attendance_save_v779',{p_worker_id:state.attendanceWorkerId,p_attendance_date:date,p_check_in_at:localISO(date,$('checkInTime').value),p_check_out_at:localISO(date,$('checkOutTime').value),p_status:status,p_is_holiday:$('attendanceHoliday').checked,p_source_type:$('attendanceSource').value,p_remarks:$('attendanceRemarks').value||null,p_reason:$('attendanceReason').value,p_data_mode:$('attendanceMode').value});clearAttendanceForm();await loadAttendance();say('attendanceMessage','Piece attendance saved with audit history.','success')}catch(e2){say('attendanceMessage',err(e2),'error')}}

function renderAdjustments(){$('adjustmentBody').innerHTML=state.adjustments.length?state.adjustments.map(x=>`<tr><td>${safe(x.worker_name||x.worker_id)}</td><td>${safe(x.period_month)}</td><td>${safe(x.adjustment_type)}</td><td class="money">${money(x.amount)}</td><td>${safe(x.source_key||'—')}</td><td>${safe(x.reason)}</td><td>${safe(x.status)}</td><td>${x.included_piece_run_id?'YES':'—'}</td><td>${x.status==='POSTED'?`<button class="btn danger" data-cancel-adj="${x.id}" type="button">Cancel</button>`:'—'}</td></tr>`).join(''):'<tr><td colspan="9" class="muted">No Piece adjustments.</td></tr>';$('adjustmentBody').querySelectorAll('[data-cancel-adj]').forEach(b=>b.onclick=()=>cancelAdjustment(b.dataset.cancelAdj))}
async function loadAdjustments(){try{await loadWorkers($('adjustmentMode').value);const r=await state.client.from('rr_piece_adjustment_board_v779').select('*').eq('period_month',monthStart($('adjustmentMonth').value)).eq('data_mode',$('adjustmentMode').value).order('created_at',{ascending:false});if(r.error)throw r.error;state.adjustments=r.data||[];renderAdjustments();say('adjustmentMessage',`${state.adjustments.length} Piece adjustments loaded.`,'success')}catch(e){say('adjustmentMessage',err(e),'error')}}
async function saveAdjustment(e){e.preventDefault();try{if(!state.adjustmentWorkerId)throw new Error('Search and select a Piece-Rate worker.');await rpc('rr_piece_add_adjustment_v779',{p_worker_id:state.adjustmentWorkerId,p_period_month:monthStart($('adjustmentMonth').value),p_adjustment_type:$('adjustmentType').value,p_amount:Number($('adjustmentAmount').value),p_reason:$('adjustmentReason').value,p_data_mode:$('adjustmentMode').value,p_source_key:$('adjustmentSourceKey').value||null});$('adjustmentAmount').value='';$('adjustmentReason').value='';$('adjustmentSourceKey').value='';await loadAdjustments();say('adjustmentMessage','Adjustment posted. Recalculate Piece payroll to include it.','success')}catch(e2){say('adjustmentMessage',err(e2),'error')}}
async function cancelAdjustment(id){try{const reason=prompt('Cancellation reason','Wrong Piece adjustment entry')||'';if(!reason)return;await rpc('rr_piece_cancel_adjustment_v779',{p_adjustment_id:id,p_reason:reason});await loadAdjustments();say('adjustmentMessage','Adjustment cancelled.','success')}catch(e){say('adjustmentMessage',err(e),'error')}}

function ledgerMonthText(value){
  if(!value)return '—';
  return new Date(`${value}T00:00:00+05:30`).toLocaleDateString(
    'en-IN',
    {
      timeZone:'Asia/Kolkata',
      month:'short',
      year:'numeric'
    }
  );
}

function filteredLedgerDues(){
  const query=$('ledgerSearch').value.trim().toLowerCase();
  const status=$('ledgerStatus').value;
  const month=$('ledgerMonth').value;

  return state.ledgerDues.filter(row=>{
    if(month&&String(row.period_month||'').slice(0,7)!==month){
      return false;
    }

    if(
      status!=='ALL'&&
      upper(row.payment_status)!==status
    ){
      return false;
    }

    if(
      state.ledgerFocusWorkerId&&
      String(row.worker_id)!==String(state.ledgerFocusWorkerId)
    ){
      return false;
    }

    if(!query)return true;

    return JSON.stringify([
      row.worker_name,
      row.worker_code,
      row.department_code,
      row.source_module,
      row.due_reference,
      row.due_remarks,
      row.period_month,
      row.payment_status
    ]).toLowerCase().includes(query);
  });
}

function filteredLedgerEntries(){
  const query=$('ledgerSearch').value.trim().toLowerCase();
  const month=$('ledgerMonth').value;
  const dueWorkerIds=new Set(
    filteredLedgerDues().map(row=>String(row.worker_id))
  );

  return state.ledgerEntries.filter(row=>{
    if(month&&String(row.period_month||'').slice(0,7)!==month){
      return false;
    }

    if(
      state.ledgerFocusWorkerId&&
      String(row.worker_id)!==String(state.ledgerFocusWorkerId)
    ){
      return false;
    }

    if(
      !state.ledgerFocusWorkerId&&
      $('ledgerStatus').value!=='ALL'&&
      !dueWorkerIds.has(String(row.worker_id))
    ){
      return false;
    }

    if(!query)return true;

    return JSON.stringify([
      row.worker_name,
      row.worker_code,
      row.department_code,
      row.entry_type,
      row.payment_mode,
      row.reference_no,
      row.remarks,
      row.period_month,
      row.status
    ]).toLowerCase().includes(query);
  });
}

function renderLedger(){
  const dues=filteredLedgerDues();
  const entries=filteredLedgerEntries();

  const totalDue=dues.reduce(
    (sum,row)=>sum+Number(row.due_amount||0),
    0
  );
  const totalPaid=dues.reduce(
    (sum,row)=>sum+Number(row.paid_amount||0),
    0
  );
  const totalBalance=dues.reduce(
    (sum,row)=>sum+Number(row.balance_amount||0),
    0
  );

  $('ledgerStats').innerHTML=[
    ['Salary Due Rows',dues.length],
    ['Workers',new Set(dues.map(row=>String(row.worker_id))).size],
    ['Total Due ₹',money(totalDue)],
    ['Total Paid ₹',money(totalPaid)],
    ['Outstanding ₹',money(totalBalance)],
    ['Unpaid',dues.filter(row=>row.payment_status==='UNPAID').length],
    ['Partial',dues.filter(row=>row.payment_status==='PARTIAL').length],
    ['Paid',dues.filter(row=>row.payment_status==='PAID').length]
  ].map(([label,value],index)=>
    `<div class="stat ${
      (
        index===4&&totalBalance>0
      )||
      (
        index===5&&Number(value)>0
      )||
      (
        index===6&&Number(value)>0
      )
        ?'alert'
        :''
    }">
      <small>${safe(label)}</small>
      <strong>${safe(value)}</strong>
    </div>`
  ).join('');

  $('ledgerDueBody').innerHTML=dues.length
    ?dues.map(row=>{
      const balance=Number(row.balance_amount||0);
      const statusClass=paymentStatusClass(row.payment_status);

      return `<tr>
        <td>${safe(ledgerMonthText(row.period_month))}</td>
        <td>
          <b>${safe(row.worker_name||row.worker_id)}</b>
          <br>
          <small class="muted">${safe(row.worker_code||'—')}</small>
        </td>
        <td>${safe(row.department_code||'—')}</td>
        <td>${safe(row.payroll_category||'—')}</td>
        <td>${safe(row.source_module||'—')}</td>
        <td class="money"><b>${money(row.due_amount)}</b></td>
        <td class="money">${money(row.paid_amount)}</td>
        <td class="money ledger-balance">${money(balance)}</td>
        <td class="${statusClass}">${safe(row.payment_status)}</td>
        <td>${safe(localDateTime(row.last_payment_at))}</td>
        <td>
          ${
            balance>0.005
              ?`<button
                  class="btn success ledger-payment-button"
                  data-ledger-pay="${safe(row.due_entry_id)}"
                  type="button">PAY / PART PAY</button>`
              :'<span class="ledger-paid">SETTLED</span>'
          }
        </td>
        <td>
          <button
            class="btn"
            data-ledger-worker="${safe(row.worker_id)}"
            type="button">OPEN LEDGER</button>
        </td>
      </tr>`;
    }).join('')
    :'<tr><td colspan="12" class="muted">No matching worker salary due rows.</td></tr>';

  $('ledgerEntryBody').innerHTML=entries.length
    ?entries.map(row=>{
      const canReverse=
        row.entry_type==='PAYMENT'&&
        row.status==='POSTED'&&
        !state.ledgerEntries.some(item=>
          item.entry_type==='PAYMENT_REVERSAL'&&
          item.status==='POSTED'&&
          String(item.related_entry_id)===String(row.id)
        );

      return `<tr>
        <td>${safe(row.entry_date||'—')}</td>
        <td>
          <b>${safe(row.worker_name||row.worker_id)}</b>
          <br>
          <small class="muted">${safe(row.worker_code||'—')}</small>
        </td>
        <td>${safe(ledgerMonthText(row.period_month))}</td>
        <td>${safe(row.entry_type)}</td>
        <td class="money">${money(row.due_or_credit_amount)}</td>
        <td class="money">${money(row.payment_or_debit_amount)}</td>
        <td class="money ledger-balance">${money(row.running_balance)}</td>
        <td>${safe(row.payment_mode||'—')}</td>
        <td>${safe(row.reference_no||'—')}</td>
        <td>${safe(row.remarks||'—')}</td>
        <td>${safe(row.status)}</td>
        <td>
          ${
            canReverse
              ?`<button
                  class="btn danger"
                  data-reverse-payment="${safe(row.id)}"
                  type="button">REVERSE PAYMENT</button>`
              :'—'
          }
        </td>
      </tr>`;
    }).join('')
    :'<tr><td colspan="12" class="muted">No matching ledger entries.</td></tr>';

  $('ledgerDueBody').querySelectorAll('[data-ledger-pay]').forEach(
    button=>button.onclick=()=>openPayment(button.dataset.ledgerPay)
  );

  $('ledgerDueBody').querySelectorAll('[data-ledger-worker]').forEach(
    button=>button.onclick=()=>{
      state.ledgerFocusWorkerId=button.dataset.ledgerWorker;
      $('ledgerSearch').value='';
      renderLedger();
      say(
        'ledgerMessage',
        'Worker-specific ledger opened. Clear Worker Focus to show all workers.',
        'info'
      );
    }
  );

  $('ledgerEntryBody').querySelectorAll('[data-reverse-payment]').forEach(
    button=>button.onclick=()=>reversePayment(
      button.dataset.reversePayment
    )
  );
}

async function loadLedger(){
  try{
    const mode=$('ledgerMode').value;

    const [dueResult,entryResult]=await Promise.all([
      state.client
        .from('rr_worker_salary_due_board_v781')
        .select('*')
        .eq('data_mode',mode)
        .order('period_month',{ascending:false})
        .order('worker_name',{ascending:true}),

      state.client
        .from('rr_worker_salary_ledger_board_v781')
        .select('*')
        .eq('data_mode',mode)
        .order('entry_date',{ascending:false})
        .order('created_at',{ascending:false})
        .limit(5000)
    ]);

    if(dueResult.error)throw dueResult.error;
    if(entryResult.error)throw entryResult.error;

    state.ledgerDues=dueResult.data||[];
    state.ledgerEntries=entryResult.data||[];

    renderLedger();

    say(
      'ledgerMessage',
      `${state.ledgerDues.length} worker Salary Due rows and ${state.ledgerEntries.length} ledger entries loaded.`,
      'success'
    );
  }catch(error){
    say('ledgerMessage',err(error),'error');
  }
}

async function openPayment(dueEntryId,defaults={}){
  showTab('ledger');

  if(defaults.mode){
    $('ledgerMode').value=defaults.mode;
  }
  if(defaults.month){
    $('ledgerMonth').value=defaults.month;
  }

  syncSelects();

  if(
    !state.ledgerDues.some(
      row=>String(row.due_entry_id)===String(dueEntryId)
    )
  ){
    await loadLedger();
  }

  const due=state.ledgerDues.find(
    row=>String(row.due_entry_id)===String(dueEntryId)
  );

  if(!due){
    say(
      'ledgerMessage',
      'Salary due row not found. Refresh Worker Ledger.',
      'error'
    );
    return;
  }

  state.ledgerSelectedDueId=due.due_entry_id;
  state.ledgerFocusWorkerId=due.worker_id;

  $('ledgerSelectedDue').innerHTML=`
    <b>${safe(due.worker_name||due.worker_id)}</b>
    · ${safe(due.worker_code||'—')}
    · ${safe(due.department_code||'—')}
    · ${safe(ledgerMonthText(due.period_month))}
    <br>
    Salary Due ₹${money(due.due_amount)}
    · Paid ₹${money(due.paid_amount)}
    · <b>Balance ₹${money(due.balance_amount)}</b>
  `;

  $('ledgerPaymentAmount').value=Number(
    due.balance_amount||0
  ).toFixed(2);

  $('ledgerPaymentDate').value=todayDate();
  $('ledgerPaymentMode').value='CASH';
  $('ledgerPaymentReference').value='';
  $('ledgerPaymentRemarks').value='';
  syncSelects();

  $('ledgerPaymentPanel').classList.remove('hidden');

  renderLedger();

  $('ledgerPaymentPanel').scrollIntoView({
    behavior:'smooth',
    block:'start'
  });

  setTimeout(()=>{
    $('ledgerPaymentAmount').focus();
    $('ledgerPaymentAmount').select();
  },250);
}

function closePaymentForm(){
  state.ledgerSelectedDueId='';
  $('ledgerPaymentPanel').classList.add('hidden');
  $('ledgerPaymentForm').reset();
  $('ledgerPaymentDate').value=todayDate();
  syncSelects();
}

async function postLedgerPayment(event){
  event.preventDefault();

  try{
    if(!state.ledgerSelectedDueId){
      throw new Error('Select a worker Salary Due.');
    }

    const result=await rpc(
      'rr_worker_salary_payment_post_v781',
      {
        p_due_entry_id:state.ledgerSelectedDueId,
        p_amount:Number($('ledgerPaymentAmount').value),
        p_payment_date:$('ledgerPaymentDate').value,
        p_payment_mode:$('ledgerPaymentMode').value,
        p_reference_no:$('ledgerPaymentReference').value,
        p_remarks:$('ledgerPaymentRemarks').value||null
      }
    );

    closePaymentForm();
    await Promise.all([
      loadLedger(),
      loadPayroll()
    ]);

    say(
      'ledgerMessage',
      `Payment posted: ${result.worker_name||'Worker'} · ₹${money(result.payment_amount)} · Remaining ₹${money(result.new_balance)}.`,
      'success'
    );
  }catch(error){
    say('ledgerMessage',err(error),'error');
  }
}

async function reversePayment(paymentId){
  try{
    const reason=prompt(
      'Payment reversal reason',
      'Wrong payment / duplicate payment / payment entry correction'
    )||'';

    if(!reason)return;

    const result=await rpc(
      'rr_worker_salary_payment_reverse_v781',
      {
        p_payment_entry_id:paymentId,
        p_reason:reason
      }
    );

    await Promise.all([
      loadLedger(),
      loadPayroll()
    ]);

    say(
      'ledgerMessage',
      `Payment reversed: ${result.worker_name||'Worker'} · ₹${money(result.reversed_amount)}. Balance restored.`,
      'success'
    );
  }catch(error){
    say('ledgerMessage',err(error),'error');
  }
}

function clearLedgerWorkerFocus(){
  state.ledgerFocusWorkerId='';
  renderLedger();
}

function renderMapping(){const rows=state.mapping;$('mappingBody').innerHTML=rows.length?rows.map(x=>`<tr><td><b>${safe(x.check_code)}</b></td><td><span class="badge ${x.result==='PASS'?'good':x.result==='FAIL'?'bad':'warn'}">${safe(x.result)}</span></td><td>${safe(x.details)}</td></tr>`).join(''):'<tr><td colspan="3" class="muted">Run Mapping Audit.</td></tr>';$('logicCards').innerHTML=[['Monthly Salary','V778 remains Monthly-only. No V778 table/function is altered.'],['Piece Salary','V779 reads submitted UPM handoffs and frozen assignment rates.'],['Double-Pay Guard','Cumulative handoff quantity is capped by assignment-size and prior period usage is subtracted.'],['Attendance','Piece attendance is reporting-only and does not alter PCS wage.'],['Damage','UPM damage is reference-only until audited DAMAGE_DEBIT is posted.'],['Salary Head','rr_salary_head_bind_v779 is ready for the future unified dashboard.']].map(([a,b])=>`<div class="logic-card"><b>${safe(a)}</b><small>${safe(b)}</small></div>`).join('')}
async function runCompatibility(){try{const rows=await rpc('rr_piece_compatibility_report_v779',{});state.mapping=rows||[];renderMapping();const fail=state.mapping.filter(x=>x.result==='FAIL').length;say('mappingMessage',fail?`${fail} required mapping checks failed.`:'All V779 compatibility checks passed. Static PASS still requires TEST-mode data verification.',fail?'error':'success')}catch(e){say('mappingMessage',err(e),'error')}}

function showTab(tab){
  ['payroll','details','attendance','adjustments','ledger','mapping'].forEach(t=>{
    $(`tab-${t}`).classList.toggle('hidden',t!==tab);
    document.querySelector(`[data-tab="${t}"]`)?.classList.toggle('active',t===tab);
  });

  if(tab==='payroll')loadPayroll();
  if(tab==='details')loadDetails();
  if(tab==='adjustments')loadAdjustments();
  if(tab==='ledger')loadLedger();
  if(tab==='mapping'&&!state.mapping.length)runCompatibility();
}
function bind(){
  attendanceCombo=new SearchCombo(
    $('attendanceWorkerCombo'),
    row=>{
      state.attendanceWorkerId=row.worker_id;
      loadAttendance();
    }
  );

  adjustmentCombo=new SearchCombo(
    $('adjustmentWorkerCombo'),
    row=>{
      state.adjustmentWorkerId=row.worker_id;
    }
  );

  $('tabs').querySelectorAll('button').forEach(
    button=>button.onclick=()=>showTab(button.dataset.tab)
  );

  $('calculatePayroll').onclick=calculatePayroll;
  $('approvePayroll').onclick=approvePayroll;
  $('reopenPayroll').onclick=reopenPayroll;
  $('markPaid').onclick=markPaid;
  $('refreshPayroll').onclick=loadPayroll;
  $('payrollMonth').onchange=loadPayroll;
  $('payrollMode').onchange=loadPayroll;

  $('detailMonth').onchange=loadDetails;
  $('detailMode').onchange=loadDetails;
  $('detailSearch').oninput=renderDetails;
  $('detailMissingOnly').onchange=renderDetails;
  $('loadDetails').onclick=loadDetails;

  $('loadAttendance').onclick=loadAttendance;
  $('attendanceForm').onsubmit=saveAttendance;
  $('clearAttendanceForm').onclick=clearAttendanceForm;

  $('attendanceMode').onchange=()=>{
    state.attendanceWorkerId='';
    attendanceCombo.setValue('');
    loadAttendance();
  };

  $('attendanceMonth').onchange=()=>{
    if(state.attendanceWorkerId)loadAttendance();
  };

  $('adjustmentForm').onsubmit=saveAdjustment;
  $('refreshAdjustments').onclick=loadAdjustments;

  $('adjustmentMode').onchange=()=>{
    state.adjustmentWorkerId='';
    adjustmentCombo.setValue('');
    loadAdjustments();
  };

  $('adjustmentMonth').onchange=loadAdjustments;

  $('loadLedger').onclick=()=>{
    state.ledgerFocusWorkerId='';
    loadLedger();
  };

  $('ledgerMode').onchange=()=>{
    state.ledgerFocusWorkerId='';
    loadLedger();
  };

  $('ledgerMonth').onchange=()=>{
    state.ledgerFocusWorkerId='';
    renderLedger();
  };

  $('ledgerStatus').onchange=renderLedger;

  $('ledgerSearch').oninput=()=>{
    state.ledgerFocusWorkerId='';
    renderLedger();
  };

  $('ledgerPaymentForm').onsubmit=postLedgerPayment;
  $('cancelLedgerPayment').onclick=closePaymentForm;

  $('runCompatibility').onclick=runCompatibility;

  upgradeSelects();
}

async function boot(){try{state.client=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;if(!state.client)throw new Error('Supabase client unavailable. Check config.js.');if(window.RR?.requireRoles)state.auth=await RR.requireRoles(['owner','admin','account','manager','payroll','hr']);else{const s=await state.client.auth.getSession();if(!s.data?.session)throw new Error('Login required.')}bind();const m=todayMonth();$('payrollMonth').value=m;$('detailMonth').value=m;$('attendanceMonth').value=m;$('adjustmentMonth').value=m;$('ledgerMonth').value=m;$('ledgerPaymentDate').value=todayDate();$('attendanceDate').value=todayDate();await loadWorkers('REAL');await Promise.all([loadPayroll(),runCompatibility()]);$('accessBadge').textContent=`ACCESS OK · ${upper(state.auth?.role_code||state.auth?.profile?.role_code||'AUTH')}`;$('accessBadge').className='badge good';window.RR?.startAccessGuard?.()}catch(e){console.error(e);$('accessBadge').textContent='ACCESS ERROR';$('accessBadge').className='badge bad';say('payrollMessage',err(e),'error')}}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot);else boot();
})();
