(()=>{
'use strict';
const path=location.pathname,qs=new URLSearchParams(location.search),dept=(qs.get('dept')||'').trim().toUpperCase();
if(!/real-(department-lite-v9127|sticker-master-v804|metal-id-master-v804)\.html$/i.test(path))return;
const db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
const mode=()=>String(qs.get('mode')||document.getElementById('dataMode')?.value||'TEST').toUpperCase();
const norm=v=>String(v||'').trim().toLowerCase().replace(/\s+/g,' '),num=v=>Number(v||0);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let vendorNames=new Set();
async function refreshVendors(){try{const r=await db().rpc('rr_get_mc_vendor_options_v9135');if(r.error)throw r.error;vendorNames=new Set((r.data||[]).filter(x=>x.is_active!==false).map(x=>norm(x.vendor_name)).filter(Boolean));const list=document.getElementById('rr9160VendorList');if(list)list.innerHTML=(r.data||[]).filter(x=>x.is_active!==false).map(x=>`<option value="${String(x.vendor_name||'').replace(/"/g,'&quot;')}"></option>`).join('')}catch(e){console.warn('Vendor refresh v9160',e)}}
async function syncAlerts(){if(!['STICKER','METAL_ID'].includes(dept))return;try{const r=await db().rpc('rr_sync_accessory_purchase_alerts_v9160',{p_data_mode:mode()});if(r.error)throw r.error}catch(e){console.warn('Accessory alert sync v9160',e)}}
function msg(t){const e=document.getElementById('rr9160Msg');if(e)e.textContent=t}
function overlap(a,b){return a.left<b.right&&a.right>b.left&&a.top<b.bottom&&a.bottom>b.top}
function protectActions(){
 const actions=[...document.querySelectorAll('.rfsubmitassign,.rr9160-actions button,.sticky button,.print-form-actions button')].filter(el=>{const r=el.getBoundingClientRect(),s=getComputedStyle(el);return r.width>0&&r.height>0&&s.display!=='none'&&s.visibility!=='hidden'});
 if(!actions.length)return;
 [...document.querySelectorAll('button,[role="button"],.scroll-toggle,.table-scroll-toggle,[class*="scroll"][class*="toggle"]')].forEach(el=>{
  if(actions.includes(el)||el.closest('.rr9160-actions,.sticky,.rfmhead,.rfsubmitassign'))return;
  const s=getComputedStyle(el);if(s.position!=='fixed')return;const r=el.getBoundingClientRect();if(!r.width||!r.height||r.width>220||r.height>120)return;
  if(actions.some(a=>overlap(r,a.getBoundingClientRect()))){el.style.setProperty('bottom','calc(92px + env(safe-area-inset-bottom))','important');el.style.setProperty('z-index','40','important');el.dataset.rr9160Shifted='1'}
 });
}
async function getLabor(canonical){const r=await db().from('rr_upm_department_labor_cost_v9160').select('*').eq('data_mode',mode()).eq('canonical_lot_id',canonical).eq('department_code',dept).maybeSingle();if(r.error)throw r.error;return r.data||{salaried_labor_cost:0,piece_rate_labor_cost:0,missing_piece_rate_rows:0}}
async function getPurchaseCost(canonical){if(!['STICKER','METAL_ID'].includes(dept))return 0;const idField=dept==='STICKER'?'sticker_master_id':'metal_id_master_id';const r=await db().from('rr_accessory_lot_requirements_v804').select(`required_qty,avg_cost_snapshot,${idField}`).eq('data_mode',mode()).eq('canonical_lot_id',canonical).eq('item_type',dept).neq('requirement_status','RELEASED');if(r.error)throw r.error;return(r.data||[]).reduce((s,x)=>s+num(x.required_qty)*num(x.avg_cost_snapshot),0)}
function patchAtomicSubmit(){
 if(!['PRINTING','STICKER','METAL_ID'].includes(dept))return;const m=document.getElementById('rfSubmitModal'),btn=m?.querySelector('#rfDoSubmit');if(!m||!btn||m.dataset.rr9160Atomic==='1'||m.dataset.rr9160!=='1')return;m.dataset.rr9160Atomic='1';
 btn.onclick=async()=>{const rows=[...m.querySelectorAll('[data-colour]:checked')].map(x=>({colour_code:x.dataset.colour})),out=m.querySelector('#rfSubmitMsg'),costMsg=m.querySelector('#rr9160CostMsg'),canonical=m.dataset.canonical;if(!rows.length){out.innerHTML='<div class="rfmsg err">Select at least one colour.</div>';return}btn.disabled=true;btn.textContent='CHECKING COST…';try{const labor=await getLabor(canonical);if(num(labor.missing_piece_rate_rows)>0){throw new Error(`${labor.missing_piece_rate_rows} piece-rate row(s) ka actual rate missing hai.`)}let chemical=0;if(dept==='PRINTING'){const input=m.querySelector('#rr9160ChemicalCost');if(!input||String(input.value).trim()==='')throw new Error('Actual Chemical Cost fill karna required hai.');chemical=num(input.value)}const purchase=await getPurchaseCost(canonical);btn.textContent='SUBMITTING…';const r=await db().rpc('rr_upm_submit_with_direct_cost_v9160',{p_canonical_lot_id:canonical,p_department_code:dept,p_rows:rows,p_remarks:'READY TO SUBMIT V9160 ATOMIC COST',p_chemical_cost:chemical,p_salaried_labor_cost:num(labor.salaried_labor_cost),p_piece_rate_labor_cost:num(labor.piece_rate_labor_cost),p_direct_purchase_cost:purchase,p_data_mode:mode()});if(r.error)throw r.error;out.innerHTML=`<div class="rfmsg ok">SUBMITTED · actual department cost captured · ${esc(r.data?.actual_department_rate_per_piece||0)} / pc</div>`;await syncAlerts();setTimeout(()=>{m.remove();document.getElementById('refresh')?.click()},450)}catch(e){if(costMsg)costMsg.textContent=e.message||String(e);else out.innerHTML=`<div class="rfmsg err">${esc(e.message||String(e))}</div>`;btn.disabled=false;btn.textContent='SUBMIT · SAVE & EXIT'}};
}
document.addEventListener('click',e=>{
 const save=e.target.closest('#rr9160Save');
 if(save){const v=norm(document.getElementById('rr9160Vendor')?.value);if(!v||!vendorNames.has(v)){e.preventDefault();e.stopImmediatePropagation();msg('Existing Vendor select karo, ya bahar ka + ADD NEW VENDOR button use karo.');return}setTimeout(()=>{refreshVendors();syncAlerts()},1200);return}
 if(e.target.closest('#rr9160AddVendor'))setTimeout(refreshVendors,900);
},true);
new MutationObserver(()=>{protectActions();patchAtomicSubmit();if(document.getElementById('rr9160VendorList'))refreshVendors()}).observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['data-rr9160','class']});
window.addEventListener('resize',protectActions,{passive:true});window.visualViewport?.addEventListener('resize',protectActions,{passive:true});
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>{refreshVendors();protectActions();patchAtomicSubmit();syncAlerts()},{once:true});else{refreshVendors();protectActions();patchAtomicSubmit();syncAlerts()}
})();