(()=>{
'use strict';
if(window.__RR_CUTTING_RUNTIME_9192__)return;window.__RR_CUTTING_RUNTIME_9192__=true;
/* Disable the old UI watchdog. The core must finish or show its own fatal error. */
window.__RR_CUTTING_LOAD_GUARD_9191__=true;
window.__RR_CUTTING_LOADING_GUARD_9191__=true;
const client=window.supabaseClient||window.supabaseDb||window.redzedSupabase||window.sb;
if(!client||typeof client.rpc!=='function')return;
const originalRpc=client.rpc.bind(client);
const OPTIONAL_RPC_TIMEOUTS=new Map([
 ['rr_recover_lot_matching_v2',2500],
 ['rr_get_matching_cloth_stock_v2',4500],
 ['rr_get_matching_cloth_stock_v1',4500],
 ['rr_get_mc1_lot_matchings_v2',4500],
 ['rr_list_multi_lots_v3',4500]
]);
client.rpc=function(name,args,options){
 const request=originalRpc(name,args,options);
 const ms=OPTIONAL_RPC_TIMEOUTS.get(String(name||''));
 if(!ms)return request;
 return Promise.race([
   Promise.resolve(request),
   new Promise(resolve=>setTimeout(()=>resolve({data:null,error:{message:`${name} timed out after ${ms}ms`,code:'RR_OPTIONAL_TIMEOUT'}}),ms))
 ]);
};
/* Final safety: if core has data but a late UI mutation left the gallery blank, render it once. */
function reconcile(){
 const api=window.RRCuttingMasterPM,g=document.getElementById('divisionGallery');
 if(!api||!g)return;
 try{
   const st=api.state?.()||{};
   const hasRows=Array.isArray(st.galleryRows)&&st.galleryRows.length>0;
   const blank=!g.querySelector('.cm-card')&&!g.querySelector('.cm-empty');
   if(hasRows&&(blank||g.getAttribute('aria-busy')==='true'))api.renderGallery?.();
 }catch(e){console.warn('Cutting v9192 reconcile',e)}
}
window.addEventListener('load',()=>{setTimeout(reconcile,1500);setTimeout(reconcile,5000)},{once:true});
})();