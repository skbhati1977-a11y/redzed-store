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

/*
  Historical V892 Damage/GR action module is still the source of truth.
  It exposes REAL_FACTORY_CUTTING_CB_ACTIONS and refreshes source rows before
  opening the report sheet. On current mobile runtime that extra read can stall.
  For exactly one Report click, feed that original module its already-loaded
  source snapshot (even when empty) so its own openReport/render/save flow fires.
*/
function bindDamageGrSourceBridge(){
  if(document.documentElement.dataset.rrDamageGrSourceBridge==='1')return;
  document.documentElement.dataset.rrDamageGrSourceBridge='1';

  document.addEventListener('click',event=>{
    const button=event.target?.closest?.('[data-cba-report]');
    if(!button)return;

    const api=window.REAL_FACTORY_CUTTING_CB_ACTIONS;
    const snapshot=api?.state?.()||{};
    const actionClient=snapshot.client;
    if(!actionClient||typeof actionClient.from!=='function')return;

    const cached=Array.isArray(snapshot.sources)?snapshot.sources.slice():[];
    const originalFrom=actionClient.from.bind(actionClient);
    const fastTables=new Set([
      'rr_cutting_regular_purchase_sources_v1',
      'rr_cb_purchase_entries',
      'rr_cb_material_allocations',
      'rr_cb_colours',
      'rr_material_categories',
      'rr_cb_purchase_rolls'
    ]);
    let active=true;

    actionClient.from=function(table){
      const tableName=String(table||'');
      if(active&&fastTables.has(tableName)){
        const data=tableName==='rr_cutting_regular_purchase_sources_v1'?cached:[];
        const result={data,error:null};
        const chain={
          select(){return chain;},
          eq(){return chain;},
          in(){return chain;},
          order(){return chain;},
          limit(){return chain;},
          then(resolve,reject){return Promise.resolve(result).then(resolve,reject);}
        };
        return chain;
      }
      return originalFrom(table);
    };

    window.setTimeout(()=>{
      if(!active)return;
      active=false;
      actionClient.from=originalFrom;
    },1500);
  },true);
}

bindReleaseLotButton();
bindDamageGrSourceBridge();
window.addEventListener('load',()=>{
  bindReleaseLotButton();
  bindDamageGrSourceBridge();
  setTimeout(reconcile,1400);
  setTimeout(reconcile,4500);
  setTimeout(stopPermanentSpinner,12000);
},{once:true});
})();