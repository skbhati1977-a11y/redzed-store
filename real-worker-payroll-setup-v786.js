(()=>{
'use strict';

const $=id=>document.getElementById(id);
const state={
  client:null,
  workers:[],
  filtered:[],
  profiles:[],
  shifts:[],
  selectedWorker:null
};

const safe=value=>String(value??'').replace(
  /[&<>"']/g,
  character=>({
    '&':'&amp;','<':'&lt;','>':'&gt;',
    '"':'&quot;',"'":'&#039;'
  })[character]
);

const upper=value=>String(value||'').trim().toUpperCase();

const errorText=error=>[
  error?.message,error?.details,error?.hint,error?.code
].filter(Boolean).join(' — ')||'Unknown error';

function say(text,type=''){
  $('message').textContent=text||'';
  $('message').className=`message ${type}`.trim();
}

function indiaToday(){
  return new Intl.DateTimeFormat(
    'en-CA',
    {timeZone:'Asia/Kolkata',year:'numeric',month:'2-digit',day:'2-digit'}
  ).format(new Date());
}

async function rpc(name,payload={}){
  const result=await state.client.rpc(name,payload);
  if(result.error)throw result.error;
  return result.data;
}

function currentMode(){
  return upper($('dataMode').value||'TEST');
}

function categoryChanged(){
  const salaried=$('workerCategory').value==='SALARIED';
  $('salaryFields').classList.toggle('hidden',!salaried);
  $('pieceFields').classList.toggle('hidden',salaried);
  $('monthlySalary').required=salaried;
  $('shiftId').required=salaried;
}

function renderWorkers(){
  const query=$('workerSearch').value.trim().toLowerCase();

  state.filtered=state.workers.filter(worker=>{
    if(!query)return true;
    return JSON.stringify([
      worker.worker_name,
      worker.worker_code,
      worker.department_code,
      worker.department_name,
      worker.role_code
    ]).toLowerCase().includes(query);
  });

  $('workerResults').innerHTML=state.filtered.length
    ?state.filtered.map(worker=>`
      <button type="button"
        class="worker ${
          state.selectedWorker?.worker_id===worker.worker_id?'active':''
        }"
        data-worker-id="${safe(worker.worker_id)}">
        <b>${safe(worker.worker_name||'Unnamed Worker')}</b>
        <small>
          ${safe(worker.worker_code||'—')} ·
          ${safe(worker.department_name||worker.department_code||'—')}
        </small>
      </button>
    `).join('')
    :'<div style="padding:14px;color:#aeb8c8">No worker found.</div>';

  document.querySelectorAll('[data-worker-id]').forEach(button=>{
    button.onclick=()=>selectWorker(button.dataset.workerId);
  });
}

async function loadWorkers(){
  const rows=await rpc(
    'rr_upm_worker_list_v8_3',
    {p_department_code:null}
  );

  state.workers=Array.isArray(rows)?rows:[];
  renderWorkers();
}

async function loadProfiles(){
  const result=await state.client
    .from('rr_worker_payroll_board_v777_3')
    .select('*');

  if(result.error)throw result.error;
  state.profiles=result.data||[];
}

async function loadShifts(){
  const result=await state.client
    .from('rr_shift_options_v777_3')
    .select('*')
    .order('shift_name',{ascending:true});

  if(result.error)throw result.error;
  state.shifts=result.data||[];

  $('shiftId').innerHTML=
    '<option value="">Select Shift</option>'+
    state.shifts.map(shift=>`
      <option value="${safe(shift.shift_id)}">
        ${safe(shift.shift_name||shift.shift_code||'Shift')}
        · ${safe(shift.duty_start||'')}–${safe(shift.duty_end||'')}
      </option>
    `).join('');
}

function matchingProfile(workerId,mode){
  return state.profiles
    .filter(profile=>
      String(profile.worker_id)===String(workerId)&&
      upper(profile.data_mode)===upper(mode)
    )
    .sort((a,b)=>
      String(b.effective_from||'').localeCompare(
        String(a.effective_from||'')
      )
    )[0]||null;
}

function resetForm(){
  $('workerCategory').value='PIECE_RATE';
  $('effectiveFrom').value=indiaToday();
  $('effectiveTo').value='';
  $('monthlySalary').value='';
  $('shiftId').value='';
  $('advanceLimitType').value='';
  $('advanceLimitValue').value='';
  $('lateApplicable').checked=true;
  $('otApplicable').checked=true;
  $('holidayApplicable').checked=true;
  $('graceOffset').checked=true;
  $('reason').value='Worker payroll category confirmed';
  categoryChanged();
}

function fillProfile(profile){
  if(!profile){
    resetForm();
    $('profileStatus').textContent='NEW PROFILE';
    return;
  }

  $('workerCategory').value=profile.worker_category||'PIECE_RATE';
  $('effectiveFrom').value=profile.effective_from||indiaToday();
  $('effectiveTo').value=profile.effective_to||'';
  $('monthlySalary').value=Number(profile.monthly_salary||0)||'';
  $('shiftId').value=profile.shift_id||'';
  $('advanceLimitType').value=
    profile.salaried_advance_limit_type||'';
  $('advanceLimitValue').value=
    profile.salaried_advance_limit_value??'';
  $('lateApplicable').checked=
    profile.late_deduction_applicable!==false;
  $('otApplicable').checked=
    profile.overtime_applicable!==false;
  $('holidayApplicable').checked=
    profile.holiday_extra_applicable!==false;
  $('graceOffset').checked=
    profile.grace_offset_against_ot!==false;
  $('reason').value='Existing worker payroll profile update';
  $('profileStatus').textContent=
    `${upper(profile.worker_category)} · FROM ${profile.effective_from||'—'}`;

  categoryChanged();
}

function refreshSelectedProfile(){
  const worker=state.selectedWorker;
  if(!worker)return;

  const mode=currentMode();
  $('selectedMode').textContent=mode;

  const profile=matchingProfile(worker.worker_id,mode);
  fillProfile(profile);
}

function selectWorker(workerId){
  state.selectedWorker=state.workers.find(
    worker=>String(worker.worker_id)===String(workerId)
  )||null;

  if(!state.selectedWorker)return;

  $('workerId').value=state.selectedWorker.worker_id;
  $('selectedWorker').textContent=
    `${state.selectedWorker.worker_name} · ${
      state.selectedWorker.worker_code||'—'
    }`;

  $('saveProfile').disabled=false;
  renderWorkers();
  refreshSelectedProfile();
}

async function setInitialMode(){
  const requestedMode=upper(
    new URLSearchParams(location.search).get('mode')||''
  );

  if(window.RRDataModeReadyPromise){
    await window.RRDataModeReadyPromise;
  }

  if(window.RRDataMode){
    await RRDataMode.applyInitialMode(
      'dataMode',
      requestedMode
    );
  }else{
    $('dataMode').value='TEST';
  }

  $('selectedMode').textContent=currentMode();
}

async function saveProfile(event){
  event.preventDefault();

  if(!state.selectedWorker){
    say('पहले worker select करें.','error');
    return;
  }

  const category=$('workerCategory').value;
  const salaried=category==='SALARIED';
  const reason=$('reason').value.trim();

  if(reason.length<5){
    say('Reason minimum 5 characters required.','error');
    return;
  }

  if(salaried&&Number($('monthlySalary').value||0)<=0){
    say('Monthly Salary amount required.','error');
    return;
  }

  if(salaried&&!$('shiftId').value){
    say('Monthly Salary worker के लिए Shift required.','error');
    return;
  }

  const button=$('saveProfile');
  button.disabled=true;
  say('Saving worker salary profile…','info');

  try{
    await rpc(
      'rr_set_worker_payroll_profile_v777_3',
      {
        p_worker_id:state.selectedWorker.worker_id,
        p_worker_category:category,
        p_monthly_salary:salaried
          ?Number($('monthlySalary').value||0)
          :0,
        p_shift_id:salaried?$('shiftId').value:null,
        p_late_deduction_applicable:
          $('lateApplicable').checked,
        p_overtime_applicable:
          $('otApplicable').checked,
        p_holiday_extra_applicable:
          $('holidayApplicable').checked,
        p_grace_offset_against_ot:
          $('graceOffset').checked,
        p_exception_reason:reason,
        p_salaried_advance_limit_type:salaried
          ?($('advanceLimitType').value||null)
          :null,
        p_salaried_advance_limit_value:salaried
          ?(
            $('advanceLimitValue').value===''
              ?null
              :Number($('advanceLimitValue').value)
          )
          :null,
        p_effective_from:$('effectiveFrom').value,
        p_effective_to:$('effectiveTo').value||null,
        p_data_mode:currentMode(),
        p_reason:reason
      }
    );

    await loadProfiles();
    refreshSelectedProfile();

    say(
      `${state.selectedWorker.worker_name}: ${category==='SALARIED'?'MONTHLY SALARY':'PCS RATE'} profile saved in ${currentMode()} mode.`,
      'success'
    );
  }catch(error){
    say(errorText(error),'error');
  }finally{
    button.disabled=false;
  }
}

function bind(){
  $('workerSearch').oninput=renderWorkers;
  $('workerCategory').onchange=categoryChanged;
  $('profileForm').onsubmit=saveProfile;

  $('dataMode').addEventListener('change',()=>{
    window.setTimeout(()=>{
      $('selectedMode').textContent=currentMode();
      refreshSelectedProfile();
    },0);
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
      throw new Error('Supabase client unavailable.');
    }

    if(window.RR?.requireOwner){
      await RR.requireOwner();
    }else{
      throw new Error('Owner/Admin access helper unavailable.');
    }

    bind();
    await setInitialMode();
    await Promise.all([
      loadWorkers(),
      loadProfiles(),
      loadShifts()
    ]);

    $('accessBadge').textContent='OWNER ACCESS OK';
    say('Worker select करके simple salary profile set करें.','success');
  }catch(error){
    $('accessBadge').textContent='ACCESS ERROR';
    say(errorText(error),'error');
  }
}

if(document.readyState==='loading'){
  document.addEventListener('DOMContentLoaded',boot);
}else{
  boot();
}
})();
