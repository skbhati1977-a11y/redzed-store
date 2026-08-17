(()=>{
'use strict';
if(window.__RR_CUTTING_RUNTIME_9194__)return;
window.__RR_CUTTING_RUNTIME_9194__=true;

/* Rolled-back layout stays untouched; only startup I/O is made non-blocking. */
window.__RR_CUTTING_UI_LOADER_9190__=true;
window.__RR_CUTTING_LOAD_GUARD_9191__=true;
window.__RR_CUTTING_LOADING_GUARD_9191__=true;

function disableCuttingSliceBar(){
  document.body?.classList.remove('rrSliceReserved');
  document.documentElement?.style.setProperty('--rr-slice-rail','0px');
  ['rrSliceRail','rrSlicePanel','rrSliceBack'].forEach(id=>document.getElementById(id)?.remove());
}
disableCuttingSliceBar();
const sliceObserver=new MutationObserver(disableCuttingSliceBar);
sliceObserver.observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['class']});
window.addEventListener('load',()=>setTimeout(disableCuttingSliceBar,0),{once:true});

const client=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
if(!client)return;

const criticalTables=new Set([
  'rr_product_gallery_production_v719',
  'rr_product_gallery_view',
  'rr_cb_units',
  'rr_fabric_purchases'
]);
function timeoutError(label,ms){return {data:null,error:{message:`${label} timed out after ${ms}ms`,code:'RR_NONBLOCKING_TIMEOUT'}}}
function timeoutEmpty(label,ms){return {data:[],error:null,rr_timeout:true,rr_timeout_label:label,rr_timeout_ms:ms}}
function raceResult(request,ms,label,fallback){
  return Promise.race([
    Promise.resolve(request),
    new Promise(resolve=>setTimeout(()=>resolve(fallback(label,ms)),ms))
  ]);
}

/* Optional/identity RPCs must never own the main gallery render. */
if(typeof client.rpc==='function'&&!client.__rrCuttingRpc9194){
  const originalRpc=client.rpc.bind(client);
  const rpcTimeouts=new Map([
    ['rr_current_role',1500],
    ['rr_recover_lot_matching_v2',1800],
    ['rr_get_matching_cloth_stock_v2',4000],
    ['rr_get_matching_cloth_stock_v1',4000],
    ['rr_get_mc1_lot_matchings_v2',4000],
    ['rr_list_multi_lots_v3',4000]
  ]);
  client.rpc=function(name,args,options){
    const request=originalRpc(name,args,options);
    const key=String(name||'');
    const ms=rpcTimeouts.get(key);
    return ms?raceResult(request,ms,key,timeoutEmpty):request;
  };
  client.__rrCuttingRpc9194=true;
}

/* Every startup SELECT must settle. Writes are never timed out or altered. */
if(typeof client.from==='function'&&!client.__rrCuttingFrom9194){
  const originalFrom=client.from.bind(client);
  function wrapBuilder(builder,state){
    if(!builder||typeof builder!=='object')return builder;
    return new Proxy(builder,{
      get(target,prop,receiver){
        if(prop==='then'&&!state.mutating){
          const ms=state.table==='rr_cutting_cost_settings_v3'?2500:6500;
          const fallback=criticalTables.has(state.table)?timeoutError:timeoutEmpty;
          return(onFulfilled,onRejected)=>
            raceResult(target,ms,`Cutting read ${state.table}`,fallback).then(onFulfilled,onRejected);
        }
        const value=Reflect.get(target,prop,receiver);
        if(typeof value!=='function')return value;
        return(...args)=>{
          if(['insert','upsert','update','delete'].includes(String(prop)))state.mutating=true;
          const result=value.apply(target,args);
          return result&&typeof result==='object'?wrapBuilder(result,state):result;
        };
      }
    });
  }
  client.from=function(table){
    const name=String(table||'table');
    return wrapBuilder(originalFrom(table),{mutating:false,table:name});
  };
  client.__rrCuttingFrom9194=true;
}

function reconcile(){
  const api=window.RRCuttingMasterPM;
  const gallery=document.getElementById('divisionGallery');
  if(!api||!gallery)return;
  try{
    const state=api.state?.()||{};
    const rows=Array.isArray(state.galleryRows)?state.galleryRows:[];
    if(rows.length&&gallery.getAttribute('aria-busy')==='true')api.renderGallery?.();
  }catch(error){console.warn('Cutting reconcile warning',error)}
}

function stopPermanentSpinner(){
  const gallery=document.getElementById('divisionGallery');
  if(!gallery||gallery.getAttribute('aria-busy')!=='true'||gallery.querySelector('.cm-card'))return;
  const loading=gallery.querySelector('.cm-empty');
  if(!loading||!/Loading Cutting Master|Connecting CB Divisions|Connecting Product Master|Starting Cutting Master/i.test(loading.textContent||''))return;
  gallery.setAttribute('aria-busy','false');
  loading.innerHTML='<h3>Cutting Master connection delayed</h3><p>A data read did not finish. Tap Retry; the page will not remain on a permanent spinner.</p><button type="button" class="cm-primary" id="rrCuttingRetry9194">Retry</button>';
  document.getElementById('rrCuttingRetry9194')?.addEventListener('click',()=>window.RRCuttingMasterPM?.refresh?.(),{once:true});
}

window.addEventListener('load',()=>{
  setTimeout(disableCuttingSliceBar,0);
  setTimeout(reconcile,1800);
  setTimeout(reconcile,7000);
  setTimeout(stopPermanentSpinner,11000);
},{once:true});
})();