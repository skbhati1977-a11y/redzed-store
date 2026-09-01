(()=>{
'use strict';
const $=id=>document.getElementById(id);
const safe=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));
const KEYS=[
 ['menu_enabled','Market Menu'],
 ['seller_workspace_enabled','Seller Workspace'],
 ['customer_groups_enabled','Customer Groups'],
 ['send_collection_enabled','Send Collection'],
 ['receive_requirement_enabled','Receive Requirement'],
 ['forward_requirement_enabled','Forward to REDZED'],
 ['pi_convert_enabled','PI Convert'],
 ['ci_convert_enabled','CI Convert']
];
let rows=[];
function client(){return window.supabaseClient||window.sb||window.supabase?.client||null}
function accessOf(r){const a=r.access||{};return Object.fromEntries(KEYS.map(([k])=>[k,!!a[k]]))}
function render(){
 const root=$('tab-market-access'); if(!root)return;
 const q=String($('marketAccessSearch')?.value||'').trim().toLowerCase();
 const filtered=rows.filter(r=>!q||String(r.name||'').toLowerCase().includes(q)||String(r.mobile||'').includes(q)||String(r.role_code||'').toLowerCase().includes(q));
 root.innerHTML=`<div class="toolbar"><label class="grow"><span>Search Staff / Customer</span><input id="marketAccessSearch" value="${safe(q)}" placeholder="Name / mobile / role"></label><button id="marketAccessRefresh" class="secondary">Refresh</button></div><div class="panel"><div class="row between"><div><h3>Market Workspace Access</h3><p class="muted">Super Admin controlled. Customer can remain REDZED customer and separately receive seller workspace. OFF is backend authoritative, not only menu hiding.</p></div><span class="badge warn">TEST61</span></div><div class="card-list">${filtered.map(r=>{const a=accessOf(r);return `<article class="card" data-kind="${safe(r.kind)}" data-id="${safe(r.id)}"><div class="row between"><div><h4>${safe(r.name||'Unnamed')}</h4><p class="muted">${safe(r.kind)}${r.role_code?` · ${safe(r.role_code)}`:''}${r.mobile?` · ${safe(r.mobile)}`:''}</p></div><span class="badge ${a.menu_enabled?'good':'bad'}">${a.menu_enabled?'MARKET ON':'MARKET OFF'}</span></div><div class="form-checks">${KEYS.map(([k,label])=>`<label class="check"><input type="checkbox" data-access="${k}" ${a[k]?'checked':''}> ${safe(label)}</label>`).join('')}</div><div class="button-row"><button class="primary" data-save-market>Save Market Access</button></div></article>`}).join('')||'<p class="muted">No matching staff/customer.</p>'}</div></div>`;
 $('marketAccessSearch')?.addEventListener('input',render);
 $('marketAccessRefresh')?.addEventListener('click',load);
 root.querySelectorAll('[data-save-market]').forEach(b=>b.addEventListener('click',save));
}
async function load(){
 const c=client(); const root=$('tab-market-access'); if(!c||!root)return;
 root.innerHTML='<div class="panel"><p class="muted">Loading Market Access…</p></div>';
 const {data,error}=await c.rpc('rr_owner_market_access_list_v61');
 if(error){root.innerHTML=`<div class="panel"><p class="message error">${safe(error.message)}</p></div>`;return}
 rows=[...(data?.staff||[]).map(x=>({...x,kind:'STAFF'})),...(data?.customers||[]).map(x=>({...x,kind:'CUSTOMER'}))]; render();
}
async function save(ev){
 const card=ev.currentTarget.closest('[data-kind][data-id]'); if(!card)return;
 const access={}; KEYS.forEach(([k])=>access[k]=!!card.querySelector(`[data-access="${k}"]`)?.checked);
 ev.currentTarget.disabled=true; ev.currentTarget.textContent='Saving…';
 const c=client(); const {error}=await c.rpc('rr_owner_market_access_set_v61',{p_subject_kind:card.dataset.kind,p_subject_id:card.dataset.id,p_access:access});
 ev.currentTarget.disabled=false; ev.currentTarget.textContent='Save Market Access';
 if(error){alert(error.message);return} await load();
}
function install(){
 const tabs=$('tabs'); if(!tabs||$('tab-market-access'))return;
 const btn=document.createElement('button'); btn.dataset.tab='market-access'; btn.textContent='Market Access'; tabs.appendChild(btn);
 const sec=document.createElement('section'); sec.id='tab-market-access'; sec.className='hidden'; $('tab-departments')?.after(sec);
 btn.addEventListener('click',()=>{document.querySelectorAll('#tabs button').forEach(x=>x.classList.toggle('active',x===btn)); document.querySelectorAll('main.page>section[id^="tab-"]').forEach(x=>x.classList.add('hidden')); sec.classList.remove('hidden'); load();});
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install);else install();
})();