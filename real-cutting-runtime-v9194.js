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
  Damage / GR buttons use the existing action module. That module expects the
  current lot identity in the lot form. On a reopened/released D-card the lot
  can exist in runtime state while the input is empty, so sync it immediately
  before the original report click handler runs.
*/
function currentDamageGrLotNo(){
  const state=window.RRCuttingMasterPM?.state?.()||{};
  const active=state.activeCard||{};
  const division=active.division||{};
  const divisionId=String(division.division_id||division.id||'');
  const galleryRow=(Array.isArray(state.galleryRows)?state.galleryRows:[])
    .find(row=>String(row.division_id||row.unit_id||row.id||'')===divisionId)||{};
  const lotCandidates=[
    document.getElementById('cmManualLotNo')?.value,
    document.getElementById('lotNo')?.value,
    division.lot_no,
    division.latest_lot_no,
    division.released_lot_no,
    active.latestLot?.lot_no,
    active.lot?.lot_no,
    state.activeLot?.lot_no,
    state.currentLot?.lot_no,
    galleryRow.lot_no,
    galleryRow.latest_lot_no,
    galleryRow.released_lot_no
  ];
  return lotCandidates
    .map(value=>String(value||'').trim().toUpperCase())
    .find(Boolean)||'';
}

function bindDamageGrLotContext(){
  if(document.documentElement.dataset.rrDamageGrLotContext9194==='1')return;
  document.documentElement.dataset.rrDamageGrLotContext9194='1';
  document.addEventListener('click',event=>{
    const button=event.target?.closest?.('[data-cba-report]');
    if(!button)return;
    const lotNo=currentDamageGrLotNo();
    if(!lotNo)return;
    const manual=document.getElementById('cmManualLotNo');
    const legacy=document.getElementById('lotNo');
    if(manual&&!String(manual.value||'').trim()){
      manual.value=lotNo;
      manual.dispatchEvent(new Event('input',{bubbles:true}));
      manual.dispatchEvent(new Event('change',{bubbles:true}));
    }
    if(legacy&&!String(legacy.value||'').trim())legacy.value=lotNo;
  },true);
}

/*
  The action module already loads Regular Cloth source rows during boot. A report
  button should not be held hostage by a second network refresh before its sheet
  can open. For exactly the next report-source read, reuse the already-loaded
  snapshot; the original action module, form and save RPC remain unchanged.
*/
function bindDamageGrCachedSourceOpen(){
  if(document.documentElement.dataset.rrDamageGrCachedSource9194==='1')return;
  document.documentElement.dataset.rrDamageGrCachedSource9194='1';
  document.addEventListener('click',event=>{
    const button=event.target?.closest?.('[data-cba-report]');
    if(!button)return;

    const api=window.REDZED_CUTTING_CB_ACTIONS;
    const snapshot=api?.state?.()||{};
    const actionClient=snapshot.client;
    const cached=Array.isArray(snapshot.sources)?snapshot.sources.slice():[];
    if(!actionClient||typeof actionClient.from!=='function'||!cached.length)return;

    const originalFrom=actionClient.from.bind(actionClient);
    let armed=true;
    actionClient.from=function(table){
      if(armed&&String(table)==='rr_cutting_regular_purchase_sources_v1'){
        armed=false;
        actionClient.from=originalFrom;
        return {
          select(){
            return Promise.resolve({data:cached,error:null});
          }
        };
      }
      return originalFrom(table);
    };

    queueMicrotask(()=>{
      if(armed){
        armed=false;
        actionClient.from=originalFrom;
      }
    });
  },true);
}

/*
  Some global/mobile UI passes can rebuild the visible Damage / GR panel while
  preserving its data-signature. The markup survives but DOM onclick handlers do
  not. If a report button has lost its handler, force the existing action module
  to repaint/rebind the panel, then replay the same report click once.
*/
function bindDamageGrHandlerRecovery(){
  if(document.documentElement.dataset.rrDamageGrHandlerRecovery9194==='1')return;
  document.documentElement.dataset.rrDamageGrHandlerRecovery9194='1';
  document.addEventListener('click',event=>{
    const button=event.target?.closest?.('[data-cba-report]');
    if(!button||typeof button.onclick==='function'||button.dataset.rrRecoveryPending==='1')return;

    event.preventDefault();
    const type=String(button.dataset.cbaReport||'');
    if(!type)return;
    button.dataset.rrRecoveryPending='1';

    const panel=document.getElementById('rrCuttingCbActionPanel');
    if(panel)panel.dataset.signature='';

    const api=window.REDZED_CUTTING_CB_ACTIONS;
    Promise.resolve(api?.refresh?.()).catch(error=>{
      console.warn('Damage / GR handler refresh warning',error);
    }).finally(()=>{
      requestAnimationFrame(()=>{
        const fresh=[...document.querySelectorAll('[data-cba-report]')]
          .find(node=>String(node.dataset.cbaReport||'')===type);
        if(fresh&&typeof fresh.onclick==='function'){
          fresh.onclick();
          return;
        }
        const box=document.getElementById('cmMessage');
        if(box){
          box.textContent='Damage / GR action handler reconnect failed. Refresh this page once.';
          box.className='rr-message error';
        }
      });
    });
  },true);
}

bindReleaseLotButton();
bindDamageGrLotContext();
bindDamageGrCachedSourceOpen();
bindDamageGrHandlerRecovery();
window.addEventListener('load',()=>{
  bindReleaseLotButton();
  bindDamageGrLotContext();
  bindDamageGrCachedSourceOpen();
  bindDamageGrHandlerRecovery();
  setTimeout(reconcile,1400);
  setTimeout(reconcile,4500);
  setTimeout(stopPermanentSpinner,12000);
},{once:true});
})();