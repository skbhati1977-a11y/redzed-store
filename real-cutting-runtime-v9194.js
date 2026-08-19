(()=>{
'use strict';
if(window.__RR_CUTTING_RUNTIME_9194__)return;
window.__RR_CUTTING_RUNTIME_9194__=true;

/* Rolled-back layout stays untouched; only startup I/O is made non-blocking. */
window.__RR_CUTTING_UI_LOADER_9190__=true;
window.__RR_CUTTING_LOAD_GUARD_9191__=true;
window.__RR_CUTTING_LOADING_GUARD_9191__=true;

const client=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
if(!client)return;

function timeoutResult(label,ms){
  return {data:null,error:{message:`${label} timed out after ${ms}ms`,code:'RR_NONBLOCKING_TIMEOUT'}};
}
function raceResult(request,ms,label){
  return Promise.race([
    Promise.resolve(request),
    new Promise(resolve=>setTimeout(()=>resolve(timeoutResult(label,ms)),ms))
  ]);
}

/*
  Release territory guard V800 requires an OPEN lot draft before either
  SINGLE or MULTI physical lot rows are inserted. The rolled-back PM core
  predates that guard, so reserve the exact Lot No(s) immediately before
  the existing release RPC and mark them RELEASED only after commit.
*/
function releaseContext(name,args={}){
  const mode=String(name||'').includes('multi')?'multi':'single';
  const state=window.RRCuttingMasterPM?.state?.()||{};
  const active=state.activeCard||{};
  const divisionId=String(
    args.p_cb_unit_id||
    active?.division?.division_id||
    active?.division?.id||
    ''
  ).trim();
  const cbId=String(
    active?.group?.cb_id||
    active?.division?.cb_id||
    active?.group?.purchase_id||
    active?.division?.purchase_id||
    ''
  ).trim();

  let lots=[];
  if(mode==='multi'){
    let rows=args.p_lots;
    if(typeof rows==='string'){
      try{rows=JSON.parse(rows);}catch(_){rows=[];}
    }
    lots=(Array.isArray(rows)?rows:[])
      .map(row=>String(row?.lot_no||'').trim().toUpperCase())
      .filter(Boolean);
  }else{
    const lotNo=String(args.p_lot_no||'').trim().toUpperCase();
    if(lotNo)lots=[lotNo];
  }

  return {mode,divisionId,cbId,lots:[...new Set(lots)]};
}

async function saveReleaseReservations(originalRpc,name,args,options){
  const ctx=releaseContext(name,args);
  if(!ctx.divisionId||!ctx.cbId||!ctx.lots.length){
    return {
      ok:false,
      result:{
        data:null,
        error:{
          message:'Lot release reservation identity is incomplete. Reopen the Lot sheet and try again.',
          code:'RR_LOT_RESERVATION_CONTEXT'
        }
      }
    };
  }

  for(const lotNo of ctx.lots){
    const saved=await originalRpc('rr_save_cutting_lot_draft_v1',{
      p_cb_id:ctx.cbId,
      p_division_id:ctx.divisionId,
      p_lot_mode:ctx.mode,
      p_lot_no:lotNo,
      p_snapshot:{
        source:'CUTTING_MASTER',
        reservation_source:'runtime-v9194-release-fix',
        release_rpc:String(name||''),
        lot_mode:ctx.mode,
        lot_no:lotNo
      },
      p_freeze_state:'OPEN',
      p_freeze_reason:null,
      p_action_id:null
    },options);

    if(saved?.error){
      return {ok:false,result:saved,ctx};
    }
  }

  return {ok:true,ctx};
}

async function markReleaseReservations(originalRpc,ctx){
  if(!ctx?.divisionId||!ctx?.lots?.length)return;
  await Promise.all(ctx.lots.map(lotNo=>
    raceResult(
      originalRpc('rr_mark_cutting_lot_draft_released_v1',{
        p_division_id:ctx.divisionId,
        p_lot_no:lotNo
      }),
      2500,
      `Mark Lot ${lotNo} released`
    ).catch(()=>null)
  ));
}

/* Optional/identity RPCs must never own the main gallery render. */
if(typeof client.rpc==='function'&&!client.__rrCuttingRpc9194){
  const originalRpc=client.rpc.bind(client);
  const rpcTimeouts=new Map([
    ['rr_current_role',1500],
    ['rr_recover_lot_matching_v2',2000],
    ['rr_get_matching_cloth_stock_v2',4000],
    ['rr_get_matching_cloth_stock_v1',4000],
    ['rr_get_mc1_lot_matchings_v2',4000],
    ['rr_list_multi_lots_v3',4000],
    ['rr_cancel_lot_matching_v2',2500]
  ]);
  const releaseRpcs=new Set([
    'rr_release_single_lot_v4',
    'rr_release_single_lot_v3',
    'rr_release_multi_lots_v4',
    'rr_release_multi_lots_v3'
  ]);

  client.rpc=function(name,args,options){
    const rpcName=String(name||'');

    if(releaseRpcs.has(rpcName)){
      return (async()=>{
        const reserved=await saveReleaseReservations(originalRpc,rpcName,args||{},options);
        if(!reserved.ok)return reserved.result;

        const result=await originalRpc(name,args,options);
        if(!result?.error){
          await markReleaseReservations(originalRpc,reserved.ctx);
        }
        return result;
      })();
    }

    const request=originalRpc(name,args,options);
    const ms=rpcTimeouts.get(rpcName);
    return ms?raceResult(request,ms,rpcName||'RPC'):request;
  };
  client.__rrCuttingRpc9194=true;
}

/* Cost settings are optional for gallery rendering. Preserve writes; bound read chains only. */
if(typeof client.from==='function'&&!client.__rrCuttingFrom9194){
  const originalFrom=client.from.bind(client);

  function wrapCostBuilder(builder,state){
    if(!builder||typeof builder!=='object')return builder;
    return new Proxy(builder,{
      get(target,prop,receiver){
        if(prop==='then'&&!state.mutating){
          return (onFulfilled,onRejected)=>
            raceResult(target,2500,'Cutting cost settings')
              .then(onFulfilled,onRejected);
        }

        const value=Reflect.get(target,prop,receiver);
        if(typeof value!=='function')return value;

        return (...args)=>{
          if(['insert','upsert','update','delete'].includes(String(prop))){
            state.mutating=true;
          }
          const result=value.apply(target,args);
          return result&&typeof result==='object'
            ? wrapCostBuilder(result,state)
            : result;
        };
      }
    });
  }

  client.from=function(table){
    const builder=originalFrom(table);
    if(String(table)!=='rr_cutting_cost_settings_v3')return builder;
    return wrapCostBuilder(builder,{mutating:false});
  };
  client.__rrCuttingFrom9194=true;
}

/* Conservative fail-safe: never leave a permanent spinner. It never hides valid cards. */
function reconcile(){
  const api=window.RRCuttingMasterPM;
  const gallery=document.getElementById('divisionGallery');
  if(!api||!gallery)return;

  try{
    const state=api.state?.()||{};
    const rows=Array.isArray(state.galleryRows)?state.galleryRows:[];
    if(rows.length&&gallery.getAttribute('aria-busy')==='true'){
      api.renderGallery?.();
    }
  }catch(error){
    console.warn('Cutting v9194 reconcile warning',error);
  }
}

function stopPermanentSpinner(){
  const gallery=document.getElementById('divisionGallery');
  if(!gallery||gallery.getAttribute('aria-busy')!=='true')return;
  if(gallery.querySelector('.cm-card'))return;

  const loading=gallery.querySelector('.cm-empty');
  if(!loading||!/Loading Cutting Master|Connecting CB Divisions|Connecting Product Master/i.test(loading.textContent||''))return;

  gallery.setAttribute('aria-busy','false');
  loading.innerHTML=`
    <h3>Cutting Master connection delayed</h3>
    <p>Core data request did not finish in time. Retry once; the page will not stay on an endless spinner.</p>
    <button type="button" class="cm-primary" id="rrCuttingRetry9194">Retry</button>
  `;
  document.getElementById('rrCuttingRetry9194')?.addEventListener('click',()=>{
    gallery.setAttribute('aria-busy','true');
    window.RRCuttingMasterPM?.refresh?.();
  },{once:true});
}

/* Damage / GR reporting is Cutting-owned and writes the permanent Product Master ledger. */
const damageGrState={division:null,cb:null,entries:[],allocations:[],rolls:[],type:'DAMAGE'};

function injectDamageGrStyles(){
  if(document.getElementById('rrCuttingDamageGrStyle9235'))return;
  const style=document.createElement('style');
  style.id='rrCuttingDamageGrStyle9235';
  style.textContent=`
    .rr-dgr-actions{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:7px;margin-top:10px;padding-top:10px;border-top:1px solid #292930}
    .rr-dgr-actions button{min-height:42px;border:1px solid #4b3439;border-radius:11px;background:#24181c;color:#ffd2d6;font-size:11px;font-weight:900;padding:7px}
    .rr-dgr-actions button[data-dgr-type="FULL_GR"]{border-color:#6b4d35;background:#2b2118;color:#ffe0b3}
    .rr-dgr-actions button:disabled{opacity:.4}
    .rr-dgr-sheet{position:fixed;inset:0;z-index:2147482500;display:flex;align-items:flex-end;justify-content:center}
    .rr-dgr-sheet.rr-dgr-hidden{display:none!important}
    .rr-dgr-backdrop{position:absolute;inset:0;background:#000c}
    .rr-dgr-panel{position:relative;width:min(760px,100%);max-height:94vh;overflow:auto;background:#111116;border:1px solid #3b3b44;border-radius:24px 24px 0 0;padding:14px 15px 18px}
    .rr-dgr-head{display:flex;justify-content:space-between;gap:12px;align-items:flex-start;margin-bottom:12px}
    .rr-dgr-head h2{margin:3px 0}.rr-dgr-head p{margin:4px 0 0;color:#aaa}
    .rr-dgr-close{width:42px;height:42px;border:0;border-radius:12px;background:#292a30;color:#fff;font-size:24px}
    .rr-dgr-types{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:7px;margin-bottom:12px}
    .rr-dgr-types button{min-height:44px;border:1px solid #3a3a43;border-radius:11px;background:#1a1a20;color:#ddd;font-weight:900;padding:7px}
    .rr-dgr-types button.active{border-color:#ef3340;background:#3b1d22;color:#fff}
    .rr-dgr-grid{display:grid;grid-template-columns:1fr 1fr;gap:10px}
    .rr-dgr-field{display:grid;gap:6px}.rr-dgr-field>span{font-size:11px;color:#bcbcc5;font-weight:850}
    .rr-dgr-field input,.rr-dgr-field select,.rr-dgr-field textarea{width:100%;min-height:46px;border:1px solid #393942;border-radius:12px;background:#0c0c10;color:#fff;padding:11px 12px;font:inherit}
    .rr-dgr-field textarea{min-height:76px;resize:vertical}.rr-dgr-wide{grid-column:1/-1}
    .rr-dgr-check{grid-column:1/-1;display:flex;align-items:center;gap:9px;padding:10px;border:1px solid #33333c;border-radius:11px;background:#0d0d11}.rr-dgr-check input{width:20px;height:20px}
    .rr-dgr-message{min-height:22px;margin:9px 0;color:#aaa}.rr-dgr-message.error{color:#ff9eaa}.rr-dgr-message.success{color:#83e4a6}
    .rr-dgr-submit{width:100%;min-height:48px;border:0;border-radius:13px;background:#ef3340;color:#fff;font-weight:950}
    @media(max-width:650px){.rr-dgr-actions{grid-template-columns:1fr 1fr 1fr}.rr-dgr-grid{grid-template-columns:1fr}.rr-dgr-wide,.rr-dgr-check{grid-column:auto}.rr-dgr-actions button{font-size:10px;padding:6px 4px}}
  `;
  document.head.appendChild(style);
}

function ensureDamageGrSheet(){
  let sheet=document.getElementById('rrCuttingDamageGrSheet9235');
  if(sheet)return sheet;
  injectDamageGrStyles();
  sheet=document.createElement('section');
  sheet.id='rrCuttingDamageGrSheet9235';
  sheet.className='rr-dgr-sheet rr-dgr-hidden';
  sheet.innerHTML=`
    <div class="rr-dgr-backdrop" data-dgr-close></div>
    <div class="rr-dgr-panel" role="dialog" aria-modal="true" aria-labelledby="rrDgrTitle">
      <header class="rr-dgr-head"><div><small>Damage / GR Decision</small><h2 id="rrDgrTitle">Report Damage</h2><p id="rrDgrContext"></p></div><button class="rr-dgr-close" type="button" data-dgr-close>×</button></header>
      <div class="rr-dgr-types"><button type="button" data-dgr-pick="DAMAGE">Damage</button><button type="button" data-dgr-pick="PARTIAL_GR">Partial GR</button><button type="button" data-dgr-pick="FULL_GR">Full GR</button></div>
      <div class="rr-dgr-grid">
        <label class="rr-dgr-field rr-dgr-wide"><span>Manual Lot No *</span><input id="rrDgrLotNo" autocomplete="off" placeholder="Lot No"></label>
        <label class="rr-dgr-field" id="rrDgrBillWrap"><span>Source Bill *</span><select id="rrDgrBill"></select></label>
        <label class="rr-dgr-field" id="rrDgrRollWrap"><span>Roll / Particular *</span><select id="rrDgrRoll"></select></label>
        <label class="rr-dgr-field" id="rrDgrQtyWrap"><span>Qty (kg) *</span><input id="rrDgrQty" type="number" min="0.001" step="0.001" inputmode="decimal"></label>
        <label class="rr-dgr-field" id="rrDgrScopeWrap" style="display:none"><span>Full GR Scope *</span><select id="rrDgrScope"><option value="DIVISION">This Division</option><option value="CB">Full CB</option></select></label>
        <label class="rr-dgr-field rr-dgr-wide"><span>Reason *</span><input id="rrDgrReason" placeholder="Damage / GR reason"></label>
        <label class="rr-dgr-field rr-dgr-wide"><span>Notes</span><textarea id="rrDgrRemarks" placeholder="Optional details"></textarea></label>
        <label class="rr-dgr-check"><input id="rrDgrExchange" type="checkbox"><span>Replacement / exchange expected</span></label>
      </div>
      <p id="rrDgrMessage" class="rr-dgr-message" role="status"></p>
      <button id="rrDgrSubmit" class="rr-dgr-submit" type="button">Save Damage Report</button>
    </div>`;
  document.body.appendChild(sheet);
  sheet.querySelectorAll('[data-dgr-close]').forEach(el=>el.addEventListener('click',closeDamageGrSheet));
  sheet.querySelectorAll('[data-dgr-pick]').forEach(el=>el.addEventListener('click',()=>setDamageGrType(el.dataset.dgrPick)));
  document.getElementById('rrDgrBill')?.addEventListener('change',refreshDamageGrRolls);
  document.getElementById('rrDgrSubmit')?.addEventListener('click',submitDamageGr);
  return sheet;
}

function dgrText(error){
  return [error?.message,error?.details,error?.hint,error?.code?`Code: ${error.code}`:''].filter(Boolean).join(' — ')||'Unknown error';
}
function dgrMessage(text='',type=''){
  const el=document.getElementById('rrDgrMessage');if(!el)return;
  el.textContent=text;el.className=`rr-dgr-message ${type}`.trim();
}
function closeDamageGrSheet(){
  const sheet=document.getElementById('rrCuttingDamageGrSheet9235');
  if(sheet)sheet.classList.add('rr-dgr-hidden');
  document.body.style.overflow='';
}
function setDamageGrType(type){
  const value=['DAMAGE','PARTIAL_GR','FULL_GR'].includes(String(type))?String(type):'DAMAGE';
  damageGrState.type=value;
  const full=value==='FULL_GR';
  const title=value==='DAMAGE'?'Report Damage':value==='PARTIAL_GR'?'Report Partial GR':'Report Full GR';
  const titleEl=document.getElementById('rrDgrTitle');if(titleEl)titleEl.textContent=title;
  const submit=document.getElementById('rrDgrSubmit');if(submit)submit.textContent=`Save ${title.replace('Report ','')}`;
  ['rrDgrBillWrap','rrDgrRollWrap','rrDgrQtyWrap'].forEach(id=>{const el=document.getElementById(id);if(el)el.style.display=full?'none':'';});
  const scope=document.getElementById('rrDgrScopeWrap');if(scope)scope.style.display=full?'':'none';
  document.querySelectorAll('[data-dgr-pick]').forEach(el=>el.classList.toggle('active',el.dataset.dgrPick===value));
  dgrMessage('');
}

async function loadDamageGrContext(divisionId){
  const unitR=await client.from('rr_cb_units').select('*').eq('id',divisionId).maybeSingle();
  if(unitR.error||!unitR.data)throw unitR.error||new Error('CB child not found.');
  const division=unitR.data;
  const cbR=await client.from('rr_fabric_purchases').select('*').eq('id',division.purchase_id).maybeSingle();
  if(cbR.error||!cbR.data)throw cbR.error||new Error('CB not found.');
  const regularR=await client.rpc('rr_cutting_regular_category_id_v1');
  if(regularR.error||!regularR.data)throw regularR.error||new Error('Regular Cloth category not found.');
  const allocR=await client.from('rr_cb_material_allocations').select('*').eq('division_id',divisionId);
  if(allocR.error)throw allocR.error;
  const allocations=allocR.data||[];
  const entryIds=[...new Set(allocations.map(x=>x.purchase_entry_id).filter(Boolean))];
  let entries=[];
  if(entryIds.length){
    const entryR=await client.from('rr_cb_purchase_entries').select('*').in('id',entryIds);
    if(entryR.error)throw entryR.error;
    entries=(entryR.data||[]).filter(x=>String(x.material_category_id)===String(regularR.data));
  }
  let rolls=[];
  const regularEntryIds=entries.map(x=>x.id);
  if(regularEntryIds.length){
    const rollR=await client.from('rr_cb_purchase_rolls').select('*').in('purchase_entry_id',regularEntryIds);
    if(rollR.error)throw rollR.error;
    rolls=(rollR.data||[]).filter(x=>!x.division_id||String(x.division_id)===String(divisionId));
  }
  Object.assign(damageGrState,{division,cb:cbR.data,entries,allocations,rolls});
}

function refreshDamageGrBills(){
  const select=document.getElementById('rrDgrBill');if(!select)return;
  const allocationMap=new Map(damageGrState.allocations.map(a=>[String(a.purchase_entry_id),a]));
  select.innerHTML='<option value="">Select Source Bill</option>'+damageGrState.entries.map(entry=>{
    const alloc=allocationMap.get(String(entry.id));
    const qty=Number(alloc?.current_qty??alloc?.allocated_qty??0);
    return `<option value="${String(entry.id).replace(/"/g,'&quot;')}">${String(entry.vendor_bill_no||entry.id)} · ${String(entry.vendor_name||'Vendor')} · ${String(entry.fabric_name||'Fabric')} · ${qty.toFixed(3)} kg</option>`;
  }).join('');
  refreshDamageGrRolls();
}
function refreshDamageGrRolls(){
  const billId=String(document.getElementById('rrDgrBill')?.value||'');
  const select=document.getElementById('rrDgrRoll');if(!select)return;
  const rows=damageGrState.rolls.filter(r=>String(r.purchase_entry_id)===billId);
  select.innerHTML='<option value="">Select Roll / Particular</option>'+rows.map(row=>`<option value="${String(row.id).replace(/"/g,'&quot;')}">${String(row.roll_no||'Roll')} · ${Number(row.quantity||0).toFixed(3)} kg</option>`).join('');
}

async function openDamageGrSheet(divisionId,type){
  const sheet=ensureDamageGrSheet();
  sheet.classList.remove('rr-dgr-hidden');document.body.style.overflow='hidden';
  dgrMessage('Loading source bills…');
  try{
    await loadDamageGrContext(divisionId);
    const cbNo=damageGrState.cb?.cb_no||'CB';
    const child=damageGrState.division?.cb_code||`D${damageGrState.division?.division_index||1}`;
    const context=document.getElementById('rrDgrContext');if(context)context.textContent=`${cbNo} · ${child}`;
    refreshDamageGrBills();
    document.getElementById('rrDgrLotNo').value='';
    document.getElementById('rrDgrQty').value='';
    document.getElementById('rrDgrReason').value='';
    document.getElementById('rrDgrRemarks').value='';
    document.getElementById('rrDgrExchange').checked=false;
    document.getElementById('rrDgrScope').value='DIVISION';
    setDamageGrType(type);
  }catch(error){
    console.error('Damage / GR context failed',error);dgrMessage(dgrText(error),'error');
  }
}

async function submitDamageGr(){
  const button=document.getElementById('rrDgrSubmit');
  if(!button||button.disabled)return;
  const type=damageGrState.type;
  const lotNo=String(document.getElementById('rrDgrLotNo')?.value||'').trim().toUpperCase();
  const reason=String(document.getElementById('rrDgrReason')?.value||'').trim();
  const remarks=String(document.getElementById('rrDgrRemarks')?.value||'').trim();
  const billId=String(document.getElementById('rrDgrBill')?.value||'');
  const rollId=String(document.getElementById('rrDgrRoll')?.value||'');
  const qty=Number(document.getElementById('rrDgrQty')?.value||0);
  const scope=String(document.getElementById('rrDgrScope')?.value||'DIVISION');
  const exchange=Boolean(document.getElementById('rrDgrExchange')?.checked);
  if(!lotNo)return dgrMessage('Manual Lot No required.','error');
  if(!reason)return dgrMessage('Reason required.','error');
  if(type!=='FULL_GR'&&!billId)return dgrMessage('Source Bill required.','error');
  if(type!=='FULL_GR'&&!rollId)return dgrMessage('Roll / Particular required.','error');
  if(type!=='FULL_GR'&&qty<=0)return dgrMessage('Qty must be greater than zero.','error');
  button.disabled=true;const old=button.textContent;button.textContent='Saving…';dgrMessage('Posting permanent Damage / GR ledger…');
  try{
    const result=await client.rpc('rr_cutting_report_cb_action_v1',{
      p_cb_id:damageGrState.cb.id,
      p_division_id:damageGrState.division.id,
      p_action_type:type,
      p_purchase_entry_id:type==='FULL_GR'?null:billId,
      p_roll_id:type==='FULL_GR'?null:rollId,
      p_qty:type==='FULL_GR'?null:qty,
      p_full_gr_scope:type==='FULL_GR'?scope:null,
      p_lot_no:lotNo,
      p_reason:reason,
      p_remarks:remarks||null,
      p_admin_phone:null,
      p_exchange_expected:exchange
    });
    if(result.error)throw result.error;
    const action=result.data?.action||{};
    dgrMessage(`${action.action_no||'Damage / GR'} saved. Product Master CB ledger updated.`,'success');
    window.RRCuttingMasterPM?.refresh?.();
  }catch(error){
    console.error('Damage / GR report failed',error);dgrMessage(dgrText(error),'error');
  }finally{button.disabled=false;button.textContent=old;}
}

function decorateDamageGrCards(){
  injectDamageGrStyles();
  document.querySelectorAll('.cm-card[data-division-id]').forEach(card=>{
    if(card.querySelector('.rr-dgr-actions'))return;
    const divisionId=card.getAttribute('data-division-id');if(!divisionId)return;
    const released=Boolean(card.getAttribute('data-lot-no'));
    const row=document.createElement('div');row.className='rr-dgr-actions';
    row.innerHTML=`<button type="button" data-dgr-type="DAMAGE" ${released?'disabled':''}>Report Damage</button><button type="button" data-dgr-type="PARTIAL_GR" ${released?'disabled':''}>Report Partial GR</button><button type="button" data-dgr-type="FULL_GR" ${released?'disabled':''}>Report Full GR</button>`;
    row.querySelectorAll('[data-dgr-type]').forEach(button=>button.addEventListener('click',()=>openDamageGrSheet(divisionId,button.dataset.dgrType)));
    card.appendChild(row);
  });
}

/* Release Lot button only: bypass the lost form-submit event on mobile and call the existing release function directly. */
function bindReleaseLotButton(){
  const button=document.getElementById('releaseLotBtn');
  if(!button||button.dataset.rrDirectRelease9194==='1')return;

  button.dataset.rrDirectRelease9194='1';
  button.addEventListener('click',event=>{
    event.preventDefault();
    event.stopImmediatePropagation();

    const api=window.RRCuttingMasterPM;
    if(typeof api?.createLot!=='function')return;

    api.createLot({
      preventDefault(){},
      submitter:button
    });
  },true);
}

bindReleaseLotButton();
decorateDamageGrCards();
setInterval(decorateDamageGrCards,1400);
window.addEventListener('load',()=>{
  bindReleaseLotButton();
  decorateDamageGrCards();
  setTimeout(reconcile,1400);
  setTimeout(reconcile,4500);
  setTimeout(stopPermanentSpinner,12000);
},{once:true});
})();