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

/* Optional/identity RPCs must never own the main gallery render. */
if(typeof client.rpc==='function'&&!client.__rrCuttingRpc9194){
  const originalRpc=client.rpc.bind(client);
  const rpcTimeouts=new Map([
    ['rr_current_role',1500],
    ['rr_recover_lot_matching_v2',2000],
    ['rr_get_matching_cloth_stock_v2',4000],
    ['rr_get_matching_cloth_stock_v1',4000],
    ['rr_get_mc1_lot_matchings_v2',4000],
    ['rr_list_multi_lots_v3',4000]
  ]);
  client.rpc=function(name,args,options){
    const request=originalRpc(name,args,options);
    const ms=rpcTimeouts.get(String(name||''));
    return ms?raceResult(request,ms,String(name||'RPC')):request;
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

window.addEventListener('load',()=>{
  setTimeout(reconcile,1400);
  setTimeout(reconcile,4500);
  setTimeout(stopPermanentSpinner,12000);
},{once:true});
})();