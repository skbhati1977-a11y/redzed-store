(()=>{
'use strict';

const VERSION='772.2';
const $=id=>document.getElementById(id);
const safe=v=>String(v??'').replace(/[&<>"']/g,c=>({
  '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'
}[c]));
const upper=v=>String(v||'').trim().toUpperCase();
const money=v=>Number(v||0).toLocaleString('en-IN',{
  minimumFractionDigits:2,
  maximumFractionDigits:4
});
const qty=v=>Number(v||0).toLocaleString('en-IN',{
  minimumFractionDigits:0,
  maximumFractionDigits:3
});
const errorText=e=>[e?.message,e?.details,e?.hint,e?.code].filter(Boolean).join(' — ')||'Unknown error';

const state={
  client:null,
  rows:[],
  filtered:[],
  loading:false
};

function getClient(){
  return window.supabaseClient||
    window.supabaseDb||
    window.redzedSupabase||
    window.sb||
    window.supabase?.client||
    null;
}

async function rpc(name,payload={}){
  const client=state.client||getClient();
  if(!client)throw new Error('Supabase client unavailable. Check config.js.');
  const r=await client.rpc(name,payload);
  if(r.error)throw r.error;
  return r.data;
}

function currentLotNo(){
  const identity=$('identity');
  if(identity){
    const boxes=[...identity.querySelectorAll('.box')];
    for(const box of boxes){
      const label=upper(box.querySelector('small')?.textContent);
      if(label==='LOT NO'){
        const clone=box.cloneNode(true);
        clone.querySelector('small')?.remove();
        const value=clone.textContent.trim();
        if(value)return upper(value);
      }
    }
    const m=identity.textContent.match(/LOT\s*NO\s*([A-Z0-9-]+)/i);
    if(m?.[1])return upper(m[1]);
  }
  const search=$('search')?.value?.trim();
  return search?upper(search):'';
}

function installStyles(){
  if($('rrV7722Styles'))return;
  const style=document.createElement('style');
  style.id='rrV7722Styles';
  style.textContent=`
  #rrActiveRateModalV7722{
    position:fixed;inset:0;background:#000d;z-index:9999;
    display:flex;align-items:flex-end;justify-content:center;
  }
  #rrActiveRateModalV7722.rr-hidden{display:none!important}
  #rrActiveRateModalV7722 .rr-sheet{
    width:min(1500px,100%);height:min(96vh,1100px);
    background:#10131a;border:1px solid #39414d;
    border-radius:18px 18px 0 0;padding:12px;overflow:auto;color:#fff;
  }
  #rrActiveRateModalV7722 .rr-head,
  #rrActiveRateModalV7722 .rr-tools{
    display:flex;align-items:center;justify-content:space-between;gap:8px;flex-wrap:wrap;
  }
  #rrActiveRateModalV7722 .rr-tools{
    position:sticky;top:-12px;z-index:3;background:#10131af5;padding:10px 0;
  }
  #rrActiveRateModalV7722 input,
  #rrActiveRateModalV7722 button{
    background:#242934;color:#fff;border:1px solid #39414d;
    border-radius:9px;padding:10px;font:inherit;
  }
  #rrActiveRateModalV7722 button{font-weight:800;cursor:pointer}
  #rrActiveRateModalV7722 button:disabled{opacity:.5;cursor:not-allowed}
  #rrActiveRateModalV7722 .rr-load{background:#174936;border-color:#318b65}
  #rrActiveRateModalV7722 .rr-close{background:#481d24;border-color:#8c3c49}
  #rrActiveRateModalV7722 .rr-search{flex:1;min-width:240px}
  #rrActiveRateModalV7722 .rr-note{
    padding:9px 10px;border-left:3px solid #ffc857;
    background:#281f0d;border-radius:8px;color:#ffe3a0;margin:8px 0;
  }
  #rrActiveRateModalV7722 .rr-msg{min-height:24px;padding:8px 0;color:#56efb2}
  #rrActiveRateModalV7722 .rr-msg.rr-error{color:#ff8d95}
  #rrActiveRateModalV7722 .rr-wrap{overflow:auto;border:1px solid #303641;border-radius:12px}
  #rrActiveRateModalV7722 table{width:100%;border-collapse:collapse;min-width:1180px}
  #rrActiveRateModalV7722 th,
  #rrActiveRateModalV7722 td{
    padding:8px;border-bottom:1px solid #2a303a;text-align:left;white-space:nowrap
  }
  #rrActiveRateModalV7722 th{position:sticky;top:76px;background:#20252e;z-index:2}
  #rrActiveRateModalV7722 .rr-bad{color:#ff8d95;font-weight:900}
  #rrActiveRateModalV7722 .rr-ok{color:#56efb2;font-weight:900}
  #rrActiveRateModalV7722 .rr-rate-editor{display:flex;gap:6px;align-items:center}
  #rrActiveRateModalV7722 .rr-rate-editor input{width:115px}
  #rrActiveRateModalV7722 .rr-rate-editor button{background:#174936;border-color:#318b65}
  #rrActiveRateModalV7722 .rr-stats{display:flex;gap:8px;flex-wrap:wrap;margin:8px 0}
  #rrActiveRateModalV7722 .rr-stat{
    background:#171b23;border:1px solid #303641;border-radius:10px;padding:8px 10px
  }
  #rrActiveRateModalV7722 .rr-stat small{display:block;color:#98a2b3}
  #rrActiveRateModalV7722 .rr-stat b{font-size:18px}
  #rrActiveRateV7722{background:#493915;border-color:#8a6b2b}
  @media(max-width:700px){
    #rrActiveRateModalV7722 .rr-sheet{height:99vh}
    #rrActiveRateModalV7722 .rr-tools{align-items:stretch}
    #rrActiveRateModalV7722 .rr-search{width:100%}
  }`;
  document.head.appendChild(style);
}

function installModal(){
  if($('rrActiveRateModalV7722'))return;
  const modal=document.createElement('div');
  modal.id='rrActiveRateModalV7722';
  modal.className='rr-hidden';
  modal.innerHTML=`
    <section class="rr-sheet">
      <div class="rr-head">
        <div>
          <h2 style="margin:0">ACTIVE ASSIGNMENT ACTUAL RATE · V${VERSION}</h2>
          <div style="color:#98a2b3;margin-top:3px">
            Exact Lot + Department + Worker + Colour assignment rate
          </div>
        </div>
        <button id="rrCloseActiveRateV7722" class="rr-close" type="button">CLOSE</button>
      </div>

      <div class="rr-note">
        यह Costing Department Rate नहीं है। Submit और PCS salary के लिए केवल exact
        Assignment Actual Rate save होगी। Standard Rate या Department Rate fallback नहीं लगेगा।
      </div>

      <div class="rr-tools">
        <input id="rrActiveRateSearchV7722" class="rr-search"
          placeholder="Search Lot / Department / Worker / Colour">
        <label style="display:flex;gap:7px;align-items:center">
          <input id="rrMissingOnlyV7722" type="checkbox" checked style="width:20px;height:20px">
          Missing Rate only
        </label>
        <button id="rrLoadActiveRateV7722" class="rr-load" type="button">LOAD ACTIVE ASSIGNMENTS</button>
      </div>

      <div id="rrActiveRateStatsV7722" class="rr-stats"></div>
      <div id="rrActiveRateMsgV7722" class="rr-msg"></div>

      <div class="rr-wrap">
        <table>
          <thead>
            <tr>
              <th>Lot</th><th>Department</th><th>Worker</th><th>Worker Code</th>
              <th>Colour</th><th>Status</th><th>Assigned PCS</th>
              <th>Current Actual Rate</th><th>Rate Filled By</th><th>Fill / Edit</th>
            </tr>
          </thead>
          <tbody id="rrActiveRateBodyV7722"></tbody>
        </table>
      </div>
    </section>`;
  document.body.appendChild(modal);

  $('rrCloseActiveRateV7722').onclick=()=>modal.classList.add('rr-hidden');
  modal.addEventListener('click',e=>{
    if(e.target===modal)modal.classList.add('rr-hidden');
  });
  $('rrLoadActiveRateV7722').onclick=loadActiveAssignments;
  $('rrActiveRateSearchV7722').addEventListener('input',renderActiveAssignments);
  $('rrMissingOnlyV7722').addEventListener('change',renderActiveAssignments);
}

function installButtons(){
  if(!$('rrSubmittedWorkV772')){
    const submitted=document.createElement('button');
    submitted.id='rrSubmittedWorkV772';
    submitted.type='button';
    submitted.textContent='SUBMITTED WORK';
    submitted.title='Department / Worker wise submitted PCS and Assignment Actual Rate';
    submitted.dataset.version=VERSION;
    submitted.onclick=()=>{location.href='real-upm-submitted-work-v772.html?v=7722'};
    const bar=document.querySelector('.modulebar')||document.querySelector('.toolbar')||document.querySelector('.top');
    if(bar)bar.appendChild(submitted);
    else{
      submitted.style.cssText='position:fixed;right:14px;bottom:14px;z-index:45;background:#174936;border-color:#318b65';
      document.body.appendChild(submitted);
    }
  }

  if(!$('rrActiveRateV7722')){
    const active=document.createElement('button');
    active.id='rrActiveRateV7722';
    active.type='button';
    active.textContent='ACTIVE RATE';
    active.title='Current active assignments का exact Actual Rate fill/edit करें';
    active.dataset.version=VERSION;
    active.onclick=openActiveRate;
    const bar=document.querySelector('.modulebar')||document.querySelector('.toolbar')||document.querySelector('.top');
    if(bar)bar.appendChild(active);
    else{
      active.style.cssText='position:fixed;right:14px;bottom:64px;z-index:45';
      document.body.appendChild(active);
    }
  }
}

function say(text,type=''){
  const el=$('rrActiveRateMsgV7722');
  if(!el)return;
  el.textContent=text||'';
  el.className=`rr-msg ${type==='error'?'rr-error':''}`.trim();
}

function openActiveRate(){
  const modal=$('rrActiveRateModalV7722');
  modal.classList.remove('rr-hidden');
  const lot=currentLotNo();
  if(lot)$('rrActiveRateSearchV7722').value=lot;
  loadActiveAssignments();
}

async function loadActiveAssignments(){
  if(state.loading)return;
  state.loading=true;
  const button=$('rrLoadActiveRateV7722');
  try{
    button.disabled=true;
    say('Active assignments load ho rahe hain…');
    state.client=getClient();
    if(!state.client)throw new Error('Supabase client unavailable. Check config.js.');

    const r=await state.client
      .from('rr_upm_work_assignments_v8')
      .select('id,lot_no,department_code,worker_id,worker_code,worker_name_snapshot,colour_code,colour_name,assigned_qty,status,actual_rate,rate_filled_by_name,rate_filled_at,assigned_at')
      .in('status',['ASSIGNED','IN_PROGRESS'])
      .order('assigned_at',{ascending:false})
      .limit(5000);

    if(r.error)throw r.error;
    state.rows=r.data||[];
    renderActiveAssignments();
    say(`${state.rows.length} active assignments loaded.`);
  }catch(e){
    say(errorText(e),'error');
  }finally{
    state.loading=false;
    button.disabled=false;
  }
}

function filteredRows(){
  const q=$('rrActiveRateSearchV7722').value.trim().toLowerCase();
  const missingOnly=$('rrMissingOnlyV7722').checked;
  return state.rows.filter(x=>{
    if(missingOnly&&Number(x.actual_rate||0)>0)return false;
    if(!q)return true;
    return JSON.stringify([
      x.lot_no,x.department_code,x.worker_name_snapshot,x.worker_code,
      x.colour_code,x.colour_name,x.status
    ]).toLowerCase().includes(q);
  });
}

function renderActiveAssignments(){
  const rows=filteredRows();
  state.filtered=rows;
  const missing=rows.filter(x=>Number(x.actual_rate||0)<=0).length;
  const totalQty=rows.reduce((a,x)=>a+Number(x.assigned_qty||0),0);

  $('rrActiveRateStatsV7722').innerHTML=[
    ['Rows',rows.length],
    ['Missing Rate',missing],
    ['Assigned PCS',qty(totalQty)],
    ['Departments',new Set(rows.map(x=>upper(x.department_code))).size],
    ['Workers',new Set(rows.map(x=>String(x.worker_id))).size]
  ].map(([a,b])=>`<div class="rr-stat"><small>${safe(a)}</small><b>${safe(b)}</b></div>`).join('');

  $('rrActiveRateBodyV7722').innerHTML=rows.length?rows.map(x=>{
    const current=Number(x.actual_rate||0);
    return `<tr>
      <td><b>${safe(x.lot_no||'—')}</b></td>
      <td>${safe(x.department_code||'—')}</td>
      <td><b>${safe(x.worker_name_snapshot||'—')}</b></td>
      <td>${safe(x.worker_code||'—')}</td>
      <td>${safe(x.colour_name||x.colour_code||'—')} · ${safe(x.colour_code||'—')}</td>
      <td>${safe(x.status||'—')}</td>
      <td>${qty(x.assigned_qty)}</td>
      <td class="${current>0?'rr-ok':'rr-bad'}">${current>0?'₹'+money(current):'MISSING'}</td>
      <td>${safe(x.rate_filled_by_name||'—')}</td>
      <td>
        <div class="rr-rate-editor">
          <input data-rr-rate="${safe(x.id)}" type="number"
            min="0.0001" step="0.0001"
            value="${current>0?safe(current):''}"
            placeholder="Actual Rate">
          <button data-rr-save="${safe(x.id)}" type="button">${current>0?'UPDATE':'FILL RATE'}</button>
        </div>
      </td>
    </tr>`;
  }).join(''):'<tr><td colspan="10" style="padding:24px;text-align:center;color:#98a2b3">No matching active assignments.</td></tr>';

  $('rrActiveRateBodyV7722').querySelectorAll('[data-rr-save]').forEach(button=>{
    button.onclick=()=>saveActiveRate(button);
  });
}

async function saveActiveRate(button){
  const id=button.dataset.rrSave;
  const input=$('rrActiveRateBodyV7722').querySelector(`[data-rr-rate="${CSS.escape(id)}"]`);
  const row=state.rows.find(x=>String(x.id)===String(id));
  const rate=Number(input?.value);

  if(!Number.isFinite(rate)||rate<=0){
    say('Actual Rate 0 se zyada hona chahiye.','error');
    input?.focus();
    return;
  }

  const defaultReason=Number(row?.actual_rate||0)>0
    ?'Authorized active assignment Actual Rate correction'
    :'Missing active assignment Actual Rate filled before Submit';

  const reason=prompt(
    `Reason · ${row?.lot_no||''} · ${row?.department_code||''} · ${row?.worker_name_snapshot||''} · ${row?.colour_code||''}`,
    defaultReason
  )||'';

  if(!reason.trim())return;

  try{
    button.disabled=true;
    say('Assignment Actual Rate save ho rahi hai…');
    await rpc('rr_upm_set_assignment_actual_rate_v772',{
      p_assignment_id:id,
      p_actual_rate:rate,
      p_reason:reason.trim()
    });
    await loadActiveAssignments();
    say(
      `Saved: ${row?.lot_no||''} · ${row?.department_code||''} · ${row?.worker_name_snapshot||''} · ${row?.colour_code||''} · ₹${money(rate)}`
    );
  }catch(e){
    say(errorText(e),'error');
  }finally{
    button.disabled=false;
  }
}

function install(){
  installStyles();
  installModal();
  installButtons();
}

if(document.readyState==='loading'){
  document.addEventListener('DOMContentLoaded',install);
}else{
  install();
}
})();
