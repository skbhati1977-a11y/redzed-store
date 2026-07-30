(() => {
'use strict';
const VERSION='9.0.0',$=id=>document.getElementById(id);
const safe=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const state={client:null,lotId:'',lotNo:'',department:'',context:[],selected:new Set(),workers:[],commonWorkerId:'',actualRate:null};
const client=()=>window.supabaseClient||window.sb;
async function rpc(name,args){const {data,error}=await state.client.rpc(name,args);if(error)throw error;return data;}
const qtyOf=r=>Number(r?.cutting_qty??r?.cut_qty??r?.qty??r?.total_qty??0);
const locked=r=>Boolean(r?.is_assigned??r?.is_locked);
function injectStyles(){if($('rrAssignV85Styles'))return;const s=document.createElement('style');s.id='rrAssignV85Styles';s.textContent=`
.rr-assign-open{background:#274b79!important;border-color:#4a83c2!important}.rr-assign-sheet{width:min(980px,100%);max-height:94vh;overflow:auto}
.rr-assign-grid{display:grid;grid-template-columns:1fr 1fr;gap:10px}.rr-colour-toolbar{display:flex;gap:8px;flex-wrap:wrap;margin:12px 0}
.rr-colour-pick{display:flex;gap:8px;flex-wrap:wrap}.rr-colour-chip{border:1px solid #454550;background:#17171d;color:#fff;border-radius:999px;padding:9px 12px;font-weight:900}
.rr-colour-chip.selected{background:#8e2632;border-color:#e05a68}.rr-colour-chip.locked{opacity:.55;cursor:not-allowed;text-decoration:line-through}
.rr-assign-row{border:1px solid #383842;border-radius:13px;padding:12px;margin:10px 0;background:#111116}.rr-assign-row-head{display:flex;justify-content:space-between;gap:10px;align-items:center;flex-wrap:wrap}
.rr-size-line{display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin:9px 0}.rr-size-pill{border:1px solid #383842;border-radius:999px;padding:6px 9px;white-space:nowrap}
.rr-worker-line{display:grid;grid-template-columns:minmax(260px,1fr) 170px 170px;gap:10px;align-items:end}.rr-worker-line select,.rr-worker-line input{width:100%}
.rr-assigned-banner{border:1px solid #2f8654;background:#102319;padding:10px;border-radius:10px;margin:10px 0}
@media(max-width:760px){.rr-assign-grid,.rr-worker-line{grid-template-columns:1fr}.rr-assign-sheet{height:100vh;max-height:100vh;border-radius:0}}`;document.head.appendChild(s);}
function injectModal(){if($('rrAssignV8Modal'))return;const w=document.createElement('div');w.id='rrAssignV8Modal';w.className='modal hidden';w.innerHTML=`
<form id="rrAssignV8Form" class="sheet rr-assign-sheet"><div class="top"><div><small style="color:#d9a93d;font-weight:900">WORK ASSIGN V8.5</small>
<h2 style="margin:4px 0">Assign Work — <span id="rrAssignLotNo">—</span></h2></div><button type="button" id="rrAssignClose">Close</button></div>
<div class="rr-assign-grid"><label class="field"><span>Department</span><select id="rrAssignDept" required></select></label>
<label class="field"><span>Worker — Unified Directory</span><select id="rrAssignCommonWorker"><option value="">Select worker</option></select></label>
<label class="field full"><span>Actual Rate — Lot + Department (enter once)</span><input id="rrAssignRate" type="number" min="0" step="0.01" placeholder="Auto-filled after first save"></label></div>
<div class="rr-colour-toolbar"><button type="button" id="rrAssignAll">ALL COLOURS</button><button type="button" id="rrAssignClear">CLEAR</button>
<button type="button" class="primary" id="rrAssignOk">REFRESH ROWS</button></div><div id="rrAssignColourPick" class="rr-colour-pick"></div><div id="rrAssignRows"></div>
<label class="field full"><span>Remarks</span><textarea id="rrAssignRemarks" placeholder="Optional assignment remarks"></textarea></label>
<div id="rrAssignStatus" class="status-line">Select Department.</div><div class="actions"><button type="button" id="rrAssignCancel">Cancel</button>
<button type="submit" class="primary" id="rrAssignSave">ASSIGN WORK</button></div></form>`;document.body.appendChild(w);
$('rrAssignClose').onclick=$('rrAssignCancel').onclick=closeModal;
$('rrAssignDept').onchange=async()=>{state.department=$('rrAssignDept').value;await loadWorkers();await loadContext();};
$('rrAssignCommonWorker').onchange=()=>{state.commonWorkerId=$('rrAssignCommonWorker').value;document.querySelectorAll('[data-row-worker]').forEach(e=>e.value=state.commonWorkerId);};
$('rrAssignAll').onclick=()=>{state.selected=new Set(state.context.filter(x=>!locked(x)).map(x=>x.colour_code));renderColourPick();renderRows();};
$('rrAssignClear').onclick=()=>{state.selected.clear();renderColourPick();$('rrAssignRows').innerHTML='';$('rrAssignStatus').textContent='Selection cleared.';};
$('rrAssignOk').onclick=renderRows;$('rrAssignV8Form').onsubmit=saveAssignments;}
function closeModal(){$('rrAssignV8Modal')?.classList.add('hidden');}
function departmentOptions(){const s=$('eDept');return s?[...s.options].map(o=>`<option value="${safe(o.value)}">${safe(o.textContent)}</option>`).join(''):'<option value="">Department unavailable</option>';}
async function openAssign(lotId,lotNo){state.client=client();if(!state.client)return alert('Supabase client unavailable.');state.lotId=String(lotId||'').trim();state.lotNo=String(lotNo||lotId||'').trim();
state.selected.clear();state.commonWorkerId='';state.actualRate=null;$('rrAssignRate').value='';$('rrAssignRate').readOnly=false;$('rrAssignLotNo').textContent=state.lotNo||'—';$('rrAssignDept').innerHTML=departmentOptions();state.department=$('rrAssignDept').value;
$('rrAssignRemarks').value='';$('rrAssignRows').innerHTML='';$('rrAssignV8Modal').classList.remove('hidden');await loadWorkers();await loadContext();}
async function loadWorkers(){$('rrAssignStatus').textContent='Loading Unified Worker Directory…';const rows=await rpc('rr_upm_worker_list_v8_3',{p_department_code:state.department||null});
state.workers=Array.isArray(rows)?rows:[];$('rrAssignCommonWorker').innerHTML='<option value="">Select worker</option>'+state.workers.map(w=>`<option value="${safe(w.worker_id)}">${safe(w.worker_name)} — ${safe(w.worker_code)} — ${safe(w.role_code||'worker')}</option>`).join('');state.commonWorkerId='';}
async function loadContext(){$('rrAssignStatus').textContent='Loading Cutting colour-size quantities…';const rows=await rpc('rr_upm_get_work_assign_context_v8_2',{p_canonical_lot_id:state.lotId||null,p_lot_no:state.lotNo||null,p_department_code:state.department});
state.context=Array.isArray(rows)?rows:[];state.actualRate=state.context.find(x=>x.actual_rate!=null)?.actual_rate??null;$('rrAssignRate').value=state.actualRate==null?'':Number(state.actualRate);$('rrAssignRate').readOnly=state.actualRate!=null;state.selected.clear();renderColourPick();$('rrAssignRows').innerHTML='';$('rrAssignStatus').textContent=state.context.length?`${state.context.length} Cutting colour mapped. Select colour; row opens immediately.`:'Cutting colour-size mapping not found for this Lot.';}
function renderColourPick(){$('rrAssignColourPick').innerHTML=state.context.map(r=>{const l=locked(r),sel=state.selected.has(r.colour_code),cls=`rr-colour-chip${sel?' selected':''}${l?' locked':''}`;
const suffix=l?` — Assigned: ${safe(r.assigned_worker_name||'')} (${safe(r.assigned_worker_code||'')})`:` — ${qtyOf(r)} PCS`;
return `<button type="button" class="${cls}" data-colour="${safe(r.colour_code)}" ${l?'disabled':''}>${safe(r.colour_name||r.colour_code)}${suffix}</button>`;}).join('');
document.querySelectorAll('[data-colour]').forEach(b=>b.onclick=()=>{const c=b.dataset.colour;state.selected.has(c)?state.selected.delete(c):state.selected.add(c);renderColourPick();renderRows();});}
function workerOptions(sel=''){return '<option value="">Select worker</option>'+state.workers.map(w=>`<option value="${safe(w.worker_id)}" ${String(w.worker_id)===String(sel)?'selected':''}>${safe(w.worker_name)} — ${safe(w.worker_code)} — ${safe(w.role_code||'worker')}</option>`).join('');}
function sizeHtml(r){return (Array.isArray(r.size_breakup)?r.size_breakup:[]).map(s=>`<span class="rr-size-pill"><b>${safe(s.size_code)}</b> ${Number(s.qty||0)} PCS</span>`).join('');}
function renderRows(){const rows=state.context.filter(x=>state.selected.has(x.colour_code)&&!locked(x));if(!rows.length){$('rrAssignRows').innerHTML='';$('rrAssignStatus').textContent='Select at least one unassigned colour.';return;}
$('rrAssignRows').innerHTML=rows.map(r=>`<section class="rr-assign-row" data-assign-row="${safe(r.colour_code)}"><div class="rr-assign-row-head"><h3 style="margin:0">${safe(r.colour_code)} — ${safe(r.colour_name||r.colour_code)}</h3><b>Cutting Qty ${qtyOf(r)} PCS</b></div>
<div class="rr-size-line">${sizeHtml(r)}</div><div class="rr-worker-line"><label class="field"><span>Worker — Directory Role & Permission</span><select data-row-worker required>${workerOptions(state.commonWorkerId)}</select></label>
<label class="field"><span>Cutting Qty — Auto</span><input data-row-qty type="number" value="${qtyOf(r)}" readonly></label>
<label class="field"><span>Actual Rate / Pc — Auto</span><input data-row-rate type="number" value="${state.actualRate==null?'':Number(state.actualRate)}" readonly></label></div></section>`).join('');
$('rrAssignStatus').textContent=`${rows.length} colour selected. Worker select karein; rate Lot + Department se auto rahega.`;}
async function saveAssignments(ev){ev.preventDefault();try{const nodes=[...document.querySelectorAll('[data-assign-row]')];if(!nodes.length)throw new Error('Select at least one colour.');
const rateText=$('rrAssignRate').value,rate=Number(rateText);if(rateText===''||!Number.isFinite(rate)||rate<0)throw new Error('Valid Actual Rate is required once for this Lot + Department.');
const rows=nodes.map(n=>{const colour=n.dataset.assignRow,worker=n.querySelector('[data-row-worker]').value,qty=Number(n.querySelector('[data-row-qty]').value||0);
if(!worker)throw new Error(`Worker is required for colour ${colour}.`);
return {colour_code:colour,worker_id:worker,assigned_qty:qty,actual_rate:rate};});
$('rrAssignSave').disabled=true;$('rrAssignSave').textContent='ASSIGNING…';await rpc('rr_upm_set_department_rate_v2',{p_canonical_lot_id:state.lotId,p_department_code:state.department,p_actual_rate:rate});await rpc('rr_upm_assign_colours_v8_3',{p_canonical_lot_id:state.lotId||null,p_lot_no:state.lotNo||null,p_department_code:state.department,p_rows:rows,p_remarks:$('rrAssignRemarks').value||null});
alert('Work assigned successfully.');await loadContext();$('refresh')?.click();closeModal();}catch(e){alert(e.message||String(e));}finally{$('rrAssignSave').disabled=false;$('rrAssignSave').textContent='ASSIGN WORK';}}
function enhanceCards(){document.querySelectorAll('[data-work-assign-placeholder]').forEach(btn=>{const id=btn.dataset.workAssignPlaceholder;if(!id)return;const card=btn.closest('.upm-lot-card,.card'),lot=card?.dataset.lotNo||card?.querySelector('.lot-number')?.textContent?.replace(/^LOT\s*/i,'').trim()||id;btn.classList.add('rr-assign-open');btn.dataset.workAssign=id;btn.removeAttribute('data-work-assign-placeholder');btn.onclick=()=>openAssign(id,lot);});document.querySelectorAll('[data-entry]').forEach(btn=>{const id=btn.dataset.entry;if(!id||btn.parentElement.querySelector(`[data-work-assign="${CSS.escape(id)}"]`))return;const card=btn.closest('.card'),lot=card?.dataset.lotNo||card?.querySelector('.lot-number')?.textContent?.replace(/^LOT\s*/i,'').trim()||id,b=document.createElement('button');b.type='button';b.className='rr-assign-open';b.dataset.workAssign=id;b.textContent='Assign Work';b.onclick=()=>openAssign(id,lot);btn.parentElement.insertBefore(b,btn);});}
function start(){injectStyles();injectModal();enhanceCards();new MutationObserver(enhanceCards).observe(document.body,{childList:true,subtree:true});console.info(`REDZED UPM Work Assignment V${VERSION} loaded`);}
document.readyState==='loading'?document.addEventListener('DOMContentLoaded',start,{once:true}):start();
})();