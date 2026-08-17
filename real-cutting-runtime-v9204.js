(()=>{
'use strict';
if(window.__RR_CUTTING_RUNTIME_9204__)return;
window.__RR_CUTTING_RUNTIME_9204__=true;
window.__RR_CUTTING_UI_LOADER_9190__=true;
window.__RR_CUTTING_LOAD_GUARD_9191__=true;
window.__RR_CUTTING_LOADING_GUARD_9191__=true;

function cleanCuttingOverlays(){
  document.body?.classList.remove('rrSliceReserved');
  document.documentElement?.style.setProperty('--rr-slice-rail','0px');
  ['rrSliceRail','rrSlicePanel','rrSliceBack','rr-global-data-mode-badge-v786-1-1']
    .forEach(id=>document.getElementById(id)?.remove());
  document.querySelectorAll('a').forEach(el=>{
    const text=String(el.textContent||'').replace(/\s+/g,' ').trim().toUpperCase();
    if(text==='TEST DEFAULT · REAL PROTECTED'||text==='REAL LIVE · TEST PROTECTED')el.remove();
  });
}
cleanCuttingOverlays();
const overlayObserver=new MutationObserver(cleanCuttingOverlays);
overlayObserver.observe(document.documentElement,{childList:true,subtree:true});
document.addEventListener('DOMContentLoaded',cleanCuttingOverlays,{once:true});
window.addEventListener('load',()=>{cleanCuttingOverlays();setTimeout(cleanCuttingOverlays,250);setTimeout(cleanCuttingOverlays,1000)},{once:true});

const client=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
if(!client)return;

const criticalTables=new Set(['rr_product_gallery_view','rr_cb_units','rr_fabric_purchases']);
function timeoutError(label,ms){return {data:null,error:{message:`${label} timed out after ${ms}ms`,code:'RR_NONBLOCKING_TIMEOUT'}}}
function timeoutEmpty(label,ms){return {data:[],error:null,rr_timeout:true,rr_timeout_label:label,rr_timeout_ms:ms}}
function raceResult(request,ms,label,fallback){return Promise.race([Promise.resolve(request),new Promise(resolve=>setTimeout(()=>resolve(fallback(label,ms)),ms))])}

/* First role lookup must never delay the gallery. A later refresh can still resolve the real role. */
if(typeof client.rpc==='function'&&!client.__rrCuttingRpc9204){
  const originalRpc=client.rpc.bind(client);
  let firstRoleLookup=true;
  const rpcTimeouts=new Map([
    ['rr_current_role',1500],
    ['rr_recover_lot_matching_v2',1200],
    ['rr_get_matching_cloth_stock_v2',3500],
    ['rr_get_matching_cloth_stock_v1',3500],
    ['rr_get_mc1_lot_matchings_v2',3500],
    ['rr_list_multi_lots_v3',3500]
  ]);
  client.rpc=function(name,args,options){
    const key=String(name||'');
    if(key==='rr_current_role'&&firstRoleLookup){
      firstRoleLookup=false;
      return Promise.resolve({data:null,error:null,rr_startup_bypass:true});
    }
    if(key==='rr_recover_lot_matching_v2'){
      try{void originalRpc(name,args,options)}catch(_){}
      return Promise.resolve({data:null,error:null,rr_startup_bypass:true});
    }
    const request=originalRpc(name,args,options);
    const ms=rpcTimeouts.get(key);
    return ms?raceResult(request,ms,key,timeoutEmpty):request;
  };
  client.__rrCuttingRpc9204=true;
}

/* All startup SELECTs settle. Only the three gallery-source tables remain critical. Writes are never timed out. */
if(typeof client.from==='function'&&!client.__rrCuttingFrom9204){
  const originalFrom=client.from.bind(client);
  function wrapBuilder(builder,state){
    if(!builder||typeof builder!=='object')return builder;
    return new Proxy(builder,{
      get(target,prop,receiver){
        if(prop==='then'&&!state.mutating){
          const ms=state.table==='rr_cutting_cost_settings_v3'?2200:5500;
          const fallback=criticalTables.has(state.table)?timeoutError:timeoutEmpty;
          return(onFulfilled,onRejected)=>raceResult(target,ms,`Cutting read ${state.table}`,fallback).then(onFulfilled,onRejected);
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
  client.__rrCuttingFrom9204=true;
}

function reconcile(){
  const api=window.RRCuttingMasterPM;
  const gallery=document.getElementById('divisionGallery');
  if(!api||!gallery)return;
  try{
    const state=api.state?.()||{};
    const rows=Array.isArray(state.galleryRows)?state.galleryRows:[];
    if(rows.length&&gallery.getAttribute('aria-busy')==='true')api.renderGallery?.();
  }catch(error){console.warn('Cutting v9204 reconcile warning',error)}
}

function stopStaticSpinner(){
  const gallery=document.getElementById('divisionGallery');
  if(!gallery||gallery.querySelector('.cm-card'))return;
  const loading=gallery.querySelector('.cm-empty');
  if(!loading)return;
  const text=String(loading.textContent||'');
  if(!/Loading Cutting Master|Connecting CB Divisions|Connecting Product Master/i.test(text))return;
  gallery.setAttribute('aria-busy','false');
  loading.innerHTML='<h3>Cutting Master connection delayed</h3><p>Startup did not complete. Tap Retry to restart the PM loader.</p><button type="button" class="cm-primary" id="rrCuttingRetry9204">Retry</button>';
  document.getElementById('rrCuttingRetry9204')?.addEventListener('click',()=>{
    gallery.setAttribute('aria-busy','true');
    window.RRCuttingMasterPM?.refresh?.();
  },{once:true});
}

window.addEventListener('load',()=>{
  setTimeout(reconcile,1200);
  setTimeout(reconcile,5000);
  setTimeout(stopStaticSpinner,9000);
},{once:true});
})();