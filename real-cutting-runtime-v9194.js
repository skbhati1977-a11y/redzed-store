(()=>{
'use strict';
if(window.__RR_CUTTING_RUNTIME_9194__)return;
window.__RR_CUTTING_RUNTIME_9194__=true;
window.__RR_CUTTING_UI_LOADER_9190__=true;
window.__RR_CUTTING_LOAD_GUARD_9191__=true;
window.__RR_CUTTING_LOADING_GUARD_9191__=true;

/* Cutting keeps the Slice Menu, but does not opt back into data-mode/mobile-fill globals. */
function ensureCuttingSliceMenu(){
  if(window.__RR_SLICE_MENU_9190__||document.getElementById('rrSliceRail'))return;
  if(document.getElementById('rrCuttingSliceMenu9222'))return;
  const script=document.createElement('script');
  script.id='rrCuttingSliceMenu9222';
  script.src='/redzed-store/real-global-slice-menu-v9190.js?v=9222';
  script.async=false;
  (document.head||document.documentElement).appendChild(script);
}
ensureCuttingSliceMenu();

const stageNode=document.querySelector('#divisionGallery .cm-empty p');
if(stageNode)stageNode.textContent='Cutting runtime ready · opening factory data…';
const stageMessage=document.getElementById('cmMessage');
if(stageMessage&&!stageMessage.textContent){stageMessage.textContent='Cutting runtime ready · opening factory data…';stageMessage.className='rr-message info'}

const client=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
if(!client)return;

const criticalTables=new Set(['rr_product_gallery_production_v719','rr_product_gallery_view','rr_cb_units','rr_fabric_purchases']);
function timeoutError(label,ms){return {data:null,error:{message:`${label} timed out after ${ms}ms`,code:'RR_NONBLOCKING_TIMEOUT'}}}
function timeoutEmpty(label,ms){return {data:[],error:null,rr_timeout:true,rr_timeout_label:label,rr_timeout_ms:ms}}
function raceResult(request,ms,label,fallback){return Promise.race([Promise.resolve(request),new Promise(resolve=>setTimeout(()=>resolve(fallback(label,ms)),ms))])}

if(typeof client.rpc==='function'&&!client.__rrCuttingRpc9194){
  const originalRpc=client.rpc.bind(client);
  let startupRoleBypass=1;
  let startupRecoveryBypass=1;
  const rpcTimeouts=new Map([
    ['rr_current_role',1500],
    ['rr_recover_lot_matching_v2',1800],
    ['rr_get_matching_cloth_stock_v2',4000],
    ['rr_get_matching_cloth_stock_v1',4000],
    ['rr_get_mc1_lot_matchings_v2',4000],
    ['rr_list_multi_lots_v3',4000]
  ]);
  client.rpc=function(name,args,options){
    const key=String(name||'');
    if(key==='rr_current_role'&&startupRoleBypass>0){startupRoleBypass--;return Promise.resolve({data:null,error:null,rr_startup_bypass:true})}
    if(key==='rr_recover_lot_matching_v2'&&startupRecoveryBypass>0){startupRecoveryBypass--;try{void originalRpc(name,args,options)}catch(_){}return Promise.resolve({data:null,error:null,rr_startup_bypass:true})}
    const ms=rpcTimeouts.get(key);
    if(!ms)return originalRpc(name,args,options);
    let request;
    try{request=originalRpc(name,args,options)}catch(error){return Promise.resolve({data:null,error})}
    return raceResult(request,ms,key,timeoutEmpty);
  };
  client.__rrCuttingRpc9194=true;
}

if(typeof client.from==='function'&&!client.__rrCuttingFrom9194){
  const originalFrom=client.from.bind(client);
  function wrapBuilder(builder,state){
    if(!builder||typeof builder!=='object')return builder;
    return new Proxy(builder,{
      get(target,prop,receiver){
        if(prop==='then'&&!state.mutating){
          const ms=state.table==='rr_cutting_cost_settings_v3'?2500:6500;
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
  client.from=function(table){const name=String(table||'table');return wrapBuilder(originalFrom(table),{mutating:false,table:name})};
  client.__rrCuttingFrom9194=true;
}

function reconcile(){
  const api=window.RRCuttingMasterPM;
  const gallery=document.getElementById('divisionGallery');
  if(!api||!gallery)return;
  try{const state=api.state?.()||{};const rows=Array.isArray(state.galleryRows)?state.galleryRows:[];if(rows.length&&gallery.getAttribute('aria-busy')==='true')api.renderGallery?.()}catch(error){console.warn('Cutting reconcile warning',error)}
}

function stopPermanentSpinner(){
  const gallery=document.getElementById('divisionGallery');
  if(!gallery||gallery.getAttribute('aria-busy')!=='true'||gallery.querySelector('.cm-card'))return;
  const loading=gallery.querySelector('.cm-empty');
  if(!loading||!/Loading Cutting Master|Connecting CB Divisions|Connecting Product Master|Starting Cutting Master|Preparing factory screen|Connecting data engine|Opening factory config|Starting nonblocking guard|Cutting runtime ready|Loading factory cards/i.test(loading.textContent||''))return;
  gallery.setAttribute('aria-busy','false');
  loading.innerHTML='<h3>Cutting Master connection delayed</h3><p>A data read did not finish. Tap Retry; the page will not remain on a permanent spinner.</p><button type="button" class="cm-primary" id="rrCuttingRetry9194">Retry</button>';
  document.getElementById('rrCuttingRetry9194')?.addEventListener('click',()=>{if(window.RRCuttingMasterPM?.refresh)window.RRCuttingMasterPM.refresh();else location.reload()},{once:true});
}

setTimeout(reconcile,1800);
setTimeout(reconcile,7000);
setTimeout(stopPermanentSpinner,11000);
})();