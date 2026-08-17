(()=>{
'use strict';
const path=location.pathname,qs=new URLSearchParams(location.search),dept=(qs.get('dept')||'').trim().toUpperCase();
if(!/real-(department-lite-v9127|sticker-master-v804|metal-id-master-v804)\.html$/i.test(path))return;
const db=()=>window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
const mode=()=>String(qs.get('mode')||document.getElementById('dataMode')?.value||'TEST').toUpperCase();
const norm=v=>String(v||'').trim().toLowerCase().replace(/\s+/g,' ');
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
document.addEventListener('click',e=>{
 const save=e.target.closest('#rr9160Save');
 if(save){const v=norm(document.getElementById('rr9160Vendor')?.value);if(!v||!vendorNames.has(v)){e.preventDefault();e.stopImmediatePropagation();msg('Existing Vendor select karo, ya bahar ka + ADD NEW VENDOR button use karo.');return}setTimeout(()=>{refreshVendors();syncAlerts()},1200);return}
 if(e.target.closest('#rr9160AddVendor'))setTimeout(refreshVendors,900);
},true);
new MutationObserver(()=>{protectActions();if(document.getElementById('rr9160VendorList'))refreshVendors()}).observe(document.documentElement,{childList:true,subtree:true});
window.addEventListener('resize',protectActions,{passive:true});window.visualViewport?.addEventListener('resize',protectActions,{passive:true});
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>{refreshVendors();protectActions();syncAlerts()},{once:true});else{refreshVendors();protectActions();syncAlerts()}
})();