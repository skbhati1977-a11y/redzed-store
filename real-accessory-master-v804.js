/* REAL FACTORY GLOBAL ENTER FLOW RULE
   Apply only to genuine data-entry/ledger forms.
   Enter => next visible enabled eligible field.
   Skip hidden/disabled/buttons.
   Last eligible field => submit/save.
   Textareas keep normal Enter unless form explicitly opts in.
   Search/filter/chat/notes where multiline is expected remain normal.
   This is a frontend UX rule, not a backend rule.
*/
(()=>{
'use strict';
const C=window.ACCESSORY_MASTER_CONFIG||{};
const $=id=>document.getElementById(id);
const state={client:null,items:[],editing:null,mode:'TEST'};
const safe=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));
const err=e=>[e?.message,e?.details,e?.hint,e?.code].filter(Boolean).join(' — ')||'Unknown error';
const money=v=>new Intl.NumberFormat('en-IN',{style:'currency',currency:'INR',minimumFractionDigits:2,maximumFractionDigits:2}).format(Number(v||0));
const qty=v=>Number(v||0).toLocaleString('en-IN',{maximumFractionDigits:2});
const today=()=>new Date().toISOString().slice(0,10);
function say(t='',cls=''){const el=$('message');el.textContent=t;el.className=`message ${cls}`.trim()}
function cleanNumInput(el,decimals=2){el.addEventListener('focus',()=>{if(/^0(?:\.0+)?$/.test(String(el.value||'')))el.value=''});el.addEventListener('input',()=>{let raw=String(el.value||'').replace(/,/g,'').replace(/[^0-9.]/g,'');const p=raw.split('.');raw=p.length>1?`${p.shift()}.${p.join('').slice(0,decimals)}`:p[0];if(el.value!==raw)el.value=raw});}

function bindEnterNext(form, saveSelector='button[type="submit"]'){
  if(!form||form.dataset.enterFlowBound==='1')return;
  form.dataset.enterFlowBound='1';
  form.addEventListener('keydown',ev=>{
    if(ev.key!=='Enter'||ev.shiftKey||ev.ctrlKey||ev.altKey||ev.metaKey)return;
    const target=ev.target;
    if(!target||target.tagName==='TEXTAREA'||target.type==='file'||target.type==='checkbox'||target.type==='radio')return;
    const eligible=[...form.querySelectorAll('input,select,textarea,button')].filter(el=>{
      if(el.disabled||el.hidden)return false;
      if(el.type==='hidden'||el.type==='button'||el.type==='reset')return false;
      if(el.closest('.hidden'))return false;
      return el.offsetParent!==null;
    });
    const saveBtn=form.querySelector(saveSelector);
    const fields=eligible.filter(el=>el!==saveBtn&&el.type!=='submit');
    const idx=fields.indexOf(target);
    if(idx<0)return;
    ev.preventDefault();
    const next=fields[idx+1];
    if(next){
      next.focus();
      if(typeof next.select==='function'&&['text','search','tel','url','email','number'].includes(next.type||'text')){
        try{next.select()}catch(_e){}
      }
      return;
    }
    if(saveBtn&&!saveBtn.disabled){
      if(typeof form.requestSubmit==='function')form.requestSubmit(saveBtn);
      else saveBtn.click();
    }
  });
}

async function rpc(name,payload={}){const r=await state.client.rpc(name,payload);if(r.error)throw r.error;return r.data}
async function bootMode(){if(window.RRDataModeReadyPromise)await window.RRDataModeReadyPromise;if(window.RRDataMode){await RRDataMode.refresh();state.mode=await RRDataMode.applyInitialMode('dataMode',new URLSearchParams(location.search).get('mode')||'')}else state.mode='TEST';$('dataMode').value=state.mode;}
function itemNo(x){return x.item_no??x[C.noField]??''} function itemName(x){return x.item_name??x[C.nameField]??''} function itemAttr(x){return x.item_attr??x[C.attrField]??''}
function renderStats(){const active=state.items.filter(x=>x.is_active!==false).length,stock=state.items.reduce((s,x)=>s+Number(x.physical_stock_qty||0),0),req=state.items.reduce((s,x)=>s+Number(x.req_now_qty||0),0);$('stats').innerHTML=[[`${C.label} Items`,active],['Physical Stock',qty(stock)],['Req Now',qty(req)]].map(([a,b])=>`<article class="stat"><small>${safe(a)}</small><strong>${safe(b)}</strong></article>`).join('')}
function render(){renderStats();const q=String($('search').value||'').trim().toLowerCase();const rows=state.items.filter(x=>!q||[itemNo(x),itemName(x),itemAttr(x)].join(' ').toLowerCase().includes(q));$('cards').innerHTML=`<div class="tablewrap"><table><thead><tr><th>Image</th><th>No.</th><th>Name</th><th>${safe(C.attrLabel)}</th><th>Physical</th><th>Reserved</th><th>Free</th><th>Req Now</th><th>Avg Cost</th><th>Active</th><th>Actions</th></tr></thead><tbody>${rows.map(x=>`<tr><td>${x.image_url?`<button data-image="${x.id}" title="View image" style="padding:0;border:0;background:transparent"><img class="thumb" src="${safe(x.image_url)}" alt=""></button>`:'—'}</td><td><strong>${safe(itemNo(x))}</strong></td><td>${safe(itemName(x)||'—')}</td><td>${safe(itemAttr(x)||'—')}</td><td>${qty(x.physical_stock_qty)}</td><td>${qty(x.reserved_qty)}</td><td>${qty(x.free_stock_qty)}</td><td><strong>${qty(x.req_now_qty)}</strong></td><td>${money(x.weighted_avg_cost_per_piece)}</td><td class="${x.is_active!==false?'status-ok':'status-off'}">${x.is_active!==false?'Yes':'No'}</td><td><div class="mini-actions"><button data-edit="${x.id}">Edit</button><button class="primary" data-purchase="${x.id}">+ Purchase</button><button data-ledger="${x.id}">Ledger</button>${x.image_url?`<button data-image="${x.id}">View</button>`:''}</div></td></tr>`).join('')||`<tr><td colspan="11">No items found.</td></tr>`}</tbody></table></div>`;document.querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>openItem(b.dataset.edit));document.querySelectorAll('[data-purchase]').forEach(b=>b.onclick=()=>openPurchase(b.dataset.purchase));document.querySelectorAll('[data-ledger]').forEach(b=>b.onclick=()=>openLedger(b.dataset.ledger));document.querySelectorAll('[data-image]').forEach(b=>b.onclick=()=>openImage(b.dataset.image));}
async function load(){say('Loading…');try{state.items=await rpc('rr_accessory_master_list_v804',{p_item_type:C.itemType,p_data_mode:state.mode})||[];render();say(`${C.label} Master loaded.`,'success')}catch(e){console.error(e);say(err(e),'error')}}
function openSheet(id){$(id).classList.remove('hidden');document.body.style.overflow='hidden'} function closeSheet(id){$(id).classList.add('hidden');document.body.style.overflow=''}
function openItem(id=null){state.editing=state.items.find(x=>String(x.id)===String(id))||null;const edit=!!state.editing;$('itemTitle').textContent=edit?`Edit ${C.label} · ${itemNo(state.editing)}`:`New ${C.label}`;$('itemSaveBtn').textContent=edit?`Update ${C.label}`:`Save ${C.label}`;$('itemNo').value=edit?itemNo(state.editing):'';$('itemName').value=edit?itemName(state.editing):'';$('itemActive').checked=edit?state.editing.is_active!==false:true;$('attrButtons').innerHTML=C.attrOptions.map(v=>`<button type="button" data-attr="${safe(v)}" class="${edit&&String(itemAttr(state.editing)).toUpperCase()===v?'selected':''}">${safe(v)}</button>`).join('');$('itemAttr').value=edit?String(itemAttr(state.editing)).toUpperCase():C.attrOptions[0];document.querySelectorAll('[data-attr]').forEach(b=>b.onclick=()=>{document.querySelectorAll('[data-attr]').forEach(x=>x.classList.remove('selected'));b.classList.add('selected');$('itemAttr').value=b.dataset.attr});$('itemImage').value='';const box=$('currentImageBox'),prev=$('currentImagePreview');if(edit&&state.editing.image_url){box.style.display='block';prev.innerHTML=`<img src="${safe(state.editing.image_url)}" alt="" style="max-width:180px;max-height:180px;border-radius:10px;object-fit:contain">`;$('imageLabel').textContent='Replace Reference Image'}else{box.style.display='none';prev.innerHTML='';$('imageLabel').textContent='Reference Image'}openSheet('itemSheet')}
async function saveItem(ev){ev.preventDefault();const btn=ev.submitter;btn.disabled=true;try{const payload={p_id:state.editing?.id||null,p_is_active:$('itemActive').checked};payload[C.rpcNoParam]=$('itemNo').value.trim();payload[C.rpcNameParam]=$('itemName').value.trim()||null;payload[C.rpcAttrParam]=$('itemAttr').value;const id=await rpc(C.upsertRpc,payload);const file=$('itemImage').files?.[0];if(file){if(!window.RR?.uploadMedia)throw new Error('Image upload runtime unavailable.');await RR.uploadMedia({file,entityType:C.entityType,entityId:String(id),mediaCategory:'reference',sourceType:'gallery',visibilityScope:'factory',caption:`${C.label} ${$('itemNo').value.trim()}`})}closeSheet('itemSheet');await load();say(`${C.label} ${state.editing?'updated':'saved'}.`,'success');state.editing=null}catch(e){say(err(e),'error')}finally{btn.disabled=false}}
function openPurchase(id){const x=state.items.find(v=>String(v.id)===String(id));if(!x)return;$('purchaseMasterId').value=id;$('purchaseTitle').textContent=`Purchase · ${itemNo(x)} · ${itemName(x)||''}`;$('vendor').value='';$('billNo').value='';$('billDate').value=today();$('purchaseQty').value='';$('purchaseRate').value='';$('purchaseNotes').value='';openSheet('purchaseSheet');setTimeout(()=>{$('vendor')?.focus()},0)}
async function savePurchase(ev){ev.preventDefault();const btn=ev.submitter;btn.disabled=true;try{await rpc('rr_post_accessory_purchase_v804',{p_data_mode:state.mode,p_item_type:C.itemType,p_master_id:$('purchaseMasterId').value,p_vendor_name:$('vendor').value.trim()||null,p_bill_no:$('billNo').value.trim()||null,p_bill_date:$('billDate').value||null,p_qty:Number($('purchaseQty').value||0),p_rate_per_piece:Number($('purchaseRate').value||0),p_notes:$('purchaseNotes').value.trim()||null});closeSheet('purchaseSheet');await load();say('Purchase saved; stock and requirements recalculated.','success')}catch(e){say(err(e),'error')}finally{btn.disabled=false}}
async function openLedger(id){const x=state.items.find(v=>String(v.id)===String(id));if(!x)return;$('ledgerTitle').textContent=`Purchase Ledger · ${itemNo(x)}`;$('ledgerBody').innerHTML='Loading…';openSheet('ledgerSheet');try{const rows=await rpc('rr_accessory_purchase_history_v804',{p_item_type:C.itemType,p_master_id:id,p_data_mode:state.mode})||[];$('ledgerBody').innerHTML=`<div class="tablewrap"><table class="ledger"><thead><tr><th>Date</th><th>Type</th><th>Vendor</th><th>Bill</th><th>Qty</th><th>Rate/pc</th><th>Value</th><th>Notes</th></tr></thead><tbody>${rows.map(r=>`<tr><td>${safe(r.bill_date||String(r.created_at||'').slice(0,10))}</td><td>${safe(r.entry_type||'')}</td><td>${safe(r.vendor_name||'—')}</td><td>${safe(r.bill_no||'—')}</td><td>${qty(r.qty)}</td><td>${money(r.rate_per_piece)}</td><td>${money(Number(r.qty||0)*Number(r.rate_per_piece||0))}</td><td>${safe(r.notes||'—')}</td></tr>`).join('')||'<tr><td colspan="8">No purchase entry yet.</td></tr>'}</tbody></table></div>`}catch(e){$('ledgerBody').textContent=err(e)}}
function openImage(id){const x=state.items.find(v=>String(v.id)===String(id));if(!x||!x.image_url)return;$('imageTitle').textContent=`${C.label} ${itemNo(x)} · Reference Image`;$('imageBody').innerHTML=`<img src="${safe(x.image_url)}" alt="" style="display:block;max-width:100%;max-height:70vh;margin:auto;border-radius:12px;object-fit:contain">`;openSheet('imageSheet')}
async function boot(){try{state.client=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;if(!state.client)throw new Error('Supabase client unavailable.');if(window.RR?.requireRoles)await RR.requireRoles(['owner','admin']);await bootMode();$('pageTitle').textContent=`${C.label} Master`;$('heroTitle').textContent=`${C.label} + Inventory`;$('attrLabel').textContent=C.attrLabel;$('newItem').textContent=`+ ${C.label} New`;$('search').placeholder=`Search ${C.label} No / Name / ${C.attrLabel}`;$('newItem').onclick=()=>openItem();$('refresh').onclick=load;$('search').oninput=render;$('itemForm').onsubmit=saveItem;$('purchaseForm').onsubmit=savePurchase;document.querySelectorAll('[data-close]').forEach(b=>b.onclick=()=>closeSheet(b.dataset.close));cleanNumInput($('purchaseQty'),2);cleanNumInput($('purchaseRate'),2);bindEnterNext($('purchaseForm'));$('dataMode').onchange=async()=>{state.mode=$('dataMode').value;await load()};await load()}catch(e){console.error(e);say(err(e),'error')}}
document.readyState==='loading'?document.addEventListener('DOMContentLoaded',boot):boot();
})();
