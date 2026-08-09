(()=>{
'use strict';
const C=window.ACCESSORY_MASTER_CONFIG||{};
const $=id=>document.getElementById(id);
const state={client:null,items:[],balances:[],purchases:[],media:[],editing:null,mode:'TEST'};
const safe=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));
const err=e=>[e?.message,e?.details,e?.hint,e?.code].filter(Boolean).join(' — ')||'Unknown error';
const money=v=>new Intl.NumberFormat('en-IN',{style:'currency',currency:'INR',minimumFractionDigits:2,maximumFractionDigits:2}).format(Number(v||0));
const qty=v=>Number(v||0).toLocaleString('en-IN',{maximumFractionDigits:2});
const today=()=>new Date().toISOString().slice(0,10);
function say(t='',cls=''){const el=$('message');el.textContent=t;el.className=`message ${cls}`.trim()}
function cleanNumInput(el,decimals=2){
  el.addEventListener('focus',()=>{if(/^0(?:\.0+)?$/.test(String(el.value||'')))el.value=''});
  el.addEventListener('input',()=>{let raw=String(el.value||'').replace(/,/g,'').replace(/[^0-9.]/g,'');const p=raw.split('.');raw=p.length>1?`${p.shift()}.${p.join('').slice(0,decimals)}`:p[0];if(el.value!==raw)el.value=raw});
  el.addEventListener('blur',()=>{if(String(el.value).trim()==='')el.value=''});
}
async function rpc(name,payload={}){const r=await state.client.rpc(name,payload);if(r.error)throw r.error;return r.data}
async function bootMode(){
  if(window.RRDataModeReadyPromise)await window.RRDataModeReadyPromise;
  if(window.RRDataMode){await RRDataMode.refresh();state.mode=await RRDataMode.applyInitialMode('dataMode',new URLSearchParams(location.search).get('mode')||'')}else state.mode='TEST';
  $('dataMode').value=state.mode;
}
function itemId(row){return row.id}
function itemNo(row){return row[C.noField]||''}
function itemName(row){return row[C.nameField]||''}
function itemAttr(row){return row[C.attrField]||''}
function balanceFor(id){return state.balances.find(b=>String(b[C.balanceIdField])===String(id)&&String(b.data_mode).toUpperCase()===state.mode)||{}}
function imageFor(id){return state.media.find(m=>String(m.entity_type)===C.entityType&&String(m.entity_id)===String(id))?.file_url||''}
function renderStats(){
  const total=state.items.filter(x=>x.is_active!==false).length;
  const stock=state.items.reduce((s,x)=>s+Number(balanceFor(x.id).physical_stock_qty||0),0);
  const req=state.items.reduce((s,x)=>s+Number(balanceFor(x.id).req_now_qty||0),0);
  $('stats').innerHTML=[[`${C.label} Items`,total],['Physical Stock',qty(stock)],['Req Now',qty(req)]].map(([a,b])=>`<article class="stat"><small>${safe(a)}</small><strong>${safe(b)}</strong></article>`).join('');
}
function render(){
  renderStats(); const q=String($('search').value||'').toLowerCase();
  const rows=state.items.filter(x=>!q||JSON.stringify(x).toLowerCase().includes(q));
  $('cards').innerHTML=rows.map(x=>{const b=balanceFor(x.id),img=imageFor(x.id),short=Number(b.req_now_qty||0)>0;return `<article class="card ${short?'short':''}">
    <div class="media">${img?`<img src="${safe(img)}" alt="">`:`<div class="ph">${safe(C.label)}</div>`}</div>
    <div class="body"><div class="row between"><div><small>${safe(C.label.toUpperCase())}</small><h3>${safe(itemNo(x))}</h3></div><span class="pill">${safe(itemAttr(x))}</span></div>
    <p>${safe(itemName(x)||'—')}</p>
    <div class="grid4"><span><small>Available</small><b>${qty(b.physical_stock_qty)}</b></span><span><small>Reserved</small><b>${qty(Math.min(Number(b.physical_stock_qty||0),Number(b.open_requirement_qty||0)))}</b></span><span><small>Free</small><b>${qty(b.free_stock_qty)}</b></span><span><small>Req Now</small><b>${qty(b.req_now_qty)}</b></span><span><small>Avg Cost</small><b>${money(b.weighted_avg_cost_per_piece)}</b></span></div>
    <div class="actions"><button data-edit="${x.id}">Edit</button><button class="primary" data-purchase="${x.id}">+ Purchase</button></div></div></article>`}).join('')||'<article class="empty">No items found.</article>';
  document.querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>openItem(b.dataset.edit));
  document.querySelectorAll('[data-purchase]').forEach(b=>b.onclick=()=>openPurchase(b.dataset.purchase));
}
async function load(){
  say('Loading…');
  try{
    const [a,b,m,p]=await Promise.all([
      state.client.from(C.masterTable).select('*').order(C.noField),
      state.client.from('rr_accessory_stock_balance_v804').select('*').eq('data_mode',state.mode).eq('item_type',C.itemType),
      state.client.from('rr_media').select('*').eq('entity_type',C.entityType).order('created_at',{ascending:false}),
      state.client.from('rr_accessory_purchase_ledger_v804').select('*').eq('data_mode',state.mode).eq('item_type',C.itemType).order('created_at',{ascending:false}).limit(50)
    ]);
    [a,b,m,p].forEach(r=>{if(r.error)throw r.error}); state.items=a.data||[];state.balances=b.data||[];state.media=m.data||[];state.purchases=p.data||[];render();say(`${C.label} Master loaded.`,'success');
  }catch(e){console.error(e);say(err(e),'error')}
}
function openSheet(id){$(id).classList.remove('hidden');document.body.style.overflow='hidden'}function closeSheet(id){$(id).classList.add('hidden');document.body.style.overflow=''}
function openItem(id=null){
  state.editing=state.items.find(x=>String(x.id)===String(id))||null; $('itemTitle').textContent=state.editing?`Edit ${itemNo(state.editing)}`:`New ${C.label}`;
  $('itemNo').value=state.editing?itemNo(state.editing):'';$('itemName').value=state.editing?itemName(state.editing):'';$('itemActive').checked=state.editing?state.editing.is_active!==false:true;
  $('attrButtons').innerHTML=C.attrOptions.map(v=>`<button type="button" data-attr="${safe(v)}" class="${state.editing&&String(itemAttr(state.editing)).toUpperCase()===v?'selected':''}">${safe(v)}</button>`).join('');
  $('itemAttr').value=state.editing?String(itemAttr(state.editing)).toUpperCase():C.attrOptions[0];document.querySelectorAll('[data-attr]').forEach(b=>b.onclick=()=>{document.querySelectorAll('[data-attr]').forEach(x=>x.classList.remove('selected'));b.classList.add('selected');$('itemAttr').value=b.dataset.attr});$('itemImage').value='';openSheet('itemSheet');
}
async function saveItem(ev){
  ev.preventDefault();const btn=ev.submitter;btn.disabled=true;
  try{
    const payload={p_id:state.editing?.id||null,p_is_active:$('itemActive').checked};payload[C.rpcNoParam]=$('itemNo').value.trim();payload[C.rpcNameParam]=$('itemName').value.trim()||null;payload[C.rpcAttrParam]=$('itemAttr').value;
    const id=await rpc(C.upsertRpc,payload);const file=$('itemImage').files?.[0];if(file){if(!window.RR?.uploadMedia)throw new Error('Image upload runtime unavailable.');await RR.uploadMedia({file,entityType:C.entityType,entityId:String(id),mediaCategory:'reference',sourceType:'gallery',visibilityScope:'factory',caption:`${C.label} ${$('itemNo').value.trim()}`})}
    closeSheet('itemSheet');await load();say(`${C.label} saved.`,'success');
  }catch(e){say(err(e),'error')}finally{btn.disabled=false}
}
function openPurchase(id){const x=state.items.find(v=>String(v.id)===String(id));if(!x)return;$('purchaseMasterId').value=id;$('purchaseTitle').textContent=`Purchase · ${itemNo(x)}`;$('vendor').value='';$('billNo').value='';$('billDate').value=today();$('purchaseQty').value='';$('purchaseRate').value='';$('purchaseNotes').value='';openSheet('purchaseSheet')}
async function savePurchase(ev){ev.preventDefault();const btn=ev.submitter;btn.disabled=true;try{await rpc('rr_post_accessory_purchase_v804',{p_data_mode:state.mode,p_item_type:C.itemType,p_master_id:$('purchaseMasterId').value,p_vendor_name:$('vendor').value.trim()||null,p_bill_no:$('billNo').value.trim()||null,p_bill_date:$('billDate').value||null,p_qty:Number($('purchaseQty').value||0),p_rate_per_piece:Number($('purchaseRate').value||0),p_notes:$('purchaseNotes').value.trim()||null});closeSheet('purchaseSheet');await load();say('Purchase saved; stock and requirements recalculated.','success')}catch(e){say(err(e),'error')}finally{btn.disabled=false}}
async function boot(){try{state.client=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;if(!state.client)throw new Error('Supabase client unavailable.');if(window.RR?.requireRoles)await RR.requireRoles(['owner','admin']);await bootMode();$('pageTitle').textContent=`${C.label} Master`;$('heroTitle').textContent=`${C.label} + Inventory`;$('attrLabel').textContent=C.attrLabel;$('newItem').textContent=`+ ${C.label} New`;$('search').placeholder=`Search ${C.label} No / Name`;$('newItem').onclick=()=>openItem();$('refresh').onclick=load;$('search').oninput=render;$('itemForm').onsubmit=saveItem;$('purchaseForm').onsubmit=savePurchase;document.querySelectorAll('[data-close]').forEach(b=>b.onclick=()=>closeSheet(b.dataset.close));cleanNumInput($('purchaseQty'),2);cleanNumInput($('purchaseRate'),2);$('dataMode').onchange=async()=>{state.mode=$('dataMode').value;await load()};await load()}catch(e){console.error(e);say(err(e),'error')}}
document.readyState==='loading'?document.addEventListener('DOMContentLoaded',boot):boot();
})();
