(()=>{
'use strict';
window.REDZED_PCS_RATE_PAYROLL_VERSION='779.2.2';

const state={client:null,auth:null,workers:[],run:null,lines:[],details:[],attendance:[],holidays:[],adjustments:[],mapping:[],attendanceWorkerId:'',adjustmentWorkerId:''};
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
    this.input.addEventListener('input',()=>this.render(false));
    this.input.addEventListener('keydown',e=>this.key(e));
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
    this.list.querySelectorAll('[data-si]').forEach(el=>el.onclick=()=>this.pick(Number(el.dataset.si)));
  }
  pick(i){
    const o=this.filtered[i];
    if(!o)return;
    this.select.value=o.value;
    this.sync();
    this.list.classList.add('hidden');
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

function renderPayroll(){
  const r=state.run,lines=state.lines;
  $('payrollStats').innerHTML=[
    ['Status',r?.status||'NOT CALCULATED'],['Workers',r?.worker_count||0],['Payable PCS',qty(r?.total_payable_qty)],['Exceptions',r?.incomplete_worker_count||0],['Gross ₹',money(r?.gross_total)],['Deduction ₹',money(r?.deduction_total)],['Net ₹',money(r?.net_total)]
  ].map(([a,b],i)=>`<div class="stat ${i===3&&Number(b)>0?'alert':''}"><small>${a}</small><strong>${safe(b)}</strong></div>`).join('');
  $('payrollBody').innerHTML=lines.length?lines.map(x=>`<tr>
    <td><b>${safe(x.worker_name||x.worker_id)}</b><br><small class="muted">${safe(x.worker_code||'—')}</small></td>
    <td>${safe(x.department_code||'—')}</td><td>${safe(x.compensation_mode||'PCS_ONLY')}</td>
    <td>${qty(x.payable_qty)}</td><td class="money">${money(x.average_base_rate)}</td><td class="money">${money(x.base_piece_earning)}</td>
    <td class="money">${money(x.rate_enhancement_earning)}</td><td class="money">${money(x.monthly_flat_incentive)}</td><td class="money">${money(x.adjustment_earning)}</td>
    <td class="money">${money(x.adjustment_deduction)}</td><td class="money">${money(x.advance_deduction)}</td><td class="money">${money(x.damage_reference_amount)}</td>
    <td>${qty(x.attendance_present_days)}</td><td>${qty(x.attendance_absent_days)}</td><td class="${Number(x.missing_rate_rows)>0?'status-MISSING_RATE':''}">${x.missing_rate_rows}</td>
    <td class="${Number(x.missing_cap_rows)>0?'status-MISSING_SIZE_CAP':''}">${x.missing_cap_rows}</td><td class="money"><b>${money(x.net_pay)}</b></td>
    <td><button class="btn" data-worker-detail="${safe(x.worker_name||'')}" type="button">Open</button></td>
  </tr>`).join(''):'<tr><td colspan="18" class="muted">Calculate Piece payroll to create immutable snapshot lines.</td></tr>';
  $('payrollBody').querySelectorAll('[data-worker-detail]').forEach(b=>b.onclick=()=>{showTab('details');$('detailSearch').value=b.dataset.workerDetail;loadDetails()});
  const locked=['APPROVED','PAID'].includes(r?.status);
  $('calculatePayroll').disabled=locked;$('approvePayroll').disabled=!r||r.status!=='CALCULATED'||Number(r.incomplete_worker_count)>0;$('reopenPayroll').disabled=!locked;$('markPaid').disabled=!r||r.status!=='APPROVED';
}

async function loadPayroll(){
  try{
    const month=monthStart($('payrollMonth').value),mode=$('payrollMode').value;
    const rr=await state.client.from('rr_piece_payroll_run_board_v779').select('*').eq('period_month',month).eq('data_mode',mode).maybeSingle();if(rr.error)throw rr.error;
    state.run=rr.data||null;
    if(state.run){const lr=await state.client.from('rr_piece_payroll_line_board_v779').select('*').eq('piece_run_id',state.run.id).order('worker_name');if(lr.error)throw lr.error;state.lines=lr.data||[]}else state.lines=[];
    renderPayroll();say('payrollMessage',state.run?`Run loaded: ${state.run.status}`:'No calculated run for this month.','success');
  }catch(e){say('payrollMessage',err(e),'error')}
}
async function calculatePayroll(){try{say('payrollMessage','Reading UPM handoff, assignment-size cap and frozen rates…','info');const id=await rpc('rr_piece_payroll_calculate_v779',{p_period_month:monthStart($('payrollMonth').value),p_data_mode:$('payrollMode').value});await loadPayroll();say('payrollMessage',`Piece payroll calculated. Run ${id}`,'success')}catch(e){say('payrollMessage',err(e),'error')}}
async function approvePayroll(){try{if(!state.run)throw new Error('Calculate payroll first.');const reason=prompt('Approval reason','UPM PCS, rates and adjustments verified')||'';if(!reason)return;await rpc('rr_piece_payroll_approve_v779',{p_piece_run_id:state.run.id,p_reason:reason});await loadPayroll();say('payrollMessage','Piece payroll approved and locked.','success')}catch(e){say('payrollMessage',err(e),'error')}}
async function reopenPayroll(){try{if(!state.run)throw new Error('Run missing.');const reason=prompt('OWNER reopen reason','Rate / UPM / adjustment correction required')||'';if(!reason)return;await rpc('rr_piece_payroll_reopen_v779',{p_piece_run_id:state.run.id,p_reason:reason});await loadPayroll();say('payrollMessage','Piece payroll reopened. Correct data and recalculate.','success')}catch(e){say('payrollMessage',err(e),'error')}}
async function markPaid(){try{if(!state.run)throw new Error('Run missing.');const ref=prompt('Payment reference','Bank transfer / Cash voucher')||'';if(!ref)return;await rpc('rr_piece_payroll_mark_paid_v779',{p_piece_run_id:state.run.id,p_payment_reference:ref});await loadPayroll();say('payrollMessage','Piece payroll marked PAID.','success')}catch(e){say('payrollMessage',err(e),'error')}}

function renderDetails(){
  const qv=$('detailSearch').value.trim().toLowerCase();const rows=state.details.filter(x=>!qv||JSON.stringify([x.worker_name,x.worker_code,x.lot_no,x.department_code,x.to_department_code,x.colour_code,x.colour_name,x.size_code]).toLowerCase().includes(qv));
  $('detailStats').innerHTML=[['Rows',rows.length],['Workers',new Set(rows.map(x=>x.worker_id)).size],['Payable PCS',qty(rows.reduce((a,x)=>a+Number(x.payable_qty||0),0))],['Base ₹',money(rows.reduce((a,x)=>a+Number(x.base_amount||0),0))],['Enhancement ₹',money(rows.reduce((a,x)=>a+Number(x.enhancement_amount||0),0))],['Missing Actual Rate',rows.filter(x=>x.mapping_status==='MISSING_ACTUAL_RATE'||x.mapping_status==='MISSING_RATE').length],['Missing Cap',rows.filter(x=>x.mapping_status==='MISSING_SIZE_CAP').length]].map(([a,b],i)=>`<div class="stat ${i>4&&Number(b)>0?'alert':''}"><small>${a}</small><strong>${safe(b)}</strong></div>`).join('');
  $('detailBody').innerHTML=rows.length?rows.map(x=>`<tr><td>${safe(x.worker_name||x.worker_id)}</td><td><b>${safe(x.lot_no||'—')}</b></td><td>${safe(x.department_code||'—')}</td><td>${safe(x.to_department_code||'—')}</td><td>${safe(x.colour_name||x.colour_code||'—')}</td><td>${safe(x.size_code||'—')}</td><td>${qty(x.assigned_cap_qty)}</td><td>${qty(x.submitted_before_qty)}</td><td>${qty(x.submitted_to_end_qty)}</td><td><b>${qty(x.payable_qty)}</b></td><td class="money">${money(x.base_rate)}</td><td>${safe(x.rate_source)}</td><td class="money">${money(x.enhanced_rate)}</td><td class="money">${money(x.base_amount)}</td><td class="money">${money(x.enhancement_amount)}</td><td class="status-${safe(x.mapping_status)}">${safe(x.mapping_status)}</td><td>${safe(localDateTime(x.last_source_at))}</td></tr>`).join(''):'<tr><td colspan="17" class="muted">No detail rows.</td></tr>';
}
async function loadDetails(){try{const month=monthStart($('detailMonth').value),mode=$('detailMode').value;const rr=await state.client.from('rr_piece_payroll_run_board_v779').select('id').eq('period_month',month).eq('data_mode',mode).maybeSingle();if(rr.error)throw rr.error;if(!rr.data){state.details=[];renderDetails();say('detailMessage','Calculate payroll first.','info');return}const d=await state.client.from('rr_piece_payroll_detail_board_v779').select('*').eq('piece_run_id',rr.data.id).order('worker_name').order('lot_no').order('department_code').order('size_code');if(d.error)throw d.error;state.details=d.data||[];renderDetails();say('detailMessage',`${state.details.length} UPM mapping rows loaded.`,'success')}catch(e){say('detailMessage',err(e),'error')}}

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

function renderMapping(){const rows=state.mapping;$('mappingBody').innerHTML=rows.length?rows.map(x=>`<tr><td><b>${safe(x.check_code)}</b></td><td><span class="badge ${x.result==='PASS'?'good':x.result==='FAIL'?'bad':'warn'}">${safe(x.result)}</span></td><td>${safe(x.details)}</td></tr>`).join(''):'<tr><td colspan="3" class="muted">Run Mapping Audit.</td></tr>';$('logicCards').innerHTML=[['Monthly Salary','V778 remains Monthly-only. No V778 table/function is altered.'],['Piece Salary','V779 reads submitted UPM handoffs and frozen assignment rates.'],['Double-Pay Guard','Cumulative handoff quantity is capped by assignment-size and prior period usage is subtracted.'],['Attendance','Piece attendance is reporting-only and does not alter PCS wage.'],['Damage','UPM damage is reference-only until audited DAMAGE_DEBIT is posted.'],['Salary Head','rr_salary_head_bind_v779 is ready for the future unified dashboard.']].map(([a,b])=>`<div class="logic-card"><b>${safe(a)}</b><small>${safe(b)}</small></div>`).join('')}
async function runCompatibility(){try{const rows=await rpc('rr_piece_compatibility_report_v779',{});state.mapping=rows||[];renderMapping();const fail=state.mapping.filter(x=>x.result==='FAIL').length;say('mappingMessage',fail?`${fail} required mapping checks failed.`:'All V779 compatibility checks passed. Static PASS still requires TEST-mode data verification.',fail?'error':'success')}catch(e){say('mappingMessage',err(e),'error')}}

function showTab(tab){['payroll','details','attendance','adjustments','mapping'].forEach(t=>{$(`tab-${t}`).classList.toggle('hidden',t!==tab);document.querySelector(`[data-tab="${t}"]`)?.classList.toggle('active',t===tab)});if(tab==='payroll')loadPayroll();if(tab==='details')loadDetails();if(tab==='adjustments')loadAdjustments();if(tab==='mapping'&&!state.mapping.length)runCompatibility()}
function bind(){attendanceCombo=new SearchCombo($('attendanceWorkerCombo'),row=>{state.attendanceWorkerId=row.worker_id;loadAttendance()});adjustmentCombo=new SearchCombo($('adjustmentWorkerCombo'),row=>{state.adjustmentWorkerId=row.worker_id});$('tabs').querySelectorAll('button').forEach(b=>b.onclick=()=>showTab(b.dataset.tab));$('calculatePayroll').onclick=calculatePayroll;$('approvePayroll').onclick=approvePayroll;$('reopenPayroll').onclick=reopenPayroll;$('markPaid').onclick=markPaid;$('refreshPayroll').onclick=loadPayroll;$('payrollMonth').onchange=loadPayroll;$('payrollMode').onchange=loadPayroll;$('detailMonth').onchange=loadDetails;$('detailMode').onchange=loadDetails;$('detailSearch').oninput=renderDetails;$('loadDetails').onclick=loadDetails;$('loadAttendance').onclick=loadAttendance;$('attendanceForm').onsubmit=saveAttendance;$('clearAttendanceForm').onclick=clearAttendanceForm;$('attendanceMode').onchange=()=>{state.attendanceWorkerId='';attendanceCombo.setValue('');loadAttendance()};$('attendanceMonth').onchange=()=>state.attendanceWorkerId&&loadAttendance();$('adjustmentForm').onsubmit=saveAdjustment;$('refreshAdjustments').onclick=loadAdjustments;$('adjustmentMode').onchange=()=>{state.adjustmentWorkerId='';adjustmentCombo.setValue('');loadAdjustments()};$('adjustmentMonth').onchange=loadAdjustments;$('runCompatibility').onclick=runCompatibility;upgradeSelects()}

async function boot(){try{state.client=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;if(!state.client)throw new Error('Supabase client unavailable. Check config.js.');if(window.RR?.requireRoles)state.auth=await RR.requireRoles(['owner','admin','account','manager','payroll','hr']);else{const s=await state.client.auth.getSession();if(!s.data?.session)throw new Error('Login required.')}bind();const m=todayMonth();$('payrollMonth').value=m;$('detailMonth').value=m;$('attendanceMonth').value=m;$('adjustmentMonth').value=m;$('attendanceDate').value=todayDate();await loadWorkers('REAL');await Promise.all([loadPayroll(),runCompatibility()]);$('accessBadge').textContent=`ACCESS OK · ${upper(state.auth?.role_code||state.auth?.profile?.role_code||'AUTH')}`;$('accessBadge').className='badge good';window.RR?.startAccessGuard?.()}catch(e){console.error(e);$('accessBadge').textContent='ACCESS ERROR';$('accessBadge').className='badge bad';say('payrollMessage',err(e),'error')}}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot);else boot();
})();
